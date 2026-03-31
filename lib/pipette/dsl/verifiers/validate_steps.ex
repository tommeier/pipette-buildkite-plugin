defmodule Pipette.Dsl.Verifiers.ValidateSteps do
  @moduledoc "Validates step configuration constraints."
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    groups =
      dsl_state
      |> Spark.Dsl.Extension.get_entities([:pipeline])
      |> Enum.filter(&is_struct(&1, Pipette.Group))

    Enum.find_value(groups, :ok, fn group ->
      Enum.find_value(group.steps, fn step ->
        unless step.label do
          {:error,
           Spark.Error.DslError.exception(
             path: [:pipeline, :group, :step],
             message:
               "Step #{inspect(step.name)} in group #{inspect(group.name)} is missing a label"
           )}
        end
      end)
    end)
  end
end
