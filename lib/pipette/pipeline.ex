defmodule Pipette.Pipeline do
  @moduledoc """
  Pipeline configuration struct.

  Holds branches, scopes, groups, triggers, ignore patterns, pipeline-level
  config (env, secrets, cache), and force activation rules.

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

  Modules implementing this behaviour define a `pipeline/0` callback:

      defmodule MyPipeline do
        @behaviour Pipette.Pipeline

        @impl true
        def pipeline do
          %Pipette.Pipeline{...}
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
