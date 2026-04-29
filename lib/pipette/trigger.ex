defmodule Pipette.Trigger do
  @moduledoc """
  Buildkite trigger step that starts another pipeline.

  Trigger steps allow one pipeline to kick off a build in a separate
  Buildkite pipeline, optionally passing build parameters and
  controlling whether to wait for completion.

  ## Top-level vs nested triggers

  Triggers can be declared at two levels:

    * **Top level** — sibling to `group`. Renders as its own step on
      the Buildkite canvas. `depends_on` references must be top-level
      group names (validated at compile time).
    * **Nested inside a `group`** — listed alongside `step` entries
      under that group's `steps:` array in the emitted YAML, so the
      trigger appears as a child of the group's canvas card. Useful
      when a deploy is conceptually one logical phase that combines a
      cross-pipeline trigger and follow-up steps (e.g. tag/release).

  Field semantics are identical for both. Resolution of `depends_on`
  differs slightly: nested-trigger atoms are matched against sibling
  step names first (resolved at compile time), then against top-level
  group names (resolved at runtime). Strings always pass through as
  explicit Buildkite step keys.

  ## Fields

    * `:name` (`atom()`) — unique identifier for this trigger
    * `:label` (`String.t() | nil`) — display label in the Buildkite UI
    * `:pipeline` (`String.t()`) — slug of the Buildkite pipeline to
      trigger (e.g. `"deploy-production"`)
    * `:depends_on` — atom (sibling step or top-level group),
      string (explicit Buildkite key), or list mixing the two forms
    * `:only` (`String.t() | [String.t()] | nil`) — branch pattern(s)
      restricting when this trigger fires
    * `:build` (`map() | nil`) — build parameters to pass
      (e.g. `%{message: "Deploy", env: %{DEPLOY_ENV: "production"}}`)
    * `:async` (`boolean() | nil`) — when `true`, don't wait for the
      triggered build to complete
    * `:key` (`String.t() | nil`) — explicit Buildkite step key.
      Auto-derived as `"<group_key>-<name>"` for nested triggers and
      `"<name>"` for top-level triggers if omitted.

  ## Examples

      # Top-level trigger
      trigger :deploy do
        label ":rocket: Deploy"
        pipeline "deploy-production"
        depends_on [:api, :web]
        only "main"
        async true
      end

      # Nested trigger (inside a group)
      group :backend_deploy do
        label ":rocket: Backend Deploy"
        only "main"

        trigger :rollout do
          label ":rocket: Deploy"
          pipeline "deploy-production"
          depends_on :backend       # top-level group, resolved at runtime
          build %{commit: "${BUILDKITE_COMMIT}"}
        end

        step :tag_release,
          label: ":github: Tag & Release",
          command: "bash tag-release.sh",
          depends_on: :rollout      # sibling trigger, resolved at compile time
      end
  """

  defstruct [
    :name,
    :label,
    :pipeline,
    :depends_on,
    :only,
    :build,
    :async,
    :key,
    :__identifier__,
    :__spark_metadata__
  ]

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
