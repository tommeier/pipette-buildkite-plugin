defmodule Pipette.Dsl.Verifiers.ValidateSteps do
  @moduledoc "Validates step and trigger configuration constraints inside groups."
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    groups =
      dsl_state
      |> Spark.Dsl.Extension.get_entities([:pipeline])
      |> Enum.filter(&is_struct(&1, Pipette.Group))

    Enum.find_value(groups, :ok, fn group ->
      Enum.find_value(group.steps, &validate_child(&1, group))
    end)
  end

  defp validate_child(%Pipette.Step{} = step, group) do
    cond do
      !step.label ->
        {:error,
         Spark.Error.DslError.exception(
           path: [:pipeline, :group, :step],
           message:
             "Step #{inspect(step.name)} in group #{inspect(group.name)} is missing a label"
         )}

      step.concurrency_group && !step.concurrency ->
        {:error,
         Spark.Error.DslError.exception(
           path: [:pipeline, :group, :step],
           message:
             "Step #{inspect(step.name)} in group #{inspect(group.name)} has concurrency_group without concurrency"
         )}

      true ->
        nil
    end
  end

  # Triggers carry their own schema-level `required: true` constraints
  # (`pipeline`, `name`); no per-trigger verifier checks today.
  defp validate_child(%Pipette.Trigger{}, _group), do: nil
end
