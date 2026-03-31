defmodule Pipette.Trigger do
  @moduledoc """
  Buildkite trigger step that starts another pipeline.

  Trigger steps allow one pipeline to kick off a build in a separate
  Buildkite pipeline, optionally passing build parameters and
  controlling whether to wait for completion.

  ## Fields

    * `:name` (`atom()`) — unique identifier for this trigger
    * `:label` (`String.t() | nil`) — display label in the Buildkite UI
    * `:pipeline` (`String.t()`) — slug of the Buildkite pipeline to
      trigger (e.g. `"deploy-production"`)
    * `:depends_on` (`atom() | [atom()] | nil`) — group(s) that must
      complete before triggering
    * `:only` (`String.t() | [String.t()] | nil`) — branch pattern(s)
      restricting when this trigger fires
    * `:build` (`map() | nil`) — build parameters to pass
      (e.g. `%{message: "Deploy", env: %{DEPLOY_ENV: "production"}}`)
    * `:async` (`boolean() | nil`) — when `true`, don't wait for the
      triggered build to complete
    * `:key` (`String.t() | nil`) — explicit Buildkite step key

  ## Example

      %Pipette.Trigger{
        name: :deploy,
        label: ":rocket: Deploy",
        pipeline: "deploy-production",
        depends_on: [:api, :web],
        only: "main",
        async: true
      }
  """

  defstruct [:name, :label, :pipeline, :depends_on, :only, :build, :async, :key, :__spark_metadata__]

  @type t :: %__MODULE__{
          name: atom(),
          label: String.t() | nil,
          pipeline: String.t(),
          depends_on: atom() | [atom()] | nil,
          only: String.t() | [String.t()] | nil,
          build: map() | nil,
          async: boolean() | nil,
          key: String.t() | nil
        }
end
