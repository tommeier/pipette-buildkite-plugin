defmodule Pipette.Dsl.Verifiers.ValidateAcyclic do
  @moduledoc false
  use Spark.Dsl.Verifier
  def verify(_dsl_state), do: :ok
end
