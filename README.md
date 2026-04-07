# Pipette

[![Hex.pm](https://img.shields.io/hexpm/v/buildkite_pipette.svg)](https://hex.pm/packages/buildkite_pipette)
[![CI](https://github.com/tommeier/pipette-buildkite-plugin/actions/workflows/ci.yml/badge.svg)](https://github.com/tommeier/pipette-buildkite-plugin/actions)
[![License](https://img.shields.io/hexpm/l/buildkite_pipette.svg)](LICENSE)

**Declarative Buildkite pipeline generation for monorepos, written in Elixir.**

Define your CI pipeline with a declarative DSL powered by [Spark](https://hexdocs.pm/spark) — scope-based change detection, branch policies, commit message targeting, dependency graphs, and dynamic group generation. Compile-time validation catches misconfigured scopes, missing dependencies, and label conflicts before your pipeline runs.

## Features

- **Scope-based activation** — map file globs to named scopes; only groups whose scope matches changed files will run
- **Branch policies** — run all groups on `main`, restrict to specific scopes on release branches, use file-based detection elsewhere
- **Commit message targeting** — `[ci:api]` or `[ci:api/test]` in commit messages to run specific groups/steps
- **Dependency propagation** — groups that `depends_on` an active group are pulled in automatically; scopeless groups activate when any dependency is active
- **Force activation** — environment variables like `FORCE_DEPLOY=true` bypass scope detection to activate specific groups
- **Dynamic groups** — `extra_groups` callback to generate groups at runtime (e.g. discovering packages in a directory)
- **Branch-scoped groups** — `only: "main"` restricts groups to specific branches
- **Trigger steps** — fire downstream Buildkite pipelines when conditions are met
- **Compile-time validation** — Spark verifiers catch scope ref errors, dependency cycles, and label collisions at compile time
- **YAML output** — generates valid Buildkite pipeline YAML via `ymlr`

## Quick Start

Define a pipeline module:

```elixir
defmodule MyApp.Pipeline do
  use Pipette.DSL

  branch("main", scopes: :all, disable: [:targeting])

  scope(:api_code, files: ["apps/api/**", "mix.exs"])
  scope(:web_code, files: ["apps/web/**", "package.json"])
  scope(:infra_code, files: ["infra/**"], exclude: ["**/*.md"])

  ignore(["docs/**", "*.md"])

  group :api do
    label(":elixir: API")
    scope(:api_code)
    step(:test, label: "Test", command: "mix test", timeout_in_minutes: 15)
    step(:lint, label: "Lint", command: "mix credo", timeout_in_minutes: 10)
  end

  group :web do
    label(":react: Web")
    scope(:web_code)
    step(:test, label: "Test", command: "pnpm test", timeout_in_minutes: 15)
    step(:lint, label: "Lint", command: "pnpm lint", timeout_in_minutes: 10)
  end

  group :deploy do
    label(":rocket: Deploy")
    depends_on([:api, :web])
    only("main")
    step(:push, label: "Push", command: "./deploy.sh")
  end
end
```

Create a pipeline script at `.buildkite/pipeline.exs`:

```elixir
Mix.install([{:buildkite_pipette, "~> 0.5"}])
Pipette.run(MyApp.Pipeline)
```

Wire it into your `.buildkite/pipeline.yml`:

```yaml
steps:
  - label: ":pipeline: Generate"
    command: elixir .buildkite/pipeline.exs
```

## Installation

Add `pipette` to your `mix.exs` dependencies:

```elixir
def deps do
  [{:buildkite_pipette, "~> 0.5"}]
end
```

Or use `Mix.install` in standalone pipeline scripts (no project required):

```elixir
Mix.install([{:buildkite_pipette, "~> 0.5"}])
```

## How It Works

```
pipeline.exs
    |
    v
Spark DSL compile
    |
    v
+-------------------+
| Validate config   |  scope refs, dep refs, cycles, labels (compile-time verifiers)
+-------------------+
    |
    v
+-------------------+
| Build context     |  BUILDKITE_BRANCH, BUILDKITE_MESSAGE, etc.
+-------------------+
    |
    v
+-------------------+
| Detect changes    |  git diff --name-only <base>
+-------------------+
    |
    v
+-------------------+
| Activation engine |
|                   |
| 1. Branch policy  |  main -> all groups, release/* -> specific scopes
| 2. Targeting      |  [ci:api] in commit message or CI_TARGET env
| 3. Scope matching |  changed files -> fired scopes -> active groups
| 4. Force groups   |  FORCE_DEPLOY=true -> [:web, :deploy]
| 5. Pull deps      |  :deploy depends_on :web -> pull :web in
| 6. only filter    |  :deploy only: "main" -> skip on feature branches
| 7. Step filter    |  [ci:api/test] -> only run the :test step
+-------------------+
    |
    v
+-------------------+
| Serialize YAML    |  groups, steps, triggers -> Buildkite YAML
+-------------------+
    |
    v
buildkite-agent pipeline upload
```

The activation engine runs through these phases in order. Each phase narrows (or expands) the set of active groups. The final set is serialized to YAML and uploaded to Buildkite.

## Pipeline Definition

### `Pipette.Pipeline`

Top-level configuration struct. Built automatically from `use Pipette.DSL` declarations via `Pipette.Info.to_pipeline/1`.

| Field | Type | Description |
|-------|------|-------------|
| `branches` | `[Branch.t()]` | Branch policies controlling activation behavior |
| `scopes` | `[Scope.t()]` | File-to-scope mappings |
| `groups` | `[Group.t()]` | Step groups (the units of activation) |
| `triggers` | `[Trigger.t()]` | Downstream pipeline triggers |
| `ignore` | `[String.t()]` | Glob patterns for files that should not activate anything |
| `env` | `map() \| nil` | Pipeline-level environment variables |
| `secrets` | `[String.t()] \| nil` | Secret names to inject |
| `cache` | `keyword() \| nil` | Cache configuration |
| `force_activate` | `%{String.t() => [atom()] \| :all}` | Env var -> groups to force-activate |

### `Pipette.Branch`

Branch policy controlling how activation works on matching branches.

| Field | Type | Description |
|-------|------|-------------|
| `pattern` | `String.t()` | Branch glob pattern (e.g. `"main"`, `"release/*"`) |
| `scopes` | `:all \| [atom()] \| nil` | `:all` runs everything; a list restricts to named scopes; `nil` uses file detection |
| `disable` | `[atom()] \| nil` | Features to disable (e.g. `[:targeting]`) |

### `Pipette.Scope`

Maps file patterns to a named scope.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `atom()` | Unique scope identifier |
| `files` | `[String.t()]` | Glob patterns that trigger this scope |
| `exclude` | `[String.t()] \| nil` | Glob patterns to exclude from matching |
| `activates` | `:all \| nil` | When `:all`, any match activates every group |

### `Pipette.Group`

A group of Buildkite steps. Groups are the unit of activation — when a scope fires, its bound group runs.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `atom()` | Unique group identifier |
| `label` | `String.t() \| nil` | Display label in Buildkite UI |
| `scope` | `atom() \| nil` | Scope that activates this group |
| `depends_on` | `atom() \| [atom()] \| nil` | Groups this group depends on |
| `only` | `String.t() \| [String.t()] \| nil` | Branch pattern(s) restricting this group |
| `steps` | `[Step.t()]` | Command steps in this group |

### `Pipette.Step`

A single Buildkite command step.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `atom()` | Unique identifier within the group |
| `label` | `String.t()` | Display label in Buildkite UI |
| `command` | `String.t() \| [String.t()]` | Shell command(s) to run |
| `timeout_in_minutes` | `pos_integer() \| nil` | Step timeout |
| `depends_on` | `atom() \| {atom(), atom()} \| list()` | Step-level dependencies |
| `env` | `map() \| nil` | Step environment variables |
| `agents` | `map() \| nil` | Agent targeting rules |
| `plugins` | `list() \| nil` | Buildkite plugins |
| `retry` | `map() \| nil` | Retry configuration |
| `parallelism` | `pos_integer() \| nil` | Parallel job count |
| `soft_fail` | `boolean() \| list() \| nil` | Soft fail configuration |
| `artifact_paths` | `String.t() \| [String.t()] \| nil` | Artifact upload paths |

See `Pipette.Step` module docs for the full list of fields.

### `Pipette.Trigger`

Fires a downstream Buildkite pipeline.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `atom()` | Unique trigger identifier |
| `label` | `String.t() \| nil` | Display label |
| `pipeline` | `String.t()` | Slug of the pipeline to trigger |
| `depends_on` | `atom() \| [atom()] \| nil` | Groups that must complete first |
| `only` | `String.t() \| [String.t()] \| nil` | Branch filter |
| `build` | `map() \| nil` | Build parameters to pass |
| `async` | `boolean() \| nil` | Don't wait for the triggered build |

## Buildkite Plugin

This repository doubles as a Buildkite plugin. Instead of adding `pipette` to a Mix project, you can use the plugin directly in your `pipeline.yml`:

```yaml
steps:
  - plugins:
      - tommeier/pipette#v0.5.0:
          pipeline: .buildkite/pipeline.exs
```

The plugin runs `elixir <pipeline>` — your pipeline script should use `Mix.install` to pull in the `pipette` dependency:

```elixir
# .buildkite/pipeline.exs
Mix.install([{:buildkite_pipette, "~> 0.5"}])

defmodule MyApp.Pipeline do
  use Pipette.DSL

  # ... your pipeline definition
end

Pipette.run(MyApp.Pipeline)
```

Requires Elixir to be installed on the Buildkite agent (or use a Docker-based agent with Elixir available).

## Targeting

Targeting lets developers manually select which groups and steps to run, bypassing file-based scope detection.

### Commit message syntax

Prefix your commit message with `[ci:<targets>]`:

```
[ci:api] Fix login bug            # run only the :api group
[ci:api,web] Update shared types  # run :api and :web groups
[ci:api/test] Fix flaky test      # run only the :test step in :api
```

### CI_TARGET environment variable

Set `CI_TARGET` on the build (same syntax without brackets):

```bash
CI_TARGET=api             # run only :api
CI_TARGET=api/test        # run only :api :test step
CI_TARGET=api,web         # run :api and :web
```

Commit message targets take precedence over `CI_TARGET`.

### Disabling targeting

On branches where you want to run everything (like `main`), disable targeting in the branch policy:

```elixir
branch("main", scopes: :all, disable: [:targeting])
```

See the [Targeting guide](guides/targeting.md) for more details.

## Force Activation

Force-activate groups via environment variables, bypassing scope detection and `only` branch filters:

```elixir
force_activate(%{"FORCE_DEPLOY" => [:web, :deploy], "FORCE_ALL" => :all})
```

When `FORCE_DEPLOY=true` is set on the build, the `:web` and `:deploy` groups are activated regardless of which files changed or which branch you're on.

Dependencies are still pulled in — if `:deploy` depends on `:web`, both will run.

## Dynamic Groups

For monorepos with dynamic package discovery, use the `extra_groups` option:

```elixir
Pipette.run(MyApp.Pipeline,
  extra_groups: fn _ctx, _changed_files ->
    "packages"
    |> File.ls!()
    |> Enum.filter(&File.dir?(Path.join("packages", &1)))
    |> Enum.map(fn pkg ->
      %Pipette.Group{
        name: String.to_atom(pkg),
        label: ":package: #{pkg}",
        key: pkg,
        steps: [
          %Pipette.Step{
            name: :test,
            label: "Test",
            command: "cd packages/#{pkg} && mix test",
            key: "#{pkg}-test"
          }
        ]
      }
    end)
  end
)
```

Note: Extra groups are constructed as plain structs since they're generated at runtime, outside the compile-time DSL.

See the [Dynamic Groups guide](guides/dynamic-groups.md) for more details.

## Testing Your Pipeline

Use `Pipette.generate/2` in your tests to verify activation logic without uploading to Buildkite:

```elixir
defmodule MyApp.PipelineTest do
  use ExUnit.Case

  test "API changes activate only the API group" do
    {:ok, yaml} = Pipette.generate(MyApp.Pipeline,
      env: %{
        "BUILDKITE_BRANCH" => "feature/login",
        "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
        "BUILDKITE_COMMIT" => "abc123",
        "BUILDKITE_MESSAGE" => "Add login endpoint"
      },
      changed_files: ["apps/api/lib/user.ex"]
    )

    assert yaml =~ "api"
    refute yaml =~ "web"
  end

  test "docs-only changes produce no pipeline" do
    assert :noop = Pipette.generate(MyApp.Pipeline,
      env: %{
        "BUILDKITE_BRANCH" => "docs/update",
        "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
        "BUILDKITE_COMMIT" => "abc123",
        "BUILDKITE_MESSAGE" => "Update docs"
      },
      changed_files: ["docs/guide.md", "README.md"]
    )
  end
end
```

See the [Testing guide](guides/testing.md) for more patterns.

## License

MIT - see [LICENSE](LICENSE).
