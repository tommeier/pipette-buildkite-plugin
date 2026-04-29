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
    triggers = resolve_triggers(pipeline, result.groups, ctx)

    extra_groups =
      case Keyword.get(opts, :extra_groups) do
        fun when is_function(fun, 2) -> fun.(ctx, changed_files)
        _ -> []
      end

    all_groups = result.groups ++ extra_groups

    # Resolve group/trigger depends_on atoms to key strings for Buildkite YAML.
    # The activation engine uses atom names internally; Buildkite needs key strings.
    group_key_map = Map.new(pipeline.groups ++ extra_groups, &{&1.name, &1.key})

    all_groups =
      Enum.map(all_groups, fn group ->
        # Resolve nested-trigger depends_on against the top-level group
        # key map (mirroring top-level trigger semantics). Steps inside
        # the group already had their depends_on resolved at compile time
        # by GenerateKeys.
        resolved_steps =
          Enum.map(group.steps, fn
            %Pipette.Trigger{} = trigger ->
              %{trigger | depends_on: resolve_depends_on_keys(trigger.depends_on, group_key_map)}

            other ->
              other
          end)

        %{
          group
          | depends_on: resolve_depends_on_keys(group.depends_on, group_key_map),
            steps: resolved_steps
        }
      end)

    triggers =
      Enum.map(triggers, fn trigger ->
        %{trigger | depends_on: resolve_depends_on_keys(trigger.depends_on, group_key_map)}
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

  defp resolve_depends_on_keys(deps, map) when is_list(deps),
    do: Enum.map(deps, &resolve_depends_on_keys(&1, map))

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
