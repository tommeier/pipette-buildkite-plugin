defmodule Pipette.BuildkiteTest do
  use ExUnit.Case, async: true

  alias Pipette.Buildkite

  describe "to_yaml/2" do
    test "serializes a simple group with steps" do
      groups = [
        %Pipette.Group{
          name: :backend,
          label: ":elixir: Backend",
          key: "backend",
          steps: [
            %Pipette.Step{
              name: :test,
              label: ":test_tube: Test",
              command: "mix test",
              key: "backend-test"
            },
            %Pipette.Step{
              name: :format,
              label: ":art: Format",
              command: "mix format --check-formatted",
              key: "backend-format"
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      assert yaml =~ "steps:"
      assert yaml =~ "group:"
      assert yaml =~ "Backend"
      assert yaml =~ "key: backend"
      assert yaml =~ "key: backend-test"
      assert yaml =~ "key: backend-format"
      assert yaml =~ "Test"
      assert yaml =~ "command: mix test"
    end

    test "serializes group depends_on" do
      groups = [
        %Pipette.Group{
          name: :packaging,
          label: "Packaging",
          key: "packaging",
          depends_on: "backend",
          steps: [
            %Pipette.Step{
              name: :build,
              label: "Build",
              command: "docker build .",
              key: "packaging-build"
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      assert yaml =~ "depends_on:"
      assert yaml =~ "backend"
    end

    test "serializes step with env, agents, timeout" do
      groups = [
        %Pipette.Group{
          name: :deploy,
          label: "Deploy",
          key: "deploy",
          steps: [
            %Pipette.Step{
              name: :ios,
              label: "iOS",
              command: "bash ios.sh",
              key: "deploy-ios",
              agents: %{queue: "mac"},
              timeout_in_minutes: 45,
              env: %{FOO: "bar"}
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      assert yaml =~ "timeout_in_minutes: 45"
      assert yaml =~ "queue: mac"
      assert yaml =~ "FOO: bar"
    end

    test "serializes step depends_on" do
      groups = [
        %Pipette.Group{
          name: :deploy,
          label: "Deploy",
          key: "deploy",
          steps: [
            %Pipette.Step{
              name: :pre,
              label: "Pre",
              command: "bash pre.sh",
              key: "deploy-pre"
            },
            %Pipette.Step{
              name: :ios,
              label: "iOS",
              command: "bash ios.sh",
              key: "deploy-ios",
              depends_on: "deploy-pre"
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      assert yaml =~ "depends_on"
      assert yaml =~ "deploy-pre"
    end

    test "serializes soft_fail boolean" do
      groups = [
        %Pipette.Group{
          name: :checks,
          label: "Checks",
          key: "checks",
          steps: [
            %Pipette.Step{
              name: :audit,
              label: "Audit",
              command: "mix audit",
              key: "checks-audit",
              soft_fail: true
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      assert yaml =~ "soft_fail: true"
    end

    test "serializes plugins" do
      groups = [
        %Pipette.Group{
          name: :deploy,
          label: "Deploy",
          key: "deploy",
          steps: [
            %Pipette.Step{
              name: :build,
              label: "Build",
              command: "build.sh",
              key: "deploy-build",
              plugins: [
                {"docker-compose#v4.0", %{run: "app", config: "docker-compose.ci.yml"}}
              ]
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      assert yaml =~ "plugins:"
      assert yaml =~ "docker-compose#v4.0"
    end

    test "serializes secrets" do
      groups = [
        %Pipette.Group{
          name: :deploy,
          label: "Deploy",
          key: "deploy",
          steps: [
            %Pipette.Step{
              name: :push,
              label: "Push",
              command: "push.sh",
              key: "deploy-push",
              secrets: ["API_KEY", "SECRET_TOKEN"]
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      assert yaml =~ "secrets:"
      assert yaml =~ "API_KEY"
      assert yaml =~ "SECRET_TOKEN"
    end

    test "serializes concurrency settings" do
      groups = [
        %Pipette.Group{
          name: :deploy,
          label: "Deploy",
          key: "deploy",
          steps: [
            %Pipette.Step{
              name: :push,
              label: "Push",
              command: "push.sh",
              key: "deploy-push",
              concurrency: 1,
              concurrency_group: "deploy-prod"
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      assert yaml =~ "concurrency: 1"
      assert yaml =~ "concurrency_group: deploy-prod"
    end

    test "serializes pipeline-level config" do
      groups = [
        %Pipette.Group{
          name: :checks,
          label: "Checks",
          key: "checks",
          steps: [
            %Pipette.Step{
              name: :test,
              label: "Test",
              command: "mix test",
              key: "checks-test"
            }
          ]
        }
      ]

      pipeline_config = %{
        env: %{LANG: "C.UTF-8"},
        secrets: ["SENTRY_TOKEN"]
      }

      yaml = Buildkite.to_yaml(groups, pipeline_config)

      assert yaml =~ "LANG: C.UTF-8"
      assert yaml =~ "SENTRY_TOKEN"
    end

    test "omits nil/empty properties" do
      groups = [
        %Pipette.Group{
          name: :checks,
          label: "Checks",
          key: "checks",
          steps: [
            %Pipette.Step{
              name: :test,
              label: "Test",
              command: "mix test",
              key: "checks-test"
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      refute yaml =~ "timeout_in_minutes"
      refute yaml =~ "agents"
      refute yaml =~ "concurrency"
      refute yaml =~ "soft_fail"
      refute yaml =~ "retry"
      refute yaml =~ "plugins"
      refute yaml =~ "secrets"
    end

    test "serializes plugin-only step (no command)" do
      groups = [
        %Pipette.Group{
          name: :checks,
          label: "Checks",
          key: "checks",
          steps: [
            %Pipette.Step{
              name: :shellcheck,
              label: "ShellCheck",
              key: "checks-shellcheck",
              plugins: [
                {"shellcheck#v1.4.0", %{files: ["**/*.sh"], recursive_glob: true}}
              ]
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      assert yaml =~ "shellcheck#v1.4.0"
      assert yaml =~ "ShellCheck"
      refute yaml =~ "command:"
    end

    test "serializes retry config" do
      groups = [
        %Pipette.Group{
          name: :deploy,
          label: "Deploy",
          key: "deploy",
          steps: [
            %Pipette.Step{
              name: :push,
              label: "Push",
              command: "push.sh",
              key: "deploy-push",
              retry: %{automatic: [%{exit_status: -1, limit: 2}]}
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      assert yaml =~ "retry:"
      assert yaml =~ "automatic:"
      assert yaml =~ "exit_status: -1"
      assert yaml =~ "limit: 2"
    end
  end
end
