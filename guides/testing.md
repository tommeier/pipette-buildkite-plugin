# Testing

Pipette pipelines are plain Elixir structs and functions, so they're straightforward to test. Use `Pipette.generate/2` to produce YAML without uploading to Buildkite.

## Basic Setup

```elixir
defmodule MyApp.PipelineTest do
  use ExUnit.Case, async: true

  # Helper to build a fake Buildkite environment
  defp env(overrides \\ %{}) do
    Map.merge(
      %{
        "BUILDKITE_BRANCH" => "feature/test",
        "BUILDKITE_COMMIT" => "abc123",
        "BUILDKITE_MESSAGE" => "Test commit",
        "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main"
      },
      overrides
    )
  end

  defp generate(opts) do
    Pipette.generate(MyApp.Pipeline, opts)
  end
end
```

## Testing Scope Activation

Verify that changing specific files activates the expected groups:

```elixir
test "API file changes activate the API group" do
  {:ok, yaml} = generate(
    env: env(),
    changed_files: ["apps/api/lib/user.ex"]
  )

  assert yaml =~ "api"
  refute yaml =~ "web"
end

test "web file changes activate the web group" do
  {:ok, yaml} = generate(
    env: env(),
    changed_files: ["apps/web/src/App.tsx"]
  )

  assert yaml =~ "web"
  refute yaml =~ "api"
end

test "changes across multiple scopes activate multiple groups" do
  {:ok, yaml} = generate(
    env: env(),
    changed_files: ["apps/api/lib/user.ex", "apps/web/src/App.tsx"]
  )

  assert yaml =~ "api"
  assert yaml =~ "web"
end
```

## Testing Ignored Files

```elixir
test "docs-only changes produce no pipeline" do
  assert :noop = generate(
    env: env(),
    changed_files: ["docs/guide.md", "README.md"]
  )
end

test "mixed changes with docs still activate groups" do
  {:ok, yaml} = generate(
    env: env(),
    changed_files: ["docs/guide.md", "apps/api/lib/user.ex"]
  )

  assert yaml =~ "api"
end
```

## Testing Branch Policies

```elixir
test "main branch runs all groups" do
  {:ok, yaml} = generate(
    env: env(%{"BUILDKITE_BRANCH" => "main"}),
    changed_files: ["apps/api/lib/user.ex"]
  )

  assert yaml =~ "api"
  assert yaml =~ "web"
  assert yaml =~ "deploy"
end

test "feature branch filters deploy group" do
  {:ok, yaml} = generate(
    env: env(),
    changed_files: ["apps/web/src/App.tsx"]
  )

  assert yaml =~ "web"
  refute yaml =~ "deploy"
end
```

## Testing Targeting

```elixir
test "commit message targeting runs only targeted group" do
  {:ok, yaml} = generate(
    env: env(%{"BUILDKITE_MESSAGE" => "[ci:api] Quick fix"}),
    changed_files: ["apps/api/lib/user.ex", "apps/web/src/App.tsx"]
  )

  assert yaml =~ "api"
  refute yaml =~ "web"
end

test "step-level targeting filters steps" do
  {:ok, yaml} = generate(
    env: env(%{"BUILDKITE_MESSAGE" => "[ci:api/test] Fix flaky test"}),
    changed_files: ["apps/api/lib/user.ex"]
  )

  assert yaml =~ "Test"
  refute yaml =~ "Lint"
end

test "CI_TARGET works like commit message targeting" do
  {:ok, yaml} = generate(
    env: env(%{"CI_TARGET" => "api"}),
    changed_files: ["apps/web/src/App.tsx"]
  )

  assert yaml =~ "api"
  refute yaml =~ "web"
end
```

## Testing Force Activation

```elixir
test "FORCE_DEPLOY activates deploy group on feature branch" do
  {:ok, yaml} = generate(
    env: env(%{"FORCE_DEPLOY" => "true"}),
    changed_files: ["README.md"]
  )

  assert yaml =~ "deploy"
  assert yaml =~ "web"
end
```

## Testing Triggers

```elixir
test "triggers fire on main when dependencies are met" do
  {:ok, yaml} = generate(
    env: env(%{"BUILDKITE_BRANCH" => "main"}),
    changed_files: ["apps/api/lib/user.ex"]
  )

  assert yaml =~ "my-deploy-pipeline"
end

test "triggers don't fire on feature branches" do
  {:ok, yaml} = generate(
    env: env(),
    changed_files: ["apps/api/lib/user.ex"]
  )

  refute yaml =~ "my-deploy-pipeline"
end
```

## Testing YAML Structure

For more precise assertions, parse group keys from the YAML output:

```elixir
defp active_group_names({:ok, yaml}) do
  yaml
  |> String.split("\n")
  |> Enum.reduce(MapSet.new(), fn line, names ->
    trimmed = String.trim(line)

    if String.starts_with?(trimmed, "key:") and not String.starts_with?(trimmed, "- ") do
      key = trimmed |> String.replace_prefix("key: ", "") |> String.trim("'\"")
      MapSet.put(names, key)
    else
      names
    end
  end)
end

defp active_group_names(:noop), do: MapSet.new()

test "precise group activation check" do
  result = generate(
    env: env(),
    changed_files: ["apps/api/lib/user.ex"]
  )

  names = active_group_names(result)
  assert "api" in names
  refute "web" in names
  refute "deploy" in names
end
```

## Tips

- **`async: true`** — pipeline tests are pure functions with no side effects, so they can run concurrently.
- **`changed_files` option** — always pass this in tests to avoid hitting `git diff` on the host machine.
- **`env` option** — always pass this to control the Buildkite environment. Without it, Pipette reads `System.get_env()`.
- **Test the contract, not the YAML** — assert on group/step names and presence, not on exact YAML formatting.
