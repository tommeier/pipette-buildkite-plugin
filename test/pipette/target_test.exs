defmodule Pipette.TargetTest do
  use ExUnit.Case, async: true

  alias Pipette.Target

  describe "parse_commit_message/1" do
    test "parses single group target" do
      assert Target.parse_commit_message("[ci:backend] Fix login bug") ==
               {:ok, %{groups: MapSet.new([:backend]), steps: MapSet.new()}}
    end

    test "parses single step target" do
      assert Target.parse_commit_message("[ci:backend/test] Fix flaky test") ==
               {:ok, %{groups: MapSet.new([:backend]), steps: MapSet.new([{:backend, :test}])}}
    end

    test "parses multiple targets" do
      assert Target.parse_commit_message("[ci:backend,native] Update types") ==
               {:ok, %{groups: MapSet.new([:backend, :native]), steps: MapSet.new()}}
    end

    test "parses mixed group and step targets" do
      assert Target.parse_commit_message("[ci:backend/test,native] Fix") ==
               {:ok,
                %{
                  groups: MapSet.new([:backend, :native]),
                  steps: MapSet.new([{:backend, :test}])
                }}
    end

    test "returns nil for messages without ci tag" do
      assert Target.parse_commit_message("Fix login bug") == :none
    end

    test "returns nil for ci tag not at start" do
      assert Target.parse_commit_message("Fix [ci:backend] login bug") == :none
    end

    test "handles underscores in names" do
      assert Target.parse_commit_message("[ci:deploy/pre_release] Test") ==
               {:ok,
                %{
                  groups: MapSet.new([:deploy]),
                  steps: MapSet.new([{:deploy, :pre_release}])
                }}
    end
  end

  describe "parse_ci_target/1" do
    test "parses single group" do
      assert Target.parse_ci_target("backend") ==
               {:ok, %{groups: MapSet.new([:backend]), steps: MapSet.new()}}
    end

    test "parses single step" do
      assert Target.parse_ci_target("backend/test") ==
               {:ok, %{groups: MapSet.new([:backend]), steps: MapSet.new([{:backend, :test}])}}
    end

    test "parses comma-separated targets" do
      assert Target.parse_ci_target("backend,native") ==
               {:ok, %{groups: MapSet.new([:backend, :native]), steps: MapSet.new()}}
    end

    test "returns nil for nil input" do
      assert Target.parse_ci_target(nil) == :none
    end

    test "returns nil for empty input" do
      assert Target.parse_ci_target("") == :none
    end
  end

  describe "resolve/1 with context" do
    test "prefers commit message over CI_TARGET" do
      ctx = %Pipette.Context{
        message: "[ci:backend] Fix",
        ci_target: "native"
      }

      assert Target.resolve(ctx) ==
               {:ok, %{groups: MapSet.new([:backend]), steps: MapSet.new()}}
    end

    test "falls back to CI_TARGET" do
      ctx = %Pipette.Context{
        message: "Fix login bug",
        ci_target: "native"
      }

      assert Target.resolve(ctx) ==
               {:ok, %{groups: MapSet.new([:native]), steps: MapSet.new()}}
    end

    test "returns :none when no targets" do
      ctx = %Pipette.Context{
        message: "Fix login bug",
        ci_target: nil
      }

      assert Target.resolve(ctx) == :none
    end
  end
end
