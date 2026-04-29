defmodule Pipette.NestedTriggerTest do
  use ExUnit.Case, async: true

  alias Pipette.{Buildkite, Group, Step, Trigger}

  describe "DSL: trigger inside a group" do
    test "parses a group containing a single nested trigger" do
      defmodule SingleNestedTriggerPipeline do
        use Pipette.DSL

        group :deploy do
          label(":rocket: Deploy")

          trigger :rollout do
            label(":rocket: Rollout")
            pipeline("downstream-deploy")
            depends_on(:checks)
            build(%{commit: "${BUILDKITE_COMMIT}"})
          end
        end

        group :checks do
          label("Checks")
          step(:test, label: "Test", command: "mix test")
        end
      end

      [deploy_group, _checks_group] = Pipette.Info.groups(SingleNestedTriggerPipeline)
      assert deploy_group.name == :deploy
      assert [%Trigger{} = trigger] = deploy_group.steps
      assert trigger.name == :rollout
      assert trigger.label == ":rocket: Rollout"
      assert trigger.pipeline == "downstream-deploy"
      assert trigger.depends_on == :checks
      assert trigger.build == %{commit: "${BUILDKITE_COMMIT}"}

      # Nested trigger does NOT appear in the top-level triggers list.
      assert Pipette.Info.triggers(SingleNestedTriggerPipeline) == []
    end

    test "parses a group with mixed nested step and nested trigger" do
      defmodule MixedChildrenPipeline do
        use Pipette.DSL

        group :deploy do
          label("Deploy")

          trigger :rollout do
            label("Rollout")
            pipeline("downstream")
          end

          step(:tag, label: "Tag", command: "git tag", depends_on: :rollout)
        end
      end

      [group] = Pipette.Info.groups(MixedChildrenPipeline)
      assert [%Trigger{name: :rollout}, %Step{name: :tag}] = group.steps

      tag_step = Enum.find(group.steps, &match?(%Step{name: :tag}, &1))
      # Step depends_on resolves to sibling trigger's key at compile time.
      assert tag_step.depends_on == "deploy-rollout"
    end

    test "parses multiple nested triggers in one group" do
      defmodule MultiTriggerGroupPipeline do
        use Pipette.DSL

        group :fanout do
          label("Fanout")

          trigger :east do
            label("East")
            pipeline("east-deploy")
          end

          trigger :west do
            label("West")
            pipeline("west-deploy")
          end
        end
      end

      [group] = Pipette.Info.groups(MultiTriggerGroupPipeline)
      names = Enum.map(group.steps, & &1.name)
      assert names == [:east, :west]
      assert Enum.all?(group.steps, &is_struct(&1, Trigger))
    end

    test "preserves all trigger fields (build, async, only, key)" do
      defmodule FullFieldsTriggerPipeline do
        use Pipette.DSL

        group :deploy do
          label("Deploy")

          trigger :go do
            label(":bell: Go")
            pipeline("downstream")
            depends_on([:a, :b])
            build(%{message: "Deploy", env: %{FOO: "bar"}})
            async(true)
            only("main")
            key("custom-go-key")
          end
        end
      end

      [group] = Pipette.Info.groups(FullFieldsTriggerPipeline)
      [trigger] = group.steps
      assert trigger.label == ":bell: Go"
      assert trigger.pipeline == "downstream"
      assert trigger.depends_on == [:a, :b]
      assert trigger.build == %{message: "Deploy", env: %{FOO: "bar"}}
      assert trigger.async == true
      assert trigger.only == "main"
      assert trigger.key == "custom-go-key"
    end

    test "top-level trigger still works alongside nested triggers" do
      defmodule MixedTriggerPipeline do
        use Pipette.DSL

        group :checks do
          label("Checks")
          step(:test, label: "Test", command: "mix test")
        end

        group :deploy do
          label("Deploy")

          trigger :inner do
            label("Inner")
            pipeline("inner-deploy")
          end
        end

        trigger :outer do
          label("Outer")
          pipeline("outer-notify")
          depends_on(:deploy)
        end
      end

      groups = Pipette.Info.groups(MixedTriggerPipeline)
      deploy_group = Enum.find(groups, &(&1.name == :deploy))
      [%Trigger{name: :inner}] = deploy_group.steps

      [outer] = Pipette.Info.triggers(MixedTriggerPipeline)
      assert outer.name == :outer
    end
  end

  describe "key generation for nested triggers" do
    test "auto-derives nested trigger key as group_key-trigger_name" do
      defmodule AutoKeyNestedPipeline do
        use Pipette.DSL

        group :deploy do
          label("Deploy")

          trigger :rollout do
            pipeline("downstream")
          end
        end
      end

      [group] = Pipette.Info.groups(AutoKeyNestedPipeline)
      [trigger] = group.steps
      assert group.key == "deploy"
      assert trigger.key == "deploy-rollout"
    end

    test "explicit key: on nested trigger overrides the auto-derived key" do
      defmodule ExplicitKeyNestedPipeline do
        use Pipette.DSL

        group :deploy do
          label("Deploy")

          trigger :rollout do
            pipeline("downstream")
            key("my-explicit-rollout")
          end
        end
      end

      [group] = Pipette.Info.groups(ExplicitKeyNestedPipeline)
      [trigger] = group.steps
      assert trigger.key == "my-explicit-rollout"
    end

    test "sibling step's atom depends_on resolves to nested trigger's key" do
      defmodule SiblingDepPipeline do
        use Pipette.DSL

        group :deploy do
          label("Deploy")

          trigger :rollout do
            pipeline("downstream")
          end

          step(:after, label: "After", command: "echo done", depends_on: :rollout)
        end
      end

      [group] = Pipette.Info.groups(SiblingDepPipeline)
      after_step = Enum.find(group.steps, &match?(%Step{name: :after}, &1))
      assert after_step.depends_on == "deploy-rollout"
    end

    test "nested trigger depends_on stays as atoms after compile-time transform" do
      defmodule TriggerDepsAtomPipeline do
        use Pipette.DSL

        group :deploy do
          label("Deploy")

          trigger :rollout do
            pipeline("downstream")
            depends_on(:checks)
          end
        end

        group :checks do
          label("Checks")
          step(:test, label: "Test", command: "mix test")
        end
      end

      [deploy_group | _] =
        Pipette.Info.groups(TriggerDepsAtomPipeline)
        |> Enum.filter(&(&1.name == :deploy))

      [trigger] = deploy_group.steps
      # Atom depends_on stays as atom — runtime resolves against group_key_map.
      assert trigger.depends_on == :checks
    end

    test "nested trigger string depends_on passes through unchanged" do
      defmodule TriggerStringDepPipeline do
        use Pipette.DSL

        group :deploy do
          label("Deploy")

          trigger :rollout do
            pipeline("downstream")
            depends_on("explicit-key")
          end
        end
      end

      [group] = Pipette.Info.groups(TriggerStringDepPipeline)
      [trigger] = group.steps
      assert trigger.depends_on == "explicit-key"
    end

    test "nested trigger atom dep matching a sibling step resolves to sibling key" do
      defmodule TriggerSiblingDepPipeline do
        use Pipette.DSL

        group :deploy do
          label("Deploy")

          step(:prep, label: "Prep", command: "true")

          trigger :rollout do
            pipeline("downstream")
            depends_on(:prep)
          end
        end
      end

      [group] = Pipette.Info.groups(TriggerSiblingDepPipeline)
      trigger = Enum.find(group.steps, &match?(%Trigger{}, &1))
      # Sibling resolution at compile time -> string key.
      assert trigger.depends_on == "deploy-prep"
    end

    test "nested trigger mixed list (sibling atom + top-level group atom + string)" do
      defmodule TriggerMixedListPipeline do
        use Pipette.DSL

        group :checks do
          label("Checks")
          step(:test, label: "Test", command: "mix test")
        end

        group :deploy do
          label("Deploy")
          step(:prep, label: "Prep", command: "true")

          trigger :rollout do
            pipeline("downstream")
            # :prep -> sibling step (resolved at compile time)
            # :checks -> top-level group (deferred to runtime)
            # "explicit" -> passthrough
            depends_on([:prep, :checks, "explicit"])
          end
        end
      end

      groups = Pipette.Info.groups(TriggerMixedListPipeline)
      deploy = Enum.find(groups, &(&1.name == :deploy))
      trigger = Enum.find(deploy.steps, &match?(%Trigger{}, &1))
      # Sibling resolved, top-level atom kept for runtime, string passthrough.
      assert trigger.depends_on == ["deploy-prep", :checks, "explicit"]
    end
  end

  describe "YAML serialization" do
    test "serializes a nested trigger inside a group's steps array" do
      groups = [
        %Group{
          name: :deploy,
          label: ":rocket: Deploy",
          key: "deploy",
          steps: [
            %Trigger{
              name: :rollout,
              label: ":rocket: Rollout",
              pipeline: "downstream-deploy",
              key: "deploy-rollout"
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      assert yaml =~ "group: ':rocket: Deploy'"
      assert yaml =~ "key: deploy"
      assert yaml =~ "trigger: downstream-deploy"
      assert yaml =~ "key: deploy-rollout"
      assert yaml =~ "':rocket: Rollout'"
      # Nested trigger should not produce a `command:` line.
      refute yaml =~ "command:"
    end

    test "serializes mixed step + trigger in a single group's steps array" do
      groups = [
        %Group{
          name: :deploy,
          label: "Deploy",
          key: "deploy",
          steps: [
            %Trigger{
              name: :rollout,
              label: "Rollout",
              pipeline: "downstream",
              key: "deploy-rollout"
            },
            %Step{
              name: :tag,
              label: "Tag",
              command: "git tag",
              key: "deploy-tag",
              depends_on: "deploy-rollout"
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      assert yaml =~ "trigger: downstream"
      assert yaml =~ "key: deploy-rollout"
      assert yaml =~ "command: git tag"
      assert yaml =~ "key: deploy-tag"
      assert yaml =~ "depends_on: deploy-rollout"
    end

    test "serializes nested trigger build params, async, depends_on" do
      groups = [
        %Group{
          name: :deploy,
          label: "Deploy",
          key: "deploy",
          steps: [
            %Trigger{
              name: :rollout,
              label: "Rollout",
              pipeline: "downstream",
              key: "deploy-rollout",
              depends_on: "checks",
              async: true,
              build: %{commit: "${BUILDKITE_COMMIT}", message: "Deploy"}
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      assert yaml =~ "trigger: downstream"
      assert yaml =~ "async: true"
      assert yaml =~ "depends_on: checks"
      assert yaml =~ "build:"
      assert yaml =~ "commit:"
      assert yaml =~ "message: Deploy"
    end

    test "group containing only a trigger (no command steps) serializes" do
      groups = [
        %Group{
          name: :deploy,
          label: "Deploy",
          key: "deploy",
          steps: [
            %Trigger{
              name: :rollout,
              label: "Rollout",
              pipeline: "downstream",
              key: "deploy-rollout"
            }
          ]
        }
      ]

      yaml = Buildkite.to_yaml(groups)

      assert yaml =~ "group: Deploy"
      assert yaml =~ "trigger: downstream"
    end
  end

  describe "validation" do
    test "nested trigger without :pipeline fails at the schema level" do
      assert_raise Spark.Error.DslError, ~r/required :pipeline option not found/, fn ->
        defmodule NoPipelineNestedTriggerPipeline do
          use Pipette.DSL

          group :deploy do
            label("Deploy")

            trigger :rollout do
              label("Rollout")
              # No `pipeline(...)` — required by the @trigger schema.
            end
          end
        end
      end
    end

    test "nested trigger without :label compiles (label is optional for triggers)" do
      defmodule UnlabelledNestedTriggerPipeline do
        use Pipette.DSL

        group :deploy do
          label("Deploy")

          trigger :rollout do
            pipeline("downstream")
          end
        end
      end

      [group] = Pipette.Info.groups(UnlabelledNestedTriggerPipeline)
      [trigger] = group.steps
      assert trigger.label == nil
      assert trigger.pipeline == "downstream"
    end

    test "step-only validation (concurrency_group/concurrency) ignores nested triggers" do
      defmodule TriggerWithoutConcurrencyPipeline do
        use Pipette.DSL

        group :deploy do
          label("Deploy")

          # If the verifier accidentally applied step-validation to triggers,
          # this would fail. Triggers don't have concurrency_group/concurrency
          # at all.
          trigger :rollout do
            pipeline("downstream")
          end
        end
      end

      assert [_] = Pipette.Info.groups(TriggerWithoutConcurrencyPipeline)
    end
  end

  describe "runtime activation: depends_on resolution" do
    test "nested trigger atom depends_on resolves to top-level group key" do
      defmodule RuntimeAtomDepsPipeline do
        use Pipette.DSL

        branch("main", scopes: :all)

        group :checks do
          label("Checks")
          key("checks-key-explicit")
          step(:test, label: "Test", command: "mix test")
        end

        group :deploy do
          label("Deploy")
          depends_on(:checks)

          trigger :rollout do
            pipeline("downstream")
            depends_on(:checks)
          end
        end
      end

      {:ok, yaml} =
        Pipette.run(RuntimeAtomDepsPipeline,
          dry_run: true,
          env: %{
            "BUILDKITE_BRANCH" => "main",
            "BUILDKITE_COMMIT" => "abc",
            "BUILDKITE_MESSAGE" => "x",
            "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main"
          },
          changed_files: :all
        )

      # The trigger's depends_on should resolve to the explicit group key,
      # not the bare atom name "checks".
      assert yaml =~ "depends_on: checks-key-explicit"
    end

    test "nested trigger list depends_on resolves each atom" do
      defmodule RuntimeListDepsPipeline do
        use Pipette.DSL

        branch("main", scopes: :all)

        group :a do
          label("A")
          step(:t, label: "T", command: "true")
        end

        group :b do
          label("B")
          step(:t, label: "T", command: "true")
        end

        group :deploy do
          label("Deploy")

          trigger :rollout do
            pipeline("downstream")
            depends_on([:a, :b])
          end
        end
      end

      {:ok, yaml} =
        Pipette.run(RuntimeListDepsPipeline,
          dry_run: true,
          env: %{
            "BUILDKITE_BRANCH" => "main",
            "BUILDKITE_COMMIT" => "abc",
            "BUILDKITE_MESSAGE" => "x",
            "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main"
          },
          changed_files: :all
        )

      # Both group keys should appear under the trigger's depends_on.
      assert yaml =~ "trigger: downstream"
      assert yaml =~ ~r/depends_on:\s*\n\s*-\s*a\s*\n\s*-\s*b/
    end

    test "nested trigger with no depends_on emits no depends_on field" do
      defmodule RuntimeNoDepsPipeline do
        use Pipette.DSL

        branch("main", scopes: :all)

        group :deploy do
          label("Deploy")

          trigger :rollout do
            pipeline("downstream")
          end
        end
      end

      {:ok, yaml} =
        Pipette.run(RuntimeNoDepsPipeline,
          dry_run: true,
          env: %{
            "BUILDKITE_BRANCH" => "main",
            "BUILDKITE_COMMIT" => "abc",
            "BUILDKITE_MESSAGE" => "x",
            "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main"
          },
          changed_files: :all
        )

      assert yaml =~ "trigger: downstream"
      # The trigger block itself shouldn't have a depends_on. (Group might,
      # but this group has no group-level depends_on.)
      refute yaml =~ "depends_on:"
    end
  end

  describe "branch filtering: nested trigger :only" do
    test "nested trigger with :only is dropped when branch doesn't match" do
      defmodule TriggerOnlyMainPipeline do
        use Pipette.DSL

        branch("main", scopes: :all)
        branch("feature/*", scopes: :all)

        group :deploy do
          label("Deploy")

          trigger :rollout do
            pipeline("downstream")
            only("main")
          end

          step(:check, label: "Check", command: "echo")
        end
      end

      # On feature branch: trigger filtered out, step remains.
      {:ok, yaml} =
        Pipette.run(TriggerOnlyMainPipeline,
          dry_run: true,
          env: %{
            "BUILDKITE_BRANCH" => "feature/x",
            "BUILDKITE_COMMIT" => "abc",
            "BUILDKITE_MESSAGE" => "x",
            "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main"
          },
          changed_files: :all
        )

      refute yaml =~ "trigger: downstream"
      assert yaml =~ "command: echo"

      # On main: trigger included.
      {:ok, yaml_main} =
        Pipette.run(TriggerOnlyMainPipeline,
          dry_run: true,
          env: %{
            "BUILDKITE_BRANCH" => "main",
            "BUILDKITE_COMMIT" => "abc",
            "BUILDKITE_MESSAGE" => "x",
            "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main"
          },
          changed_files: :all
        )

      assert yaml_main =~ "trigger: downstream"
    end

    test "group containing only a trigger that gets :only-filtered is dropped" do
      defmodule LonelyTriggerPipeline do
        use Pipette.DSL

        branch("main", scopes: :all)
        branch("feature/*", scopes: :all)

        group :deploy do
          label("Deploy")

          trigger :rollout do
            pipeline("downstream")
            only("main")
          end
        end

        group :always do
          label("Always")
          step(:noop, label: "Noop", command: "true")
        end
      end

      # On a feature branch the trigger is filtered out — and the group has
      # no other children — so the deploy group itself disappears.
      {:ok, yaml} =
        Pipette.run(LonelyTriggerPipeline,
          dry_run: true,
          env: %{
            "BUILDKITE_BRANCH" => "feature/x",
            "BUILDKITE_COMMIT" => "abc",
            "BUILDKITE_MESSAGE" => "x",
            "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main"
          },
          changed_files: :all
        )

      refute yaml =~ "Deploy"
      refute yaml =~ "trigger: downstream"
      assert yaml =~ "Always"
    end
  end

  describe "step targeting via CI_TARGET pulls in sibling triggers" do
    test "targeting a step that depends on a sibling trigger pulls in the trigger" do
      defmodule TargetingPipeline do
        use Pipette.DSL

        scope(:always, files: ["**/*"], activates: :all)

        group :checks do
          label("Checks")
          scope(:always)
          step(:test, label: "Test", command: "mix test")
        end

        group :deploy do
          label("Deploy")
          scope(:always)

          trigger :rollout do
            pipeline("downstream")
          end

          step(:tag, label: "Tag", command: "git tag", depends_on: :rollout)
        end
      end

      {:ok, yaml} =
        Pipette.run(TargetingPipeline,
          dry_run: true,
          env: %{
            "BUILDKITE_BRANCH" => "feature/x",
            "BUILDKITE_COMMIT" => "abc",
            "BUILDKITE_MESSAGE" => "[ci:deploy/tag] target tag",
            "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main"
          },
          changed_files: ["foo.ex"]
        )

      # The targeted step (tag) AND its sibling trigger (rollout) should appear.
      # The unrelated checks group should NOT appear.
      assert yaml =~ "command: git tag"
      assert yaml =~ "trigger: downstream"
      refute yaml =~ "mix test"
    end

    test "targeting a nested trigger by name activates just the trigger" do
      defmodule TargetTriggerPipeline do
        use Pipette.DSL

        scope(:always, files: ["**/*"], activates: :all)

        group :deploy do
          label("Deploy")
          scope(:always)

          trigger :rollout do
            pipeline("downstream")
          end

          step(:tag, label: "Tag", command: "git tag")
        end
      end

      {:ok, yaml} =
        Pipette.run(TargetTriggerPipeline,
          dry_run: true,
          env: %{
            "BUILDKITE_BRANCH" => "feature/x",
            "BUILDKITE_COMMIT" => "abc",
            "BUILDKITE_MESSAGE" => "[ci:deploy/rollout] target rollout",
            "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main"
          },
          changed_files: ["foo.ex"]
        )

      assert yaml =~ "trigger: downstream"
      refute yaml =~ "command: git tag"
    end
  end

  describe "backward compatibility" do
    test "groups with only command steps (the existing pattern) work unchanged" do
      defmodule LegacyPipeline do
        use Pipette.DSL

        group :checks do
          label("Checks")
          step(:test, label: "Test", command: "mix test")
          step(:lint, label: "Lint", command: "mix credo")
        end
      end

      [group] = Pipette.Info.groups(LegacyPipeline)
      assert Enum.all?(group.steps, &is_struct(&1, Step))
      assert Enum.map(group.steps, & &1.name) == [:test, :lint]
    end

    test "top-level trigger semantics unchanged (depends_on: :group, no nesting)" do
      defmodule TopLevelTriggerLegacyPipeline do
        use Pipette.DSL

        branch("main", scopes: :all)

        group :checks do
          label("Checks")
          step(:test, label: "Test", command: "mix test")
        end

        trigger :deploy do
          label("Deploy")
          pipeline("downstream")
          depends_on(:checks)
          only("main")
        end
      end

      {:ok, yaml} =
        Pipette.run(TopLevelTriggerLegacyPipeline,
          dry_run: true,
          env: %{
            "BUILDKITE_BRANCH" => "main",
            "BUILDKITE_COMMIT" => "abc",
            "BUILDKITE_MESSAGE" => "x",
            "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main"
          },
          changed_files: :all
        )

      assert yaml =~ "trigger: downstream"
      assert yaml =~ "depends_on: checks"
    end
  end
end
