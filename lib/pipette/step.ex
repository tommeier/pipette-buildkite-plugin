defmodule Pipette.Step do
  @moduledoc """
  Buildkite command step.

  Represents a single command step within a group. Steps map directly
  to Buildkite command steps and support all standard attributes like
  retries, timeouts, concurrency controls, and plugins.

  ## Fields

    * `:name` (`atom()`) — unique identifier within the parent group
    * `:label` (`String.t() | nil`) — display label in Buildkite UI
    * `:command` (`String.t() | [String.t()] | nil`) — shell command(s) to run
    * `:env` (`map() | nil`) — environment variables for this step
    * `:agents` (`map() | nil`) — agent targeting rules
    * `:plugins` (`list() | nil`) — Buildkite plugins to apply
    * `:secrets` (`[String.t()] | nil`) — secret names to inject
    * `:depends_on` — step-level dependency (atom, tuple, or list)
    * `:timeout_in_minutes` (`pos_integer() | nil`) — step timeout
    * `:concurrency` (`pos_integer() | nil`) — max concurrent jobs
    * `:concurrency_group` (`String.t() | nil`) — concurrency group name
    * `:concurrency_method` (`:ordered | :eager | nil`) — concurrency method
    * `:soft_fail` (`boolean() | list() | nil`) — soft fail configuration
    * `:retry` (`map() | nil`) — retry configuration
    * `:artifact_paths` (`String.t() | [String.t()] | nil`) — artifact paths
    * `:parallelism` (`pos_integer() | nil`) — parallel job count
    * `:priority` (`integer() | nil`) — job priority
    * `:skip` (`boolean() | String.t() | nil`) — skip condition
    * `:cancel_on_build_failing` (`boolean() | nil`) — cancel if build fails
    * `:allow_dependency_failure` (`boolean() | nil`) — run even if deps fail
    * `:branches` (`String.t() | nil`) — branch filter
    * `:if_condition` (`String.t() | nil`) — conditional expression
    * `:matrix` (`list() | map() | nil`) — matrix build configuration
    * `:key` (`String.t() | nil`) — explicit Buildkite step key

  ## Example

      %Pipette.Step{
        name: :test,
        label: ":elixir: Test",
        command: "mix test",
        timeout_in_minutes: 15,
        retry: %{automatic: [%{exit_status: -1, limit: 2}]}
      }
  """

  defstruct [
    :name,
    :label,
    :command,
    :env,
    :agents,
    :plugins,
    :secrets,
    :depends_on,
    :timeout_in_minutes,
    :concurrency,
    :concurrency_group,
    :concurrency_method,
    :soft_fail,
    :retry,
    :artifact_paths,
    :parallelism,
    :priority,
    :skip,
    :cancel_on_build_failing,
    :allow_dependency_failure,
    :branches,
    :if_condition,
    :matrix,
    :key,
    :__spark_metadata__
  ]

  @type t :: %__MODULE__{
          name: atom(),
          label: String.t() | nil,
          command: String.t() | [String.t()] | nil,
          env: map() | nil,
          agents: map() | nil,
          plugins: list() | nil,
          secrets: [String.t()] | nil,
          depends_on:
            atom()
            | {atom(), atom()}
            | [atom() | {atom(), atom()}]
            | String.t()
            | [String.t()]
            | nil,
          timeout_in_minutes: pos_integer() | nil,
          concurrency: pos_integer() | nil,
          concurrency_group: String.t() | nil,
          concurrency_method: :ordered | :eager | nil,
          soft_fail: boolean() | list() | nil,
          retry: map() | nil,
          artifact_paths: String.t() | [String.t()] | nil,
          parallelism: pos_integer() | nil,
          priority: integer() | nil,
          skip: boolean() | String.t() | nil,
          cancel_on_build_failing: boolean() | nil,
          allow_dependency_failure: boolean() | nil,
          branches: String.t() | nil,
          if_condition: String.t() | nil,
          matrix: list() | map() | nil,
          key: String.t() | nil
        }
end
