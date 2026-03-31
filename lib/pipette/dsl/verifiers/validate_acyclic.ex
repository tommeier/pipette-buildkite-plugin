defmodule Pipette.Dsl.Verifiers.ValidateAcyclic do
  @moduledoc "Validates that group dependencies form a DAG (no cycles)."
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    groups =
      dsl_state
      |> Spark.Dsl.Extension.get_entities([:pipeline])
      |> Enum.filter(&is_struct(&1, Pipette.Group))

    graph = Pipette.Graph.from_groups(groups)

    case Pipette.Graph.find_cycle(graph) do
      nil ->
        :ok

      cycle ->
        formatted = cycle |> Enum.map_join(" -> ", &inspect/1)

        {:error,
         Spark.Error.DslError.exception(
           path: [:pipeline],
           message: "Dependency cycle detected: #{formatted}"
         )}
    end
  end
end
