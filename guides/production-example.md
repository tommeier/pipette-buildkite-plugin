# Production Example

This guide shows a realistic monorepo pipeline — the kind of configuration a team actually ships. It covers lint, test, build, deploy, infrastructure, downstream triggers, and the Pipette features that tie them together.

## The Pipeline

```elixir
defmodule Acme.Pipeline do
  use Pipette.DSL

  branch("main", scopes: :all, disable: [:targeting])
  branch("merge-queue/**", scopes: :all, disable: [:targeting])
  branch("release/*", scopes: [:api_code, :web_code])

  scope(:script_code, files: ["scripts/**/*.sh", ".buildkite/**"])
  scope(:api_code, files: ["apps/api/**", "mix.exs", "mix.lock"])
  scope(:web_code, files: ["apps/web/**", "package.json", "pnpm-lock.yaml"])
  scope(:infra_code, files: ["infra/**"], exclude: ["infra/**/*.md"])
  scope(:root_config, files: [".tool-versions", ".buildkite/**"], activates: :all)

  ignore(["docs/**", "*.md", "LICENSE", ".github/**"])
  force_activate(%{"FORCE_DEPLOY" => [:api, :web, :deploy], "FORCE_ALL" => :all})

  # ---------- Groups ----------

  group :lint do
    label(":mag: Lint")
    scope(:script_code)

    step(:shellcheck,
      label: ":bash: Shellcheck",
      command: "shellcheck scripts/**/*.sh",
      timeout_in_minutes: 5,
      retry: %{automatic: [%{exit_status: -1, limit: 2}]}
    )
  end

  group :api do
    label(":elixir: API")
    scope(:api_code)

    step(:format,
      label: "Format",
      command: "mix format --check-formatted",
      timeout_in_minutes: 5
    )

    step(:credo,
      label: "Credo",
      command: "mix credo --strict",
      timeout_in_minutes: 10
    )

    step(:test,
      label: "Test",
      command: ["mix ecto.create --quiet", "mix ecto.migrate --quiet", "mix test"],
      timeout_in_minutes: 15,
      env: %{
        "MIX_ENV" => "test",
        "DATABASE_URL" => "postgres://buildkite@localhost:5432/api_test"
      },
      retry: %{automatic: [%{exit_status: -1, limit: 2}]},
      artifact_paths: ["_build/test/lib/api/cover/**"]
    )

    step(:build,
      label: ":docker: Build Image",
      command: [
        "docker build -t gcr.io/acme-prod/api:${BUILDKITE_COMMIT} .",
        "docker push gcr.io/acme-prod/api:${BUILDKITE_COMMIT}"
      ],
      depends_on: :test,
      timeout_in_minutes: 20,
      plugins: [
        {"gcp-workload-identity-federation#v1.5.0",
         %{
           audience:
             "//iam.googleapis.com/projects/123456/locations/global/workloadIdentityPools/buildkite/providers/buildkite",
           "service-account": "ci-builder@acme-prod.iam.gserviceaccount.com"
         }}
      ],
      retry: %{automatic: [%{exit_status: -1, limit: 2}, %{exit_status: 1, limit: 1}]}
    )
  end

  group :web do
    label(":react: Web")
    scope(:web_code)

    step(:lint,
      label: "Lint",
      command: "pnpm lint",
      timeout_in_minutes: 10
    )

    step(:typecheck,
      label: "Typecheck",
      command: "pnpm tsc --noEmit",
      timeout_in_minutes: 10
    )

    step(:test,
      label: "Test",
      command: "pnpm test --ci --coverage",
      timeout_in_minutes: 15,
      env: %{"CI" => "true", "NODE_OPTIONS" => "--max-old-space-size=4096"},
      retry: %{automatic: [%{exit_status: -1, limit: 2}]},
      artifact_paths: ["apps/web/coverage/**"]
    )

    step(:build,
      label: ":package: Build",
      command: "pnpm build",
      depends_on: :typecheck,
      timeout_in_minutes: 15,
      env: %{"NODE_ENV" => "production"}
    )
  end

  group :deploy do
    label(":rocket: Deploy")
    depends_on([:api, :web])
    only(["main"])

    step(:pre_release,
      label: ":shipit: Pre-Release",
      command: "./scripts/pre-release.sh",
      timeout_in_minutes: 10,
      concurrency: 1,
      concurrency_group: "deploy/pre-release",
      secrets: ["DEPLOY_TOKEN", "GITHUB_TOKEN"]
    )

    step(:staging,
      label: ":construction: Deploy Staging",
      command: "./scripts/deploy.sh staging",
      depends_on: :pre_release,
      timeout_in_minutes: 30,
      agents: %{queue: "deploy"},
      env: %{"DEPLOY_ENV" => "staging"},
      retry: %{automatic: [%{exit_status: -1, limit: 2}, %{exit_status: 1, limit: 1}]}
    )

    step(:production,
      label: ":globe_with_meridians: Deploy Production",
      command: "./scripts/deploy.sh production",
      depends_on: :staging,
      timeout_in_minutes: 30,
      concurrency: 1,
      concurrency_group: "deploy/production",
      agents: %{queue: "deploy"},
      secrets: ["DEPLOY_TOKEN", "AWS_ACCESS_KEY"],
      env: %{"DEPLOY_ENV" => "production"}
    )

    step(:notify,
      label: ":slack: Notify",
      command: "./scripts/notify-deploy.sh",
      depends_on: [:staging, :production],
      soft_fail: true,
      allow_dependency_failure: true,
      timeout_in_minutes: 5
    )
  end

  group :infra do
    label(":terraform: Infrastructure")
    scope(:infra_code)

    step(:validate,
      label: "Validate",
      command: ["cd infra && terraform init -backend=false", "terraform validate"],
      timeout_in_minutes: 10,
      agents: %{queue: "infra"}
    )

    step(:plan,
      label: "Plan",
      command: ["cd infra && terraform init", "terraform plan -out=tfplan"],
      depends_on: :validate,
      timeout_in_minutes: 15,
      agents: %{queue: "infra"},
      plugins: [
        {"gcp-workload-identity-federation#v1.5.0",
         %{
           audience:
             "//iam.googleapis.com/projects/123456/locations/global/workloadIdentityPools/buildkite/providers/buildkite",
           "service-account": "terraform@acme-prod.iam.gserviceaccount.com"
         }}
      ],
      artifact_paths: ["infra/tfplan"]
    )

    step(:apply,
      label: "Apply",
      command: [
        "cd infra && terraform init",
        "buildkite-agent artifact download 'infra/tfplan' .",
        "terraform apply tfplan"
      ],
      depends_on: :plan,
      timeout_in_minutes: 30,
      concurrency: 1,
      concurrency_group: "infra/terraform-apply",
      agents: %{queue: "infra"},
      branches: "main"
    )
  end

  trigger :deploy_downstream do
    label(":rocket: Trigger Production Deploy")
    pipeline("production-deploy")
    depends_on(:api)
    only("main")

    build(%{
      commit: "${BUILDKITE_COMMIT}",
      branch: "${BUILDKITE_BRANCH}",
      message: "${BUILDKITE_MESSAGE}",
      env: %{"DEPLOY_ENV" => "production", "SOURCE_PIPELINE" => "monorepo"}
    })
  end
end
```

## What This Pipeline Does

### Scopes and activation

- **`:script_code`** — fires when shell scripts or CI config change, activating the lint group
- **`:api_code`** — fires on Elixir source, `mix.exs`, or `mix.lock` changes
- **`:web_code`** — fires on frontend source or lockfile changes
- **`:infra_code`** — fires on Terraform changes (excluding markdown)
- **`:root_config`** — changes to `.tool-versions` or `.buildkite/**` activate *every* group via `activates: :all`

### Branch policies

- **`main`** and **`merge-queue/**`** — run all groups, disable commit message targeting
- **`release/*`** — run only API and web groups (no infra, no lint)
- **Feature branches** — standard scope-based file detection

### The deploy chain

The `:deploy` group demonstrates a multi-step deployment pipeline:

1. **Pre-release** — runs first with `concurrency: 1` to prevent parallel pre-releases
2. **Staging** — `depends_on: :pre_release`, runs on a dedicated deploy agent queue
3. **Production** — `depends_on: :staging`, also concurrency-locked and on the deploy queue
4. **Notify** — `depends_on: [:staging, :production]` with `allow_dependency_failure: true` so it runs even if production fails, and `soft_fail: true` so a Slack failure doesn't mark the build red

The group itself has `depends_on: [:api, :web]` and `only: ["main"]`, so it only runs on main after both test suites pass.

### Cross-group step dependencies

Steps can depend on steps in other groups using tuple syntax:

```elixir
# A deploy step that waits for the API test step specifically
step(:deploy_api,
  label: "Deploy API",
  depends_on: {:api, :test},
  command: "./scripts/deploy-api.sh"
)
```

The tuple `{:api, :test}` resolves to the Buildkite key `"api-test"`. This is useful when a step needs a specific upstream step to pass, not just the entire group.

### Infrastructure steps

The infra group shows Terraform validate/plan/apply with:

- Agent targeting to infra-specific machines (`agents: %{queue: "infra"}`)
- GCP Workload Identity Federation for cloud credentials
- Artifact passing (plan output uploaded, then downloaded for apply)
- `branches: "main"` on the apply step as a safety net — Buildkite-level branch filter
- `concurrency: 1` on apply to prevent concurrent state mutations

### Downstream trigger

The trigger fires the `production-deploy` pipeline after the API group passes on main. It passes the current commit, branch, and message so the downstream pipeline knows what to deploy:

```elixir
trigger :deploy_downstream do
  pipeline("production-deploy")
  depends_on(:api)
  only("main")

  build(%{
    commit: "${BUILDKITE_COMMIT}",
    branch: "${BUILDKITE_BRANCH}",
    message: "${BUILDKITE_MESSAGE}",
    env: %{"DEPLOY_ENV" => "production"}
  })
end
```

### Force activation

Setting `FORCE_DEPLOY=true` on a Buildkite build activates `:api`, `:web`, and `:deploy` regardless of which files changed or which branch you're on. This bypasses `only` branch filtering too — useful for hotfix deploys from a feature branch.

## Pipeline Script

```elixir
# .buildkite/pipeline.exs
Mix.install([{:buildkite_pipette, "~> 0.4"}])
Code.require_file("lib/acme/pipeline.ex")
Pipette.run(Acme.Pipeline)
```

## Running Locally

```bash
DRY_RUN=1 elixir .buildkite/pipeline.exs
```

Or simulate a specific scenario in IEx:

```elixir
{:ok, yaml} = Pipette.generate(Acme.Pipeline,
  env: %{
    "BUILDKITE_BRANCH" => "main",
    "BUILDKITE_PIPELINE_DEFAULT_BRANCH" => "main",
    "BUILDKITE_COMMIT" => "abc123",
    "BUILDKITE_MESSAGE" => "Deploy v2.1.0"
  },
  changed_files: ["apps/api/lib/user.ex"]
)

IO.puts(yaml)
```
