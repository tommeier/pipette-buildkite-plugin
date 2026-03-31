defmodule Pipette.DSL do
  @moduledoc """
  Declarative Buildkite pipeline definition DSL.

  `use Pipette.DSL` in a module to define a pipeline with top-level
  entities — branches, scopes, groups, steps, and triggers:

      defmodule MyApp.Pipeline do
        use Pipette.DSL

        branch "main", scopes: :all, disable: [:targeting]

        scope :api_code, files: ["apps/api/**"]

        group :api do
          label ":elixir: API"
          scope :api_code
          step :test, label: "Test", command: "mix test"
        end
      end
  """

  use Spark.Dsl,
    default_extensions: [extensions: [Pipette.Dsl.Extension]]
end
