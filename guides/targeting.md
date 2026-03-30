# Targeting

Targeting lets developers manually select which groups and steps to run, bypassing file-based scope detection. This is useful for re-running specific checks, testing a known-broken group, or skipping irrelevant CI work.

## Commit Message Syntax

Prefix your commit message with `[ci:<targets>]`:

```
[ci:api] Fix login bug
```

This runs only the `:api` group, regardless of which files changed.

### Multiple groups

Comma-separate group names:

```
[ci:api,web] Update shared types
```

### Specific steps

Use `group/step` syntax to run a single step within a group:

```
[ci:api/test] Fix flaky test
```

This activates the `:api` group but only runs the `:test` step. If `:test` has intra-group `depends_on` (e.g. it depends on `:setup`), those dependency steps are included automatically.

### Combined

```
[ci:api/test,web] Fix test and update web
```

This runs the full `:web` group and only the `:test` step in `:api`.

## `CI_TARGET` Environment Variable

Set `CI_TARGET` on the Buildkite build with the same syntax (without brackets):

```
CI_TARGET=api
CI_TARGET=api/test
CI_TARGET=api,web
```

You can set this in the Buildkite UI when creating a new build, or pass it via the API.

### Precedence

Commit message targets take precedence over `CI_TARGET`. If both are present, the commit message wins.

## Dependency Resolution

When a group is targeted, its transitive dependencies in the dependency graph are also activated.

Given:

```elixir
groups: [
  %Pipette.Group{name: :lint, steps: [...]},
  %Pipette.Group{name: :api, depends_on: :lint, scope: :api_code, steps: [...]},
  %Pipette.Group{name: :deploy, depends_on: :api, only: "main", steps: [...]}
]
```

Targeting `[ci:deploy]` activates `:deploy`, `:api`, and `:lint` (transitive dependency chain). The `only` branch filter still applies unless the group is force-activated.

## Step-Level Dependency Resolution

When targeting a specific step like `[ci:api/test]`, intra-group step dependencies are resolved:

```elixir
%Pipette.Group{
  name: :api,
  steps: [
    %Pipette.Step{name: :setup, label: "Setup", command: "mix deps.get"},
    %Pipette.Step{name: :test, label: "Test", command: "mix test", depends_on: :setup}
  ]
}
```

Targeting `api/test` runs both `:setup` and `:test`, because `:test` depends on `:setup`.

## Disabling Targeting

On branches where you always want to run everything (like `main` or merge queue branches), disable targeting in the branch policy:

```elixir
branches: [
  %Pipette.Branch{pattern: "main", scopes: :all, disable: [:targeting]},
  %Pipette.Branch{pattern: "merge-queue/**", scopes: :all, disable: [:targeting]}
]
```

With targeting disabled, `[ci:api]` in the commit message is ignored and all groups run.

## Pattern Reference

| Syntax | Meaning |
|--------|---------|
| `[ci:api]` | Run the `:api` group |
| `[ci:api,web]` | Run `:api` and `:web` groups |
| `[ci:api/test]` | Run only the `:test` step in `:api` |
| `[ci:api/test,web]` | Run `:test` step in `:api`, full `:web` group |
| `CI_TARGET=api` | Same as `[ci:api]` via env var |

Group and step names must be lowercase letters and underscores (`[a-z_]+`).
