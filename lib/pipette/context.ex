defmodule Pipette.Context do
  @moduledoc """
  Runtime context built from Buildkite environment variables.

  Captures the CI environment (branch, commit, PR info) into a struct
  that other modules use for decision-making.

  ## Example

      ctx = Pipette.Context.from_env(%{
        "BUILDKITE_BRANCH" => "feature/login",
        "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
        "BUILDKITE_COMMIT" => "abc123",
        "BUILDKITE_MESSAGE" => "[ci:api] Fix login bug",
        "BUILDKITE_PULL_REQUEST_BASE_BRANCH" => "main"
      })

      ctx.branch            #=> "feature/login"
      ctx.is_default_branch  #=> false
  """

  defstruct [
    :branch,
    :default_branch,
    :commit,
    :message,
    :pull_request_base_branch,
    :ci_target,
    is_default_branch: false
  ]

  @type t :: %__MODULE__{
          branch: String.t(),
          default_branch: String.t(),
          commit: String.t(),
          message: String.t(),
          pull_request_base_branch: String.t() | nil,
          ci_target: String.t() | nil,
          is_default_branch: boolean()
        }

  @spec from_env(%{String.t() => String.t()}) :: t()
  def from_env(env) when is_map(env) do
    branch = Map.get(env, "BUILDKITE_BRANCH", "")
    default = Map.get(env, "BUILDKITE_PIPELINE_DEFAULT_BRANCH", "main")

    %__MODULE__{
      branch: branch,
      default_branch: default,
      commit: Map.get(env, "BUILDKITE_COMMIT", "HEAD"),
      message: Map.get(env, "BUILDKITE_MESSAGE", ""),
      pull_request_base_branch: non_empty(Map.get(env, "BUILDKITE_PULL_REQUEST_BASE_BRANCH")),
      ci_target: non_empty(Map.get(env, "CI_TARGET")),
      is_default_branch: branch == default
    }
  end

  @spec from_system_env() :: t()
  def from_system_env do
    from_env(System.get_env())
  end

  defp non_empty(nil), do: nil
  defp non_empty(""), do: nil
  # Buildkite sets some env vars to the string "false" instead of unsetting them
  # (e.g. BUILDKITE_PULL_REQUEST_BASE_BRANCH when there's no PR).
  defp non_empty("false"), do: nil
  defp non_empty(val), do: val
end
