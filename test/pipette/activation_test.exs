defmodule Pipette.ActivationTest do
  use ExUnit.Case, async: true

  alias Pipette.Activation

  defp test_pipeline(overrides \\ %{}) do
    base = %Pipette.Pipeline{
      branches: [
        %Pipette.Branch{pattern: "main", scopes: :all, disable: [:targeting]},
        %Pipette.Branch{pattern: "gh-readonly-queue/**", scopes: :all, disable: [:targeting]}
      ],
      scopes: [
        %Pipette.Scope{name: :api_code, files: ["apps/api/**", "mix.exs", "mix.lock"]},
        %Pipette.Scope{name: :web_code, files: ["apps/web/**", "package.json"]},
        %Pipette.Scope{name: :infra_code, files: ["infra/**"], exclude: ["**/*.md"]},
        %Pipette.Scope{name: :scripts, files: ["**/*.sh"]},
        %Pipette.Scope{name: :root_config, files: [".buildkite/**", "Justfile"], activates: :all}
      ],
      groups: [
        %Pipette.Group{
          name: :api,
          label: ":elixir: API",
          scope: :api_code,
          steps: [
            %Pipette.Step{name: :test, label: "Test"},
            %Pipette.Step{name: :lint, label: "Lint"}
          ]
        },
        %Pipette.Group{
          name: :web,
          label: ":react: Web",
          scope: :web_code,
          steps: [
            %Pipette.Step{name: :test, label: "Test"},
            %Pipette.Step{name: :lint, label: "Lint"}
          ]
        },
        %Pipette.Group{
          name: :deploy,
          label: ":rocket: Deploy",
          depends_on: :web,
          only: ["main", "gh-readonly-queue/**"],
          steps: [
            %Pipette.Step{name: :pre_release, label: "Pre-Release"},
            %Pipette.Step{
              name: :release,
              label: "Release",
              depends_on: :pre_release
            }
          ]
        },
        %Pipette.Group{
          name: :infra,
          label: ":terraform: Infra",
          scope: :infra_code,
          steps: [
            %Pipette.Step{name: :validate, label: "Validate"}
          ]
        },
        %Pipette.Group{
          name: :lint,
          label: ":bash: Lint",
          scope: :scripts,
          steps: [
            %Pipette.Step{name: :shellcheck, label: "ShellCheck"}
          ]
        }
      ],
      ignore: ["docs/**", "*.md", "LICENSE*"]
    }

    Map.merge(base, overrides)
  end

  describe "branch policy: main (scopes :all)" do
    test "activates all groups on main" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "main",
        default_branch: "main",
        message: "Fix auth bug",
        is_default_branch: true
      }

      result = Activation.resolve(pipeline, ctx, ["apps/api/lib/user.ex"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :api in group_names
      assert :web in group_names
      assert :deploy in group_names
      assert :infra in group_names
      assert :lint in group_names
    end

    test "ignores targeting on main" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "main",
        default_branch: "main",
        message: "[ci:api] Fix auth bug",
        is_default_branch: true
      }

      result = Activation.resolve(pipeline, ctx, ["apps/api/lib/user.ex"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :web in group_names
      assert :infra in group_names
    end
  end

  describe "branch policy: merge queue" do
    test "activates all groups on merge queue branch" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "gh-readonly-queue/main/pr-42",
        default_branch: "main",
        message: "Merge PR",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :api in group_names
      assert :deploy in group_names
    end
  end

  describe "feature branch: change detection" do
    test "activates api only when api code files change" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/login",
        default_branch: "main",
        message: "Fix login bug",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/api/lib/user.ex"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :api in group_names
      refute :web in group_names
      refute :deploy in group_names
      refute :infra in group_names
    end

    test "activates web only when web files change" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/ui",
        default_branch: "main",
        message: "Update styles",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :web in group_names
      refute :api in group_names
      refute :deploy in group_names
    end

    test "activates all groups when root config changes (activates: :all)" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/ci",
        default_branch: "main",
        message: "Update Justfile",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["Justfile"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :api in group_names
      assert :web in group_names
      assert :infra in group_names
      refute :deploy in group_names
    end

    test "returns empty when only docs change (ignore patterns)" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/docs",
        default_branch: "main",
        message: "Update README",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["docs/guide.md", "README.md"])

      assert result.groups == []
    end
  end

  describe "feature branch: targeting" do
    test "targeting activates specific group only" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/test",
        default_branch: "main",
        message: "[ci:api] Test API",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :api in group_names
      refute :web in group_names
      refute :deploy in group_names
      refute :infra in group_names
    end

    test "targeting a group restricted by only excludes it" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/deploy",
        default_branch: "main",
        message: "[ci:deploy] Test deploy",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"])

      group_names = MapSet.new(result.groups, & &1.name)
      refute :deploy in group_names
      assert :web in group_names
    end
  end

  describe "only filtering" do
    test "deploy runs on main" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "main",
        default_branch: "main",
        message: "Deploy",
        is_default_branch: true
      }

      result = Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :deploy in group_names
    end

    test "deploy runs on merge queue" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "gh-readonly-queue/main/pr-42",
        default_branch: "main",
        message: "Merge",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :deploy in group_names
    end

    test "deploy excluded on feature branch" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "Fix",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"])

      group_names = MapSet.new(result.groups, & &1.name)
      refute :deploy in group_names
    end
  end

  describe "step-level only filtering" do
    defp pipeline_with_step_only do
      test_pipeline(%{
        groups: [
          %Pipette.Group{
            name: :ci,
            label: ":docker: CI",
            scope: :api_code,
            steps: [
              %Pipette.Step{name: :build_test, label: "Build & Test"},
              %Pipette.Step{
                name: :update_digest,
                label: "Update Digest",
                depends_on: :build_test,
                only: "main"
              }
            ]
          },
          %Pipette.Group{
            name: :api,
            label: ":elixir: API",
            scope: :api_code,
            steps: [
              %Pipette.Step{name: :test, label: "Test"},
              %Pipette.Step{name: :lint, label: "Lint"}
            ]
          }
        ]
      })
    end

    test "step with only: main is included on main" do
      pipeline = pipeline_with_step_only()

      ctx = %Pipette.Context{
        branch: "main",
        default_branch: "main",
        message: "Deploy",
        is_default_branch: true
      }

      result = Activation.resolve(pipeline, ctx, ["apps/api/lib/user.ex"])

      ci = Enum.find(result.groups, &(&1.name == :ci))
      step_names = Enum.map(ci.steps, & &1.name)
      assert :build_test in step_names
      assert :update_digest in step_names
    end

    test "step with only: main is excluded on feature branch" do
      pipeline = pipeline_with_step_only()

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "Fix",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/api/lib/user.ex"])

      ci = Enum.find(result.groups, &(&1.name == :ci))
      step_names = Enum.map(ci.steps, & &1.name)
      assert :build_test in step_names
      refute :update_digest in step_names
    end

    test "group is removed when all steps are filtered by only" do
      pipeline =
        test_pipeline(%{
          groups: [
            %Pipette.Group{
              name: :deploy_only,
              label: ":rocket: Deploy",
              scope: :api_code,
              steps: [
                %Pipette.Step{name: :release, label: "Release", only: "main"}
              ]
            },
            %Pipette.Group{
              name: :api,
              label: ":elixir: API",
              scope: :api_code,
              steps: [%Pipette.Step{name: :test, label: "Test"}]
            }
          ]
        })

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "Fix",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/api/lib/user.ex"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :api in group_names
      refute :deploy_only in group_names
    end

    test "step with only as list matches glob patterns" do
      pipeline =
        test_pipeline(%{
          groups: [
            %Pipette.Group{
              name: :ci,
              label: ":docker: CI",
              scope: :api_code,
              steps: [
                %Pipette.Step{name: :build, label: "Build"},
                %Pipette.Step{
                  name: :deploy,
                  label: "Deploy",
                  only: ["main", "gh-readonly-queue/**"]
                }
              ]
            }
          ]
        })

      ctx = %Pipette.Context{
        branch: "gh-readonly-queue/main/pr-42",
        default_branch: "main",
        message: "Merge",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/api/lib/user.ex"])

      ci = Enum.find(result.groups, &(&1.name == :ci))
      step_names = Enum.map(ci.steps, & &1.name)
      assert :build in step_names
      assert :deploy in step_names
    end

    test "steps without only are unaffected" do
      pipeline = pipeline_with_step_only()

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "Fix",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/api/lib/user.ex"])

      api = Enum.find(result.groups, &(&1.name == :api))
      assert length(api.steps) == 2
    end
  end

  describe "git diff failure (:all changed files)" do
    test "activates all groups when changed_files is :all" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "Fix",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, :all)

      group_names = MapSet.new(result.groups, & &1.name)
      assert :api in group_names
      assert :web in group_names
      assert :infra in group_names
      refute :deploy in group_names
    end
  end

  describe "dependency propagation" do
    test "deploy depends_on web and pulls web when web scope fires" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "main",
        default_branch: "main",
        message: "Deploy",
        is_default_branch: true
      }

      result = Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :web in group_names
      assert :deploy in group_names
    end
  end

  describe "step-level targeting" do
    test "filters steps within a targeted group" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "[ci:api/test] Fix flaky test",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/api/lib/user.ex"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :api in group_names

      api = Enum.find(result.groups, &(&1.name == :api))
      step_names = Enum.map(api.steps, & &1.name)
      assert :test in step_names
      refute :lint in step_names
    end

    test "step targeting resolves intra-group step dependencies" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "[ci:deploy/release] Test release",
        is_default_branch: false
      }

      result =
        Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"], MapSet.new([:web, :deploy]))

      deploy = Enum.find(result.groups, &(&1.name == :deploy))
      step_names = Enum.map(deploy.steps, & &1.name)
      assert :release in step_names
      assert :pre_release in step_names
    end

    test "group-only target includes all steps" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "[ci:api] Run all checks",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/api/lib/user.ex"])

      api = Enum.find(result.groups, &(&1.name == :api))
      assert length(api.steps) == 2
    end
  end

  describe "force_groups" do
    test "force_groups activates specified groups on feature branch" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "Test deploy",
        is_default_branch: false
      }

      result =
        Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"], MapSet.new([:web, :deploy]))

      group_names = MapSet.new(result.groups, & &1.name)
      assert :web in group_names
      assert :deploy in group_names
    end

    test "force_groups bypasses only filter on feature branch" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "Test deploy",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["README.md"], MapSet.new([:web, :deploy]))

      group_names = MapSet.new(result.groups, & &1.name)
      assert :web in group_names
      assert :deploy in group_names
    end

    test "force_groups :all activates all groups" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "Test everything",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["README.md"], :all)

      group_names = MapSet.new(result.groups, & &1.name)
      assert :api in group_names
      assert :web in group_names
      assert :deploy in group_names
      assert :infra in group_names
      assert :lint in group_names
    end

    test "empty force_groups MapSet has no effect" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "Fix",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"], MapSet.new())

      group_names = MapSet.new(result.groups, & &1.name)
      assert :web in group_names
      refute :deploy in group_names
    end

    test "default force_groups (no fourth arg) has no effect" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "Fix",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :web in group_names
      refute :deploy in group_names
    end

    test "force_groups does not duplicate already-active groups" do
      pipeline = test_pipeline()

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "Fix",
        is_default_branch: false
      }

      result =
        Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"], MapSet.new([:web, :deploy]))

      web_count = Enum.count(result.groups, &(&1.name == :web))
      assert web_count == 1
    end
  end

  describe "ignore_global_scope" do
    defp pipeline_with_ignore_global_scope do
      test_pipeline(%{
        groups: [
          %Pipette.Group{
            name: :api,
            label: ":elixir: API",
            scope: :api_code,
            steps: [%Pipette.Step{name: :test, label: "Test"}]
          },
          %Pipette.Group{
            name: :web,
            label: ":react: Web",
            scope: :web_code,
            steps: [%Pipette.Step{name: :test, label: "Test"}]
          },
          %Pipette.Group{
            name: :deploy,
            label: ":rocket: Deploy",
            scope: :web_code,
            ignore_global_scope: true,
            depends_on: :web,
            only: ["main", "gh-readonly-queue/**"],
            steps: [
              %Pipette.Step{name: :pre_release, label: "Pre-Release"},
              %Pipette.Step{name: :release, label: "Release", depends_on: :pre_release}
            ]
          },
          %Pipette.Group{
            name: :infra,
            label: ":terraform: Infra",
            scope: :infra_code,
            steps: [%Pipette.Step{name: :validate, label: "Validate"}]
          }
        ]
      })
    end

    test "on main, excluded group does not activate when its scope files are unchanged" do
      pipeline = pipeline_with_ignore_global_scope()

      ctx = %Pipette.Context{
        branch: "main",
        default_branch: "main",
        message: "Fix auth bug",
        is_default_branch: true
      }

      result = Activation.resolve(pipeline, ctx, ["apps/api/lib/user.ex"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :api in group_names
      assert :web in group_names
      assert :infra in group_names
      refute :deploy in group_names
    end

    test "on main, excluded group activates when its scope files match" do
      pipeline = pipeline_with_ignore_global_scope()

      ctx = %Pipette.Context{
        branch: "main",
        default_branch: "main",
        message: "Update web",
        is_default_branch: true
      }

      result = Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :api in group_names
      assert :web in group_names
      assert :deploy in group_names
      assert :infra in group_names
    end

    test "on merge queue, excluded group respects file detection" do
      pipeline = pipeline_with_ignore_global_scope()

      ctx = %Pipette.Context{
        branch: "gh-readonly-queue/main/pr-42",
        default_branch: "main",
        message: "Merge PR",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/api/lib/user.ex"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :api in group_names
      assert :web in group_names
      assert :infra in group_names
      refute :deploy in group_names
    end

    test "on feature branch, ignore_global_scope has no effect" do
      pipeline = pipeline_with_ignore_global_scope()

      ctx = %Pipette.Context{
        branch: "feature/x",
        default_branch: "main",
        message: "Fix",
        is_default_branch: false
      }

      result = Activation.resolve(pipeline, ctx, ["apps/web/src/App.tsx"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :web in group_names
      refute :api in group_names
      # deploy has only: ["main", ...] so filtered out on feature branch
      refute :deploy in group_names
    end

    test "non-excluded groups still activate unconditionally on main" do
      pipeline = pipeline_with_ignore_global_scope()

      ctx = %Pipette.Context{
        branch: "main",
        default_branch: "main",
        message: "Docs only",
        is_default_branch: true
      }

      result = Activation.resolve(pipeline, ctx, ["docs/guide.md"])

      group_names = MapSet.new(result.groups, & &1.name)
      assert :api in group_names
      assert :web in group_names
      assert :infra in group_names
      refute :deploy in group_names
    end

    test "force_groups overrides ignore_global_scope" do
      pipeline = pipeline_with_ignore_global_scope()

      ctx = %Pipette.Context{
        branch: "main",
        default_branch: "main",
        message: "Force deploy",
        is_default_branch: true
      }

      result =
        Activation.resolve(pipeline, ctx, ["apps/api/lib/user.ex"], MapSet.new([:deploy]))

      group_names = MapSet.new(result.groups, & &1.name)
      assert :web in group_names
      assert :deploy in group_names
    end

    test "force_groups :all overrides ignore_global_scope" do
      pipeline = pipeline_with_ignore_global_scope()

      ctx = %Pipette.Context{
        branch: "main",
        default_branch: "main",
        message: "Force everything",
        is_default_branch: true
      }

      result = Activation.resolve(pipeline, ctx, ["README.md"], :all)

      group_names = MapSet.new(result.groups, & &1.name)
      assert :web in group_names
      assert :deploy in group_names
    end
  end
end
