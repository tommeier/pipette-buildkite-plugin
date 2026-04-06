defmodule Pipette.Group do
  @moduledoc """
  Group of Buildkite steps.

  Groups bundle related steps under a shared label, scope binding, and
  dependency graph. A group is activated when its bound scope matches
  changed files (or when branch policy overrides targeting).

  ## Fields

    * `:name` (`atom()`) — unique identifier for this group
      (e.g. `:api`, `:web`, `:deploy`)
    * `:label` (`String.t() | nil`) — display label in the Buildkite UI
      (e.g. `":elixir: API"`)
    * `:scope` (`atom() | nil`) — scope that activates this group. `nil`
      means the group always runs. Set via the nested `scope` entity
      in the DSL, or directly when constructing structs.
    * `:ignore_global_scope` (`boolean()`) — when `true`, this group is
      excluded from `scopes: :all` branch policy activation and falls
      back to file-based scope detection. Defaults to `false`. Set via
      `scope(:name, ignore_global: true)` in the DSL.
    * `:depends_on` (`atom() | [atom()] | nil`) — other group name(s)
      that must complete before this group starts
    * `:only` (`String.t() | [String.t()] | nil`) — branch pattern(s)
      restricting this group to specific branches
    * `:key` (`String.t() | nil`) — explicit Buildkite group key
      (auto-derived from `:name` if omitted)
    * `:steps` (`[Pipette.Step.t()]`) — ordered list of command steps
      in this group

  ## Example

      %Pipette.Group{
        name: :api,
        label: ":elixir: API",
        scope: :api_code,
        depends_on: :lint,
        steps: [
          %Pipette.Step{name: :test, command: "mix test"}
        ]
      }
  """

  defstruct [
    :name,
    :label,
    :scope,
    :depends_on,
    :only,
    :key,
    :__identifier__,
    :__spark_metadata__,
    ignore_global_scope: false,
    scope_refs: [],
    steps: []
  ]

  @type t :: %__MODULE__{
          name: atom(),
          label: String.t() | nil,
          scope: atom() | nil,
          ignore_global_scope: boolean(),
          depends_on: atom() | [atom()] | nil,
          only: String.t() | [String.t()] | nil,
          key: String.t() | nil,
          scope_refs: [Pipette.ScopeRef.t()],
          steps: [Pipette.Step.t()]
        }
end
