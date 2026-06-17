defmodule Pipette.OptionalDepsTest do
  use ExUnit.Case, async: true

  defmodule TestPipeline do
    use Pipette.DSL
    import Pipette.Constructors, only: [optional: 1]

    scope(:core_files, files: ["core/**"])
    scope(:dep_files, files: ["dep/**"])

    group :runner do
      scope(:core_files)

      trigger :ingest do
        pipeline("ingest")
        # :build           -> sibling, always present.
        # optional(:optdep)-> dropped only when optdep is defined-but-inactive.
        # :reqdep          -> untagged; kept even when inactive (must fail loudly).
        # optional(:ghost) -> defined nowhere; kept (a rename must fail loudly).
        depends_on([:build, optional(:optdep), :reqdep, optional(:ghost)])
        build(%{})
      end

      step(:build, label: "Build", command: "true")
    end

    group :optdep do
      scope(:dep_files)
      step(:run, label: "Run", command: "true")
    end

    group :reqdep do
      scope(:dep_files)
      step(:run, label: "Run", command: "true")
    end
  end

  defp ingest_deps(changed) do
    {:ok, yaml} =
      Pipette.run(TestPipeline,
        changed_files: changed,
        dry_run: true,
        env: %{"BUILDKITE_BRANCH" => "test"}
      )

    # depends_on renders just above the trigger's `key:` (Ymlr sorts keys).
    [_, block] = Regex.run(~r/depends_on:\n((?:\s+- .*\n)+)\s+key: runner-ingest/, yaml)

    block
    |> String.split("\n", trim: true)
    |> Enum.map(&(&1 |> String.trim() |> String.trim_leading("- ")))
  end

  test "optional dep on a group in the build is kept" do
    deps = ingest_deps(["core/x", "dep/y"])
    assert "optdep" in deps
    assert "runner-build" in deps
  end

  test "optional dep on a defined-but-inactive group is dropped" do
    refute "optdep" in ingest_deps(["core/x"])
  end

  test "untagged dep is never dropped, even when inactive (fails loudly)" do
    assert "reqdep" in ingest_deps(["core/x"])
  end

  test "optional dep on an undefined target is kept (a rename must fail loudly)" do
    assert "ghost" in ingest_deps(["core/x", "dep/y"])
    assert "ghost" in ingest_deps(["core/x"])
  end

  test "transform_groups rewrites the active groups before serialization" do
    {:ok, yaml} =
      Pipette.run(TestPipeline,
        changed_files: ["core/x"],
        dry_run: true,
        env: %{"BUILDKITE_BRANCH" => "test"},
        transform_groups: fn groups ->
          Enum.map(groups, &%{&1 | label: "transformed-#{&1.name}"})
        end
      )

    assert yaml =~ "transformed-runner"
  end
end
