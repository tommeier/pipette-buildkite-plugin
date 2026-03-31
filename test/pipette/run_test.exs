defmodule Pipette.RunTest do
  use ExUnit.Case

  defmodule TestPipeline do
    use Pipette.DSL

    branch "main", scopes: :all, disable: [:targeting]

    scope :api_code, files: ["apps/api/**"]
    scope :web_code, files: ["apps/web/**"]

    ignore ["docs/**", "*.md"]
    env %{LANG: "C.UTF-8"}
    secrets ["API_TOKEN"]

    group :api do
      label ":elixir: API"
      scope :api_code
      step :test, label: "Test", command: "mix test"
    end

    group :web do
      label ":globe: Web"
      scope :web_code
      step :lint, label: "Lint", command: "pnpm lint"
    end
  end

  defmodule ForceActivatePipeline do
    use Pipette.DSL

    scope :api_code, files: ["apps/api/**"]
    scope :web_code, files: ["apps/web/**"]

    force_activate %{
      "FORCE_DEPLOY" => [:deploy],
      "FORCE_ALL" => :all
    }

    group :api do
      label ":elixir: API"
      scope :api_code
      step :test, label: "Test", command: "mix test"
    end

    group :web do
      label ":globe: Web"
      scope :web_code
      step :build, label: "Build", command: "pnpm build"
    end

    group :deploy do
      label ":rocket: Deploy"
      depends_on [:api, :web]
      step :push, label: "Push", command: "./deploy.sh"
    end
  end

  describe "run/2 with dry_run" do
    test "generates YAML for a feature branch with api changes" do
      opts = [
        dry_run: true,
        env: %{
          "BUILDKITE_BRANCH" => "feature/login",
          "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
          "BUILDKITE_COMMIT" => "abc123",
          "BUILDKITE_MESSAGE" => "Fix login"
        },
        changed_files: ["apps/api/lib/user.ex"]
      ]

      assert {:ok, yaml} = Pipette.run(TestPipeline, opts)

      assert yaml =~ "API"
      assert yaml =~ "mix test"
      refute yaml =~ "Web"
    end

    test "generates YAML for main branch (all groups)" do
      opts = [
        dry_run: true,
        env: %{
          "BUILDKITE_BRANCH" => "main",
          "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
          "BUILDKITE_COMMIT" => "abc123",
          "BUILDKITE_MESSAGE" => "Merge PR"
        },
        changed_files: ["apps/api/lib/user.ex"]
      ]

      assert {:ok, yaml} = Pipette.run(TestPipeline, opts)

      assert yaml =~ "API"
      assert yaml =~ "Web"
    end

    test "returns :noop when all changes are ignored" do
      opts = [
        dry_run: true,
        env: %{
          "BUILDKITE_BRANCH" => "feature/docs",
          "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
          "BUILDKITE_MESSAGE" => "Update docs"
        },
        changed_files: ["docs/guide.md", "README.md"]
      ]

      assert :noop = Pipette.run(TestPipeline, opts)
    end

    test "includes pipeline-level config in YAML" do
      opts = [
        dry_run: true,
        env: %{
          "BUILDKITE_BRANCH" => "main",
          "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
          "BUILDKITE_MESSAGE" => "Deploy"
        },
        changed_files: ["apps/api/lib/user.ex"]
      ]

      assert {:ok, yaml} = Pipette.run(TestPipeline, opts)

      assert yaml =~ "LANG"
      assert yaml =~ "API_TOKEN"
    end

    test "extra_groups callback injects runtime groups" do
      extra_groups = fn _ctx, _changed_files ->
        [
          %Pipette.Group{
            name: :extra,
            label: ":package: Extra",
            key: "extra",
            steps: [
              %Pipette.Step{
                name: :check,
                label: "Check",
                command: "echo ok",
                key: "extra-check"
              }
            ]
          }
        ]
      end

      opts = [
        dry_run: true,
        env: %{
          "BUILDKITE_BRANCH" => "feature/test",
          "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
          "BUILDKITE_COMMIT" => "abc123",
          "BUILDKITE_MESSAGE" => "Test"
        },
        changed_files: ["apps/api/lib/user.ex"],
        extra_groups: extra_groups
      ]

      assert {:ok, yaml} = Pipette.run(TestPipeline, opts)

      assert yaml =~ "API"
      assert yaml =~ "Extra"
      assert yaml =~ "echo ok"
    end

    test "extra_groups are included even when no DSL groups activate" do
      extra_groups = fn _ctx, _changed_files ->
        [
          %Pipette.Group{
            name: :runtime,
            label: ":gear: Runtime",
            key: "runtime",
            steps: [
              %Pipette.Step{
                name: :check,
                label: "Check",
                command: "echo runtime",
                key: "runtime-check"
              }
            ]
          }
        ]
      end

      opts = [
        dry_run: true,
        env: %{
          "BUILDKITE_BRANCH" => "feature/pkg",
          "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
          "BUILDKITE_MESSAGE" => "Update package"
        },
        changed_files: ["packages/foo/lib/foo.ex"],
        extra_groups: extra_groups
      ]

      assert {:ok, yaml} = Pipette.run(TestPipeline, opts)
      assert yaml =~ "Runtime"
    end

    test "respects commit message targeting on feature branch" do
      opts = [
        dry_run: true,
        env: %{
          "BUILDKITE_BRANCH" => "feature/x",
          "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
          "BUILDKITE_MESSAGE" => "[ci:web] Fix styles"
        },
        changed_files: ["apps/api/lib/user.ex", "apps/web/src/App.tsx"]
      ]

      assert {:ok, yaml} = Pipette.run(TestPipeline, opts)

      assert yaml =~ "Web"
      refute yaml =~ ":elixir: API"
    end
  end

  describe "generate/2" do
    test "returns YAML without uploading" do
      opts = [
        env: %{
          "BUILDKITE_BRANCH" => "main",
          "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
          "BUILDKITE_COMMIT" => "abc123",
          "BUILDKITE_MESSAGE" => "Test"
        },
        changed_files: ["apps/api/lib/user.ex"]
      ]

      assert {:ok, yaml} = Pipette.generate(TestPipeline, opts)

      assert yaml =~ "API"
      assert is_binary(yaml)
    end

    test "returns :noop when nothing activated" do
      opts = [
        env: %{
          "BUILDKITE_BRANCH" => "feature/docs",
          "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
          "BUILDKITE_MESSAGE" => "Docs only"
        },
        changed_files: ["docs/readme.md", "CHANGELOG.md"]
      ]

      assert :noop = Pipette.generate(TestPipeline, opts)
    end
  end

  describe "force_activate" do
    test "activates groups via env var" do
      opts = [
        dry_run: true,
        env: %{
          "BUILDKITE_BRANCH" => "feature/hotfix",
          "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
          "BUILDKITE_MESSAGE" => "Hotfix",
          "FORCE_DEPLOY" => "true"
        },
        changed_files: ["apps/api/lib/user.ex"]
      ]

      assert {:ok, yaml} = Pipette.run(ForceActivatePipeline, opts)

      assert yaml =~ "Deploy"
      assert yaml =~ "API"
    end

    test ":all activates everything" do
      opts = [
        dry_run: true,
        env: %{
          "BUILDKITE_BRANCH" => "feature/hotfix",
          "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
          "BUILDKITE_MESSAGE" => "Hotfix",
          "FORCE_ALL" => "true"
        },
        changed_files: []
      ]

      assert {:ok, yaml} = Pipette.run(ForceActivatePipeline, opts)

      assert yaml =~ "API"
      assert yaml =~ "Web"
      assert yaml =~ "Deploy"
    end

    test "env var not set does not force activate" do
      opts = [
        dry_run: true,
        env: %{
          "BUILDKITE_BRANCH" => "feature/hotfix",
          "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
          "BUILDKITE_MESSAGE" => "Hotfix"
        },
        changed_files: ["packages/unrelated/lib/foo.ex"]
      ]

      assert :noop = Pipette.run(ForceActivatePipeline, opts)
    end
  end
end
