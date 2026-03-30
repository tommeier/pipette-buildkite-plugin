defmodule Pipette.Pipeline do
  @moduledoc """
  Pipeline configuration struct and behaviour.

  Holds branches, scopes, groups, triggers, ignore patterns, pipeline-level
  config (env, secrets, cache), and force activation rules. This is the
  top-level struct that defines your entire Buildkite pipeline.

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

  ## Example

      %Pipette.Pipeline{
        branches: [
          %Pipette.Branch{pattern: "main", scopes: :all, disable: [:targeting]}
        ],
        scopes: [
          %Pipette.Scope{name: :api_code, files: ["apps/api/**"]}
        ],
        groups: [
          %Pipette.Group{name: :api, label: ":elixir: API", scope: :api_code, steps: [...]}
        ],
        triggers: [],
        ignore: ["docs/**", "*.md"],
        env: %{LANG: "C.UTF-8"},
        force_activate: %{
          "FORCE_DEPLOY" => [:web, :deploy]
        }
      }

  ## Behaviour

  Modules implementing this behaviour define a `pipeline/0` callback that
  returns a `%Pipette.Pipeline{}` struct:

      defmodule MyPipeline do
        @behaviour Pipette.Pipeline

        @impl true
        def pipeline do
          %Pipette.Pipeline{
            scopes: [...],
            groups: [...],
            ignore: ["docs/**"]
          }
        end
      end
  """

  defstruct branches: [],
            scopes: [],
            groups: [],
            triggers: [],
            ignore: [],
            env: nil,
            secrets: nil,
            cache: nil,
            force_activate: %{}

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

  @callback pipeline() :: t()
end
