defmodule Pipette.DSL do
  @moduledoc """
  Convenience constructors for pipeline definitions.

  Import this module to define pipelines with a clean, concise syntax:

      defmodule MyPipeline do
        @behaviour Pipette.Pipeline
        import Pipette.DSL

        @impl true
        def pipeline do
          pipeline(
            branches: [
              branch("main", scopes: :all, disable: [:targeting])
            ],
            scopes: [
              scope(:api_code, files: ["apps/api/**", "mix.exs"])
            ],
            groups: [
              group(:api, label: ":elixir: API", scope: :api_code, steps: [
                step(:test, label: "Test", command: "mix test", timeout_in_minutes: 15),
                step(:lint, label: "Lint", command: "mix credo", timeout_in_minutes: 10)
              ])
            ],
            ignore: ["docs/**", "*.md"]
          )
        end
      end

  Each function takes a name (or pattern) as the first argument and options as
  a keyword list. Unknown keys raise `KeyError` via `struct!/2`.

  These are plain functions, not macros — no metaprogramming, no compile-time magic.
  You can also use the raw `%Pipette.Step{}` structs directly if you prefer.
  """

  @doc "Build a `%Pipette.Pipeline{}` from keyword options."
  @spec pipeline(keyword()) :: Pipette.Pipeline.t()
  def pipeline(opts \\ []), do: struct!(Pipette.Pipeline, opts)

  @doc "Build a `%Pipette.Branch{}` with the given pattern."
  @spec branch(String.t(), keyword()) :: Pipette.Branch.t()
  def branch(pattern, opts \\ []),
    do: struct!(Pipette.Branch, Keyword.put(opts, :pattern, pattern))

  @doc "Build a `%Pipette.Scope{}` with the given name."
  @spec scope(atom(), keyword()) :: Pipette.Scope.t()
  def scope(name, opts \\ []), do: struct!(Pipette.Scope, Keyword.put(opts, :name, name))

  @doc "Build a `%Pipette.Group{}` with the given name."
  @spec group(atom(), keyword()) :: Pipette.Group.t()
  def group(name, opts \\ []), do: struct!(Pipette.Group, Keyword.put(opts, :name, name))

  @doc "Build a `%Pipette.Step{}` with the given name."
  @spec step(atom(), keyword()) :: Pipette.Step.t()
  def step(name, opts \\ []), do: struct!(Pipette.Step, Keyword.put(opts, :name, name))

  @doc "Build a `%Pipette.Trigger{}` with the given name."
  @spec trigger(atom(), keyword()) :: Pipette.Trigger.t()
  def trigger(name, opts \\ []), do: struct!(Pipette.Trigger, Keyword.put(opts, :name, name))
end
