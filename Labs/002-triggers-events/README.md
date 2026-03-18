# Lab 002 - Triggers and Events

## Introduction

- A **trigger** (defined under the `on:` key) determines when a GitHub Actions workflow runs.
- GitHub Actions supports over 35 distinct event types - from code pushes and pull requests to scheduled cron jobs, manual dispatches, and external API calls.
- Choosing the right trigger is critical: too broad and your workflows run unnecessarily; too narrow and automation fails to fire at the right moment.
- This lab covers the most commonly used triggers with practical examples.

---

## 1. Push Triggers

The `push` event fires when commits are pushed to a branch.

### Basic push trigger

```yaml
on:
  push:
```

This triggers on every push to every branch. Usually too broad for production workflows.

### Filter by branch

```yaml
on:
  push:
    branches:
      - main
      - develop
      - "release/**" # glob pattern - any branch starting with release/
      - "!hotfix/**" # negation - exclude hotfix branches
```

### Filter by tag

```yaml
on:
  push:
    tags:
      - "v*.*.*" # v1.0.0, v2.3.1, etc.
      - "v[0-9]+.[0-9]+.[0-9]+" # strict semver
```

### Filter by file path

```yaml
on:
  push:
    branches: [main]
    paths:
      - "src/**"
      - "tests/**"
      - "*.go"
      - "!docs/**" # negation - ignore docs changes
```

Path filters are powerful: a workflow that only triggers when source code changes avoids running CI when only documentation is updated.

### branches vs branches-ignore

```yaml
# Run for main and develop only
on:
  push:
    branches: [main, develop]

# Run for everything EXCEPT release branches
on:
  push:
    branches-ignore:
      - 'release/**'
```

> You cannot use both `branches` and `branches-ignore` in the same trigger.

---

## 2. Pull Request Events

The `pull_request` event fires when a PR is opened, updated, or closed.

### Basic pull_request trigger

```yaml
on:
  pull_request:
    branches: [main]
```

This runs when a PR is opened or updated that targets the `main` branch.

### Pull request types

```yaml
on:
  pull_request:
    types:
      - opened # PR first created
      - synchronize # New commit pushed to PR branch
      - reopened # Closed PR re-opened
      - closed # PR closed (merged or not)
      - labeled # Label added to PR
      - unlabeled # Label removed
      - assigned # Reviewer assigned
      - review_requested # Review requested
```

Default types (when `types:` is omitted): `opened`, `synchronize`, `reopened`

### Pull request with path filters

```yaml
on:
  pull_request:
    branches: [main]
    paths:
      - "src/**"
      - "package.json"
```

### pull_request vs pull_request_target

```yaml
# pull_request: runs in the context of the PR branch (fork PRs have limited secrets)
on:
  pull_request:
    branches: [main]

# pull_request_target: runs in the context of the BASE branch (has access to secrets)
# WARNING: Be careful with pull_request_target - it can expose secrets to untrusted code
on:
  pull_request_target:
    branches: [main]
```

---

## 3. Schedule Triggers (Cron)

Run workflows on a schedule using cron syntax.

```yaml
on:
  schedule:
    - cron: "0 0 * * *" # Daily at midnight UTC
    - cron: "0 9 * * 1-5" # Weekdays at 9 AM UTC
```

### Cron syntax

```
┌───────── minute (0-59)
│ ┌─────── hour (0-23)
│ │ ┌───── day of month (1-31)
│ │ │ ┌─── month (1-12)
│ │ │ │ ┌─ day of week (0-6, Sunday=0)
│ │ │ │ │
* * * * *
```

### Common cron examples

```yaml
on:
  schedule:
    - cron: "0 * * * *" # Every hour
    - cron: "*/15 * * * *" # Every 15 minutes
    - cron: "0 8 * * 1" # Every Monday at 8 AM UTC
    - cron: "0 0 1 * *" # First day of every month at midnight
    - cron: "0 0 * * 0" # Every Sunday at midnight
    - cron: "30 5 1,15 * *" # 5:30 AM on 1st and 15th of every month
```

### Important notes about scheduled workflows

- Scheduled workflows only run on the **default branch** (usually `main`)
- GitHub may delay or skip scheduled runs during high load periods
- Workflows scheduled more frequently than every 5 minutes are not guaranteed
- If your repo is inactive for 60 days, scheduled workflows are disabled

---

## 4. Workflow Dispatch (Manual Trigger)

`workflow_dispatch` lets users trigger a workflow manually from the GitHub UI or CLI.

### Basic manual trigger

```yaml
on:
  workflow_dispatch:
```

### Manual trigger with inputs

```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        description: "Target environment"
        required: true
        type: choice
        options:
          - staging
          - production
        default: staging

      version:
        description: "Version to deploy (e.g., 1.2.3)"
        required: true
        type: string

      dry-run:
        description: "Perform a dry run without deploying"
        required: false
        type: boolean
        default: false

      log-level:
        description: "Log verbosity level"
        required: false
        type: choice
        options:
          - debug
          - info
          - warning
          - error
        default: info
```

### Accessing inputs in steps

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy
        run: |
          echo "Environment: ${{ inputs.environment }}"
          echo "Version:     ${{ inputs.version }}"
          echo "Dry run:     ${{ inputs.dry-run }}"
          echo "Log level:   ${{ inputs.log-level }}"
```

### Triggering from CLI

```bash
# Trigger with no inputs
gh workflow run deploy.yml

# Trigger with inputs
gh workflow run deploy.yml \
  -f environment=staging \
  -f version=1.2.3 \
  -f dry-run=true

# Trigger on a specific branch
gh workflow run deploy.yml --ref feature/my-branch
```

---

## 5. Repository Dispatch (External Trigger)

`repository_dispatch` is triggered by an external HTTP POST request to the GitHub API. It is useful for triggering workflows from external systems (CI pipelines, webhooks, deployment tools).

```yaml
on:
  repository_dispatch:
    types: [deploy-staging, deploy-production, run-tests]
```

### Sending a repository_dispatch event

```bash
# Using gh CLI
gh api repos/{owner}/{repo}/dispatches \
  --method POST \
  -f event_type=deploy-staging \
  -f client_payload='{"version":"1.2.3","env":"staging"}'

# Using curl
curl -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/OWNER/REPO/dispatches \
  -d '{"event_type":"deploy-staging","client_payload":{"version":"1.2.3"}}'
```

### Accessing the payload

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy
        run: |
          echo "Event type: ${{ github.event.action }}"
          echo "Version: ${{ github.event.client_payload.version }}"
          echo "Environment: ${{ github.event.client_payload.env }}"
```

---

## 6. Release Events

```yaml
on:
  release:
    types:
      - published # A release is published (most common)
      - created # A release is created (may still be a draft)
      - edited # Release notes are edited
      - prereleased # A pre-release is published
      - released # A release moves out of pre-release
      - deleted # A release is deleted
```

### Typical release workflow

```yaml
name: Release Pipeline

on:
  release:
    types: [published]

jobs:
  build-and-upload:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build release artifacts
        run: make build

      - name: Upload to release
        run: |
          gh release upload "${{ github.event.release.tag_name }}" \
            ./dist/*.tar.gz
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## 7. Combining Multiple Triggers

You can specify multiple triggers in a single workflow:

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: "0 2 * * *"
  workflow_dispatch:
    inputs:
      reason:
        description: "Why are you running this manually?"
        required: false
        type: string
```

### Checking which event triggered the workflow

```yaml
jobs:
  check-trigger:
    runs-on: ubuntu-latest
    steps:
      - name: Show trigger
        run: |
          echo "Triggered by: ${{ github.event_name }}"
          echo "Actor: ${{ github.actor }}"

      - name: Push-specific step
        if: github.event_name == 'push'
        run: echo "This was triggered by a push"

      - name: Schedule-specific step
        if: github.event_name == 'schedule'
        run: echo "This was triggered by a schedule"

      - name: Manual trigger step
        if: github.event_name == 'workflow_dispatch'
        run: echo "Manual trigger reason: ${{ inputs.reason }}"
```

---

## 8. Other Useful Events

| Event               | Description                         |
| ------------------- | ----------------------------------- |
| `issues`            | Issue opened, closed, labeled, etc. |
| `issue_comment`     | Comment added to an issue or PR     |
| `create`            | Branch or tag created               |
| `delete`            | Branch or tag deleted               |
| `fork`              | Repository forked                   |
| `watch`             | Repository starred                  |
| `gollum`            | Wiki page created or updated        |
| `deployment`        | Deployment created                  |
| `deployment_status` | Deployment status changes           |
| `page_build`        | GitHub Pages build completes        |
| `registry_package`  | Package published or updated        |
| `check_run`         | Check run created or completed      |
| `check_suite`       | Check suite requested               |

---

## Hands-on

1. Create a workflow that triggers on push to `main` only when files under `src/` change:

   ??? success "Solution"
   `bash
    cat > .github/workflows/push-path-filter.yml << 'EOF'
    name: Push with Path Filter
    on:
      push:
        branches: [main]
        paths:
          - "src/**"
    jobs:
      build:
        runs-on: ubuntu-latest
        steps:
          - run: echo "src/ changed on main"
    EOF
    `

2. Create a workflow that runs on a schedule every day at 2 AM UTC:

   ??? success "Solution"
   `bash
    cat > .github/workflows/nightly.yml << 'EOF'
    name: Nightly Build
    on:
      schedule:
        - cron: "0 2 * * *"
    jobs:
      nightly:
        runs-on: ubuntu-latest
        steps:
          - run: echo "Nightly run at $(date)"
    EOF
    `

3. Create a workflow with `workflow_dispatch` that accepts an `environment` input with choices `staging` and `production`:

   ??? success "Solution"
   `bash
    cat > .github/workflows/manual-deploy.yml << 'EOF'
    name: Manual Deploy
    on:
      workflow_dispatch:
        inputs:
          environment:
            description: "Target environment"
            required: true
            type: choice
            options: [staging, production]
            default: staging
    jobs:
      deploy:
        runs-on: ubuntu-latest
        steps:
          - run: echo "Deploying to ${{ inputs.environment }}"
    EOF
    `

4. Check when a specific workflow last ran using `gh run list`:

   ??? success "Solution"
   `bash
    gh run list --workflow nightly.yml --limit 3
    gh run list --workflow nightly.yml --limit 1 --json createdAt,status --jq '.[0]'
    `

5. List every unique workflow trigger defined across all workflow files in the repository:

   ??? success "Solution"
   `bash
    python3 -c "
    import yaml, glob
    for path in glob.glob('.github/workflows/*.yml'):
        data = yaml.safe_load(open(path))
        triggers = list((data or {}).get('on', {}).keys()) if isinstance((data or {}).get('on'), dict) else [data.get('on')]
        print(f'{path}: {triggers}')
    "
    `

## Exercises

### Exercise 1: Push with Path Filters

Create a workflow that only runs when Go files change:

```yaml
name: Go CI
on:
  push:
    branches: [main]
    paths:
      - "**/*.go"
      - "go.mod"
      - "go.sum"
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Go files changed - running tests"
```

### Exercise 2: Scheduled Nightly Build

```yaml
name: Nightly Build
on:
  schedule:
    - cron: "0 2 * * *" # 2 AM UTC every day
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Nightly build at $(date)"
```

### Exercise 3: Manual Deploy with Inputs

```yaml
name: Manual Deploy
on:
  workflow_dispatch:
    inputs:
      env:
        type: choice
        options: [staging, production]
        required: true
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: echo "Deploying to ${{ inputs.env }}"
```

---

## Summary

- The `push` trigger supports `branches`, `tags`, `paths`, and their `-ignore` counterparts to finely control which changes trigger the workflow
- The `pull_request` trigger fires on PR lifecycle events; use `types:` to target specific actions like `opened`, `synchronize`, or `closed`
- The `schedule` trigger uses standard 5-field cron syntax and only runs on the default branch; GitHub may delay execution during high load
- The `workflow_dispatch` trigger enables manual execution with typed inputs (string, boolean, choice) accessible via `${{ inputs.name }}`
- The `repository_dispatch` trigger allows external systems to start workflows via a POST to the GitHub API, with a custom payload accessible in `github.event.client_payload`
- Multiple triggers can coexist under `on:`; use `github.event_name` in `if:` conditions to branch behavior based on what fired the workflow
- The `release` event with `types: [published]` is the standard way to trigger build-and-upload pipelines that produce downloadable artifacts
