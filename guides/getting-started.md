# Getting Started

This guide walks through setting up Pipette for a Buildkite pipeline in an Elixir monorepo.

## Prerequisites

- Elixir 1.17+ installed on your Buildkite agents
- A monorepo with multiple apps or components
- An existing Buildkite pipeline

## Step 1: Define your pipeline module

Create a module that uses `Pipette.DSL`. This is where you define your scopes, groups, and steps as top-level declarations.

```elixir
defmodule MyApp.Pipeline do
  use Pipette.DSL

  branch("main", scopes: :all, disable: [:targeting])
  branch("merge-queue/**", scopes: :all, disable: [:targeting])

  scope(:api_code, files: ["apps/api/**"])
  scope(:web_code, files: ["apps/web/**"])
  scope(:root_config, files: [".buildkite/**", "mix.exs"], activates: :all)

  ignore(["docs/**", "*.md", "LICENSE"])

  group :api do
    label(":elixir: API")
    scope(:api_code)
    step(:test, label: "Test", command: "mix test", timeout_in_minutes: 15)
    step(:lint, label: "Lint", command: "mix credo --strict", timeout_in_minutes: 10)
  end

  group :web do
    label(":globe_with_meridians: Web")
    scope(:web_code)
    step(:test, label: "Test", command: "pnpm test")
    step(:build, label: "Build", command: "pnpm build")
  end

  group :deploy do
    label(":rocket: Deploy")
    depends_on([:api, :web])
    only("main")
    step(:push, label: "Push", command: "./deploy.sh")
  end

  trigger :notify do
    pipeline("slack-notify")
    depends_on(:deploy)
    only("main")
  end
end
```

> The DSL is powered by [Spark](https://hexdocs.pm/spark). Compile-time verifiers catch scope reference errors, dependency cycles, and label collisions before your pipeline ever runs.

Key decisions:

- **Branch policies**: `main` runs all groups. Feature branches use file-based detection.
- **Scopes**: Each scope maps file globs to a name. Groups reference scopes.
- **`:root_config` with `activates: :all`**: Changes to CI config or `mix.exs` run the entire pipeline.
- **`:deploy` with `only: "main"`**: Deploy group is filtered out on feature branches.
- **`ignore`**: Documentation-only changes produce no pipeline at all.

## Step 2: Create the pipeline script

Create `.buildkite/pipeline.exs`:

```elixir
Mix.install([{:buildkite_pipette, "~> 0.4"}])

# Define the pipeline module inline, or Code.require_file it from elsewhere
defmodule MyApp.Pipeline do
  use Pipette.DSL

  # ... same as above
end

Pipette.run(MyApp.Pipeline)
```

If your pipeline module is in a separate file (e.g. `lib/my_app/pipeline.ex`), you can require it:

```elixir
Mix.install([{:buildkite_pipette, "~> 0.4"}])
Code.require_file("lib/my_app/pipeline.ex")
Pipette.run(MyApp.Pipeline)
```

## Step 3: Configure your Buildkite pipeline

In your `.buildkite/pipeline.yml`, add a step that runs the pipeline script:

```yaml
steps:
  - label: ":pipeline: Generate Pipeline"
    command: elixir .buildkite/pipeline.exs
```

Or use the Buildkite plugin:

```yaml
steps:
  - plugins:
      - tommeier/pipette#v0.4.6:
          pipeline: .buildkite/pipeline.exs
```

## Step 4: Test locally with DRY_RUN

Before pushing, verify your pipeline generates the expected output:

```bash
# Set DRY_RUN=1 to print YAML instead of uploading
DRY_RUN=1 elixir .buildkite/pipeline.exs
```

You can also simulate a specific branch and changed files in an IEx session:

```elixir
Mix.install([{:buildkite_pipette, "~> 0.4"}])

# Load your pipeline module
Code.require_file(".buildkite/pipeline.exs")

{:ok, yaml} = Pipette.generate(MyApp.Pipeline,
  env: %{
    "BUILDKITE_BRANCH" => "feature/login",
    "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
    "BUILDKITE_COMMIT" => "abc123",
    "BUILDKITE_MESSAGE" => "Add login endpoint"
  },
  changed_files: ["apps/api/lib/user.ex"]
)

IO.puts(yaml)
```

## Step 5: Write tests

Add tests to verify your pipeline activation logic. See the [Testing guide](testing.md) for details.

```elixir
defmodule MyApp.PipelineTest do
  use ExUnit.Case

  test "API changes activate the API group" do
    {:ok, yaml} = Pipette.generate(MyApp.Pipeline,
      env: %{
        "BUILDKITE_BRANCH" => "feature/test",
        "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
        "BUILDKITE_COMMIT" => "abc123",
        "BUILDKITE_MESSAGE" => "Fix test"
      },
      changed_files: ["apps/api/lib/user.ex"]
    )

    assert yaml =~ "api"
    refute yaml =~ "web"
  end
end
```

## Gotcha: helpers inside DSL entities

Spark DSL macros expand at compile time. Private functions (`defp`) defined on
the same module are **not available** inside entity arguments:

```elixir
# ❌ This will fail — defp is not accessible during macro expansion
defp my_plugin, do: {"plugin#v1.0", nil}

group :app do
  step(:test, plugins: [my_plugin()])  # undefined function my_plugin/0
end
```

Use **module attributes** instead:

```elixir
# ✅ Module attributes are resolved at compile time
@my_plugin {"plugin#v1.0", nil}

group :app do
  step(:test, plugins: [@my_plugin])
end
```

For parameterized helpers, define one attribute per variant:

```elixir
@wif_prod {@wif_plugin, %{audience: @audience, "service-account": @prod_sa}}
@wif_staging {@wif_plugin, %{audience: @audience, "service-account": @staging_sa}}
```

Alternatively, define helpers in a **separate module** and `import` it — imported
functions from already-compiled modules are available during DSL expansion:

```elixir
defmodule MyApp.PipelineHelpers do
  def wif_plugin(sa), do: {"gcp-wif#v1.0", %{sa: sa}}
end

defmodule MyApp.Pipeline do
  use Pipette.DSL
  import MyApp.PipelineHelpers

  group :app do
    step(:deploy, plugins: [wif_plugin("prod@gcp")])
  end
end
```

## Next steps

- [Production Example](production-example.md) — a realistic monorepo pipeline with deploys, plugins, and triggers
- [Activation](activation.md) — understand the full activation algorithm
- [Targeting](targeting.md) — run specific groups via commit messages
- [Dynamic Groups](dynamic-groups.md) — generate groups at runtime
- [Testing](testing.md) — comprehensive testing patterns
