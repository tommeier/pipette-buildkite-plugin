defmodule Pipette.Pipeline do
  @moduledoc """
  Pipeline configuration struct.

  Holds branches, scopes, groups, triggers, ignore patterns, pipeline-level
  config (env, secrets, cache), and force activation rules. Used internally
  by the engine — pipeline modules are defined via `use Pipette.DSL` and
  converted to this struct by `Pipette.Info.to_pipeline/1`.

  ## Fields

    * `:branches` — list of `Pipette.Branch` policies controlling activation
      behavior on matching branches
    * `:scopes` — list of `Pipette.Scope` file-to-scope mappings
    * `:groups` — list of `Pipette.Group` step groups (the units of activation)
    * `:triggers` — list of `Pipette.Trigger` downstream pipeline triggers
    * `:ignore` — glob patterns for files that should not activate any group
      (e.g. `["docs/**", "*.md"]`). When all changed files match these
      patterns, the pipeline returns `:noop`
    * `:env` — pipeline-level environment variables (map with atom or string keys)
    * `:secrets` — list of secret names to inject into the pipeline
    * `:cache` — cache configuration (keyword list, e.g. `[paths: ["deps/"]]`)
    * `:force_activate` — map of environment variable names to groups to
      force-activate when the env var is set to `"true"` (e.g.
      `%{"FORCE_DEPLOY" => [:web, :deploy]}`)
  """

  defstruct branches: [],
            scopes: [],
            groups: [],
            triggers: [],
            ignore: [],
            env: nil,
            secrets: nil,
            cache: nil,
            force_activate: %{},
            __spark_metadata__: nil

  @type t :: %__MODULE__{
          branches: [Pipette.Branch.t()],
          scopes: [Pipette.Scope.t()],
          groups: [Pipette.Group.t()],
          triggers: [Pipette.Trigger.t()],
          ignore: [String.t()],
          env: map() | nil,
          secrets: [String.t()] | nil,
          cache: keyword() | nil,
          force_activate: %{String.t() => [atom()] | :all}
        }
end
