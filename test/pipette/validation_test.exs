defmodule Pipette.ValidationTest do
  use ExUnit.Case, async: true

  describe "validate!/1" do
    test "passes for a valid pipeline" do
      pipeline = %Pipette.Pipeline{
        scopes: [
          %Pipette.Scope{name: :api_code, files: ["apps/api/**"]}
        ],
        groups: [
          %Pipette.Group{
            name: :api,
            scope: :api_code,
            steps: [
              %Pipette.Step{name: :test, label: "Test", command: "mix test"}
            ]
          }
        ]
      }

      assert :ok = Pipette.validate!(pipeline)
    end

    test "raises on invalid scope reference" do
      pipeline = %Pipette.Pipeline{
        scopes: [
          %Pipette.Scope{name: :api_code, files: ["apps/api/**"]}
        ],
        groups: [
          %Pipette.Group{
            name: :api,
            scope: :nonexistent,
            steps: [
              %Pipette.Step{name: :test, label: "Test", command: "mix test"}
            ]
          }
        ]
      }

      assert_raise RuntimeError, ~r/undefined scope :nonexistent/, fn ->
        Pipette.validate!(pipeline)
      end
    end

    test "raises on invalid group depends_on reference" do
      pipeline = %Pipette.Pipeline{
        scopes: [],
        groups: [
          %Pipette.Group{
            name: :deploy,
            depends_on: :nonexistent,
            steps: [
              %Pipette.Step{name: :push, label: "Push", command: "push.sh"}
            ]
          }
        ]
      }

      assert_raise RuntimeError, ~r/depends on undefined group :nonexistent/, fn ->
        Pipette.validate!(pipeline)
      end
    end

    test "raises on invalid group depends_on list reference" do
      pipeline = %Pipette.Pipeline{
        scopes: [],
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]
          },
          %Pipette.Group{
            name: :deploy,
            depends_on: [:api, :missing],
            steps: [%Pipette.Step{name: :push, label: "Push", command: "push.sh"}]
          }
        ]
      }

      assert_raise RuntimeError, ~r/depends on undefined group :missing/, fn ->
        Pipette.validate!(pipeline)
      end
    end

    test "raises on invalid trigger depends_on reference" do
      pipeline = %Pipette.Pipeline{
        scopes: [],
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]
          }
        ],
        triggers: [
          %Pipette.Trigger{
            name: :deploy,
            pipeline: "deploy-pipeline",
            depends_on: :nonexistent
          }
        ]
      }

      assert_raise RuntimeError, ~r/Trigger.*depends on undefined group :nonexistent/, fn ->
        Pipette.validate!(pipeline)
      end
    end

    test "raises on dependency cycle" do
      pipeline = %Pipette.Pipeline{
        scopes: [],
        groups: [
          %Pipette.Group{
            name: :a,
            depends_on: :c,
            steps: [%Pipette.Step{name: :s, label: "S", command: "s"}]
          },
          %Pipette.Group{
            name: :b,
            depends_on: :a,
            steps: [%Pipette.Step{name: :s, label: "S", command: "s"}]
          },
          %Pipette.Group{
            name: :c,
            depends_on: :b,
            steps: [%Pipette.Step{name: :s, label: "S", command: "s"}]
          }
        ]
      }

      assert_raise RuntimeError, ~r/Dependency cycle detected/, fn ->
        Pipette.validate!(pipeline)
      end
    end

    test "raises when step is missing a label" do
      pipeline = %Pipette.Pipeline{
        scopes: [],
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [
              %Pipette.Step{name: :test, command: "mix test"}
            ]
          }
        ]
      }

      assert_raise RuntimeError, ~r/missing a label/, fn ->
        Pipette.validate!(pipeline)
      end
    end

    test "passes with groups that have no scope" do
      pipeline = %Pipette.Pipeline{
        scopes: [],
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [
              %Pipette.Step{name: :test, label: "Test", command: "mix test"}
            ]
          }
        ]
      }

      assert :ok = Pipette.validate!(pipeline)
    end

    test "validates multiple groups with valid depends_on chain" do
      pipeline = %Pipette.Pipeline{
        scopes: [
          %Pipette.Scope{name: :api_code, files: ["apps/api/**"]}
        ],
        groups: [
          %Pipette.Group{
            name: :api,
            scope: :api_code,
            steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]
          },
          %Pipette.Group{
            name: :packaging,
            depends_on: :api,
            steps: [%Pipette.Step{name: :build, label: "Build", command: "docker build ."}]
          },
          %Pipette.Group{
            name: :deploy,
            depends_on: :packaging,
            steps: [%Pipette.Step{name: :push, label: "Push", command: "push.sh"}]
          }
        ]
      }

      assert :ok = Pipette.validate!(pipeline)
    end

    test "error message includes available scopes" do
      pipeline = %Pipette.Pipeline{
        scopes: [
          %Pipette.Scope{name: :api_code, files: ["apps/api/**"]},
          %Pipette.Scope{name: :web_code, files: ["apps/web/**"]}
        ],
        groups: [
          %Pipette.Group{
            name: :api,
            scope: :typo_scope,
            steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]
          }
        ]
      }

      assert_raise RuntimeError, ~r/Available scopes:/, fn ->
        Pipette.validate!(pipeline)
      end
    end

    test "error message includes available groups for depends_on" do
      pipeline = %Pipette.Pipeline{
        scopes: [],
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]
          },
          %Pipette.Group{
            name: :deploy,
            depends_on: :typo_group,
            steps: [%Pipette.Step{name: :push, label: "Push", command: "push.sh"}]
          }
        ]
      }

      assert_raise RuntimeError, ~r/Available groups:/, fn ->
        Pipette.validate!(pipeline)
      end
    end

    test "force_activate with invalid group raises" do
      pipeline = %Pipette.Pipeline{
        scopes: [],
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]
          }
        ],
        force_activate: %{
          "FORCE_DEPLOY" => [:nonexistent]
        }
      }

      assert_raise RuntimeError,
                   ~r/force_activate.*references undefined group :nonexistent/,
                   fn ->
                     Pipette.validate!(pipeline)
                   end
    end

    test "force_activate with :all passes validation" do
      pipeline = %Pipette.Pipeline{
        scopes: [],
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]
          }
        ],
        force_activate: %{
          "FORCE_ALL" => :all
        }
      }

      assert :ok = Pipette.validate!(pipeline)
    end

    test "force_activate with valid groups passes" do
      pipeline = %Pipette.Pipeline{
        scopes: [],
        groups: [
          %Pipette.Group{
            name: :api,
            steps: [%Pipette.Step{name: :test, label: "Test", command: "mix test"}]
          },
          %Pipette.Group{
            name: :web,
            steps: [%Pipette.Step{name: :build, label: "Build", command: "pnpm build"}]
          }
        ],
        force_activate: %{
          "FORCE_API" => [:api],
          "FORCE_ALL" => [:api, :web]
        }
      }

      assert :ok = Pipette.validate!(pipeline)
    end
  end
end
