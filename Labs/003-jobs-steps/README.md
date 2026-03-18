# Lab 003 - Jobs and Steps

## Introduction

- A GitHub Actions **job** is a set of steps that runs on the same runner.
- **Steps** are the individual tasks within a job - they can run shell commands, call published actions, or set outputs for subsequent steps.
- Understanding how to structure jobs and steps is the foundation of writing maintainable, efficient workflows.
- This lab covers parallel and sequential execution, job dependencies, step outputs, and best practices for organizing complex pipelines.

---

## 1. Defining Jobs

Every workflow has at least one job. Jobs are defined under the `jobs:` key with a unique alphanumeric ID.

```yaml
jobs:
  build: # job ID - used in needs:, outputs:, etc.
    name: Build Application # optional human-readable name
    runs-on: ubuntu-latest
    steps:
      - run: echo "Building..."

  test:
    name: Run Tests
    runs-on: ubuntu-latest
    steps:
      - run: echo "Testing..."
```

### Job ID rules

- Must start with a letter or `_`
- Can contain alphanumeric characters, `-`, and `_`
- Case-sensitive
- Must be unique within the workflow

---

## 2. Parallel vs Sequential Execution

### Parallel (default)

By default, all jobs run in **parallel**:

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo "Linting..." # runs at the same time as 'test' and 'security'

  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo "Testing..."

  security:
    runs-on: ubuntu-latest
    steps:
      - run: echo "Security scan..."
```

All three jobs start simultaneously. Total time ≈ max(lint_time, test_time, security_time).

### Sequential with `needs`

Use `needs:` to express that a job must wait for another to complete:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo "Build done"

  test:
    runs-on: ubuntu-latest
    needs: build # waits for 'build' to succeed
    steps:
      - run: echo "Test done"

  deploy:
    runs-on: ubuntu-latest
    needs: test # waits for 'test' to succeed
    steps:
      - run: echo "Deploy done"
```

### Fan-out / Fan-in pattern

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo "Build artifacts"

  test-unit:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - run: echo "Unit tests"

  test-integration:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - run: echo "Integration tests"

  test-e2e:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - run: echo "E2E tests"

  deploy:
    runs-on: ubuntu-latest
    needs: [test-unit, test-integration, test-e2e] # wait for ALL three
    steps:
      - run: echo "All tests passed - deploying"
```

This pattern builds once, tests in parallel, then deploys only when all tests pass.

---

## 3. Using Actions with `uses`

Published actions from the GitHub Marketplace (or any repository) are invoked with `uses:`.

```yaml
steps:
  # Official GitHub action from github.com/actions/checkout
  - name: Checkout code
    uses: actions/checkout@v4

  # Action with parameters (with:)
  - name: Setup Node.js
    uses: actions/setup-node@v4
    with:
      node-version: "20"
      cache: "npm"

  # Action from a specific commit (most secure - pinned SHA)
  - name: Setup Go
    uses: actions/setup-go@v5
    with:
      go-version: "1.22"

  # Action from a private repo in the same org
  - name: Internal action
    uses: my-org/my-actions/.github/actions/my-action@main

  # Local action (defined in the same repo)
  - name: My local action
    uses: ./.github/actions/my-local-action
```

### Version pinning strategies

| Strategy          | Example                                                     | Security | Reproducibility |
| ----------------- | ----------------------------------------------------------- | -------- | --------------- |
| Major version tag | `actions/checkout@v4`                                       | Medium   | Medium          |
| Specific version  | `actions/checkout@v4.1.7`                                   | Good     | Good            |
| Full commit SHA   | `actions/checkout@a5ac7e51b41094c92402da3b24376905380afc29` | Best     | Best            |
| Branch            | `actions/checkout@main`                                     | Poor     | Poor            |

---

## 4. Running Shell Commands with `run`

```yaml
steps:
  # Single line
  - run: echo "Hello"

  # Multi-line (pipe character |)
  - name: Multi-line commands
    run: |
      echo "Line 1"
      echo "Line 2"
      ls -la

  # Specify the shell explicitly
  - name: Python script inline
    shell: python
    run: |
      print("Hello from Python")
      import os
      print(f"Runner OS: {os.environ.get('RUNNER_OS')}")

  # PowerShell (on windows runners)
  - name: PowerShell step
    shell: pwsh
    run: Write-Host "Hello from PowerShell"

  # Bash with options
  - name: Bash with errexit
    shell: bash
    run: |
      set -euo pipefail
      echo "This script exits on error"
      false    # this would cause the step to fail
```

### Default shell behavior

On Linux/macOS runners, `run:` uses `bash -e {0}` by default - it exits on the first error. On Windows, it uses PowerShell.

---

## 5. Step Outputs

Steps can produce outputs that subsequent steps (or jobs) can consume.

### Setting outputs within a job

```yaml
steps:
  - name: Generate version
    id: version # required to reference outputs
    run: |
      VERSION="1.$(date +%Y%m%d).$(git rev-parse --short HEAD)"
      echo "version=$VERSION" >> $GITHUB_OUTPUT
      echo "Generated: $VERSION"

  - name: Use the version
    run: |
      echo "Building version: ${{ steps.version.outputs.version }}"
```

### Passing outputs between jobs

```yaml
jobs:
  generate:
    runs-on: ubuntu-latest
    outputs: # declare which step outputs to expose
      app-version: ${{ steps.ver.outputs.version }}
      build-date: ${{ steps.date.outputs.date }}
    steps:
      - id: ver
        run: echo "version=2.1.0" >> $GITHUB_OUTPUT
      - id: date
        run: echo "date=$(date -u +%Y-%m-%d)" >> $GITHUB_OUTPUT

  build:
    runs-on: ubuntu-latest
    needs: generate
    steps:
      - name: Build with version
        run: |
          echo "Version:    ${{ needs.generate.outputs.app-version }}"
          echo "Build date: ${{ needs.generate.outputs.build-date }}"
```

---

## 6. Environment Variables in Steps

```yaml
jobs:
  demo:
    runs-on: ubuntu-latest
    env:
      JOB_VAR: "I am a job-level variable"   # available to all steps in this job

    steps:
      - name: Step with its own env
        env:
          STEP_VAR: "I am a step-level variable"
        run: |
          echo "Job var:  $JOB_VAR"
          echo "Step var: $STEP_VAR"

      - name: Setting env for subsequent steps
        run: echo "DYNAMIC_VAR=hello_from_step1" >> $GITHUB_ENV

      - name: Using the dynamic env var
        run: echo "Dynamic: $DYNAMIC_VAR"
```

---

## 7. Artifacts: Sharing Files Between Jobs

Artifacts allow jobs to share files built in one job and consumed in another.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Build
        run: |
          mkdir dist
          echo "app binary content" > dist/app
          echo "1.0.0" > dist/version.txt

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: build-artifacts
          path: dist/
          retention-days: 7

  deploy:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: build-artifacts
          path: dist/

      - name: List downloaded files
        run: ls -la dist/

      - name: Deploy
        run: cat dist/version.txt
```

---

## 8. Working Directory

```yaml
steps:
  - uses: actions/checkout@v4

  - name: Run from subdirectory
    working-directory: src/backend
    run: |
      echo "Current dir: $(pwd)"
      ls -la

  - name: Run from default workspace
    run: echo "Back in: $GITHUB_WORKSPACE"
```

---

## 9. Timeout and Continue on Error

```yaml
steps:
  - name: Long-running step
    timeout-minutes: 10 # fail if step takes more than 10 minutes
    run: sleep 300

  - name: Flaky step
    continue-on-error: true # step failure does not fail the job
    run: |
      echo "This might fail but that's OK"
      exit 1

  - name: This still runs
    run: echo "Previous step failed but continue-on-error allowed us to proceed"
```

---

## Complete Example: Build and Test Pipeline

```yaml
name: CI Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Lint source
        run: echo "Linting complete (no errors)"

  unit-tests:
    name: Unit Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run unit tests
        run: |
          echo "Running unit tests..."
          echo "All tests passed"

  integration-tests:
    name: Integration Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run integration tests
        run: echo "Integration tests passed"

  build:
    name: Build
    runs-on: ubuntu-latest
    needs: [lint, unit-tests]
    outputs:
      artifact-name: ${{ steps.build.outputs.artifact-name }}
    steps:
      - uses: actions/checkout@v4

      - name: Build application
        id: build
        run: |
          mkdir dist
          echo "app-v1.0.0" > dist/app
          echo "artifact-name=my-app-${{ github.sha }}" >> $GITHUB_OUTPUT

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: ${{ steps.build.outputs.artifact-name }}
          path: dist/

  deploy-staging:
    name: Deploy to Staging
    runs-on: ubuntu-latest
    needs: [build, integration-tests]
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact-name }}

      - name: Deploy to staging
        run: |
          echo "Deploying to staging..."
          ls -la
          echo "Staging deploy complete"
```

---

## Hands-on

1. Create a workflow with three jobs (`build` → `test` → `deploy`) where each depends on the previous:

   ??? success "Solution"
   `bash
    cat > .github/workflows/pipeline.yml << 'EOF'
    name: Three-Job Pipeline
    on: [push]
    jobs:
      build:
        runs-on: ubuntu-latest
        steps:
          - run: echo "Build complete"
      test:
        runs-on: ubuntu-latest
        needs: build
        steps:
          - run: echo "Tests passed"
      deploy:
        runs-on: ubuntu-latest
        needs: test
        steps:
          - run: echo "Deployed"
    EOF
    `

2. Add a step that sets an output, then consume that output in the next step within the same job:

   ??? success "Solution"
   `bash
    cat > .github/workflows/step-outputs.yml << 'EOF'
    name: Step Outputs
    on: [push]
    jobs:
      demo:
        runs-on: ubuntu-latest
        steps:
          - id: gen
            run: echo "color=blue" >> $GITHUB_OUTPUT
          - run: echo "The color is ${{ steps.gen.outputs.color }}"
    EOF
    `

3. Add `timeout-minutes: 5` to a job to prevent it from running indefinitely:

   ??? success "Solution"
   `bash
    cat > .github/workflows/timeout-demo.yml << 'EOF'
    name: Timeout Demo
    on: [push]
    jobs:
      bounded:
        runs-on: ubuntu-latest
        timeout-minutes: 5
        steps:
          - run: echo "This job will be killed if it runs longer than 5 minutes"
    EOF
    `

4. Add `continue-on-error: true` to a step that intentionally fails, and confirm the next step still runs:

   ??? success "Solution"
   `bash
    cat > .github/workflows/continue-on-error.yml << 'EOF'
    name: Continue on Error
    on: [push]
    jobs:
      demo:
        runs-on: ubuntu-latest
        steps:
          - name: Flaky step
            continue-on-error: true
            run: exit 1
          - name: Still runs
            run: echo "Previous step failed but we continued"
    EOF
    `

5. View the job-level status of the latest workflow run using `gh run view`:

   ??? success "Solution"
   `bash
    RUN_ID=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
    gh run view "$RUN_ID"
    `

## Exercises

### Exercise 1: Create a Fan-out Pipeline

Build a workflow with one build job and three parallel test jobs that all feed into a final deploy job.

### Exercise 2: Use Step Outputs

Create a workflow where one step generates a random number and a subsequent step uses it:

```bash
- id: rand
  run: echo "number=$RANDOM" >> $GITHUB_OUTPUT
- run: echo "Random number was ${{ steps.rand.outputs.number }}"
```

### Exercise 3: Share Artifacts Between Jobs

Create a workflow that builds a text file in one job and reads it in another job using `upload-artifact` and `download-artifact`.

### Exercise 4: Add Timeouts

Add `timeout-minutes: 5` to a job and `continue-on-error: true` to a step that intentionally exits with a non-zero code.

---

## Summary

- Jobs in a workflow run in parallel by default; use `needs: [job-id]` to enforce sequential execution or fan-in patterns
- Steps within a job always run sequentially on the same runner; the workspace and environment persist across all steps in a job
- Use `uses:` to invoke published or local actions; always pin to a specific version tag or commit SHA for reproducibility
- Step outputs are set via `echo "key=value" >> $GITHUB_OUTPUT` and referenced with `${{ steps.<id>.outputs.<key> }}`; job outputs expose step outputs to downstream jobs via the `outputs:` block
- Use `actions/upload-artifact` and `actions/download-artifact` to share files between jobs, since each job runs on a fresh runner with its own filesystem
- `continue-on-error: true` allows a step to fail without failing the entire job, useful for optional checks or known-flaky steps
- `timeout-minutes:` can be set on both jobs and steps to prevent runaway processes from consuming runner minutes indefinitely
