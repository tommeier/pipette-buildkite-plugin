defmodule Pipette.Branch do
  @moduledoc """
  Branch policy for activation.

  Controls which groups are activated on matching branches and which
  pipeline features are disabled.

  ## Fields

    * `:pattern` (`String.t()`) — branch name or glob pattern to match
      (e.g. `"main"`, `"release/*"`)
    * `:scopes` (`:all | [atom()] | nil`) — which scopes to activate.
      `:all` bypasses file-based targeting and activates every group.
      A list restricts activation to the named scopes. `nil` uses
      default file-based targeting.
    * `:disable` (`[atom()] | nil`) — pipeline features to turn off for
      this branch (e.g. `[:targeting]` to skip scope-based filtering)

  ## Example

      %Pipette.Branch{
        pattern: "main",
        scopes: :all,
        disable: [:targeting]
      }

      %Pipette.Branch{
        pattern: "release/*",
        scopes: [:api, :web],
        disable: nil
      }
  """

  defstruct [:pattern, :scopes, :disable, :name, :__identifier__, :__spark_metadata__]

  @type t :: %__MODULE__{
          pattern: String.t(),
          scopes: :all | [atom()] | nil,
          disable: [atom()] | nil
        }
end
