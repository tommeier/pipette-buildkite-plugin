defmodule Pipette.Dsl.Extension do
  @moduledoc false

  @step %Spark.Dsl.Entity{
    name: :step,
    describe: "A Buildkite command step within a group.",
    target: Pipette.Step,
    args: [:name],
    identifier: :name,
    schema: [
      name: [type: :atom, required: true, doc: "Unique step identifier within the group."],
      label: [type: :string, doc: "Display label in Buildkite UI (supports emoji)."],
      command: [
        type: {:or, [:string, {:list, :string}]},
        doc: "Shell command(s) to execute. Omit for plugin-only steps."
      ],
      timeout_in_minutes: [type: :pos_integer, doc: "Step timeout in minutes."],
      soft_fail: [type: :any, doc: "Soft fail config (`true`, or list of exit code rules)."],
      retry: [type: :map, doc: "Retry config."],
      parallelism: [type: :pos_integer, doc: "Number of parallel jobs."],
      concurrency: [type: :pos_integer, doc: "Max concurrent jobs."],
      concurrency_group: [type: :string, doc: "Concurrency group key."],
      concurrency_method: [type: {:in, [:ordered, :eager]}, doc: "Concurrency method."],
      artifact_paths: [type: {:or, [:string, {:list, :string}]}, doc: "Artifact upload paths."],
      plugins: [type: {:list, :any}, doc: "Buildkite plugins list."],
      agents: [type: :map, doc: "Agent targeting."],
      env: [type: :map, doc: "Step-level environment variables."],
      secrets: [type: {:list, :string}, doc: "Step-level secrets."],
      depends_on: [type: :any, doc: "Step deps: atom, `{group, step}` tuple, or list."],
      only: [type: {:or, [:string, {:list, :string}]}, doc: "Branch restriction for this step."],
      key: [type: :string, doc: "Override auto-generated Buildkite key."],
      if_condition: [type: :string, doc: "Buildkite conditional (maps to `if` in YAML)."],
      allow_dependency_failure: [type: :boolean, doc: "Run even if dependencies failed."],
      skip: [type: {:or, [:boolean, :string]}, doc: "Skip this step."],
      priority: [type: :integer, doc: "Job priority."],
      cancel_on_build_failing: [type: :boolean, doc: "Cancel if build is failing."],
      branches: [type: :string, doc: "Branch filter expression."],
      matrix: [type: :any, doc: "Matrix build configuration."],
      notify: [type: {:list, :map}, doc: "Notification rules."]
    ]
  }

  @scope_ref %Spark.Dsl.Entity{
    name: :scope,
    describe: "Binds this group to a named scope for activation control.",
    target: Pipette.ScopeRef,
    args: [:name],
    identifier: :name,
    schema: [
      name: [type: :atom, required: true, doc: "Scope name to bind to."],
      ignore_global: [
        type: :boolean,
        default: false,
        doc:
          "When true, this group is excluded from `scopes: :all` branch policy activation and falls back to file-based scope detection."
      ]
    ]
  }

  @group %Spark.Dsl.Entity{
    name: :group,
    describe: "A group of related CI steps that share activation scope.",
    target: Pipette.Group,
    args: [:name],
    identifier: :name,
    entities: [steps: [@step], scope_refs: [@scope_ref]],
    schema: [
      name: [type: :atom, required: true, doc: "Unique group identifier."],
      label: [type: :string, doc: "Display label in Buildkite UI."],
      depends_on: [
        type: {:or, [:atom, {:list, :atom}]},
        doc: "Group(s) that must complete first."
      ],
      only: [
        type: {:or, [:string, {:list, :string}]},
        doc: "Branch pattern(s) restricting this group."
      ],
      key: [type: :string, doc: "Override auto-generated Buildkite key."]
    ]
  }

  @branch %Spark.Dsl.Entity{
    name: :branch,
    describe: "A branch policy controlling activation behavior on matching branches.",
    target: Pipette.Branch,
    args: [:pattern],
    identifier: :pattern,
    transform: {__MODULE__, :set_branch_name, []},
    schema: [
      pattern: [type: :string, required: true, doc: "Branch name or glob pattern."],
      name: [type: :string, doc: false, hide: [:docs]],
      scopes: [
        type: {:or, [{:in, [:all]}, {:list, :atom}]},
        doc: "`:all` activates every group, or a list of scope names."
      ],
      disable: [
        type: {:list, {:in, [:targeting]}},
        default: [],
        doc: "Features to disable on this branch."
      ]
    ]
  }

  @scope %Spark.Dsl.Entity{
    name: :scope,
    describe: "Maps file glob patterns to a named scope for change detection.",
    target: Pipette.Scope,
    args: [:name],
    identifier: :name,
    schema: [
      name: [type: :atom, required: true, doc: "Unique scope identifier."],
      files: [
        type: {:list, :string},
        required: true,
        doc: "Glob patterns that trigger this scope."
      ],
      exclude: [type: {:list, :string}, default: [], doc: "Glob patterns to exclude."],
      activates: [
        type: {:in, [:all]},
        doc: "Set to `:all` to activate all groups when this scope fires."
      ]
    ]
  }

  @trigger %Spark.Dsl.Entity{
    name: :trigger,
    describe: "Triggers a downstream Buildkite pipeline.",
    target: Pipette.Trigger,
    args: [:name],
    identifier: :name,
    schema: [
      name: [type: :atom, required: true, doc: "Unique trigger identifier."],
      label: [type: :string, doc: "Display label in Buildkite UI."],
      pipeline: [type: :string, required: true, doc: "Downstream pipeline slug."],
      depends_on: [
        type: {:or, [:atom, {:list, :atom}]},
        doc: "Group(s) that must complete before triggering."
      ],
      only: [type: {:or, [:string, {:list, :string}]}, doc: "Branch restriction."],
      build: [type: :map, doc: "Build parameters for the triggered pipeline."],
      async: [type: :boolean, default: false, doc: "Fire and forget."],
      key: [type: :string, doc: "Override auto-generated Buildkite key."]
    ]
  }

  @doc false
  def set_branch_name(%Pipette.Branch{pattern: pattern} = branch) do
    {:ok, %{branch | name: pattern}}
  end

  @pipeline_section %Spark.Dsl.Section{
    name: :pipeline,
    top_level?: true,
    describe: "Declarative Buildkite pipeline configuration.",
    entities: [@branch, @scope, @group, @trigger],
    schema: [
      env: [type: :map, default: %{}, doc: "Pipeline-level environment variables."],
      secrets: [type: {:list, :string}, default: [], doc: "Pipeline-level secrets."],
      cache: [type: :keyword_list, doc: "Cache configuration."],
      ignore: [type: {:list, :string}, default: [], doc: "File patterns that never activate CI."],
      force_activate: [
        type: {:map, :string, {:or, [{:list, :atom}, {:in, [:all]}]}},
        default: %{},
        doc: "Env var -> group list for forced activation."
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@pipeline_section],
    transformers: [Pipette.Dsl.Transformers.GenerateKeys],
    verifiers: [
      Pipette.Dsl.Verifiers.ValidateRefs,
      Pipette.Dsl.Verifiers.ValidateAcyclic,
      Pipette.Dsl.Verifiers.ValidateSteps
    ]
end
