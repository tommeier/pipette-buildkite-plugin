# Activation

The activation engine determines which groups and steps run for a given build. It combines branch policies, scope-based change detection, targeting, dependency propagation, and branch filtering into a single resolution pipeline.

## The Algorithm

Activation runs through these phases in order:

### 1. Branch Policy

The engine matches the current branch against defined branch policies:

```elixir
branches: [
  %Pipette.Branch{pattern: "main", scopes: :all, disable: [:targeting]},
  %Pipette.Branch{pattern: "release/*", scopes: [:api_code, :web_code]}
]
```

- **`scopes: :all`** — activates every group, skips file-based detection entirely
- **`scopes: [:api_code, :web_code]`** — treats those scopes as fired without checking files
- **`scopes: nil`** (or no matching policy) — proceeds to file-based detection

### 2. Targeting

If targeting is not disabled for the current branch, the engine checks for explicit targets in the commit message or `CI_TARGET` environment variable:

```
[ci:api] Fix login bug        -> activates :api group
[ci:api/test] Fix flaky test  -> activates :api group, filters to :test step
```

When targets are found, the engine activates only the targeted groups (plus their transitive dependencies). File-based scope detection is skipped entirely.

See the [Targeting guide](targeting.md) for full syntax.

### 3. Scope Matching

If no branch policy override and no targeting, the engine:

1. Gets the list of changed files from `git diff --name-only <base>`
2. Checks if all changed files match the pipeline's `ignore` patterns — if so, returns `:noop` (no pipeline)
3. Tests each scope's `files` patterns against the changed files (respecting `exclude` patterns)
4. Collects the set of "fired" scopes
5. If any fired scope has `activates: :all`, all groups are activated
6. Otherwise, activates groups whose `scope` is in the fired set

```elixir
scopes: [
  %Pipette.Scope{name: :api_code, files: ["apps/api/**"]},
  %Pipette.Scope{name: :infra, files: ["infra/**"], activates: :all}
]
```

Changing `infra/main.tf` fires the `:infra` scope, which has `activates: :all`, so every group runs.

### 4. Force Activation

Groups can be force-activated via environment variables:

```elixir
force_activate: %{
  "FORCE_DEPLOY" => [:web, :deploy],
  "FORCE_ALL" => :all
}
```

When `FORCE_DEPLOY=true` is set, `:web` and `:deploy` are added to the active set. Force-activated groups bypass the `only` branch filter — they run on any branch.

### 5. Dependency Propagation

Two kinds of dependency propagation occur:

**Pull dependencies**: If group A is active and `depends_on: :B`, group B is pulled into the active set (even if B's scope didn't fire).

**Scopeless propagation**: Groups without a `scope` are activated when any of their `depends_on` groups are active. This is useful for deploy/release groups that should run whenever their upstream groups run.

```elixir
groups: [
  %Pipette.Group{name: :api, scope: :api_code, steps: [...]},
  %Pipette.Group{name: :deploy, depends_on: :api, only: "main", steps: [...]}
]
```

When `:api` is activated by scope matching, `:deploy` is pulled in because it `depends_on: :api` and has no scope of its own.

### 6. `only` Branch Filter

After all activation and propagation, groups are filtered by their `only` field:

```elixir
%Pipette.Group{name: :deploy, only: "main", ...}
%Pipette.Group{name: :release, only: ["main", "release/*"], ...}
```

The `:deploy` group is removed if the current branch is not `main`. Glob patterns are supported.

Force-activated groups bypass this filter.

### 7. Step Filter

If targeting specified individual steps (e.g. `[ci:api/test]`), only those steps (plus their intra-group dependencies) are kept:

```elixir
# Given [ci:api/test]:
# - :api group is activated
# - Only the :test step (and any steps it depends_on) run
# - If :test depends_on :setup, both run
```

## Scope Patterns

Scopes use glob patterns with `**` and `*`:

- `**` matches any path segment(s), including nested directories
- `*` matches anything except `/`
- Patterns without `/` also match against the basename

```elixir
%Pipette.Scope{
  name: :api_code,
  files: ["apps/api/**", "libs/shared/**"],
  exclude: ["**/*.md", "apps/api/docs/**"]
}
```

A file must match at least one `files` pattern and not match any `exclude` pattern to fire the scope.

## Ignore Patterns

Pipeline-level `ignore` patterns prevent activation when only ignored files changed:

```elixir
ignore: ["docs/**", "*.md", "LICENSE"]
```

If a commit changes only `README.md` and `docs/guide.md`, the pipeline returns `:noop` and no Buildkite steps are generated.

If the commit also changes `apps/api/lib/user.ex`, the ignore patterns are not applied — normal scope detection runs.

## Cross-Group Step Dependencies

Steps can depend on specific steps in other groups using tuple syntax:

```elixir
import Pipette.DSL

group(:deploy, label: ":rocket: Deploy", depends_on: [:api, :web], only: "main", steps: [
  step(:deploy_api,
    label: "Deploy API",
    depends_on: {:api, :test},
    command: "./scripts/deploy-api.sh"
  ),
  step(:deploy_web,
    label: "Deploy Web",
    depends_on: {:web, :build},
    command: "./scripts/deploy-web.sh"
  )
])
```

The tuple `{:api, :test}` resolves to the Buildkite step key `"api-test"`. This lets you express fine-grained dependencies — the deploy step waits for the specific upstream step, not just the group as a whole.

You can also mix cross-group and intra-group dependencies in a list:

```elixir
step(:integration,
  label: "Integration Tests",
  depends_on: [{:api, :build}, {:web, :build}, :setup],
  command: "./scripts/integration-test.sh"
)
```

Here `:setup` refers to another step within the same group, while the tuples reference steps in the `:api` and `:web` groups.

## `activates: :all`

A scope with `activates: :all` causes all groups to activate when that scope fires:

```elixir
%Pipette.Scope{
  name: :root_config,
  files: [".buildkite/**", "mix.exs", ".tool-versions"],
  activates: :all
}
```

This is useful for CI config files, lock files, or shared configuration that could affect any part of the pipeline.
