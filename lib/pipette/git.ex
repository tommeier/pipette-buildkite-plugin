defmodule Pipette.Git do
  @moduledoc """
  Git change detection and glob matching for pipeline activation.

  Provides utilities to determine which files changed between commits,
  match file paths against glob patterns, and resolve which scopes
  should be activated based on changed files.

  ## Glob Matching Rules

  Patterns use `**` and `*` wildcards:

    * `**` — matches any number of path segments (including zero), e.g.
      `"apps/api/**"` matches `"apps/api/lib/user.ex"`
    * `*` — matches anything except `/`, e.g. `"*.md"` matches `"README.md"`
    * Patterns without `/` also match against the file's basename, so
      `"*.md"` matches both `"README.md"` and `"docs/guide.md"`

  ## Base Commit Resolution

  The base commit for `git diff` is determined by priority:

    1. PR base branch (`BUILDKITE_PULL_REQUEST_BASE_BRANCH`) — `origin/<base>`
    2. Non-default branch — `origin/<default_branch>`
    3. Default branch — `HEAD~1`

  ## Examples

      base = Pipette.Git.base_commit(ctx)
      {:ok, files} = Pipette.Git.changed_files(base)

      fired = Pipette.Git.fired_scopes(scopes, files)

      Pipette.Git.matches_glob?("apps/api/lib/user.ex", "apps/api/**")
      #=> true

      Pipette.Git.matches_glob?("README.md", "*.md")
      #=> true
  """

  alias Pipette.Context

  @doc """
  Check if a file path matches a glob pattern.

  Patterns without `/` also match against the file's basename.

  ## Examples

      iex> Pipette.Git.matches_glob?("apps/api/lib/user.ex", "apps/api/**")
      true

      iex> Pipette.Git.matches_glob?("README.md", "*.md")
      true

      iex> Pipette.Git.matches_glob?("apps/api/lib/user.ex", "apps/web/**")
      false
  """
  @spec matches_glob?(String.t(), String.t()) :: boolean()
  def matches_glob?(file_path, pattern) do
    regex = glob_to_regex(pattern)

    if String.contains?(pattern, "/") do
      Regex.match?(regex, file_path)
    else
      Regex.match?(regex, file_path) or Regex.match?(regex, Path.basename(file_path))
    end
  end

  @doc """
  Determine the base commit for `git diff` comparison.

  Resolution order:
  1. PR base branch — `origin/<BUILDKITE_PULL_REQUEST_BASE_BRANCH>`
  2. Non-default branch — `origin/<default_branch>`
  3. Default branch — `HEAD~1`

  ## Examples

      iex> ctx = %Pipette.Context{pull_request_base_branch: "main", branch: "feature/x", default_branch: "main"}
      iex> Pipette.Git.base_commit(ctx)
      "origin/main"

      iex> ctx = %Pipette.Context{pull_request_base_branch: nil, branch: "main", default_branch: "main"}
      iex> Pipette.Git.base_commit(ctx)
      "HEAD~1"
  """
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

  @doc """
  Get the list of files changed since the base commit.

  Runs `git diff --name-only <base>` and returns the list of file paths.
  Accepts a `:runner` option for testing (a function that takes the base
  commit and returns `{:ok, output}` or `{:error, reason}`).

  ## Examples

      {:ok, files} = Pipette.Git.changed_files("origin/main")
      files  #=> ["apps/api/lib/user.ex", "apps/web/src/App.tsx"]
  """
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

  @doc """
  Determine which scopes are fired by the given changed files.

  A scope fires when any changed file matches at least one of its `files`
  patterns and none of its `exclude` patterns.

  ## Examples

      scopes = [
        %Pipette.Scope{name: :api_code, files: ["apps/api/**"]},
        %Pipette.Scope{name: :web_code, files: ["apps/web/**"]}
      ]

      fired = Pipette.Git.fired_scopes(scopes, ["apps/api/lib/user.ex"])
      fired  #=> MapSet.new([:api_code])
  """
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

  @doc """
  Check if all changed files match the ignore patterns.

  Returns `true` when every file in the list matches at least one ignore
  pattern. Returns `false` for an empty file list (no changes means not ignored).

  ## Examples

      Pipette.Git.all_ignored?(["README.md", "docs/guide.md"], ["*.md", "docs/**"])
      #=> true

      Pipette.Git.all_ignored?(["README.md", "apps/api/lib/user.ex"], ["*.md"])
      #=> false

      Pipette.Git.all_ignored?([], ["*.md"])
      #=> false
  """
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
