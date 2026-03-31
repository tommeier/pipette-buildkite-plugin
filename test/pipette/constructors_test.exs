defmodule Pipette.ConstructorsTest do
  use ExUnit.Case, async: true

  import Pipette.Constructors

  test "step/2 builds a Step struct" do
    s = step(:test, label: "Test", command: "mix test", timeout_in_minutes: 10)
    assert %Pipette.Step{name: :test, label: "Test", command: "mix test"} = s
    assert s.timeout_in_minutes == 10
  end

  test "group/2 builds a Group struct with steps" do
    g =
      group(:api,
        label: "API",
        key: "api",
        steps: [
          step(:test, label: "Test", command: "mix test", key: "api-test")
        ]
      )

    assert %Pipette.Group{name: :api, label: "API"} = g
    assert length(g.steps) == 1
  end

  test "raises on unknown keys" do
    assert_raise KeyError, fn -> step(:test, unknown: true) end
  end
end
