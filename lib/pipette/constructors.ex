defmodule Pipette.Constructors do
  @moduledoc """
  Convenience constructors for building pipeline structs at runtime.

  Use these in `extra_groups` callbacks and tests where you need to
  create `Pipette.Step` and `Pipette.Group` structs outside the DSL:

      import Pipette.Constructors

      def discover_packages(ctx, changed_files) do
        [group(:pkg_foo, label: "Foo", key: "pkg-foo", steps: [
          step(:test, label: "Test", command: "mix test", key: "pkg-foo-test")
        ])]
      end

  These are thin wrappers around `struct!/2` — identical to the
  convenience functions that existed in `Pipette.DSL` before v0.4.0.
  """

  @doc "Build a `%Pipette.Branch{}` with the given pattern."
  @spec branch(String.t(), keyword()) :: Pipette.Branch.t()
  def branch(pattern, opts \\ []),
    do: struct!(Pipette.Branch, Keyword.put(opts, :pattern, pattern))

  @doc "Build a `%Pipette.Scope{}` with the given name."
  @spec scope(atom(), keyword()) :: Pipette.Scope.t()
  def scope(name, opts \\ []),
    do: struct!(Pipette.Scope, Keyword.put(opts, :name, name))

  @doc "Build a `%Pipette.Group{}` with the given name."
  @spec group(atom(), keyword()) :: Pipette.Group.t()
  def group(name, opts \\ []),
    do: struct!(Pipette.Group, Keyword.put(opts, :name, name))

  @doc "Build a `%Pipette.Step{}` with the given name."
  @spec step(atom(), keyword()) :: Pipette.Step.t()
  def step(name, opts \\ []),
    do: struct!(Pipette.Step, Keyword.put(opts, :name, name))

  @doc "Build a `%Pipette.Trigger{}` with the given name."
  @spec trigger(atom(), keyword()) :: Pipette.Trigger.t()
  def trigger(name, opts \\ []),
    do: struct!(Pipette.Trigger, Keyword.put(opts, :name, name))
end
