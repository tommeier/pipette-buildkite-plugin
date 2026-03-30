defmodule Pipette.KeysTest do
  use ExUnit.Case, async: true

  describe "generate_keys/1" do
    test "generates group keys from atom names" do
      pipeline = %Pipette.Pipeline{
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]
          },
          %Pipette.Group{
            name: :web,
            steps: [%Pipette.Step{name: :build, label: "Build", command: "pnpm build"}]
          }
        ]
      }

      result = Pipette.generate_keys(pipeline)

      keys = Enum.map(result.groups, & &1.key)
      assert keys == ["api", "web"]
    end

    test "generates step keys as group-step" do
      pipeline = %Pipette.Pipeline{
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [
              %Pipette.Step{name: :test, label: "Test", command: "mix test"},
              %Pipette.Step{name: :format, label: "Format", command: "mix format"}
            ]
          }
        ]
      }

      result = Pipette.generate_keys(pipeline)

      [group] = result.groups
      assert group.key == "api"

      [test_step, format_step] = group.steps
      assert test_step.key == "api-test"
      assert format_step.key == "api-format"
    end

    test "generates trigger keys from atom names" do
      pipeline = %Pipette.Pipeline{
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [%Pipette.Step{name: :test, label: "Test"}]
          }
        ],
        triggers: [
          %Pipette.Trigger{
            name: :deploy_api,
            pipeline: "deploy-pipeline",
            depends_on: :api
          }
        ]
      }

      result = Pipette.generate_keys(pipeline)

      [trigger] = result.triggers
      assert trigger.key == "deploy_api"
    end

    test "resolves step depends_on atom to key string" do
      pipeline = %Pipette.Pipeline{
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [
              %Pipette.Step{name: :compile, label: "Compile"},
              %Pipette.Step{name: :test, label: "Test", depends_on: :compile}
            ]
          }
        ]
      }

      result = Pipette.generate_keys(pipeline)

      [group] = result.groups
      test_step = Enum.find(group.steps, &(&1.name == :test))
      assert test_step.depends_on == "api-compile"
    end

    test "resolves step depends_on list to key strings" do
      pipeline = %Pipette.Pipeline{
        groups: [
          %Pipette.Group{
            name: :deploy,
            steps: [
              %Pipette.Step{name: :pre_release, label: "Pre"},
              %Pipette.Step{name: :ios, label: "iOS", depends_on: :pre_release},
              %Pipette.Step{name: :android, label: "Android", depends_on: :pre_release},
              %Pipette.Step{name: :post, label: "Post", depends_on: [:ios, :android]}
            ]
          }
        ]
      }

      result = Pipette.generate_keys(pipeline)

      [group] = result.groups
      post = Enum.find(group.steps, &(&1.name == :post))
      assert post.depends_on == ["deploy-ios", "deploy-android"]
    end

    test "resolves cross-group step depends_on tuple" do
      pipeline = %Pipette.Pipeline{
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [%Pipette.Step{name: :test, label: "Test"}]
          },
          %Pipette.Group{
            name: :deploy,
            depends_on: :api,
            steps: [
              %Pipette.Step{name: :push, label: "Push", depends_on: {:api, :test}}
            ]
          }
        ]
      }

      result = Pipette.generate_keys(pipeline)

      deploy = Enum.find(result.groups, &(&1.name == :deploy))
      push = Enum.find(deploy.steps, &(&1.name == :push))
      assert push.depends_on == "api-test"
    end

    test "resolves group depends_on atom to key string" do
      pipeline = %Pipette.Pipeline{
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [%Pipette.Step{name: :test, label: "Test"}]
          },
          %Pipette.Group{
            name: :packaging,
            depends_on: :api,
            steps: [%Pipette.Step{name: :build, label: "Build"}]
          }
        ]
      }

      result = Pipette.generate_keys(pipeline)

      packaging = Enum.find(result.groups, &(&1.name == :packaging))
      assert packaging.depends_on == "api"
    end

    test "resolves group depends_on list to key strings" do
      pipeline = %Pipette.Pipeline{
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [%Pipette.Step{name: :test, label: "Test"}]
          },
          %Pipette.Group{
            name: :web,
            steps: [%Pipette.Step{name: :build, label: "Build"}]
          },
          %Pipette.Group{
            name: :deploy,
            depends_on: [:api, :web],
            steps: [%Pipette.Step{name: :push, label: "Push"}]
          }
        ]
      }

      result = Pipette.generate_keys(pipeline)

      deploy = Enum.find(result.groups, &(&1.name == :deploy))
      assert deploy.depends_on == ["api", "web"]
    end

    test "resolves trigger depends_on to key string" do
      pipeline = %Pipette.Pipeline{
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [%Pipette.Step{name: :test, label: "Test"}]
          }
        ],
        triggers: [
          %Pipette.Trigger{
            name: :deploy_api,
            pipeline: "deploy-pipeline",
            depends_on: :api
          }
        ]
      }

      result = Pipette.generate_keys(pipeline)

      [trigger] = result.triggers
      assert trigger.depends_on == "api"
    end

    test "resolves trigger depends_on list to key strings" do
      pipeline = %Pipette.Pipeline{
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [%Pipette.Step{name: :test, label: "Test"}]
          },
          %Pipette.Group{
            name: :web,
            steps: [%Pipette.Step{name: :build, label: "Build"}]
          }
        ],
        triggers: [
          %Pipette.Trigger{
            name: :deploy_all,
            pipeline: "deploy-pipeline",
            depends_on: [:api, :web]
          }
        ]
      }

      result = Pipette.generate_keys(pipeline)

      [trigger] = result.triggers
      assert trigger.depends_on == ["api", "web"]
    end

    test "preserves nil depends_on" do
      pipeline = %Pipette.Pipeline{
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [
              %Pipette.Step{name: :test, label: "Test"}
            ]
          }
        ]
      }

      result = Pipette.generate_keys(pipeline)

      [group] = result.groups
      assert group.depends_on == nil

      [step] = group.steps
      assert step.depends_on == nil
    end

    test "passes through binary step depends_on unchanged" do
      pipeline = %Pipette.Pipeline{
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [
              %Pipette.Step{name: :test, label: "Test", depends_on: "already-resolved"}
            ]
          }
        ]
      }

      result = Pipette.generate_keys(pipeline)

      [group] = result.groups
      [step] = group.steps
      assert step.depends_on == "already-resolved"
    end
  end
end
