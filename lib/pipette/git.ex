defmodule Pipette.Git do
  @moduledoc """
  Git change detection and glob matching for pipeline activation.

  Provides utilities to determine which files changed between commits,
  match file paths against glob patterns, and resolve which scopes
  should be activated based on changed files.

  ## Example

      # Determine the base commit for diff comparison
      base = Pipette.Git.base_commit(ctx)
      {:ok, files} = Pipette.Git.changed_files(base)

      # Check which scopes are affected
      fired = Pipette.Git.fired_scopes(scopes, files)

      # Check if a file matches a glob pattern
      Pipette.Git.matches_glob?("apps/api/lib/user.ex", "apps/api/**")
      #=> true
  """

  alias Pipette.Context

  @spec matches_glob?(String.t(), String.t()) :: boolean()
  def matches_glob?(file_path, pattern) do
    regex = glob_to_regex(pattern)

    if String.contains?(pattern, "/") do
      Regex.match?(regex, file_path)
    else
      Regex.match?(regex, file_path) or Regex.match?(regex, Path.basename(file_path))
    end
  end

  @spec base_commit(Context.t()) :: String.t()
  def base_commit(%Context{} = ctx) do
    cond do
      ctx.pull_request_base_branch != nil ->
        "origin/#{ctx.pull_request_base_branch}"

      ctx.branch != ctx.default_branch ->
        "origin/#{ctx.default_branch}"

      true ->
        "HEAD~1"
    end
  end

  @spec changed_files(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, String.t()}
  def changed_files(base, opts \\ []) do
    runner = Keyword.get(opts, :runner, &default_runner/1)

    case runner.(base) do
      {:ok, output} ->
        files =
          output
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        {:ok, files}

      {:error, _} = error ->
        error
    end
  end

  defp default_runner(base) do
    case System.cmd("git", ["diff", "--name-only", base], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _code} -> {:error, "git diff failed: #{output}"}
    end
  end

  @spec fired_scopes([Pipette.Scope.t()], [String.t()]) :: MapSet.t(atom())
  def fired_scopes(scopes, changed_files) do
    Enum.reduce(scopes, MapSet.new(), fn scope, fired ->
      if scope_matches?(scope, changed_files) do
        MapSet.put(fired, scope.name)
      else
        fired
      end
    end)
  end

  defp scope_matches?(scope, changed_files) do
    Enum.any?(changed_files, fn file ->
      matches_any?(file, scope.files || []) and not matches_any?(file, scope.exclude || [])
    end)
  end

  defp matches_any?(file, patterns) do
    Enum.any?(patterns, &matches_glob?(file, &1))
  end

  @spec all_ignored?([String.t()], [String.t()]) :: boolean()
  def all_ignored?([], _ignore_patterns), do: false

  def all_ignored?(changed_files, ignore_patterns) do
    Enum.all?(changed_files, fn file ->
      matches_any?(file, ignore_patterns)
    end)
  end

  defp glob_to_regex(pattern) do
    regex_str =
      pattern
      |> String.replace("**", "\0DOUBLESTAR\0")
      |> String.replace("*", "\0STAR\0")
      |> Regex.escape()
      |> String.replace("\0DOUBLESTAR\0", ".*")
      |> String.replace("\0STAR\0", "[^/]*")

    Regex.compile!("^#{regex_str}$")
  end
end
