defmodule Pipette.IntegrationTest do
  use ExUnit.Case, async: true

  defmodule TestPipeline do
    use Pipette.DSL

    branch "main", scopes: :all, disable: [:targeting]
    branch "merge-queue/**", scopes: :all, disable: [:targeting]

    scope :api_code, files: ["apps/api/**"]
    scope :web_code, files: ["apps/web/**"]
    scope :infra_code, files: ["infra/**"], exclude: ["**/*.md"]
    scope :scripts, files: ["**/*.sh"]
    scope :root_config, files: [".buildkite/**", "Justfile", ".mise.toml"], activates: :all

    env %{MIX_ENV: "test", NODE_ENV: "test"}
    secrets ["DEPLOY_TOKEN"]
    cache paths: ["deps/", "node_modules/"]
    ignore ["docs/**", "*.md", "LICENSE*"]
    force_activate %{"FORCE_DEPLOY" => [:web, :deploy]}

    group :api do
      label ":elixir: API"
      scope :api_code
      step :format, label: "Format", command: "mix format --check-formatted"
      step :test, label: "Test", command: "mix test"
    end

    group :web do
      label ":globe_with_meridians: Web"
      scope :web_code
      step :lint, label: "Lint", command: "pnpm lint"
      step :test, label: "Test", command: "pnpm test"
    end

    group :deploy do
      label ":rocket: Deploy"
      depends_on :web
      only ["main", "merge-queue/**"]
      step :pre_release, label: "Pre-Release", command: "./pre-release.sh"
      step :release, label: "Release", command: "./release.sh", depends_on: :pre_release
    end

    group :infra do
      label ":terraform: Infra"
      scope :infra_code
      step :validate, label: "Validate", command: "terraform validate"
      step :plan, label: "Plan", command: "terraform plan"
    end

    group :lint do
      label ":bash: Lint"
      scope :scripts
      step :shellcheck, label: "ShellCheck", command: "shellcheck **/*.sh"
      step :shfmt, label: "shfmt", command: "shfmt -d ."
    end

    trigger :deploy_api do
      label ":rocket: Deploy API"
      pipeline "my-deploy-pipeline"
      depends_on :api
      only "main"
    end
  end

  defp ctx(overrides \\ %{}) do
    Map.merge(
      %{
        "BUILDKITE_BRANCH" => "feature/test",
        "BUILDKITE_COMMIT" => "abc123",
        "BUILDKITE_MESSAGE" => "Test commit",
        "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main"
      },
      overrides
    )
  end

  defp generate(opts) do
    Pipette.generate(TestPipeline, opts)
  end

  defp active_group_names({:ok, yaml}) do
    # Parse group keys from YAML by looking for "group:" entries
    yaml
    |> String.split("\n")
    |> Enum.reduce({nil, MapSet.new()}, fn line, {_current_key, names} = acc ->
      cond do
        String.contains?(line, "key:") and not String.starts_with?(String.trim(line), "- ") ->
          key = line |> String.split("key:") |> List.last() |> String.trim() |> String.trim("'\"")
          {key, MapSet.put(names, key)}

        true ->
          acc
      end
    end)
    |> elem(1)
  end

  defp active_group_names(:noop), do: MapSet.new()

  describe "main branch" do
    test "all 5 groups active + trigger fires" do
      result =
        generate(
          env: ctx(%{"BUILDKITE_BRANCH" => "main"}),
          changed_files: ["apps/api/lib/user.ex"]
        )

      assert {:ok, yaml} = result

      names = active_group_names(result)
      assert "api" in names
      assert "web" in names
      assert "deploy" in names
      assert "infra" in names
      assert "lint" in names

      assert yaml =~ "my-deploy-pipeline"
    end
  end

  describe "feature branch + API changes" do
    test "only :api active, no trigger" do
      result =
        generate(
          env: ctx(),
          changed_files: ["apps/api/lib/user.ex", "apps/api/test/user_test.exs"]
        )

      assert {:ok, yaml} = result

      names = active_group_names(result)
      assert "api" in names
      refute "web" in names
      refute "deploy" in names
      refute "infra" in names
      refute "lint" in names

      refute yaml =~ "my-deploy-pipeline"
    end
  end

  describe "feature branch + web changes" do
    test "only :web active, deploy filtered by only" do
      result =
        generate(
          env: ctx(),
          changed_files: ["apps/web/src/App.tsx"]
        )

      assert {:ok, _yaml} = result

      names = active_group_names(result)
      assert "web" in names
      refute "deploy" in names
      refute "api" in names
    end
  end

  describe "feature branch + infra changes" do
    test "only :infra active" do
      result =
        generate(
          env: ctx(),
          changed_files: ["infra/main.tf"]
        )

      assert {:ok, _yaml} = result

      names = active_group_names(result)
      assert "infra" in names
      refute "api" in names
      refute "web" in names
      refute "deploy" in names
    end
  end

  describe "feature branch + shell script changes" do
    test "only :lint active" do
      result =
        generate(
          env: ctx(),
          changed_files: ["scripts/deploy.sh"]
        )

      assert {:ok, _yaml} = result

      names = active_group_names(result)
      assert "lint" in names
      refute "api" in names
      refute "web" in names
    end
  end

  describe "root config changes" do
    test "all groups activated via activates: :all" do
      result =
        generate(
          env: ctx(),
          changed_files: [".buildkite/pipeline.yml"]
        )

      assert {:ok, yaml} = result

      names = active_group_names(result)
      assert "api" in names
      assert "web" in names
      assert "infra" in names
      assert "lint" in names
      # deploy is filtered by only on feature branch
      refute "deploy" in names

      refute yaml =~ "my-deploy-pipeline"
    end
  end

  describe "docs-only changes" do
    test "returns :noop" do
      result =
        generate(
          env: ctx(),
          changed_files: ["docs/guide.md", "README.md"]
        )

      assert :noop = result
    end
  end

  describe "merge queue branch" do
    test "all 5 groups active, trigger does not fire (only: main)" do
      result =
        generate(
          env: ctx(%{"BUILDKITE_BRANCH" => "merge-queue/main/pr-99"}),
          changed_files: ["apps/api/lib/user.ex"]
        )

      assert {:ok, yaml} = result

      names = active_group_names(result)
      assert "api" in names
      assert "web" in names
      assert "deploy" in names
      assert "infra" in names
      assert "lint" in names

      # Trigger only: ["main"], so it does not fire on merge-queue
      refute yaml =~ "my-deploy-pipeline"
    end
  end

  describe "commit message targeting [ci:api]" do
    test "only :api group activated" do
      result =
        generate(
          env: ctx(%{"BUILDKITE_MESSAGE" => "[ci:api] Quick API fix"}),
          changed_files: ["apps/api/lib/user.ex", "apps/web/src/App.tsx"]
        )

      assert {:ok, _yaml} = result

      names = active_group_names(result)
      assert "api" in names
      refute "web" in names
      refute "deploy" in names
    end
  end

  describe "commit message targeting [ci:api/test]" do
    test "only :api with only the test step (+ its deps)" do
      result =
        generate(
          env: ctx(%{"BUILDKITE_MESSAGE" => "[ci:api/test] Fix flaky test"}),
          changed_files: ["apps/api/lib/user.ex"]
        )

      assert {:ok, yaml} = result

      names = active_group_names(result)
      assert "api" in names

      assert yaml =~ "Test"
      refute yaml =~ "Format"
    end
  end

  describe "FORCE_DEPLOY=true on feature branch" do
    test ":web + :deploy active, bypasses only filter" do
      result =
        generate(
          env: ctx(%{"FORCE_DEPLOY" => "true"}),
          changed_files: ["README.md"]
        )

      assert {:ok, _yaml} = result

      names = active_group_names(result)
      assert "web" in names
      assert "deploy" in names
    end
  end

  describe "FORCE_DEPLOY not set" do
    test "no forced groups" do
      result =
        generate(
          env: ctx(),
          changed_files: ["README.md"]
        )

      assert :noop = result
    end
  end

  describe "CI_TARGET=api on feature branch" do
    test "only :api activated" do
      result =
        generate(
          env: ctx(%{"CI_TARGET" => "api"}),
          changed_files: ["apps/web/src/App.tsx"]
        )

      assert {:ok, _yaml} = result

      names = active_group_names(result)
      assert "api" in names
      refute "web" in names
    end
  end

  describe "YAML structure" do
    test "output contains expected keys, depends_on, labels" do
      {:ok, yaml} =
        generate(
          env: ctx(%{"BUILDKITE_BRANCH" => "main"}),
          changed_files: ["apps/api/lib/user.ex"]
        )

      assert yaml =~ "group:"
      assert yaml =~ "key:"
      assert yaml =~ "label:"
      assert yaml =~ "command:"

      # Pipeline-level config
      assert yaml =~ "MIX_ENV"
      assert yaml =~ "DEPLOY_TOKEN"
      assert yaml =~ "paths"

      # Deploy group has depends_on
      assert yaml =~ "depends_on"

      # Step keys follow group-step pattern
      assert yaml =~ "api-format"
      assert yaml =~ "api-test"
      assert yaml =~ "web-lint"
      assert yaml =~ "deploy-pre_release"
      assert yaml =~ "deploy-release"

      # Trigger present on main
      assert yaml =~ "my-deploy-pipeline"
    end
  end

  describe "trigger only fires on main" do
    test "feature branch with all groups but no trigger" do
      result =
        generate(
          env: ctx(),
          changed_files: [".buildkite/pipeline.yml"]
        )

      assert {:ok, yaml} = result

      names = active_group_names(result)
      assert "api" in names
      assert "web" in names

      refute yaml =~ "my-deploy-pipeline"
    end
  end

  describe "deploy group pulls web dependency" do
    test "when deploy is targeted, web is pulled in too" do
      result =
        generate(
          env: ctx(%{"FORCE_DEPLOY" => "true"}),
          changed_files: []
        )

      assert {:ok, _yaml} = result

      names = active_group_names(result)
      assert "deploy" in names
      assert "web" in names
    end
  end
end
