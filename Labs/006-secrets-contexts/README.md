# Lab 006 - Secrets and Contexts

## Introduction

- **Secrets** store sensitive values (API keys, tokens, passwords) that your workflows need without exposing them in logs or YAML files.
- **Contexts** are structured objects that provide runtime information about the workflow, the triggering event, the runner, and more.
- Together, secrets and contexts give you access to everything you need - safely and expressively - to build powerful, production-grade workflows.

---

## 1. GitHub Actions Contexts

A context is a collection of properties available via the `${{ context.property }}` expression syntax. Every context is automatically populated by GitHub at runtime.

### Available contexts

| Context    | Description                                                 |
| ---------- | ----------------------------------------------------------- |
| `github`   | Information about the workflow run and triggering event     |
| `env`      | Environment variables defined in the workflow, job, or step |
| `vars`     | Repository/org/environment variables (non-sensitive)        |
| `secrets`  | Repository/org/environment secrets                          |
| `runner`   | Information about the runner executing the job              |
| `job`      | Information about the currently executing job               |
| `jobs`     | Outputs from other jobs (reusable workflow context)         |
| `steps`    | Outputs and results from previous steps in the same job     |
| `inputs`   | Workflow dispatch or reusable workflow inputs               |
| `needs`    | Outputs from jobs that this job depends on                  |
| `strategy` | Strategy parameters for the current matrix job              |
| `matrix`   | Matrix parameters for the current job                       |

---

## 2. The `github` Context

The most frequently used context - provides information about the repository, event, actor, and run:

```yaml
steps:
  - name: Dump github context
    run: |
      echo "Repository:   ${{ github.repository }}"
      echo "Owner:        ${{ github.repository_owner }}"
      echo "SHA:          ${{ github.sha }}"
      echo "Ref:          ${{ github.ref }}"
      echo "Ref name:     ${{ github.ref_name }}"
      echo "Ref type:     ${{ github.ref_type }}"
      echo "Event name:   ${{ github.event_name }}"
      echo "Actor:        ${{ github.actor }}"
      echo "Workflow:     ${{ github.workflow }}"
      echo "Run ID:       ${{ github.run_id }}"
      echo "Run number:   ${{ github.run_number }}"
      echo "Run attempt:  ${{ github.run_attempt }}"
      echo "Server URL:   ${{ github.server_url }}"
      echo "API URL:      ${{ github.api_url }}"
```

### Useful `github` properties

| Property                  | Description                 | Example                       |
| ------------------------- | --------------------------- | ----------------------------- |
| `github.sha`              | Full commit SHA             | `ffac537e6cbbf934b...`        |
| `github.ref`              | Full ref                    | `refs/heads/main`             |
| `github.ref_name`         | Short ref name              | `main`                        |
| `github.ref_type`         | `branch` or `tag`           | `branch`                      |
| `github.event_name`       | Trigger event               | `push`                        |
| `github.actor`            | User who triggered the run  | `octocat`                     |
| `github.repository`       | `owner/repo`                | `octocat/hello-world`         |
| `github.repository_owner` | Repo owner                  | `octocat`                     |
| `github.workspace`        | Checkout path               | `/home/runner/work/repo/repo` |
| `github.token`            | Auto-generated GITHUB_TOKEN | `ghs_...`                     |
| `github.event`            | Full event payload object   | `{ "pusher": {...}, ... }`    |
| `github.job`              | Current job ID              | `build`                       |
| `github.run_id`           | Unique run ID               | `1234567890`                  |
| `github.run_number`       | Sequential run number       | `42`                          |
| `github.head_ref`         | PR source branch            | `feature/my-feature`          |
| `github.base_ref`         | PR target branch            | `main`                        |

---

## 3. The `env` Context

Access environment variables defined in the workflow:

```yaml
env:
  APP_NAME: my-app
  DEPLOY_REGION: us-east-1

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      # Use env context in 'with:' block (where shell expansion doesn't work)
      - uses: some-action/deploy@v1
        with:
          app: ${{ env.APP_NAME }}
          region: ${{ env.DEPLOY_REGION }}

      # Use in 'if:' condition
      - name: Debug mode
        if: env.LOG_LEVEL == 'debug'
        run: echo "Debug logging enabled"
```

---

## 4. The `vars` Context

Repository, organization, and environment variables are non-sensitive configuration stored in GitHub's Settings. They are accessible via `vars`:

```yaml
steps:
  - name: Use configuration variables
    run: |
      echo "Deploy bucket: ${{ vars.DEPLOY_BUCKET }}"
      echo "AWS region:    ${{ vars.AWS_REGION }}"
      echo "Max retries:   ${{ vars.MAX_RETRY_COUNT }}"
```

### Setting vars with the gh CLI

```bash
# Repository-level variable
gh variable set DEPLOY_BUCKET --body "my-production-bucket"
gh variable set AWS_REGION --body "us-east-1"

# List variables
gh variable list

# Organization-level variable
gh variable set MY_ORG_VAR --org my-org --body "org-wide value"
```

---

## 5. Secrets

Secrets are encrypted values stored by GitHub. They are:

- Masked in log output (replaced with `***`)
- Never available in pull requests from forked repositories (by default)
- Accessible via `${{ secrets.NAME }}`

### Setting secrets with the gh CLI

```bash
# Set a secret from a string
gh secret set MY_API_KEY --body "sk-abc123xyz"

# Set a secret from a file
gh secret set TLS_CERT < ./cert.pem

# Set a secret interactively (prompt)
gh secret set DATABASE_PASSWORD

# Set multiple secrets from an env file
gh secret set --env-file .secrets.env

# List secrets (names only - values are never shown)
gh secret list

# Delete a secret
gh secret delete MY_OLD_SECRET
```

### Accessing secrets in workflows

```yaml
steps:
  - name: Use a secret
    env:
      API_KEY: ${{ secrets.MY_API_KEY }}
    run: |
      echo "Using API key (masked): $API_KEY"
      # GitHub replaces $API_KEY with *** in logs
      curl -H "Authorization: Bearer $API_KEY" https://api.example.com/data

  - name: Pass secret to action
    uses: some-action/deploy@v1
    with:
      token: ${{ secrets.DEPLOY_TOKEN }}
```

### The automatic GITHUB_TOKEN

GitHub automatically creates a `GITHUB_TOKEN` secret for every workflow run. It has permissions scoped to the repository and expires when the job completes.

```yaml
steps:
  - name: Use GITHUB_TOKEN
    run: |
      gh release create v1.0.0 --notes "Release notes"
    env:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  - name: Create a comment on PR
    uses: actions/github-script@v7
    with:
      script: |
        github.rest.issues.createComment({
          issue_number: context.issue.number,
          owner: context.repo.owner,
          repo: context.repo.repo,
          body: 'CI passed!'
        })
```

### Configuring GITHUB_TOKEN permissions

```yaml
# Workflow-level permissions
permissions:
  contents: write # read, write, or none
  pull-requests: write
  issues: read
  packages: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: write # job-level override
    steps:
      - run: echo "This job can write to the repo"
```

---

## 6. The `runner` Context

```yaml
steps:
  - name: Runner info
    run: |
      echo "OS:         ${{ runner.os }}"
      echo "Arch:       ${{ runner.arch }}"
      echo "Name:       ${{ runner.name }}"
      echo "Temp dir:   ${{ runner.temp }}"
      echo "Tool cache: ${{ runner.tool_cache }}"
```

---

## 7. The `steps` Context

Reference outputs and the result of previous steps:

```yaml
steps:
  - name: Generate output
    id: gen
    run: |
      echo "value=hello-world" >> $GITHUB_OUTPUT
      echo "count=42"          >> $GITHUB_OUTPUT

  - name: Reference previous step
    run: |
      echo "Value:  ${{ steps.gen.outputs.value }}"
      echo "Count:  ${{ steps.gen.outputs.count }}"
      echo "Result: ${{ steps.gen.outcome }}"    # success, failure, skipped
      echo "Concl:  ${{ steps.gen.conclusion }}" # success, failure, skipped, cancelled
```

---

## 8. The `needs` Context

Access outputs from upstream jobs:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.ver.outputs.version }}
    steps:
      - id: ver
        run: echo "version=1.2.3" >> $GITHUB_OUTPUT

  deploy:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - run: |
          echo "Deploying: ${{ needs.build.outputs.version }}"
          echo "Build result: ${{ needs.build.result }}"  # success/failure/...
```

---

## 9. Dumping Full Context (Debugging)

To see the full contents of any context, use `toJSON()`:

```yaml
steps:
  - name: Dump all contexts
    env:
      GITHUB_CONTEXT: ${{ toJSON(github) }}
      RUNNER_CONTEXT: ${{ toJSON(runner) }}
      JOB_CONTEXT: ${{ toJSON(job) }}
      STEPS_CONTEXT: ${{ toJSON(steps) }}
    run: |
      echo "=== GitHub Context ==="
      echo "$GITHUB_CONTEXT" | python3 -m json.tool

      echo "=== Runner Context ==="
      echo "$RUNNER_CONTEXT" | python3 -m json.tool
```

---

## 10. Passing Secrets to Reusable Workflows

```yaml
# Caller workflow
jobs:
  call-deploy:
    uses: ./.github/workflows/deploy.yml
    secrets:
      deploy-token: ${{ secrets.DEPLOY_TOKEN }}
      db-password: ${{ secrets.DATABASE_PASSWORD }}
    # Or inherit all secrets:
    # secrets: inherit

# Called reusable workflow (deploy.yml)
on:
  workflow_call:
    secrets:
      deploy-token:
        required: true
      db-password:
        required: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: echo "Deploying with token"
        env:
          TOKEN: ${{ secrets.deploy-token }}
```

---

## Hands-on

1. Set a repository secret named `MY_API_KEY` using the `gh` CLI:

   ??? success "Solution"
   `bash
    gh secret set MY_API_KEY --body "sk-demo-12345"
    `

2. List all secrets defined in the current repository:

   ??? success "Solution"
   `bash
    gh secret list
    `

3. Create a workflow that dumps the full `github` context as pretty-printed JSON:

   ??? success "Solution"
   `bash
    cat > .github/workflows/dump-context.yml << 'EOF'
    name: Dump github Context
    on: [workflow_dispatch]
    jobs:
      dump:
        runs-on: ubuntu-latest
        steps:
          - env:
              GITHUB_CONTEXT: ${{ toJSON(github) }}
            run: echo "$GITHUB_CONTEXT" | python3 -m json.tool
    EOF
    `

4. Set a repository variable with `gh variable set` and reference it in a workflow via the `vars` context:

   ??? success "Solution"
   `bash
    gh variable set DEPLOY_REGION --body "us-east-1"
    cat > .github/workflows/use-vars.yml << 'EOF'
    name: Use vars Context
    on: [workflow_dispatch]
    jobs:
      show:
        runs-on: ubuntu-latest
        steps:
          - run: echo "Region is ${{ vars.DEPLOY_REGION }}"
    EOF
    `

5. Mask a custom value at runtime so it never appears in plain text in the workflow logs:

   ??? success "Solution"
   `bash
    cat > .github/workflows/mask-value.yml << 'EOF'
    name: Mask Custom Value
    on: [workflow_dispatch]
    jobs:
      mask:
        runs-on: ubuntu-latest
        steps:
          - run: |
              MY_VALUE="super-secret-runtime-value"
              echo "::add-mask::$MY_VALUE"
              echo "Value is: $MY_VALUE"
    EOF
    `

## Exercises

### Exercise 1: Set and Use a Secret

```bash
gh secret set MY_LAB_SECRET --body "super-secret-value"
```

Then create a workflow that uses it:

```yaml
steps:
  - run: echo "Secret value: ${{ secrets.MY_LAB_SECRET }}"
```

Observe that the actual value is masked in the logs.

### Exercise 2: Dump the github Context

Create a workflow that dumps the full `github` context to the job log using `toJSON(github)`.

### Exercise 3: Use vars for Configuration

```bash
gh variable set APP_NAME --body "my-test-app"
gh variable set DEPLOY_REGION --body "us-west-2"
```

Use them in a workflow: `${{ vars.APP_NAME }}` and `${{ vars.DEPLOY_REGION }}`.

### Exercise 4: Minimal GITHUB_TOKEN Permissions

Create a workflow that sets `permissions: read-all` at the workflow level and `permissions: contents: write` at a specific job level.

---

## Summary

- The `github` context provides rich metadata about the triggering event, repository, actor, and run - accessed with `${{ github.sha }}`, `${{ github.ref_name }}`, etc.
- Secrets are encrypted at rest, masked in logs, and accessed via `${{ secrets.NAME }}`; use `gh secret set` to store them from the CLI
- The `GITHUB_TOKEN` is automatically created for every run, scoped to the repository, and used to authenticate API calls and gh CLI commands
- The `vars` context holds non-sensitive configuration variables set in repo/org settings, accessible as `${{ vars.NAME }}` - ideal for region names, bucket names, feature flags
- The `steps` context exposes `outputs`, `outcome`, and `conclusion` for previous steps in the same job - use a step's `id:` to reference it
- Use `toJSON(github)` in an env variable to dump the full context object for debugging, passed through `python3 -m json.tool` for readable output
- Restrict `GITHUB_TOKEN` permissions using the `permissions:` key at workflow or job level to follow the principle of least privilege
