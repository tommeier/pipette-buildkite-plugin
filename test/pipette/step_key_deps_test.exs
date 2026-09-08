defmodule Pipette.StepKeyDepsTest do
  use ExUnit.Case, async: true

  # Cross-group `{group, step}` references must resolve to the target step's
  # explicit `key:`, not the synthesised "group-step" form, or the rendered
  # dependency names a key Buildkite has never seen.
  defmodule TestPipeline do
    use Pipette.DSL
    import Pipette.Constructors, only: [optional: 1]

    scope(:core_files, files: ["core/**"])
    scope(:image_files, files: ["image/**"])

    # Defined after the group that references it: resolution must not depend
    # on group order.
    group :cache do
      scope(:core_files)
      step(:refresh, label: "Refresh", command: "true", depends_on: [optional({:image, :sign})])
    end

    group :image do
      scope(:image_files)
      step(:bake, label: "Bake", command: "true")
      step(:sign, key: "image-signed", label: "Sign", command: "true", depends_on: :bake)
    end

    trigger :notify do
      pipeline("notify")
      depends_on([{:image, :sign}])
      build(%{})
    end

    trigger :audit do
      pipeline("audit")
      depends_on([optional({:image, :sign})])
      build(%{})
    end
  end

  defp render(changed) do
    {:ok, yaml} =
      Pipette.run(TestPipeline,
        changed_files: changed,
        dry_run: true,
        env: %{"BUILDKITE_BRANCH" => "test"}
      )

    yaml
  end

  # depends_on renders just above the step's `key:` (Ymlr sorts keys).
  defp deps_of(yaml, key) do
    case Regex.run(~r/depends_on:\n((?:\s+- .*\n)+)\s+key: #{Regex.escape(key)}/, yaml) do
      nil ->
        []

      [_, block] ->
        block
        |> String.split("\n", trim: true)
        |> Enum.map(&(&1 |> String.trim() |> String.trim_leading("- ")))
    end
  end

  test "step tuple resolves to the target's explicit key at compile time" do
    cache = Pipette.Info.groups(TestPipeline) |> Enum.find(&(&1.name == :cache))
    refresh = Enum.find(cache.steps, &(&1.name == :refresh))
    assert refresh.depends_on == [%Pipette.Optional{dep: "image-signed"}]
  end

  test "optional step tuple is kept, by explicit key, when the target is active" do
    assert deps_of(render(["core/x", "image/y"]), "cache-refresh") == ["image-signed"]
  end

  test "optional step tuple is dropped when the target is defined but inactive" do
    yaml = render(["core/x"])
    assert deps_of(yaml, "cache-refresh") == []
    refute yaml =~ "image-sign"
  end

  test "trigger tuple resolves to the target's explicit key at runtime" do
    assert deps_of(render(["core/x", "image/y"]), "notify") == ["image-signed"]
  end

  test "trigger tuple gates activation on the target's group" do
    refute render(["core/x"]) =~ "key: notify"
  end

  test "optional trigger tuple never gates activation and drops when inactive" do
    yaml = render(["core/x"])
    assert yaml =~ "key: audit"
    assert deps_of(yaml, "audit") == []
    assert deps_of(render(["core/x", "image/y"]), "audit") == ["image-signed"]
  end
end
