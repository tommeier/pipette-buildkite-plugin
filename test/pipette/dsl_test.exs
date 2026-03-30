defmodule Pipette.DSLTest do
  use ExUnit.Case, async: true

  import Pipette.DSL

  describe "build_pipeline/1" do
    test "builds a pipeline struct" do
      p =
        build_pipeline(
          branches: [branch("main", scopes: :all)],
          scopes: [scope(:code, files: ["lib/**"])],
          groups: [group(:app, label: "App", steps: [step(:test, label: "Test")])],
          ignore: ["*.md"]
        )

      assert %Pipette.Pipeline{} = p
      assert length(p.branches) == 1
      assert length(p.scopes) == 1
      assert length(p.groups) == 1
      assert p.ignore == ["*.md"]
    end

    test "raises on unknown keys" do
      assert_raise KeyError, fn ->
        build_pipeline(unknown_option: true)
      end
    end

    test "pipeline/1 is a deprecated alias" do
      assert pipeline(ignore: ["*.md"]) == build_pipeline(ignore: ["*.md"])
    end
  end

  describe "branch/2" do
    test "builds with pattern and options" do
      b = branch("main", scopes: :all, disable: [:targeting])
      assert b == %Pipette.Branch{pattern: "main", scopes: :all, disable: [:targeting]}
    end

    test "builds with pattern only" do
      b = branch("feature/**")
      assert b == %Pipette.Branch{pattern: "feature/**"}
    end
  end

  describe "scope/2" do
    test "builds with name and files" do
      s = scope(:api_code, files: ["apps/api/**"], exclude: ["**/*.md"], activates: :all)

      assert s == %Pipette.Scope{
               name: :api_code,
               files: ["apps/api/**"],
               exclude: ["**/*.md"],
               activates: :all
             }
    end
  end

  describe "group/2" do
    test "builds with nested steps" do
      g =
        group(:api,
          label: ":elixir: API",
          scope: :api_code,
          depends_on: :infra,
          only: ["main"],
          key: "api-checks",
          steps: [
            step(:test, label: "Test", command: "mix test", timeout_in_minutes: 15),
            step(:lint, label: "Lint", command: "mix credo", timeout_in_minutes: 10)
          ]
        )

      assert g.name == :api
      assert g.label == ":elixir: API"
      assert g.scope == :api_code
      assert g.depends_on == :infra
      assert g.only == ["main"]
      assert g.key == "api-checks"
      assert length(g.steps) == 2
      assert hd(g.steps).name == :test
    end
  end

  describe "step/2" do
    test "builds with all common options" do
      s =
        step(:deploy,
          label: "Deploy",
          command: "./deploy.sh",
          env: %{NODE_ENV: "production"},
          agents: %{queue: "deploy"},
          timeout_in_minutes: 30,
          depends_on: :build,
          retry: %{automatic: [%{exit_status: 1, limit: 2}]},
          soft_fail: true,
          concurrency: 1,
          concurrency_group: "deploy"
        )

      assert s.name == :deploy
      assert s.label == "Deploy"
      assert s.command == "./deploy.sh"
      assert s.env == %{NODE_ENV: "production"}
      assert s.agents == %{queue: "deploy"}
      assert s.timeout_in_minutes == 30
      assert s.depends_on == :build
      assert s.soft_fail == true
      assert s.concurrency == 1
    end

    test "raises on typo in option name" do
      assert_raise KeyError, fn ->
        # typo: lable instead of label
        step(:test, lable: "Test")
      end
    end
  end

  describe "trigger/2" do
    test "builds with all options" do
      t =
        trigger(:deploy_api,
          label: ":rocket: Deploy",
          pipeline: "my-deploy-pipeline",
          depends_on: :api,
          only: ["main"],
          async: true,
          build: %{commit: "${BUILDKITE_COMMIT}"}
        )

      assert t.name == :deploy_api
      assert t.pipeline == "my-deploy-pipeline"
      assert t.depends_on == :api
      assert t.only == ["main"]
      assert t.async == true
    end
  end

  describe "equivalence with raw structs" do
    test "DSL output matches raw struct construction" do
      dsl_result =
        group(:api,
          label: ":elixir: API",
          scope: :api_code,
          steps: [
            step(:test, label: "Test", command: "mix test"),
            step(:lint, label: "Lint", command: "mix credo")
          ]
        )

      raw_result = %Pipette.Group{
        name: :api,
        label: ":elixir: API",
        scope: :api_code,
        steps: [
          %Pipette.Step{name: :test, label: "Test", command: "mix test"},
          %Pipette.Step{name: :lint, label: "Lint", command: "mix credo"}
        ]
      }

      assert dsl_result == raw_result
    end
  end
end
