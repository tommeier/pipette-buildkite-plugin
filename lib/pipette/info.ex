defmodule Pipette.Info do
  @moduledoc """
  Accessor functions for reading pipeline configuration from Spark DSL modules.

  These functions extract entities and options from modules that
  `use Pipette.DSL`:

      branches  = Pipette.Info.branches(MyApp.Pipeline)
      groups    = Pipette.Info.groups(MyApp.Pipeline)
      pipeline  = Pipette.Info.to_pipeline(MyApp.Pipeline)
  """

  @doc "Returns all `%Pipette.Branch{}` entities."
  @spec branches(module()) :: [Pipette.Branch.t()]
  def branches(module) do
    module
    |> entities()
    |> Enum.filter(&is_struct(&1, Pipette.Branch))
  end

  @doc "Returns all `%Pipette.Scope{}` entities."
  @spec scopes(module()) :: [Pipette.Scope.t()]
  def scopes(module) do
    module
    |> entities()
    |> Enum.filter(&is_struct(&1, Pipette.Scope))
  end

  @doc "Returns all `%Pipette.Group{}` entities."
  @spec groups(module()) :: [Pipette.Group.t()]
  def groups(module) do
    module
    |> entities()
    |> Enum.filter(&is_struct(&1, Pipette.Group))
  end

  @doc "Returns all `%Pipette.Trigger{}` entities."
  @spec triggers(module()) :: [Pipette.Trigger.t()]
  def triggers(module) do
    module
    |> entities()
    |> Enum.filter(&is_struct(&1, Pipette.Trigger))
  end

  @doc "Returns the pipeline-level `:env` map."
  @spec env(module()) :: map()
  def env(module), do: get_opt(module, :env, %{})

  @doc "Returns the pipeline-level `:secrets` list."
  @spec secrets(module()) :: [String.t()]
  def secrets(module), do: get_opt(module, :secrets, [])

  @doc "Returns the pipeline-level `:cache` config."
  @spec cache(module()) :: keyword() | nil
  def cache(module), do: get_opt(module, :cache, nil)

  @doc "Returns the pipeline-level `:ignore` patterns."
  @spec ignore(module()) :: [String.t()]
  def ignore(module), do: get_opt(module, :ignore, [])

  @doc "Returns the pipeline-level `:force_activate` map."
  @spec force_activate(module()) :: map()
  def force_activate(module), do: get_opt(module, :force_activate, %{})

  @doc """
  Assembles a `%Pipette.Pipeline{}` struct from the Spark DSL data
  on the given module.
  """
  @spec to_pipeline(module()) :: Pipette.Pipeline.t()
  def to_pipeline(module) do
    %Pipette.Pipeline{
      branches: branches(module),
      scopes: scopes(module),
      groups: groups(module),
      triggers: triggers(module),
      env: env(module),
      secrets: secrets(module),
      cache: cache(module),
      ignore: ignore(module),
      force_activate: force_activate(module)
    }
  end

  defp entities(module) do
    Spark.Dsl.Extension.get_entities(module, [:pipeline])
  end

  defp get_opt(module, key, default) do
    Spark.Dsl.Extension.get_opt(module, [:pipeline], key, default)
  end
end
