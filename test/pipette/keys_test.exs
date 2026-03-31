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

      assert packaging.depends_on == "api"
    end

    test "resolves group depends_on using actual group key when group has explicit key" do
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

      # Should resolve to the ACTUAL key "native-lint", not "native"
      assert deploy.depends_on == "native-lint"
    end

    test "resolves trigger depends_on using actual group key" do
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
      # Should resolve to "backend-checks", not "backend"
      assert trigger.depends_on == "backend-checks"
    end

    test "resolves group depends_on list to key strings" do
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
      assert deploy.depends_on == ["api", "web"]
    end

    test "resolves trigger depends_on to key string" do
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
      assert trigger.depends_on == "api"
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
end
