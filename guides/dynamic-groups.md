# Dynamic Groups

For monorepos where the set of packages or components isn't known at compile time, Pipette supports generating groups dynamically at runtime via the `extra_groups` callback.

## The `extra_groups` Option

Pass a 2-arity function to `Pipette.run/2` or `Pipette.generate/2`:

```elixir
Pipette.run(MyApp.Pipeline,
  extra_groups: fn ctx, changed_files ->
    # Return a list of %Pipette.Group{} structs
    []
  end
)
```

The function receives:
- `ctx` — a `%Pipette.Context{}` struct with branch, commit, message, etc.
- `changed_files` — the list of changed file paths (or `:all` if change detection failed)

## Package Discovery Example

Discover packages in a `packages/` directory and generate a group for each with format, test, and build steps:

```elixir
# .buildkite/pipeline.exs
Mix.install([{:buildkite_pipette, "~> 0.4"}])

defmodule MyApp.Pipeline do
  use Pipette.DSL

  branch("main", scopes: :all)

  scope(:api_code, files: ["apps/api/**"])

  group :api do
    label(":elixir: API")
    scope(:api_code)
    step(:test, label: "Test", command: "mix test", timeout_in_minutes: 15)
  end
end

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
            name: :format,
            label: "Format",
            command: "cd packages/#{pkg} && mix format --check-formatted",
            key: "#{pkg}-format",
            timeout_in_minutes: 5
          },
          %Pipette.Step{
            name: :test,
            label: "Test",
            command: "cd packages/#{pkg} && mix test",
            key: "#{pkg}-test",
            timeout_in_minutes: 15,
            env: %{"MIX_ENV" => "test"},
            retry: %{automatic: [%{exit_status: -1, limit: 2}]}
          },
          %Pipette.Step{
            name: :build,
            label: "Build",
            command: "cd packages/#{pkg} && mix compile --warnings-as-errors",
            key: "#{pkg}-build",
            depends_on: "#{pkg}-format",
            timeout_in_minutes: 10
          }
        ]
      }
    end)
  end
)
```

## Filtering by Changed Files

You can use the `changed_files` argument to only generate groups for packages that actually changed:

```elixir
extra_groups: fn _ctx, changed_files ->
  packages =
    "packages"
    |> File.ls!()
    |> Enum.filter(&File.dir?(Path.join("packages", &1)))

  case changed_files do
    :all ->
      # Can't determine changes — run everything
      build_groups(packages)

    files ->
      changed_packages =
        Enum.filter(packages, fn pkg ->
          Enum.any?(files, &String.starts_with?(&1, "packages/#{pkg}/"))
        end)

      build_groups(changed_packages)
  end
end
```

## Important Notes

- **Keys must be unique**: Dynamic group and step keys must not collide with static pipeline groups. Use the package name as a prefix.
- **No validation**: Extra groups bypass compile-time Spark verifiers — scope references, dependency references, and cycle detection are not checked for dynamically added groups.
- **Appended after activation**: Extra groups are added after the activation engine runs. They always appear in the pipeline regardless of scope matching.
- **Branch filtering**: Extra groups do not go through `only` branch filtering. If you need branch-specific behavior, filter in your callback using `ctx.branch`.

## Branch-Aware Dynamic Groups

```elixir
extra_groups: fn ctx, _changed_files ->
  if ctx.is_default_branch do
    [
      %Pipette.Group{
        name: :publish,
        label: ":rocket: Publish Packages",
        key: "publish",
        steps: [
          %Pipette.Step{
            name: :publish,
            label: "Publish",
            command: "./scripts/publish-all.sh",
            key: "publish-all",
            timeout_in_minutes: 15,
            concurrency: 1,
            concurrency_group: "publish-packages"
          }
        ]
      }
    ]
  else
    []
  end
end
```
