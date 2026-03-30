defmodule Pipette.ContextTest do
  use ExUnit.Case, async: true

  alias Pipette.Context

  describe "from_env/1" do
    test "builds context from environment map" do
      env = %{
        "BUILDKITE_BRANCH" => "feature/login",
        "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
        "BUILDKITE_COMMIT" => "abc123",
        "BUILDKITE_MESSAGE" => "Fix login bug",
        "BUILDKITE_PULL_REQUEST_BASE_BRANCH" => "main",
        "CI_TARGET" => "backend"
      }

      ctx = Context.from_env(env)

      assert ctx.branch == "feature/login"
      assert ctx.default_branch == "main"
      assert ctx.commit == "abc123"
      assert ctx.message == "Fix login bug"
      assert ctx.pull_request_base_branch == "main"
      assert ctx.ci_target == "backend"
      assert ctx.is_default_branch == false
    end

    test "detects default branch" do
      env = %{
        "BUILDKITE_BRANCH" => "main",
        "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main"
      }

      ctx = Context.from_env(env)
      assert ctx.is_default_branch == true
    end

    test "uses defaults for missing values" do
      ctx = Context.from_env(%{})

      assert ctx.branch == ""
      assert ctx.default_branch == "main"
      assert ctx.commit == "HEAD"
      assert ctx.message == ""
      assert ctx.pull_request_base_branch == nil
      assert ctx.ci_target == nil
    end

    test "treats empty strings as nil for optional fields" do
      env = %{
        "BUILDKITE_PULL_REQUEST_BASE_BRANCH" => "",
        "CI_TARGET" => ""
      }

      ctx = Context.from_env(env)
      assert ctx.pull_request_base_branch == nil
      assert ctx.ci_target == nil
    end

    test "treats 'false' as nil for PR base branch" do
      # Buildkite sets this to "false" when not a PR
      env = %{
        "BUILDKITE_PULL_REQUEST_BASE_BRANCH" => "false"
      }

      ctx = Context.from_env(env)
      assert ctx.pull_request_base_branch == nil
    end
  end

  describe "from_system_env/0" do
    test "reads from actual System env" do
      # Just verify it doesn't crash -- actual values depend on the environment
      ctx = Context.from_system_env()
      assert %Context{} = ctx
    end
  end
end
