defmodule Pipette.ScopeRef do
  @moduledoc """
  A reference to a named scope within a group.

  Created by the `scope/1,2` call inside a `group` block:

      group :deploy do
        scope(:web_code)                          # simple binding
        scope(:web_code, ignore_global: true)     # opt out of scopes: :all
      end

  ## Fields

    * `:name` (`atom()`) — the scope name to bind to (must match a
      top-level `scope` definition)
    * `:ignore_global` (`boolean()`) — when `true`, the parent group
      is excluded from `scopes: :all` branch policy activation and
      falls back to file-based scope detection. Defaults to `false`.
  """

  defstruct [:name, :__identifier__, :__spark_metadata__, ignore_global: false]

  @type t :: %__MODULE__{
          name: atom(),
          ignore_global: boolean()
        }
end
