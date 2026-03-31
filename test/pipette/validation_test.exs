defmodule Pipette.Dsl.VerifiersTest do
  use ExUnit.Case, async: true

  alias Pipette.Dsl.Verifiers.{ValidateRefs, ValidateAcyclic, ValidateSteps}

  # Helper to build a minimal dsl_state map for testing verifiers directly.
  # This mirrors the structure Spark passes to verify/1.
  defp build_dsl_state(entities, opts \\ []) do
    force_activate = Keyword.get(opts, :force_activate, %{})

    %{
      [:pipeline] => %{
        entities: entities,
        opts: [force_activate: force_activate]
      }
    }
  end

  describe "ValidateRefs — scope references" do
    test "passes for valid scope reference" do
      entities = [
        %Pipette.Scope{name: :api_code, files: ["apps/api/**"]},
        %Pipette.Group{name: :api, scope: :api_code, steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]}
      ]

      assert :ok = ValidateRefs.verify(build_dsl_state(entities))
    end

    test "returns error on undefined scope reference" do
      entities = [
        %Pipette.Scope{name: :api_code, files: ["apps/api/**"]},
        %Pipette.Group{name: :api, scope: :nonexistent, steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]}
      ]

      assert {:error, %Spark.Error.DslError{message: message}} = ValidateRefs.verify(build_dsl_state(entities))
      assert message =~ "undefined scope :nonexistent"
    end

    test "passes when group has no scope" do
      entities = [
        %Pipette.Group{name: :deploy, steps: [%Pipette.Step{name: :push, label: "Push", command: "push.sh"}]}
      ]

      assert :ok = ValidateRefs.verify(build_dsl_state(entities))
    end
  end

  describe "ValidateRefs — depends_on references" do
    test "returns error on undefined group depends_on" do
      # After GenerateKeys, depends_on is a string
      entities = [
        %Pipette.Group{name: :deploy, depends_on: "nonexistent", steps: [%Pipette.Step{name: :push, label: "Push", command: "push.sh"}]}
      ]

      assert {:error, %Spark.Error.DslError{message: message}} = ValidateRefs.verify(build_dsl_state(entities))
      assert message =~ "depends on undefined group :nonexistent"
    end

    test "returns error on undefined trigger depends_on" do
      entities = [
        %Pipette.Group{name: :api, steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]},
        %Pipette.Trigger{name: :deploy, pipeline: "deploy-pipeline", depends_on: "nonexistent"}
      ]

      assert {:error, %Spark.Error.DslError{message: message}} = ValidateRefs.verify(build_dsl_state(entities))
      assert message =~ "depends on undefined group :nonexistent"
    end

    test "returns error on undefined force_activate group" do
      entities = [
        %Pipette.Group{name: :api, steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]}
      ]

      state = build_dsl_state(entities, force_activate: %{"FORCE" => [:nonexistent]})
      assert {:error, %Spark.Error.DslError{message: message}} = ValidateRefs.verify(state)
      assert message =~ "force_activate"
      assert message =~ "undefined group :nonexistent"
    end

    test "force_activate :all passes" do
      entities = [
        %Pipette.Group{name: :api, steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]}
      ]

      state = build_dsl_state(entities, force_activate: %{"FORCE_ALL" => :all})
      assert :ok = ValidateRefs.verify(state)
    end
  end

  describe "ValidateAcyclic" do
    test "returns error on dependency cycle" do
      # After GenerateKeys, depends_on is a string
      entities = [
        %Pipette.Group{name: :a, depends_on: "c", steps: [%Pipette.Step{name: :s, label: "S", command: "s"}]},
        %Pipette.Group{name: :b, depends_on: "a", steps: [%Pipette.Step{name: :s, label: "S", command: "s"}]},
        %Pipette.Group{name: :c, depends_on: "b", steps: [%Pipette.Step{name: :s, label: "S", command: "s"}]}
      ]

      assert {:error, %Spark.Error.DslError{message: message}} = ValidateAcyclic.verify(build_dsl_state(entities))
      assert message =~ ~r/[Cc]ycle/
    end

    test "passes for valid dependency chain" do
      entities = [
        %Pipette.Scope{name: :code, files: ["lib/**"]},
        %Pipette.Group{name: :api, scope: :code, steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]},
        %Pipette.Group{name: :packaging, depends_on: "api", steps: [%Pipette.Step{name: :build, label: "Build", command: "docker build ."}]},
        %Pipette.Group{name: :deploy, depends_on: "packaging", steps: [%Pipette.Step{name: :push, label: "Push", command: "push.sh"}]}
      ]

      assert :ok = ValidateAcyclic.verify(build_dsl_state(entities))
    end
  end

  describe "ValidateSteps" do
    test "returns error when step is missing a label" do
      entities = [
        %Pipette.Group{name: :api, steps: [%Pipette.Step{name: :test, command: "mix test"}]}
      ]

      assert {:error, %Spark.Error.DslError{message: message}} = ValidateSteps.verify(build_dsl_state(entities))
      assert message =~ "missing a label"
    end

    test "passes for steps with labels" do
      entities = [
        %Pipette.Group{name: :api, steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]}
      ]

      assert :ok = ValidateSteps.verify(build_dsl_state(entities))
    end
  end

  describe "integration — DSL compilation" do
    test "valid pipeline compiles successfully" do
      defmodule ValidPipeline do
        use Pipette.DSL
        scope :api_code, files: ["apps/api/**"]
        group :api do
          label "API"
          scope :api_code
          step :test, label: "Test", command: "mix test"
        end
      end

      assert Pipette.Info.groups(ValidPipeline) |> length() == 1
    end

    test "valid chain compiles successfully" do
      defmodule ValidChainPipeline do
        use Pipette.DSL
        scope :code, files: ["lib/**"]
        group :api do
          label "API"
          scope :code
          step :test, label: "Test", command: "mix test"
        end
        group :packaging do
          label "Packaging"
          depends_on :api
          step :build, label: "Build", command: "docker build ."
        end
        group :deploy do
          label "Deploy"
          depends_on :packaging
          step :push, label: "Push", command: "push.sh"
        end
      end

      assert Pipette.Info.groups(ValidChainPipeline) |> length() == 3
    end

    test "force_activate :all compiles successfully" do
      defmodule ForceAllPipeline do
        use Pipette.DSL
        force_activate %{"FORCE_ALL" => :all}
        group :api do
          label "API"
          step :test, label: "Test", command: "mix test"
        end
      end

      assert Pipette.Info.groups(ForceAllPipeline) |> length() == 1
    end
  end
end
