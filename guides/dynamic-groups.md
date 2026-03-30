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

Discover packages in a `packages/` directory and generate a test group for each:

```elixir
# .buildkite/pipeline.exs
Mix.install([{:buildkite_pipette, "~> 0.1"}])

defmodule MyApp.Pipeline do
  @behaviour Pipette.Pipeline

  @impl true
  def pipeline do
    %Pipette.Pipeline{
      branches: [
        %Pipette.Branch{pattern: "main", scopes: :all}
      ],
      scopes: [
        %Pipette.Scope{name: :api_code, files: ["apps/api/**"]}
      ],
      groups: [
        %Pipette.Group{
          name: :api,
          label: ":elixir: API",
          scope: :api_code,
          steps: [
            %Pipette.Step{name: :test, label: "Test", command: "mix test"}
          ]
        }
      ]
    }
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
- **No validation**: Extra groups bypass `Pipette.validate!/1` — scope references, dependency references, and cycle detection are not checked for dynamically added groups.
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
            key: "publish-all"
          }
        ]
      }
    ]
  else
    []
  end
end
```
