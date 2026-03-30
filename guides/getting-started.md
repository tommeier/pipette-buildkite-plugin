# Getting Started

This guide walks through setting up Pipette for a Buildkite pipeline in an Elixir monorepo.

## Prerequisites

- Elixir 1.17+ installed on your Buildkite agents
- A monorepo with multiple apps or components
- An existing Buildkite pipeline

## Step 1: Define your pipeline module

Create a module that implements the `Pipette.Pipeline` behaviour. This is where you define your scopes, groups, and steps.

```elixir
defmodule MyApp.Pipeline do
  @behaviour Pipette.Pipeline

  @impl true
  def pipeline do
    %Pipette.Pipeline{
      branches: [
        # Run all groups on main, disable commit message targeting
        %Pipette.Branch{pattern: "main", scopes: :all, disable: [:targeting]},
        # Same for merge queue branches
        %Pipette.Branch{pattern: "merge-queue/**", scopes: :all, disable: [:targeting]}
      ],
      scopes: [
        %Pipette.Scope{name: :api_code, files: ["apps/api/**"]},
        %Pipette.Scope{name: :web_code, files: ["apps/web/**"]},
        %Pipette.Scope{
          name: :root_config,
          files: [".buildkite/**", "mix.exs"],
          activates: :all
        }
      ],
      groups: [
        %Pipette.Group{
          name: :api,
          label: ":elixir: API",
          scope: :api_code,
          steps: [
            %Pipette.Step{
              name: :test,
              label: "Test",
              command: "mix test",
              timeout_in_minutes: 15
            },
            %Pipette.Step{
              name: :lint,
              label: "Lint",
              command: "mix credo --strict",
              timeout_in_minutes: 10
            }
          ]
        },
        %Pipette.Group{
          name: :web,
          label: ":globe_with_meridians: Web",
          scope: :web_code,
          steps: [
            %Pipette.Step{name: :test, label: "Test", command: "pnpm test"},
            %Pipette.Step{name: :build, label: "Build", command: "pnpm build"}
          ]
        },
        %Pipette.Group{
          name: :deploy,
          label: ":rocket: Deploy",
          depends_on: [:api, :web],
          only: "main",
          steps: [
            %Pipette.Step{name: :push, label: "Push", command: "./deploy.sh"}
          ]
        }
      ],
      triggers: [
        %Pipette.Trigger{
          name: :notify,
          pipeline: "slack-notify",
          depends_on: :deploy,
          only: "main"
        }
      ],
      ignore: ["docs/**", "*.md", "LICENSE"]
    }
  end
end
```

Key decisions:

- **Branch policies**: `main` runs all groups. Feature branches use file-based detection.
- **Scopes**: Each scope maps file globs to a name. Groups reference scopes.
- **`:root_config` with `activates: :all`**: Changes to CI config or `mix.exs` run the entire pipeline.
- **`:deploy` with `only: "main"`**: Deploy group is filtered out on feature branches.
- **`ignore`**: Documentation-only changes produce no pipeline at all.

## Step 2: Create the pipeline script

Create `.buildkite/pipeline.exs`:

```elixir
Mix.install([{:buildkite_pipette, "~> 0.1"}])

# Define the pipeline module inline, or Code.require_file it from elsewhere
defmodule MyApp.Pipeline do
  @behaviour Pipette.Pipeline

  @impl true
  def pipeline do
    # ... same as above
  end
end

Pipette.run(MyApp.Pipeline)
```

If your pipeline module is in a separate file (e.g. `lib/my_app/pipeline.ex`), you can require it:

```elixir
Mix.install([{:buildkite_pipette, "~> 0.1"}])
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
      - tommeier/pipette-buildkite-plugin#v0.1.0:
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
Mix.install([{:buildkite_pipette, "~> 0.1"}])

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

## Next steps

- [Activation](activation.md) — understand the full activation algorithm
- [Targeting](targeting.md) — run specific groups via commit messages
- [Dynamic Groups](dynamic-groups.md) — generate groups at runtime
- [Testing](testing.md) — comprehensive testing patterns
