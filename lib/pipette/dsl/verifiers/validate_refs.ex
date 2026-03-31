defmodule Pipette.Dsl.Verifiers.ValidateRefs do
  @moduledoc false
  use Spark.Dsl.Verifier
  def verify(_dsl_state), do: :ok
end
