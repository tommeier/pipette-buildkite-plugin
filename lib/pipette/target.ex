defmodule Pipette.Target do
  @moduledoc """
  Parses pipeline targets from commit messages and the `CI_TARGET` environment variable.

  Targets allow developers to manually select which groups and steps
  to run, bypassing file-based scope detection. This is useful for
  re-running specific checks or skipping irrelevant CI work.

  ## Commit Message Syntax

  Prefix the commit message with `[ci:<targets>]`:

      [ci:api] Fix login bug            # run :api group
      [ci:api/test] Fix flaky test      # run only :test step in :api
      [ci:api,web] Update shared types  # run :api and :web groups

  Group and step names must match `[a-z_]+`.

  ## `CI_TARGET` Environment Variable

  Same format as the tag content (without brackets):

      CI_TARGET=api          # run :api group
      CI_TARGET=api/test     # run only :test step in :api
      CI_TARGET=api,web      # run :api and :web groups

  Commit message targets take precedence over `CI_TARGET`.

  ## Return Format

  Parsed targets are returned as a map with two keys:

    * `:groups` — `MapSet` of group name atoms to activate
    * `:steps` — `MapSet` of `{group, step}` tuples for step-level filtering

  ## Examples

      Pipette.Target.parse_commit_message("[ci:api] Fix login bug")
      #=> {:ok, %{groups: MapSet.new([:api]), steps: MapSet.new()}}

      Pipette.Target.parse_ci_target("api/test")
      #=> {:ok, %{groups: MapSet.new([:api]), steps: MapSet.new([{:api, :test}])}}

      Pipette.Target.resolve(ctx)
      #=> {:ok, %{groups: ..., steps: ...}} or :none
  """

  @type target_set :: %{
          groups: MapSet.t(atom()),
          steps: MapSet.t({atom(), atom()})
        }

  @commit_message_regex ~r/^\[ci:([a-z_\/,]+)\]/

  @doc """
  Parse targets from a commit message.

  Looks for a `[ci:...]` prefix at the start of the message.

  ## Examples

      iex> Pipette.Target.parse_commit_message("[ci:api] Fix bug")
      {:ok, %{groups: MapSet.new([:api]), steps: MapSet.new()}}

      iex> Pipette.Target.parse_commit_message("[ci:api/test] Fix flaky")
      {:ok, %{groups: MapSet.new([:api]), steps: MapSet.new([{:api, :test}])}}

      iex> Pipette.Target.parse_commit_message("No targets here")
      :none
  """
  @spec parse_commit_message(String.t()) :: {:ok, target_set()} | :none
  def parse_commit_message(message) when is_binary(message) do
    case Regex.run(@commit_message_regex, message) do
      [_, targets_str] -> {:ok, parse_targets(targets_str)}
      nil -> :none
    end
  end

  @doc """
  Parse targets from the `CI_TARGET` environment variable value.

  ## Examples

      iex> Pipette.Target.parse_ci_target("api")
      {:ok, %{groups: MapSet.new([:api]), steps: MapSet.new()}}

      iex> Pipette.Target.parse_ci_target("api,web")
      {:ok, %{groups: MapSet.new([:api, :web]), steps: MapSet.new()}}

      iex> Pipette.Target.parse_ci_target(nil)
      :none
  """
  @spec parse_ci_target(String.t() | nil) :: {:ok, target_set()} | :none
  def parse_ci_target(nil), do: :none
  def parse_ci_target(""), do: :none

  def parse_ci_target(target_str) when is_binary(target_str) do
    {:ok, parse_targets(target_str)}
  end

  @doc """
  Resolve targets from the build context.

  Checks the commit message first, then falls back to `CI_TARGET`.
  Returns `:none` if no targets are found.

  ## Examples

      ctx = %Pipette.Context{message: "[ci:api] Fix bug", ci_target: nil}
      Pipette.Target.resolve(ctx)
      #=> {:ok, %{groups: MapSet.new([:api]), steps: MapSet.new()}}
  """
  @spec resolve(Pipette.Context.t()) :: {:ok, target_set()} | :none
  def resolve(%Pipette.Context{} = ctx) do
    case parse_commit_message(ctx.message || "") do
      {:ok, _} = result -> result
      :none -> parse_ci_target(ctx.ci_target)
    end
  end

  defp parse_targets(targets_str) do
    targets_str
    |> String.split(",", trim: true)
    |> Enum.reduce(%{groups: MapSet.new(), steps: MapSet.new()}, fn part, acc ->
      case String.split(part, "/", parts: 2) do
        [group, step] ->
          group_atom = String.to_atom(group)
          step_atom = String.to_atom(step)

          %{
            acc
            | groups: MapSet.put(acc.groups, group_atom),
              steps: MapSet.put(acc.steps, {group_atom, step_atom})
          }

        [group] ->
          %{acc | groups: MapSet.put(acc.groups, String.to_atom(group))}
      end
    end)
  end
end
