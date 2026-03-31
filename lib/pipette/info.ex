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
  def branches(module) do
    module
    |> entities()
    |> Enum.filter(&is_struct(&1, Pipette.Branch))
  end

  @doc "Returns all `%Pipette.Scope{}` entities."
  def scopes(module) do
    module
    |> entities()
    |> Enum.filter(&is_struct(&1, Pipette.Scope))
  end

  @doc "Returns all `%Pipette.Group{}` entities."
  def groups(module) do
    module
    |> entities()
    |> Enum.filter(&is_struct(&1, Pipette.Group))
  end

  @doc "Returns all `%Pipette.Trigger{}` entities."
  def triggers(module) do
    module
    |> entities()
    |> Enum.filter(&is_struct(&1, Pipette.Trigger))
  end

  @doc "Returns the pipeline-level `:env` map."
  def env(module), do: get_opt(module, :env, %{})

  @doc "Returns the pipeline-level `:secrets` list."
  def secrets(module), do: get_opt(module, :secrets, [])

  @doc "Returns the pipeline-level `:cache` config."
  def cache(module), do: get_opt(module, :cache, nil)

  @doc "Returns the pipeline-level `:ignore` patterns."
  def ignore(module), do: get_opt(module, :ignore, [])

  @doc "Returns the pipeline-level `:force_activate` map."
  def force_activate(module), do: get_opt(module, :force_activate, %{})

  @doc """
  Assembles a `%Pipette.Pipeline{}` struct from the Spark DSL data
  on the given module.
  """
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
