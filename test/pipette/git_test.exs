defmodule Pipette.GitTest do
  use ExUnit.Case, async: true

  alias Pipette.Git

  describe "matches_glob?/2" do
    test "matches simple glob" do
      assert Git.matches_glob?("apps/backend/lib/foo.ex", "apps/backend/**")
    end

    test "matches nested path" do
      assert Git.matches_glob?("apps/backend/lib/deep/nested/file.ex", "apps/backend/**")
    end

    test "does not match different path" do
      refute Git.matches_glob?("apps/native/lib/foo.js", "apps/backend/**")
    end

    test "matches exact file" do
      assert Git.matches_glob?("mix.exs", "mix.exs")
    end

    test "matches extension glob" do
      assert Git.matches_glob?("docs/README.md", "*.md")
    end

    test "matches extension glob in subdirectory" do
      assert Git.matches_glob?("docs/guide/intro.md", "**/*.md")
    end

    test "matches root-level glob" do
      assert Git.matches_glob?("mix.lock", "mix.*")
    end

    test "does not match partial name" do
      refute Git.matches_glob?("apps/backend/lib/foo.ex", "apps/back/**")
    end
  end

  describe "base_commit/1" do
    test "uses PR base branch when available" do
      ctx = %Pipette.Context{
        branch: "feature/login",
        default_branch: "main",
        pull_request_base_branch: "main"
      }

      assert Git.base_commit(ctx) == "origin/main"
    end

    test "uses default branch for non-PR feature branches" do
      ctx = %Pipette.Context{
        branch: "feature/login",
        default_branch: "main",
        pull_request_base_branch: nil
      }

      assert Git.base_commit(ctx) == "origin/main"
    end

    test "uses HEAD~1 on the default branch" do
      ctx = %Pipette.Context{
        branch: "main",
        default_branch: "main",
        pull_request_base_branch: nil
      }

      assert Git.base_commit(ctx) == "HEAD~1"
    end
  end

  describe "fired_scopes/2" do
    test "fires scope when changed file matches" do
      scopes = [
        %Pipette.Scope{name: :backend, files: ["apps/backend/**"]},
        %Pipette.Scope{name: :native, files: ["apps/native/**"]}
      ]

      changed = ["apps/backend/lib/user.ex", "apps/backend/test/user_test.exs"]

      fired = Git.fired_scopes(scopes, changed)

      assert :backend in fired
      refute :native in fired
    end

    test "fires multiple scopes" do
      scopes = [
        %Pipette.Scope{name: :backend, files: ["apps/backend/**"]},
        %Pipette.Scope{name: :native, files: ["apps/native/**"]}
      ]

      changed = ["apps/backend/lib/user.ex", "apps/native/src/App.tsx"]

      fired = Git.fired_scopes(scopes, changed)

      assert :backend in fired
      assert :native in fired
    end

    test "respects exclude patterns" do
      scopes = [
        %Pipette.Scope{name: :infra, files: ["infra/**"], exclude: ["**/*.md"]}
      ]

      changed = ["infra/README.md"]

      fired = Git.fired_scopes(scopes, changed)
      refute :infra in fired
    end

    test "fires when non-excluded file present" do
      scopes = [
        %Pipette.Scope{name: :infra, files: ["infra/**"], exclude: ["**/*.md"]}
      ]

      changed = ["infra/main.tf", "infra/README.md"]

      fired = Git.fired_scopes(scopes, changed)
      assert :infra in fired
    end

    test "scope with multiple file patterns" do
      scopes = [
        %Pipette.Scope{name: :backend, files: ["apps/backend/**", "mix.exs", "mix.lock"]}
      ]

      changed = ["mix.exs"]

      fired = Git.fired_scopes(scopes, changed)
      assert :backend in fired
    end

    test "returns empty set when no scopes match" do
      scopes = [
        %Pipette.Scope{name: :backend, files: ["apps/backend/**"]}
      ]

      changed = ["docs/README.md"]

      fired = Git.fired_scopes(scopes, changed)
      assert fired == MapSet.new()
    end
  end

  describe "all_ignored?/2" do
    test "returns true when all files match ignore patterns" do
      ignore = ["docs/**", "*.md", ".claude/**"]
      changed = ["docs/guide.md", "README.md"]

      assert Git.all_ignored?(changed, ignore)
    end

    test "returns false when some files don't match" do
      ignore = ["docs/**", "*.md"]
      changed = ["docs/guide.md", "lib/app.ex"]

      refute Git.all_ignored?(changed, ignore)
    end

    test "returns false for empty changed list" do
      refute Git.all_ignored?([], ["docs/**"])
    end
  end
end
