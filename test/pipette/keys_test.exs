defmodule Pipette.Dsl.Transformers.GenerateKeysTest do
  use ExUnit.Case, async: true

  describe "group keys" do
    test "generates group keys from atom names" do
      defmodule GroupKeysPipeline do
        use Pipette.DSL

        group :api do
          label("API")
          step(:test, label: "Test", command: "mix test")
        end

        group :web do
          label("Web")
          step(:build, label: "Build", command: "pnpm build")
        end
      end

      groups = Pipette.Info.groups(GroupKeysPipeline)
      keys = Enum.map(groups, & &1.key)
      assert "api" in keys
      assert "web" in keys
    end
  end

  describe "step keys" do
    test "generates step keys as group-step" do
      defmodule StepKeysPipeline do
        use Pipette.DSL

        group :api do
          label("API")
          step(:test, label: "Test", command: "mix test")
          step(:format, label: "Format", command: "mix format")
        end
      end

      [group] = Pipette.Info.groups(StepKeysPipeline)
      assert group.key == "api"
      test_step = Enum.find(group.steps, &(&1.name == :test))
      format_step = Enum.find(group.steps, &(&1.name == :format))
      assert test_step.key == "api-test"
      assert format_step.key == "api-format"
    end
  end

  describe "trigger keys" do
    test "generates trigger keys from atom names" do
      defmodule TriggerKeysPipeline do
        use Pipette.DSL

        group :api do
          label("API")
          step(:test, label: "Test", command: "mix test")
        end

        trigger :deploy_api do
          pipeline("deploy-pipeline")
          depends_on(:api)
        end
      end

      [trigger] = Pipette.Info.triggers(TriggerKeysPipeline)
      assert trigger.key == "deploy_api"
    end
  end

  describe "depends_on resolution" do
    test "resolves step depends_on atom to key string" do
      defmodule StepDepsAtomPipeline do
        use Pipette.DSL

        group :api do
          label("API")
          step(:compile, label: "Compile", command: "mix compile")
          step(:test, label: "Test", command: "mix test", depends_on: :compile)
        end
      end

      [group] = Pipette.Info.groups(StepDepsAtomPipeline)
      test_step = Enum.find(group.steps, &(&1.name == :test))
      assert test_step.depends_on == "api-compile"
    end

    test "resolves step depends_on list to key strings" do
      defmodule StepDepsListPipeline do
        use Pipette.DSL

        group :deploy do
          label("Deploy")
          step(:pre_release, label: "Pre", command: "pre.sh")
          step(:ios, label: "iOS", command: "ios.sh", depends_on: :pre_release)
          step(:android, label: "Android", command: "android.sh", depends_on: :pre_release)
          step(:post, label: "Post", command: "post.sh", depends_on: [:ios, :android])
        end
      end

      [group] = Pipette.Info.groups(StepDepsListPipeline)
      post = Enum.find(group.steps, &(&1.name == :post))
      assert post.depends_on == ["deploy-ios", "deploy-android"]
    end

    test "resolves cross-group step depends_on tuple" do
      defmodule CrossGroupDepsPipeline do
        use Pipette.DSL

        group :api do
          label("API")
          step(:test, label: "Test", command: "mix test")
        end

        group :deploy do
          label("Deploy")
          depends_on(:api)
          step(:push, label: "Push", command: "push.sh", depends_on: {:api, :test})
        end
      end

      deploy = Pipette.Info.groups(CrossGroupDepsPipeline) |> Enum.find(&(&1.name == :deploy))
      push = Enum.find(deploy.steps, &(&1.name == :push))
      assert push.depends_on == "api-test"
    end

    test "resolves group depends_on atom to key string" do
      defmodule GroupDepsAtomPipeline do
        use Pipette.DSL

        group :api do
          label("API")
          step(:test, label: "Test", command: "mix test")
        end

        group :packaging do
          label("Packaging")
          depends_on(:api)
          step(:build, label: "Build", command: "docker build .")
        end
      end

      packaging =
        Pipette.Info.groups(GroupDepsAtomPipeline) |> Enum.find(&(&1.name == :packaging))

      # Group depends_on stays as atoms (activation engine uses atoms)
      assert packaging.depends_on == :api
    end

    test "preserves group depends_on as atoms even with explicit keys" do
      defmodule GroupDepsExplicitKeyPipeline do
        use Pipette.DSL

        group :native do
          key("native-lint")
          label("Native")
          step(:lint, label: "Lint", command: "pnpm lint")
        end

        group :deploy do
          label("Deploy")
          depends_on(:native)
          step(:push, label: "Push", command: "push.sh")
        end
      end

      deploy =
        Pipette.Info.groups(GroupDepsExplicitKeyPipeline) |> Enum.find(&(&1.name == :deploy))

      # Stays as atom — Pipette.run/2 resolves to key strings before YAML output
      assert deploy.depends_on == :native
    end

    test "preserves trigger depends_on as atoms" do
      defmodule TriggerDepsExplicitKeyPipeline do
        use Pipette.DSL

        group :backend do
          key("backend-checks")
          label("Backend")
          step(:test, label: "Test", command: "mix test")
        end

        trigger :deploy do
          pipeline("deploy-pipeline")
          depends_on(:backend)
        end
      end

      [trigger] = Pipette.Info.triggers(TriggerDepsExplicitKeyPipeline)
      assert trigger.depends_on == :backend
    end

    test "preserves group depends_on list as atoms" do
      defmodule GroupDepsListPipeline do
        use Pipette.DSL

        group :api do
          label("API")
          step(:test, label: "Test", command: "mix test")
        end

        group :web do
          label("Web")
          step(:build, label: "Build", command: "pnpm build")
        end

        group :deploy do
          label("Deploy")
          depends_on([:api, :web])
          step(:push, label: "Push", command: "push.sh")
        end
      end

      deploy = Pipette.Info.groups(GroupDepsListPipeline) |> Enum.find(&(&1.name == :deploy))
      assert deploy.depends_on == [:api, :web]
    end

    test "preserves trigger depends_on as atom" do
      defmodule TriggerDepsPipeline do
        use Pipette.DSL

        group :api do
          label("API")
          step(:test, label: "Test", command: "mix test")
        end

        trigger :deploy do
          pipeline("deploy-pipeline")
          depends_on(:api)
        end
      end

      [trigger] = Pipette.Info.triggers(TriggerDepsPipeline)
      assert trigger.depends_on == :api
    end

    test "resolves step depends_on using actual step key when step has explicit key" do
      defmodule ExplicitKeyDepsPipeline do
        use Pipette.DSL

        group :backend do
          key("backend-checks")
          label("Backend")
          step(:test, key: "backend-test", label: "Test", command: "mix test")

          step(:junit,
            label: "JUnit",
            depends_on: :test,
            allow_dependency_failure: true,
            plugins: [{"junit-annotate#v2.7.0", %{}}]
          )
        end
      end

      [group] = Pipette.Info.groups(ExplicitKeyDepsPipeline)
      junit = Enum.find(group.steps, &(&1.name == :junit))
      # Should resolve to the ACTUAL key "backend-test", not "backend-checks-test"
      assert junit.depends_on == "backend-test"
    end

    test "preserves nil depends_on" do
      defmodule NilDepsPipeline do
        use Pipette.DSL

        group :api do
          label("API")
          step(:test, label: "Test", command: "mix test")
        end
      end

      [group] = Pipette.Info.groups(NilDepsPipeline)
      assert group.depends_on == nil
      [step] = group.steps
      assert step.depends_on == nil
    end

    test "passes through binary step depends_on unchanged" do
      defmodule BinaryDepsPipeline do
        use Pipette.DSL

        group :api do
          label("API")
          step(:test, label: "Test", command: "mix test", depends_on: "already-resolved")
        end
      end

      [group] = Pipette.Info.groups(BinaryDepsPipeline)
      [step] = group.steps
      assert step.depends_on == "already-resolved"
    end
  end

  describe "end-to-end YAML output" do
    test "depends_on resolves to actual group keys in generated YAML" do
      defmodule YamlKeysPipeline do
        use Pipette.DSL

        scope(:code, files: ["lib/**"])

        group :checks do
          key("lint-checks")
          label("Checks")
          scope(:code)
          step(:lint, label: "Lint", command: "mix credo")
        end

        group :deploy do
          label("Deploy")
          depends_on(:checks)
          only("main")
          step(:push, label: "Push", command: "push.sh")
        end

        trigger :notify do
          pipeline("notify-pipeline")
          depends_on(:checks)
          only("main")
        end
      end

      {:ok, yaml} =
        Pipette.generate(YamlKeysPipeline,
          env: %{
            "BUILDKITE_BRANCH" => "main",
            "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
            "BUILDKITE_COMMIT" => "abc",
            "BUILDKITE_MESSAGE" => "Test"
          },
          changed_files: ["lib/foo.ex"]
        )

      # Group depends_on should use the ACTUAL key "lint-checks", not "checks"
      assert yaml =~ "lint-checks"
      # Step key should use the actual group key prefix
      assert yaml =~ "lint-checks-lint"
      # Deploy group should appear (depends_on resolved correctly)
      assert yaml =~ "Deploy"
      # Trigger should appear (depends_on resolved correctly on main)
      assert yaml =~ "notify-pipeline"
    end
  end
end
