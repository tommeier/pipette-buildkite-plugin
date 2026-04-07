defmodule Pipette.DslTest do
  use ExUnit.Case, async: true

  describe "basic compilation" do
    test "compiles a pipeline with all entity types" do
      defmodule FullPipeline do
        use Pipette.DSL

        branch("main", scopes: :all, disable: [:targeting])
        branch("release/*", scopes: [:api])

        scope(:api_code, files: ["apps/api/**", "mix.exs"], exclude: ["**/*.md"])
        scope(:infra, files: ["infra/**"], activates: :all)

        env(%{MIX_ENV: "test"})
        secrets(["API_TOKEN"])
        ignore(["docs/**", "*.md"])
        cache(paths: ["deps/"])
        force_activate(%{"FORCE_DEPLOY" => [:deploy]})

        group :api do
          label(":elixir: API")
          scope(:api_code)
          step(:test, label: "Test", command: "mix test", timeout_in_minutes: 15)
          step(:lint, label: "Lint", command: "mix credo")
        end

        group :deploy do
          label(":rocket: Deploy")
          depends_on(:api)
          only("main")
          step(:push, label: "Push", command: "./deploy.sh")
        end

        trigger :notify do
          label(":bell: Notify")
          pipeline("notify-pipeline")
          depends_on(:api)
          only("main")
          async(true)
        end
      end

      branches = Pipette.Info.branches(FullPipeline)
      assert length(branches) == 2
      assert %Pipette.Branch{pattern: "main", scopes: :all} = hd(branches)

      scopes = Pipette.Info.scopes(FullPipeline)
      assert length(scopes) == 2
      api_scope = Enum.find(scopes, &(&1.name == :api_code))
      assert api_scope.files == ["apps/api/**", "mix.exs"]
      assert api_scope.exclude == ["**/*.md"]

      groups = Pipette.Info.groups(FullPipeline)
      assert length(groups) == 2
      api_group = Enum.find(groups, &(&1.name == :api))
      assert api_group.label == ":elixir: API"
      assert api_group.scope == :api_code
      assert length(api_group.steps) == 2

      deploy_group = Enum.find(groups, &(&1.name == :deploy))
      assert deploy_group.depends_on == :api
      assert deploy_group.only == "main"

      triggers = Pipette.Info.triggers(FullPipeline)
      assert length(triggers) == 1
      assert hd(triggers).pipeline == "notify-pipeline"
      assert hd(triggers).async == true

      assert Pipette.Info.env(FullPipeline) == %{MIX_ENV: "test"}
      assert Pipette.Info.secrets(FullPipeline) == ["API_TOKEN"]
      assert Pipette.Info.ignore(FullPipeline) == ["docs/**", "*.md"]
      assert Pipette.Info.cache(FullPipeline) == [paths: ["deps/"]]
      assert Pipette.Info.force_activate(FullPipeline) == %{"FORCE_DEPLOY" => [:deploy]}
    end
  end

  describe "step syntax" do
    test "keyword syntax works" do
      defmodule KeywordStepPipeline do
        use Pipette.DSL

        group :app do
          label("App")

          step(:test,
            label: "Test",
            command: "mix test",
            timeout_in_minutes: 15,
            env: %{MIX_ENV: "test"},
            retry: %{automatic: [%{exit_status: -1, limit: 2}]}
          )
        end
      end

      [group] = Pipette.Info.groups(KeywordStepPipeline)
      [step] = group.steps
      assert step.name == :test
      assert step.timeout_in_minutes == 15
      assert step.env == %{MIX_ENV: "test"}
      assert step.retry == %{automatic: [%{exit_status: -1, limit: 2}]}
    end

    test "block syntax works" do
      defmodule BlockStepPipeline do
        use Pipette.DSL

        group :app do
          label("App")

          step :build do
            label(":docker: Build")
            command("bash build.sh")
            timeout_in_minutes(20)
            plugins([{"docker#v5.0", %{image: "elixir:1.17"}}])
            agents(%{queue: "deploy"})
            secrets(["GCP_KEY"])
          end
        end
      end

      [group] = Pipette.Info.groups(BlockStepPipeline)
      [step] = group.steps
      assert step.name == :build
      assert step.label == ":docker: Build"
      assert step.command == "bash build.sh"
      assert step.timeout_in_minutes == 20
      assert step.plugins == [{"docker#v5.0", %{image: "elixir:1.17"}}]
      assert step.agents == %{queue: "deploy"}
      assert step.secrets == ["GCP_KEY"]
    end
  end

  describe "module attributes and functions" do
    test "module attributes work in DSL" do
      defmodule AttrPipeline do
        use Pipette.DSL

        @shared_env %{LANG: "C.UTF-8"}

        group :app do
          label("App")
          step(:test, label: "Test", command: "mix test", env: @shared_env)
        end
      end

      [group] = Pipette.Info.groups(AttrPipeline)
      [step] = group.steps
      assert step.env == %{LANG: "C.UTF-8"}
    end
  end

  describe "empty pipeline" do
    test "compiles with no entities" do
      defmodule EmptyPipeline do
        use Pipette.DSL
      end

      assert Pipette.Info.groups(EmptyPipeline) == []
      assert Pipette.Info.scopes(EmptyPipeline) == []
      assert Pipette.Info.branches(EmptyPipeline) == []
      assert Pipette.Info.triggers(EmptyPipeline) == []
    end
  end

  describe "scope with ignore_global" do
    test "scope/1 sets scope without ignore_global_scope" do
      defmodule ScopeSimplePipeline do
        use Pipette.DSL

        scope(:code, files: ["lib/**"])

        group :app do
          label("App")
          scope(:code)
          step(:test, label: "Test", command: "mix test")
        end
      end

      [group] = Pipette.Info.groups(ScopeSimplePipeline)
      assert group.scope == :code
      assert group.ignore_global_scope == false
    end

    test "scope/2 with ignore_global: true sets ignore_global_scope" do
      defmodule ScopeIgnoreGlobalPipeline do
        use Pipette.DSL

        scope(:web_code, files: ["apps/web/**"])

        group :deploy do
          label(":rocket: Deploy")
          scope(:web_code, ignore_global: true)
          only("main")
          step(:release, label: "Release", command: "./deploy.sh")
        end
      end

      [group] = Pipette.Info.groups(ScopeIgnoreGlobalPipeline)
      assert group.scope == :web_code
      assert group.ignore_global_scope == true
    end

    test "group without scope has nil scope and false ignore_global_scope" do
      defmodule NoScopePipeline do
        use Pipette.DSL

        group :misc do
          label("Misc")
          step(:check, label: "Check", command: "echo ok")
        end
      end

      [group] = Pipette.Info.groups(NoScopePipeline)
      assert group.scope == nil
      assert group.ignore_global_scope == false
    end
  end

  describe "step-level only" do
    test "step with only: keyword compiles and stores the value" do
      defmodule StepOnlyPipeline do
        use Pipette.DSL

        scope(:code, files: ["lib/**"])

        group :ci do
          label("CI")
          scope(:code)
          step(:build, label: "Build", command: "make build")
          step(:publish, label: "Publish", command: "make publish", only: "main")
        end
      end

      [group] = Pipette.Info.groups(StepOnlyPipeline)
      publish = Enum.find(group.steps, &(&1.name == :publish))
      assert publish.only == "main"

      build = Enum.find(group.steps, &(&1.name == :build))
      assert build.only == nil
    end

    test "step with only: list compiles" do
      defmodule StepOnlyListPipeline do
        use Pipette.DSL

        group :ci do
          label("CI")
          step(:deploy, label: "Deploy", command: "./deploy.sh", only: ["main", "release/*"])
        end
      end

      [group] = Pipette.Info.groups(StepOnlyListPipeline)
      [step] = group.steps
      assert step.only == ["main", "release/*"]
    end
  end

  describe "to_pipeline/1" do
    test "assembles a Pipeline struct from Spark data" do
      defmodule ToPipelineTest do
        use Pipette.DSL

        env(%{MIX_ENV: "test"})
        ignore(["*.md"])

        scope(:code, files: ["lib/**"])

        group :app do
          label("App")
          scope(:code)
          step(:test, label: "Test", command: "mix test")
        end
      end

      pipeline = Pipette.Info.to_pipeline(ToPipelineTest)

      assert %Pipette.Pipeline{} = pipeline
      assert length(pipeline.groups) == 1
      assert length(pipeline.scopes) == 1
      assert pipeline.env == %{MIX_ENV: "test"}
      assert pipeline.ignore == ["*.md"]
    end
  end
end
