defmodule Pipette do
  @moduledoc """
  Declarative Buildkite pipeline generation for monorepos, written in Elixir.

  Define your CI pipeline as plain Elixir structs — no macros, no DSL,
  no metaprogramming. Pipette inspects changed files, applies branch
  policies and scope rules, then generates a Buildkite YAML pipeline
  containing only the groups that need to run.

  ## Quick start

      defmodule MyApp.Pipeline do
        @behaviour Pipette.Pipeline

        @impl true
        def pipeline do
          %Pipette.Pipeline{
            branches: [
              %Pipette.Branch{pattern: "main", scopes: :all, disable: [:targeting]}
            ],
            scopes: [
              %Pipette.Scope{name: :api_code, files: ["apps/api/**"]},
              %Pipette.Scope{name: :web_code, files: ["apps/web/**"]}
            ],
            groups: [
              %Pipette.Group{
                name: :api,
                label: ":elixir: API",
                scope: :api_code,
                steps: [
                  %Pipette.Step{name: :test, label: "Test", command: "mix test"},
                  %Pipette.Step{name: :lint, label: "Lint", command: "mix credo"}
                ]
              },
              %Pipette.Group{
                name: :web,
                label: ":globe_with_meridians: Web",
                scope: :web_code,
                steps: [
                  %Pipette.Step{name: :test, label: "Test", command: "pnpm test"},
                  %Pipette.Step{name: :build, label: "Build", command: "pnpm build"}
                ]
              },
              %Pipette.Group{
                name: :deploy,
                label: ":rocket: Deploy",
                depends_on: [:api, :web],
                only: "main",
                steps: [
                  %Pipette.Step{name: :push, label: "Push", command: "./deploy.sh"}
                ]
              }
            ],
            triggers: [
              %Pipette.Trigger{
                name: :notify,
                pipeline: "notify-pipeline",
                depends_on: :deploy,
                only: "main"
              }
            ],
            ignore: ["docs/**", "*.md"],
            force_activate: %{
              "FORCE_DEPLOY" => [:deploy]
            }
          }
        end
      end

  ## Running the pipeline

      # In your .buildkite/pipeline.exs:
      Pipette.run(MyApp.Pipeline)

      # Dry run (returns YAML without uploading):
      {:ok, yaml} = Pipette.generate(MyApp.Pipeline)

  ## How it works

  1. Calls `pipeline/0` on your module to get the `%Pipette.Pipeline{}` struct
  2. Validates the pipeline configuration (scope refs, dependency refs, cycles)
  3. Generates Buildkite keys for groups, steps, and triggers
  4. Builds a `%Pipette.Context{}` from Buildkite environment variables
  5. Determines changed files via `git diff`
  6. Resolves force-activated groups from environment variables
  7. Runs the activation engine to determine which groups to include
  8. Resolves trigger steps based on active groups and branch filters
  9. Serializes active groups and triggers to Buildkite YAML
  10. Uploads the YAML via `buildkite-agent pipeline upload` (or returns it in dry-run mode)

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

    pipeline = pipeline_module.pipeline()
    validate!(pipeline)
    pipeline = generate_keys(pipeline)

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

    if all_groups == [] and triggers == [] do
      Logger.info("No groups activated -- nothing to do")
      :noop
    else
      pipeline_config =
        %{}
        |> then(fn m -> if pipeline.env, do: Map.put(m, :env, pipeline.env), else: m end)
        |> then(fn m ->
          if pipeline.secrets, do: Map.put(m, :secrets, pipeline.secrets), else: m
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

  @doc """
  Validate a pipeline configuration at runtime.

  Checks:
  - Group scope references point to defined scopes
  - Group and trigger depends_on references point to defined groups
  - No dependency cycles
  - All steps have labels
  - force_activate references point to defined groups
  """
  @spec validate!(Pipette.Pipeline.t()) :: :ok
  def validate!(%Pipette.Pipeline{} = pipeline) do
    scope_names = MapSet.new(pipeline.scopes, & &1.name)
    group_names = MapSet.new(pipeline.groups, & &1.name)

    for group <- pipeline.groups, group.scope != nil, is_atom(group.scope) do
      unless MapSet.member?(scope_names, group.scope) do
        available = scope_names |> MapSet.to_list() |> Enum.map_join(", ", &inspect/1)

        raise "Group #{inspect(group.name)} references undefined scope #{inspect(group.scope)}. Available scopes: #{available}"
      end
    end

    for group <- pipeline.groups, dep <- List.wrap(group.depends_on), dep != nil do
      unless MapSet.member?(group_names, dep) do
        available = group_names |> MapSet.to_list() |> Enum.map_join(", ", &inspect/1)

        raise "Group #{inspect(group.name)} depends on undefined group #{inspect(dep)}. Available groups: #{available}"
      end
    end

    for trigger <- pipeline.triggers, dep <- List.wrap(trigger.depends_on), dep != nil do
      unless MapSet.member?(group_names, dep) do
        available = group_names |> MapSet.to_list() |> Enum.map_join(", ", &inspect/1)

        raise "Trigger #{inspect(trigger.name)} depends on undefined group #{inspect(dep)}. Available groups: #{available}"
      end
    end

    graph = Pipette.Graph.from_groups(pipeline.groups)

    case Pipette.Graph.find_cycle(graph) do
      nil ->
        :ok

      cycle ->
        formatted = cycle |> Enum.map_join(" -> ", &inspect/1)
        raise "Dependency cycle detected: #{formatted}"
    end

    for group <- pipeline.groups, step <- group.steps do
      unless step.label do
        raise "Step #{inspect(step.name)} in group #{inspect(group.name)} is missing a label"
      end
    end

    for {env_var, groups} <- pipeline.force_activate || %{},
        groups != :all,
        group <- List.wrap(groups) do
      unless MapSet.member?(group_names, group) do
        available = group_names |> MapSet.to_list() |> Enum.map_join(", ", &inspect/1)

        raise "force_activate #{inspect(env_var)} references undefined group #{inspect(group)}. Available groups: #{available}"
      end
    end

    :ok
  end

  @doc """
  Generate Buildkite keys for groups, steps, and triggers.

  - Groups: `:api` -> `"api"`
  - Steps: `:test` in `:api` -> `"api-test"`
  - Triggers: `:deploy` -> `"deploy"`
  - Step depends_on resolved to key strings
  """
  @spec generate_keys(Pipette.Pipeline.t()) :: Pipette.Pipeline.t()
  def generate_keys(%Pipette.Pipeline{} = pipeline) do
    groups =
      Enum.map(pipeline.groups, fn group ->
        group_key = Atom.to_string(group.name)

        steps =
          Enum.map(group.steps, fn step ->
            step_key = "#{group_key}-#{step.name}"
            resolved_depends = resolve_step_depends_on(step.depends_on, group)
            %{step | key: step_key, depends_on: resolved_depends}
          end)

        resolved_depends = resolve_group_depends_on(group.depends_on)
        %{group | key: group_key, steps: steps, depends_on: resolved_depends}
      end)

    triggers =
      Enum.map(pipeline.triggers, fn trigger ->
        trigger_key = Atom.to_string(trigger.name)
        resolved_depends = resolve_group_depends_on(trigger.depends_on)
        %{trigger | key: trigger_key, depends_on: resolved_depends}
      end)

    %{pipeline | groups: groups, triggers: triggers}
  end

  defp resolve_group_depends_on(nil), do: nil
  defp resolve_group_depends_on(dep) when is_atom(dep), do: Atom.to_string(dep)

  defp resolve_group_depends_on(deps) when is_list(deps),
    do: Enum.map(deps, &resolve_group_depends_on/1)

  defp resolve_step_depends_on(nil, _group), do: nil

  defp resolve_step_depends_on(dep, group) when is_atom(dep) do
    "#{group.name}-#{dep}"
  end

  defp resolve_step_depends_on({target_group, target_step}, _group)
       when is_atom(target_group) and is_atom(target_step) do
    "#{target_group}-#{target_step}"
  end

  defp resolve_step_depends_on(deps, group) when is_list(deps) do
    Enum.map(deps, &resolve_step_depends_on(&1, group))
  end

  defp resolve_step_depends_on(dep, _group) when is_binary(dep), do: dep

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
      case System.cmd("buildkite-agent", ["pipeline", "upload", tmp],
             stderr_to_stdout: true
           ) do
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
    do: String.to_existing_atom(dep) in active

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
