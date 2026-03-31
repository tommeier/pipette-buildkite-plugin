defmodule Pipette.Dsl.Transformers.GenerateKeys do
  @moduledoc false
  use Spark.Dsl.Transformer
  def transform(dsl_state), do: {:ok, dsl_state}
end
