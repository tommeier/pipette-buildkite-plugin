defmodule Pipette.Dsl.Verifiers.ValidateRefs do
  @moduledoc "Validates that scope, depends_on, and force_activate references are valid."
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    entities = Spark.Dsl.Extension.get_entities(dsl_state, [:pipeline])
    scope_names = entities |> Enum.filter(&is_struct(&1, Pipette.Scope)) |> MapSet.new(& &1.name)
    group_names = entities |> Enum.filter(&is_struct(&1, Pipette.Group)) |> MapSet.new(& &1.name)

    with :ok <- validate_scope_refs(entities, scope_names),
         :ok <- validate_group_deps(entities, group_names),
         :ok <- validate_trigger_deps(entities, group_names),
         :ok <- validate_force_activate(dsl_state, group_names) do
      :ok
    end
  end

  defp validate_scope_refs(entities, scope_names) do
    entities
    |> Enum.filter(&is_struct(&1, Pipette.Group))
    |> Enum.find_value(:ok, fn %{scope: scope, name: name} ->
      if scope != nil and not MapSet.member?(scope_names, scope) do
        available = format_available(scope_names)

        {:error,
         Spark.Error.DslError.exception(
           path: [:pipeline, :group],
           message:
             "Group #{inspect(name)} references undefined scope #{inspect(scope)}. Available scopes: #{available}"
         )}
      end
    end)
  end

  # After GenerateKeys, depends_on is a string or list of strings
  defp validate_group_deps(entities, group_names) do
    entities
    |> Enum.filter(&is_struct(&1, Pipette.Group))
    |> Enum.find_value(:ok, fn %{depends_on: deps, name: name} ->
      deps
      |> List.wrap()
      |> Enum.find_value(fn dep ->
        dep_atom = to_atom(dep)

        if dep_atom != nil and not MapSet.member?(group_names, dep_atom) do
          available = format_available(group_names)

          {:error,
           Spark.Error.DslError.exception(
             path: [:pipeline, :group],
             message:
               "Group #{inspect(name)} depends on undefined group #{inspect(dep_atom)}. Available groups: #{available}"
           )}
        end
      end)
    end)
  end

  defp validate_trigger_deps(entities, group_names) do
    entities
    |> Enum.filter(&is_struct(&1, Pipette.Trigger))
    |> Enum.find_value(:ok, fn %{depends_on: deps, name: name} ->
      deps
      |> List.wrap()
      |> Enum.find_value(fn dep ->
        dep_atom = to_atom(dep)

        if dep_atom != nil and not MapSet.member?(group_names, dep_atom) do
          available = format_available(group_names)

          {:error,
           Spark.Error.DslError.exception(
             path: [:pipeline, :trigger],
             message:
               "Trigger #{inspect(name)} depends on undefined group #{inspect(dep_atom)}. Available groups: #{available}"
           )}
        end
      end)
    end)
  end

  defp validate_force_activate(dsl_state, group_names) do
    force_activate = Spark.Dsl.Extension.get_opt(dsl_state, [:pipeline], :force_activate, %{})

    force_activate
    |> Enum.find_value(:ok, fn {env_var, groups} ->
      if groups == :all do
        nil
      else
        groups
        |> List.wrap()
        |> Enum.find_value(fn group ->
          if not MapSet.member?(group_names, group) do
            available = format_available(group_names)

            {:error,
             Spark.Error.DslError.exception(
               path: [:pipeline],
               message:
                 "force_activate #{inspect(env_var)} references undefined group #{inspect(group)}. Available groups: #{available}"
             )}
          end
        end)
      end
    end)
  end

  defp to_atom(dep) when is_atom(dep), do: dep
  defp to_atom(dep) when is_binary(dep), do: String.to_existing_atom(dep)
  defp to_atom(_), do: nil

  defp format_available(names) do
    names |> MapSet.to_list() |> Enum.map_join(", ", &inspect/1)
  end
end
