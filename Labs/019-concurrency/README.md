# Lab 019 - Concurrency

## Introduction

- By default, GitHub Actions runs every triggered workflow independently, which can lead to multiple workflow runs executing simultaneously.
- For deployments, this creates race conditions - two runs might try to deploy to the same environment at the same time, producing unpredictable results.
- The `concurrency` key allows you to define groups of runs that should not overlap, and to control whether a queued run should cancel or wait for the current one.

---

## The `concurrency` Key

```yaml
concurrency:
  group: my-concurrency-group
  cancel-in-progress: true
```

| Field                | Description                                                                                                                                       |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `group`              | A string identifier. Only one run per group can be active at a time.                                                                              |
| `cancel-in-progress` | `true`: cancel the currently running workflow when a new one starts. `false` (default): queue the new run and wait for the current one to finish. |

---

## Concurrency at Workflow Level vs Job Level

### Workflow-Level Concurrency

Applies to the entire workflow run:

```yaml
name: Deploy

on: push

concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: false # Queue; wait for current deploy to finish
```

### Job-Level Concurrency

Applies only to a specific job:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    concurrency:
      group: deploy-production
      cancel-in-progress: false
    steps:
      - run: ./deploy.sh
```

---

## Queuing vs Cancelling

### `cancel-in-progress: true` - Cancel

Use for CI checks where only the latest commit matters:

```
Commit A pushed → Run A starts (lint + test)
Commit B pushed → Run A is CANCELLED, Run B starts immediately
Commit C pushed → Run B is CANCELLED, Run C starts immediately
```

This keeps CI fast by not wasting time on stale commits.

### `cancel-in-progress: false` - Queue

Use for deployments where order and completion matter:

```
Push to main → Deploy A starts
Push to main → Deploy B is QUEUED (waits for A)
Push to main → Deploy C is QUEUED (waits for B)
```

This ensures every deployment completes in order.

---

## Per-Branch Concurrency Groups

The most common pattern - one concurrent run per branch:

```yaml
name: CI

on: [push, pull_request]

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

With this configuration:

- `main` branch runs are in group `ci-CI-refs/heads/main`
- `feature/my-feature` runs are in group `ci-CI-refs/heads/feature/my-feature`
- Each branch has independent concurrency control

---

## Per-PR Concurrency Groups

For pull request workflows, use the PR number:

```yaml
name: PR Checks

on: pull_request

concurrency:
  group: pr-${{ github.event.pull_request.number }}
  cancel-in-progress: true
```

This cancels outdated PR check runs when new commits are pushed to the PR.

---

## Per-Environment Concurrency Groups

Prevent parallel deployments to the same environment:

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    concurrency:
      group: deploy-staging
      cancel-in-progress: false # Let previous deploy finish
    environment: staging
    steps:
      - run: ./deploy.sh staging

  deploy-production:
    runs-on: ubuntu-latest
    needs: deploy-staging
    concurrency:
      group: deploy-production
      cancel-in-progress: false # Never cancel a production deploy
    environment: production
    steps:
      - run: ./deploy.sh production
```

---

## Combining Workflow and Job Concurrency

You can use both levels simultaneously:

```yaml
name: CI/CD

on: [push]

# Cancel stale CI runs on the same branch
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: npm run lint

  test:
    runs-on: ubuntu-latest
    steps:
      - run: npm test

  deploy:
    runs-on: ubuntu-latest
    needs: [lint, test]
    # Override at job level: deployment should never be cancelled mid-flight
    concurrency:
      group: deploy-${{ github.ref_name }}
      cancel-in-progress: false
    steps:
      - run: ./deploy.sh
```

---

## Complete Example: Full CI/CD Concurrency Strategy

```yaml
name: Full CI/CD with Concurrency

on:
  push:
    branches: [main, develop, "release/**"]
  pull_request:

# Cancel stale runs for CI jobs
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}
  # On main: queue (don't cancel)
  # On other branches/PRs: cancel stale runs

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm"
      - run: npm ci && npm test

  build:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm run build
      - uses: actions/upload-artifact@v4
        with:
          name: dist-${{ github.sha }}
          path: dist/

  deploy-staging:
    runs-on: ubuntu-latest
    needs: build
    if: github.ref == 'refs/heads/develop' || github.ref == 'refs/heads/main'
    # Separate concurrency group for staging deployments
    concurrency:
      group: deploy-staging
      cancel-in-progress: false # Queue staging deploys
    environment:
      name: staging
      url: https://staging.example.com
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: dist-${{ github.sha }}
          path: dist/
      - run: ./deploy.sh staging

  deploy-production:
    runs-on: ubuntu-latest
    needs: deploy-staging
    if: github.ref == 'refs/heads/main'
    # Production: never cancel, never run in parallel
    concurrency:
      group: deploy-production
      cancel-in-progress: false
    environment:
      name: production
      url: https://www.example.com
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: dist-${{ github.sha }}
          path: dist/
      - run: ./deploy.sh production
```

---

## Conditional `cancel-in-progress`

Use expressions to set `cancel-in-progress` dynamically:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  # Cancel on feature branches/PRs, queue on main
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}
```

```yaml
concurrency:
  group: deploy-${{ github.event.inputs.environment || 'staging' }}
  # Cancel non-production, queue production
  cancel-in-progress: ${{ github.event.inputs.environment != 'production' }}
```

---

## Concurrency Groups for Manual Deploys

```yaml
name: Manual Deploy

on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [staging, production]
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    concurrency:
      group: deploy-${{ github.event.inputs.environment }}
      cancel-in-progress: false # Manual deploys should complete
    environment: ${{ github.event.inputs.environment }}
    steps:
      - run: echo "Deploying to ${{ github.event.inputs.environment }}"
```

---

## Debug: Visualizing Concurrency Behavior

```
Scenario: rapid pushes to main with deploy-production group

Push 1 → Run 1: test ✓ build ✓ deploy starts...
Push 2 → Run 2: test ✓ build ✓ deploy QUEUED (waiting for Run 1)
Push 3 → Run 3: test ✓ build ✓ deploy QUEUED (waiting for Run 2)
...
Run 1 deploy complete → Run 2 deploy starts
Run 2 deploy complete → Run 3 deploy starts
```

Without concurrency control:

```
Push 1 → deploy starts → writing config files...
Push 2 → deploy starts → OVERWRITES config files!
Result: broken deployment state
```

---

## Hands-on

1. Add a `concurrency` group keyed on `${{ github.ref }}` with `cancel-in-progress: true` to a CI workflow:

   ??? success "Solution"
   `bash
    cat > .github/workflows/ci-concurrency.yml << 'EOF'
    name: CI with Concurrency
    on: push
    concurrency:
      group: ci-${{ github.ref }}
      cancel-in-progress: true
    jobs:
      test:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - run: sleep 30 && echo "Tests done"
    EOF
    `

2. Set `cancel-in-progress: true` at the workflow level and confirm an older run is cancelled when a new push arrives:

   ??? success "Solution"
   `bash
    git commit --allow-empty -m "trigger run 1" && git push
    git commit --allow-empty -m "trigger run 2" && git push
    gh run list --workflow ci-concurrency.yml --limit 4 \
      | awk '{print $1, $2, $3}'
    `

3. Create a per-environment concurrency group on the deploy job so staging deployments queue instead of cancel:

   ??? success "Solution"
   `bash
    cat > .github/workflows/deploy-queued.yml << 'EOF'
    name: Deploy Queued
    on: push
    jobs:
      deploy-staging:
        runs-on: ubuntu-latest
        concurrency:
          group: deploy-staging
          cancel-in-progress: false
        environment: staging
        steps:
          - run: sleep 20 && echo "Staged"
    EOF
    `

4. Trigger two runs on the same branch and watch one queue while the other runs using `gh run list`:

   ??? success "Solution"
   `bash
    git commit --allow-empty -m "queue test 1" && git push
    git commit --allow-empty -m "queue test 2" && git push
    sleep 5
    gh run list --workflow deploy-queued.yml --limit 4 \
      | awk '{print $1, $2, $3, $4}'
    `

5. Add a separate `deploy-production` concurrency group that queues (never cancels) independently from staging:

   ??? success "Solution"
   `bash
    cat > .github/workflows/deploy-prod-queued.yml << 'EOF'
    name: Deploy Prod Queued
    on:
      push:
        branches: [main]
    jobs:
      deploy-staging:
        runs-on: ubuntu-latest
        concurrency:
          group: deploy-staging
          cancel-in-progress: false
        environment: staging
        steps:
          - run: echo "Deploying to staging"
      deploy-production:
        runs-on: ubuntu-latest
        needs: deploy-staging
        concurrency:
          group: deploy-production
          cancel-in-progress: false
        environment: production
        steps:
          - run: echo "Deploying to production"
    EOF
    `

## Exercises

### Exercise 1 - Basic Cancellation

Add `cancel-in-progress: true` to a CI workflow. Push multiple commits in rapid succession and verify earlier runs are cancelled.

### Exercise 2 - Per-Branch Groups

Create a CI workflow with per-branch concurrency groups. Open two PRs and verify they do not interfere with each other.

### Exercise 3 - Deployment Queueing

Trigger a slow deployment (add a `sleep 60` step). While it runs, trigger another. Verify the second is queued, not cancelled.

### Exercise 4 - Conditional Cancel

Implement conditional `cancel-in-progress` that cancels stale runs on feature branches but queues runs on `main`.

### Exercise 5 - Mixed Strategy

Create a workflow where:

- CI jobs cancel stale runs (workflow level)
- Staging deploy queues runs (job level, `cancel-in-progress: false`)
- Production deploy also queues (job level, separate group from staging)

---

## Summary

- The `concurrency` key defines a group name that limits how many workflow runs or jobs can be active simultaneously within that group
- `cancel-in-progress: true` cancels the currently running workflow when a new run with the same group is triggered - ideal for CI checks where only the latest commit matters
- `cancel-in-progress: false` (the default) queues the new run, allowing the current one to complete first - essential for deployments that must not be interrupted
- Including `github.ref` in the group expression creates per-branch isolation so different branches do not interfere with each other's runs
- Concurrency can be set at both the workflow level and the job level, allowing CI jobs to cancel while the deploy job in the same workflow queues
- Production deployments should always use `cancel-in-progress: false` with a dedicated group to ensure every deployment completes in the correct order
- Expressions in `cancel-in-progress` (e.g., `${{ github.ref != 'refs/heads/main' }}`) enable context-sensitive behavior without multiple workflow files
