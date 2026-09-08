defmodule Pipette do
  @moduledoc """
  Declarative Buildkite pipeline generation for monorepos, written in Elixir.

  Define your CI pipeline using `Pipette.DSL` — a declarative syntax
  built on Spark. Pipette inspects changed files, applies branch
  policies and scope rules, then generates a Buildkite YAML pipeline
  containing only the groups that need to run.

  ## Quick start

      defmodule MyApp.Pipeline do
        use Pipette.DSL

        branch "main", scopes: :all, disable: [:targeting]

        scope :api_code, files: ["apps/api/**"]
        scope :web_code, files: ["apps/web/**"]

        ignore ["docs/**", "*.md"]

        group :api do
          label ":elixir: API"
          scope :api_code
          step :test, label: "Test", command: "mix test"
          step :lint, label: "Lint", command: "mix credo"
        end

        group :web do
          label ":globe_with_meridians: Web"
          scope :web_code
          step :test, label: "Test", command: "pnpm test"
          step :build, label: "Build", command: "pnpm build"
        end

        group :deploy do
          label ":rocket: Deploy"
          depends_on [:api, :web]
          only "main"
          step :push, label: "Push", command: "./deploy.sh"
        end

        trigger :notify do
          pipeline "notify-pipeline"
          depends_on :deploy
          only "main"
        end

        force_activate %{"FORCE_DEPLOY" => [:deploy]}
      end

  ## Running the pipeline

      # In your .buildkite/pipeline.exs:
      Pipette.run(MyApp.Pipeline)

      # Dry run (returns YAML without uploading):
      {:ok, yaml} = Pipette.generate(MyApp.Pipeline)

  ## How it works

  1. Reads the compiled `%Pipette.Pipeline{}` from the DSL module
     (validation and key generation happen at compile time via Spark)
  2. Builds a `%Pipette.Context{}` from Buildkite environment variables
  3. Determines changed files via `git diff`
  4. Resolves force-activated groups from environment variables
  5. Runs the activation engine to determine which groups to include
  6. Resolves trigger steps based on active groups and branch filters
  7. Serializes active groups and triggers to Buildkite YAML
  8. Uploads the YAML via `buildkite-agent pipeline upload` (or returns it in dry-run mode)

  ## Options

  Both `run/2` and `generate/2` accept these options:

    * `:env` — environment variable map (defaults to `System.get_env()`)
    * `:dry_run` — when `true`, returns YAML instead of uploading (defaults to `DRY_RUN=1`)
    * `:changed_files` — explicit list of changed files (skips `git diff`)
    * `:extra_groups` — 2-arity function `(ctx, changed_files) -> [Group.t()]` for dynamic groups
    * `:transform_groups` — 1-arity function `(groups) -> groups` applied to the
      active groups after activation, before triggers and `depends_on` resolve
      (e.g. route steps to agent queues)

  Wrap a `depends_on` reference in `optional/1` (see `Pipette.Optional`) to drop
  it when its target group isn't activated by this build instead of dangling.

  ## Testing

  Use `generate/2` with explicit `:env` and `:changed_files` to test activation logic:

      {:ok, yaml} = Pipette.generate(MyApp.Pipeline,
        env: %{
          "BUILDKITE_BRANCH" => "feature/login",
          "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
          "BUILDKITE_COMMIT" => "abc123",
          "BUILDKITE_MESSAGE" => "Add login"
        },
        changed_files: ["apps/api/lib/user.ex"]
      )

      assert yaml =~ "api"
      refute yaml =~ "web"
  """

  require Logger

  alias Pipette.{Activation, Buildkite, Context, Git}

  @doc """
  Run the pipeline: validate, resolve activation, and upload to Buildkite.

  Returns:
    * `:ok` — pipeline uploaded successfully
    * `{:ok, yaml}` — dry run mode, returns the YAML string
    * `:noop` — no groups activated (e.g. docs-only changes)
    * `{:error, message}` — upload failed

  ## Options

    * `:env` — environment variable map (defaults to `System.get_env()`)
    * `:dry_run` — return YAML instead of uploading (defaults to `DRY_RUN=1` env var)
    * `:changed_files` — explicit list of changed files (skips `git diff`)
    * `:extra_groups` — `fn ctx, changed_files -> [Group.t()]` for dynamic groups
    * `:transform_groups` — `fn groups -> groups` applied to the active groups
      after activation, before triggers and `depends_on` resolve

  ## Examples

      # Normal CI usage (reads env, runs git diff, uploads):
      Pipette.run(MyApp.Pipeline)

      # Dry run from command line:
      # DRY_RUN=1 elixir .buildkite/pipeline.exs

      # Programmatic dry run with explicit inputs:
      {:ok, yaml} = Pipette.run(MyApp.Pipeline,
        dry_run: true,
        env: %{"BUILDKITE_BRANCH" => "main", ...},
        changed_files: ["apps/api/lib/user.ex"]
      )
  """
  @spec run(module(), keyword()) :: {:ok, String.t()} | :ok | :noop | {:error, String.t()}
  def run(pipeline_module, opts \\ []) do
    env = Keyword.get(opts, :env, System.get_env())
    dry_run = Keyword.get(opts, :dry_run, env["DRY_RUN"] == "1")

    pipeline = Pipette.Info.to_pipeline(pipeline_module)

    ctx = Context.from_env(env)

    changed_files =
      case Keyword.fetch(opts, :changed_files) do
        {:ok, files} ->
          files

        :error ->
          base = Git.base_commit(ctx)
          Logger.info("Base commit: #{base}")

          case Git.changed_files(base) do
            {:ok, files} ->
              files

            {:error, reason} ->
              Logger.warning("Git diff failed: #{reason}, running all groups")
              :all
          end
      end

    force_groups = resolve_force_groups(pipeline.force_activate, env)
    result = Activation.resolve(pipeline, ctx, changed_files, force_groups)

    # Optional post-activation hook: transform the active group list (e.g. route
    # steps to specific agent queues) before triggers and depends_on resolve
    # against it. Runs here so triggers see the transformed groups.
    active_groups =
      case Keyword.get(opts, :transform_groups) do
        fun when is_function(fun, 1) -> fun.(result.groups)
        _ -> result.groups
      end

    triggers = resolve_triggers(pipeline, active_groups, ctx)

    extra_groups =
      case Keyword.get(opts, :extra_groups) do
        fun when is_function(fun, 2) -> fun.(ctx, changed_files)
        _ -> []
      end

    all_groups = active_groups ++ extra_groups

    # Resolve group/trigger depends_on atoms to key strings for Buildkite YAML.
    # The activation engine uses atom names internally; Buildkite needs key strings.
    # Group names and {group, step} pairs cannot collide, so one map serves both.
    key_map =
      (pipeline.groups ++ extra_groups)
      |> Map.new(&{&1.name, &1.key})
      |> Map.merge(step_key_map(pipeline.groups ++ extra_groups))

    # Keys defined in the pipeline but not activated by this build. An
    # `optional/1` dep pointing at one is dropped (the target legitimately isn't
    # in this build); every other dangling dep is kept so Buildkite rejects the
    # upload loudly. See `Pipette.Optional`.
    inactive =
      MapSet.difference(
        keys_of(pipeline.groups ++ extra_groups, pipeline.triggers),
        keys_of(all_groups, triggers)
      )

    all_groups =
      Enum.map(all_groups, fn group ->
        # Resolve nested-trigger and step depends_on against the top-level group
        # key map (mirroring top-level trigger semantics) and drop inactive
        # optional deps. Plain step deps were already key-resolved at compile time
        # by GenerateKeys, so re-resolving them is a no-op.
        resolved_steps =
          Enum.map(group.steps, fn
            %Pipette.Trigger{} = trigger ->
              %{trigger | depends_on: resolve_deps(trigger.depends_on, key_map, inactive)}

            %Pipette.Step{} = step ->
              %{step | depends_on: resolve_deps(step.depends_on, key_map, inactive)}

            other ->
              other
          end)

        %{
          group
          | depends_on: resolve_depends_on_keys(group.depends_on, key_map),
            steps: resolved_steps
        }
      end)

    triggers =
      Enum.map(triggers, fn trigger ->
        %{trigger | depends_on: resolve_deps(trigger.depends_on, key_map, inactive)}
      end)

    if all_groups == [] and triggers == [] do
      Logger.info("No groups activated -- nothing to do")
      :noop
    else
      pipeline_config =
        %{}
        |> then(fn m ->
          if pipeline.env not in [nil, %{}], do: Map.put(m, :env, pipeline.env), else: m
        end)
        |> then(fn m ->
          if pipeline.secrets not in [nil, []],
            do: Map.put(m, :secrets, pipeline.secrets),
            else: m
        end)
        |> then(fn m -> if pipeline.cache, do: Map.put(m, :cache, pipeline.cache), else: m end)

      yaml = Buildkite.to_yaml(all_groups, pipeline_config, triggers)

      log_summary(all_groups, triggers, ctx)

      if dry_run do
        {:ok, yaml}
      else
        case upload(yaml) do
          :ok -> :ok
          {:error, msg} -> {:error, msg}
        end
      end
    end
  end

  defp resolve_depends_on_keys(nil, _map), do: nil
  defp resolve_depends_on_keys(dep, _map) when is_binary(dep), do: dep

  defp resolve_depends_on_keys(dep, map) when is_atom(dep),
    do: Map.get(map, dep, Atom.to_string(dep))

  defp resolve_depends_on_keys({group, step} = ref, map) when is_atom(group) and is_atom(step),
    do: Map.get(map, ref, "#{group}-#{step}")

  defp resolve_depends_on_keys(deps, map) when is_list(deps),
    do: Enum.map(deps, &resolve_depends_on_keys(&1, map))

  # {group_name, child_name} -> key for every keyed step and nested trigger.
  defp step_key_map(groups) do
    Map.new(
      for group <- groups, child <- group.steps, is_binary(child.key) do
        {{group.name, child.name}, child.key}
      end
    )
  end

  # The Buildkite key of every group, step, nested trigger, and top-level
  # trigger in the given lists — the set of valid `depends_on` targets.
  defp keys_of(groups, triggers) do
    group_keys = Enum.flat_map(groups, fn g -> [g.key | Enum.map(g.steps, & &1.key)] end)
    MapSet.new(group_keys ++ Enum.map(triggers, & &1.key))
  end

  # Resolve a depends_on value to key strings, unwrapping `optional/1` markers
  # and dropping those whose target is defined-but-inactive (`inactive`).
  defp resolve_deps(nil, _map, _inactive), do: nil

  defp resolve_deps(deps, map, inactive) when is_list(deps) do
    case Enum.flat_map(deps, &resolve_dep(&1, map, inactive)) do
      [] -> nil
      kept -> kept
    end
  end

  defp resolve_deps(dep, map, inactive) do
    case resolve_dep(dep, map, inactive) do
      [kept] -> kept
      [] -> nil
    end
  end

  defp resolve_dep(%Pipette.Optional{dep: dep}, map, inactive) do
    key = resolve_depends_on_keys(dep, map)
    if MapSet.member?(inactive, key), do: [], else: [key]
  end

  defp resolve_dep(dep, map, _inactive), do: [resolve_depends_on_keys(dep, map)]

  @doc """
  Generate pipeline YAML without uploading. Convenience wrapper around `run/2`
  with `dry_run: true`.

  Returns `{:ok, yaml}` when groups are activated, or `:noop` when no groups match.

  ## Examples

      {:ok, yaml} = Pipette.generate(MyApp.Pipeline,
        env: %{"BUILDKITE_BRANCH" => "main", ...},
        changed_files: ["apps/api/lib/user.ex"]
      )

      :noop = Pipette.generate(MyApp.Pipeline,
        env: %{"BUILDKITE_BRANCH" => "feature/docs", ...},
        changed_files: ["README.md"]
      )
  """
  @spec generate(module(), keyword()) :: {:ok, String.t()} | :noop
  def generate(pipeline_module, opts \\ []) do
    run(pipeline_module, Keyword.put(opts, :dry_run, true))
  end

  defp resolve_force_groups(force_activate, env)
       when is_map(force_activate) and map_size(force_activate) > 0 do
    Enum.reduce(force_activate, MapSet.new(), fn
      {_env_var, _groups}, :all ->
        :all

      {env_var, groups}, acc ->
        if Map.get(env, env_var) == "true" do
          case groups do
            :all ->
              :all

            group_list when is_list(group_list) ->
              Enum.reduce(group_list, acc, &MapSet.put(&2, &1))
          end
        else
          acc
        end
    end)
  end

  defp resolve_force_groups(_force_activate, _env), do: MapSet.new()

  defp upload(yaml) do
    tmp = Path.join(System.tmp_dir!(), "pipette-#{System.unique_integer([:positive])}.yml")
    File.write!(tmp, yaml)

    try do
      case System.cmd("buildkite-agent", ["pipeline", "upload", tmp], stderr_to_stdout: true) do
        {_output, 0} ->
          Logger.info("Pipeline uploaded successfully")
          :ok

        {output, code} ->
          Logger.error("Pipeline upload failed (exit #{code}): #{output}")
          {:error, "Pipeline upload failed (exit #{code}): #{output}"}
      end
    after
      File.rm(tmp)
    end
  end

  defp resolve_triggers(pipeline, active_groups, ctx) do
    active_group_names = MapSet.new(active_groups, & &1.name)

    Enum.filter(pipeline.triggers, fn trigger ->
      deps_met = trigger_deps_met?(trigger.depends_on, active_group_names)
      branch_ok = trigger_branch_ok?(trigger.only, ctx.branch)
      deps_met and branch_ok
    end)
  end

  defp trigger_deps_met?(nil, _active), do: true
  defp trigger_deps_met?(dep, active) when is_atom(dep), do: dep in active

  # A step reference is met when its group is active. An optional reference
  # never gates activation: it is dropped from the rendered deps when inactive.
  defp trigger_deps_met?({group, _step}, active) when is_atom(group), do: group in active
  defp trigger_deps_met?(%Pipette.Optional{}, _active), do: true

  defp trigger_deps_met?(dep, active) when is_binary(dep),
    do: String.to_atom(dep) in active

  defp trigger_deps_met?(deps, active) when is_list(deps),
    do: Enum.all?(deps, &trigger_deps_met?(&1, active))

  defp trigger_branch_ok?(nil, _branch), do: true
  defp trigger_branch_ok?(only, branch) when is_binary(only), do: Git.matches_glob?(branch, only)

  defp trigger_branch_ok?(only, branch) when is_list(only),
    do: Enum.any?(only, &Git.matches_glob?(branch, &1))

  defp log_summary(groups, triggers, ctx) do
    group_names = Enum.map_join(groups, ", ", & &1.name)
    trigger_names = Enum.map_join(triggers, ", ", & &1.name)

    msg = "Branch: #{ctx.branch} | Active groups: #{group_names}"
    msg = if trigger_names != "", do: msg <> " | Triggers: #{trigger_names}", else: msg

    Logger.info(msg)
  end
end
