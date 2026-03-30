defmodule Pipette.Target do
  @moduledoc """
  Parses pipeline targets from commit messages and CI_TARGET environment variable.

  Targets allow developers to manually select which groups and steps
  to run, bypassing file-based scope detection.

  ## Commit Message Syntax

      [ci:api] Fix login bug
      [ci:api/test] Fix flaky test
      [ci:api,web] Update shared types

  ## CI_TARGET Syntax

  Same format as the tag content: `api`, `api/test`, `api,web`

  ## Example

      Pipette.Target.parse_commit_message("[ci:api] Fix login bug")
      #=> {:ok, %{groups: MapSet.new([:api]), steps: MapSet.new()}}

      Pipette.Target.parse_ci_target("api/test")
      #=> {:ok, %{groups: MapSet.new([:api]), steps: MapSet.new([{:api, :test}])}}
  """

  @type target_set :: %{
          groups: MapSet.t(atom()),
          steps: MapSet.t({atom(), atom()})
        }

  @commit_message_regex ~r/^\[ci:([a-z_\/,]+)\]/

  @spec parse_commit_message(String.t()) :: {:ok, target_set()} | :none
  def parse_commit_message(message) when is_binary(message) do
    case Regex.run(@commit_message_regex, message) do
      [_, targets_str] -> {:ok, parse_targets(targets_str)}
      nil -> :none
    end
  end

  @spec parse_ci_target(String.t() | nil) :: {:ok, target_set()} | :none
  def parse_ci_target(nil), do: :none
  def parse_ci_target(""), do: :none

  def parse_ci_target(target_str) when is_binary(target_str) do
    {:ok, parse_targets(target_str)}
  end

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
