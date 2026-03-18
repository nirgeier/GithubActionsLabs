# Lab 008 - Conditions

## Introduction

- **Conditional execution** lets you control which jobs and steps run based on the current state of the workflow - the triggering event, the branch, the result of previous steps, or custom inputs.
- The `if:` key is the primary mechanism for this, and it works in conjunction with GitHub Actions expressions from Lab 007.
- Mastering conditions is essential for building real-world pipelines: deploy only from main, skip expensive tests on documentation changes, send alerts only on failure, run cleanup steps regardless of outcome.

---

## 1. The `if` Key

The `if:` key can be applied to both **jobs** and **steps**:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' # job-level condition
    steps:
      - name: Only on Fridays
        if: github.event.created_at != '' # step-level condition
        run: echo "Deploy step"
```

When an `if:` condition evaluates to `false`:

- For a **step**: the step is skipped (status = `skipped`)
- For a **job**: the job is skipped, and all downstream jobs that `needs:` this job will also be skipped (unless they use special conditions)

---

## 2. Status Check Functions

By default, a job or step runs only if all previous steps/jobs **succeeded**. Status functions override this:

### `success()` - Default behavior

```yaml
steps:
  - run: echo "Step 1"

  # These are equivalent - both only run if Step 1 succeeded:
  - run: echo "Step 2 - implicit success()"
  - if: success()
    run: echo "Step 2 - explicit success()"
```

### `failure()` - Run on failure

```yaml
steps:
  - name: Run tests
    id: tests
    run: ./run-tests.sh # might fail

  - name: Notify on failure
    if: failure()
    run: |
      echo "Tests failed!"
      # Send Slack notification, create GitHub issue, etc.
      curl -X POST "$SLACK_WEBHOOK" -d '{"text":"CI failed on ${{ github.repository }}"}'
    env:
      SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK }}
```

### `always()` - Always run

```yaml
steps:
  - name: Run tests
    run: ./run-tests.sh

  - name: Upload test results
    if: always() # upload regardless of test outcome
    uses: actions/upload-artifact@v4
    with:
      name: test-results
      path: ./test-output/

  - name: Cleanup temp files
    if: always()
    run: rm -rf /tmp/test-*
```

### `cancelled()` - Run only if cancelled

```yaml
steps:
  - name: Long operation
    run: sleep 300 # simulate long task

  - name: Handle cancellation
    if: cancelled()
    run: |
      echo "Workflow was cancelled"
      # Clean up resources, release locks, etc.
```

---

## 3. Combining Status Functions

```yaml
steps:
  - id: step1
    run: echo "Step 1"

  - name: Run if step1 succeeded or was cancelled
    if: success() || cancelled()
    run: echo "Not a failure"

  - name: Run if step1 failed or was cancelled
    if: failure() || cancelled()
    run: echo "Something went wrong or was cancelled"

  - name: Run only on failure, AND we're on main
    if: failure() && github.ref == 'refs/heads/main'
    run: echo "Failure on main branch - high priority alert!"
```

---

## 4. Branch-Based Conditions

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: make build

  deploy-staging:
    runs-on: ubuntu-latest
    needs: build
    if: github.ref == 'refs/heads/develop'
    steps:
      - run: echo "Deploying to staging"

  deploy-production:
    runs-on: ubuntu-latest
    needs: build
    if: github.ref == 'refs/heads/main'
    steps:
      - run: echo "Deploying to production"

  tag-release:
    runs-on: ubuntu-latest
    needs: build
    if: startsWith(github.ref, 'refs/tags/v')
    steps:
      - run: echo "Creating release for ${{ github.ref_name }}"
```

---

## 5. Event-Based Conditions

```yaml
steps:
  - name: Push-only step
    if: github.event_name == 'push'
    run: echo "Running because of a push"

  - name: PR-only step
    if: github.event_name == 'pull_request'
    run: echo "Running because of a PR"

  - name: Manual trigger step
    if: github.event_name == 'workflow_dispatch'
    run: echo "Manually triggered by ${{ github.actor }}"

  - name: Scheduled step
    if: github.event_name == 'schedule'
    run: echo "Running on schedule"

  - name: Multiple events
    if: github.event_name == 'push' || github.event_name == 'workflow_dispatch'
    run: echo "Push or manual trigger"

  # Using contains with fromJSON for cleaner multi-event checks
  - name: Allowed events
    if: contains(fromJSON('["push", "workflow_dispatch", "release"]'), github.event_name)
    run: echo "Acceptable event type"
```

---

## 6. Actor-Based Conditions

```yaml
steps:
  - name: Only for specific user
    if: github.actor == 'dependabot[bot]'
    run: echo "Auto-merging Dependabot PR"

  - name: Block certain actors
    if: github.actor != 'some-bot'
    run: echo "Not the bot"

  - name: Only for org members
    if: github.actor == github.repository_owner
    run: echo "Owner is running this"
```

---

## 7. PR-Specific Conditions

```yaml
steps:
  - name: Check PR target branch
    if: github.event_name == 'pull_request' && github.base_ref == 'main'
    run: echo "PR targets main branch - full validation"

  - name: PR from fork
    if: github.event.pull_request.head.repo.fork == true
    run: echo "This is a fork PR"

  - name: PR draft check
    if: github.event.pull_request.draft == false
    run: echo "PR is not a draft - running CI"

  - name: Check PR label
    if: contains(github.event.pull_request.labels.*.name, 'skip-ci')
    run: |
      echo "skip-ci label detected"
      exit 0
```

---

## 8. `continue-on-error`

This is different from `if:` - instead of skipping the step, it lets the step run and fail without failing the overall job:

```yaml
steps:
  - name: Optional lint check
    continue-on-error: true
    run: |
      echo "Running optional linter..."
      # Even if this fails, the next step runs
      eslint . || exit 1

  - name: This runs even if lint failed
    run: echo "Lint failure was tolerated"
```

### Job-level `continue-on-error`

```yaml
jobs:
  flaky-test:
    runs-on: ubuntu-latest
    continue-on-error: true # entire job can fail without failing the workflow
    steps:
      - run: ./flaky-test.sh

  required-test:
    runs-on: ubuntu-latest
    steps:
      - run: ./required-test.sh
```

---

## 9. Job-Level Conditions with `needs` Results

When conditioning on the results of upstream jobs:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: ./test.sh

  deploy:
    runs-on: ubuntu-latest
    needs: test
    # needs.test.result is 'success', 'failure', 'skipped', or 'cancelled'
    if: needs.test.result == 'success' && github.ref == 'refs/heads/main'
    steps:
      - run: echo "Deploying after successful tests on main"

  notify-failure:
    runs-on: ubuntu-latest
    needs: [test, deploy]
    if: always() && (needs.test.result == 'failure' || needs.deploy.result == 'failure')
    steps:
      - run: echo "Something failed - notifying team"
```

---

## 10. Complete Example: Production Pipeline with Conditions

```yaml
name: Full CI/CD with Conditions

on:
  push:
    branches: [main, develop, "feature/**"]
  pull_request:
    branches: [main, develop]
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      force-deploy:
        type: boolean
        default: false

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Linting..."

  test:
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4

      - name: Full test suite
        run: echo "Running full tests..."

      - name: Extended tests (main/release only)
        if: github.ref == 'refs/heads/main' || github.event_name == 'release'
        run: echo "Running extended test suite..."

      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: test-output/ || true

  deploy-staging:
    runs-on: ubuntu-latest
    needs: test
    if: github.ref == 'refs/heads/develop' && github.event_name == 'push'
    steps:
      - run: echo "Deploying to staging..."

  deploy-production:
    runs-on: ubuntu-latest
    needs: test
    if: |
      (github.ref == 'refs/heads/main' && github.event_name == 'push') ||
      (github.event_name == 'release') ||
      (github.event_name == 'workflow_dispatch' && inputs.force-deploy == true)
    environment: production
    steps:
      - run: echo "Deploying to production..."

  notify-success:
    runs-on: ubuntu-latest
    needs: [deploy-staging, deploy-production]
    if: success()
    steps:
      - run: echo "All deployments succeeded"

  notify-failure:
    runs-on: ubuntu-latest
    needs: [lint, test, deploy-staging, deploy-production]
    if: failure()
    steps:
      - run: |
          echo "Pipeline failed!"
          echo "Lint result:       ${{ needs.lint.result }}"
          echo "Test result:       ${{ needs.test.result }}"
          echo "Staging result:    ${{ needs.deploy-staging.result }}"
          echo "Production result: ${{ needs.deploy-production.result }}"
```

---

## Hands-on

1. Write a job-level `if` condition that only runs the job when the triggering branch is `main`:

    ??? success "Solution"
        ```bash
        cat > .github/workflows/main-only.yml << 'EOF'
        name: Main Branch Only
        on: [push]
        jobs:
          deploy:
            runs-on: ubuntu-latest
            if: github.ref == 'refs/heads/main'
            steps:
              - run: echo "Deploying from main"
        EOF
        ```

2. Add a step with `if: always()` that runs unconditionally as a cleanup step after a potentially failing step:

    ??? success "Solution"
        ```bash
        cat > .github/workflows/always-cleanup.yml << 'EOF'
        name: Always Cleanup
        on: [push]
        jobs:
          test:
            runs-on: ubuntu-latest
            steps:
              - run: echo "Running tests..." && exit 1
                continue-on-error: true
              - name: Cleanup
                if: always()
                run: echo "Cleanup runs regardless of test outcome"
        EOF
        ```

3. Use `if: failure()` on a step to send a simulated failure notification:

    ??? success "Solution"
        ```bash
        cat > .github/workflows/failure-notify.yml << 'EOF'
        name: Failure Notification
        on: [push]
        jobs:
          build:
            runs-on: ubuntu-latest
            steps:
              - run: exit 1
              - name: Notify on failure
                if: failure()
                run: echo "Build failed on ${{ github.ref_name }} by ${{ github.actor }}"
        EOF
        ```

4. Add `continue-on-error: true` to a flaky test step so the rest of the job proceeds even when it fails:

    ??? success "Solution"
        ```bash
        cat > .github/workflows/flaky-step.yml << 'EOF'
        name: Flaky Step
        on: [push]
        jobs:
          ci:
            runs-on: ubuntu-latest
            steps:
              - name: Flaky integration test
                continue-on-error: true
                run: bash -c 'exit $((RANDOM % 2))'
              - run: echo "Job continues regardless of flaky test result"
        EOF
        ```

5. Combine `&&` and `||` conditions — run a notification step only when the job fails AND the branch is `main`:

    ??? success "Solution"
        ```bash
        cat > .github/workflows/combined-conditions.yml << 'EOF'
        name: Combined Conditions
        on: [push]
        jobs:
          build:
            runs-on: ubuntu-latest
            steps:
              - run: echo "Simulating work"
              - name: Alert on main failure
                if: failure() && github.ref == 'refs/heads/main'
                run: echo "CRITICAL: failure on main branch!"
        EOF
        ```

---

## Exercises

### Exercise 1: Branch-Conditional Deployment

Create a workflow with three jobs: `build`, `deploy-staging` (only on `develop`), and `deploy-production` (only on `main`).

### Exercise 2: Failure Notification

Add a step after a potentially-failing step that uses `if: failure()` to print an error message.

### Exercise 3: Always-Run Cleanup

Create a workflow where the last step always runs (using `if: always()`) to clean up temp files, even if earlier steps fail.

### Exercise 4: Skip CI with a PR Label

Create a step that exits early if the PR has a `skip-ci` label:

```yaml
- if: contains(github.event.pull_request.labels.*.name, 'skip-ci')
  run: echo "Skipping CI per label" && exit 0
```

---

## Summary

- The `if:` key on jobs and steps evaluates an expression; when false, the job/step is skipped rather than failed - skipped jobs propagate as skipped to downstream `needs` jobs
- Status functions `success()`, `failure()`, `always()`, and `cancelled()` override the default `success()`-only behavior and enable conditional cleanup, alerting, and recovery logic
- Branch conditions like `github.ref == 'refs/heads/main'` and `startsWith(github.ref, 'refs/tags/')` are the standard way to limit deployments to specific branches or tags
- `continue-on-error: true` on a step allows it to fail without failing the job - useful for optional lint checks, non-critical scans, or known-flaky steps
- Job-level conditions can inspect `needs.<job>.result` values (`success`, `failure`, `skipped`, `cancelled`) to create sophisticated fan-in notification and cleanup patterns
- Combining `always()` with `needs.*.result` checks in notification jobs ensures alerts fire even when upstream jobs are skipped or the workflow is cancelled
- Event-based conditions (`github.event_name == 'push'`, `github.event_name == 'release'`) and actor conditions (`github.actor == 'dependabot[bot]'`) enable fine-grained per-event behavior within a single workflow file
