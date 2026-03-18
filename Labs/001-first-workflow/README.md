# Lab 001 - First Workflow

## Introduction

- A GitHub Actions **workflow** is an automated process defined in a YAML file.
- It lives in the `.github/workflows/` directory of your repository and runs automatically when triggered by an event - a push, a pull request, a schedule, or manually.
- This lab introduces the fundamental building blocks of every workflow: `name`, `on`, `jobs`, and `steps`.
- By the end you will have a working Hello World workflow, know how to view its results with `gh`, and understand the key concepts needed for all subsequent labs.

---

## 1. Workflow File Location

GitHub Actions discovers workflows by looking for YAML files in a specific directory:

```
your-repo/
└── .github/
    └── workflows/
        ├── hello-world.yml     ← this lab
        ├── ci.yml
        └── deploy.yml
```

Key rules:

- The directory must be exactly `.github/workflows/` (case-sensitive on Linux runners)
- Files must have a `.yml` or `.yaml` extension
- A repository can have many workflow files - each runs independently

---

## 2. Core YAML Structure

Every workflow has four top-level keys:

```yaml
name: My Workflow # Human-readable name shown in the GitHub UI

on: # Event(s) that trigger this workflow
  push:
    branches: [main]

jobs: # One or more jobs to run
  my-job: # Job ID (used in needs:, outputs:, etc.)
    runs-on: ubuntu-latest # Which runner to use
    steps: # Ordered list of tasks within the job
      - name: Say hello
        run: echo "Hello, World!"
```

### The `name` key

```yaml
name: CI Pipeline
```

- Optional but strongly recommended
- Shown in the GitHub Actions tab and email notifications
- If omitted, GitHub uses the file path as the name

### The `on` key (triggers)

```yaml
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
```

The `on` key defines what events cause the workflow to run. You will explore all trigger types in Lab 002.

### The `jobs` key

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo "building..."
  test:
    runs-on: ubuntu-latest
    needs: build # runs after build job
    steps:
      - run: echo "testing..."
```

Jobs run in parallel by default unless you use `needs:` to express dependencies.

### The `steps` key

```yaml
steps:
  - name: Checkout code
    uses: actions/checkout@v4 # Use a published action

  - name: Print message
    run: echo "Hello from step 2" # Run a shell command

  - name: Multi-line command
    run: |
      echo "Line 1"
      echo "Line 2"
      ls -la
```

Each step either uses a published action (`uses:`) or runs a shell command (`run:`).

---

## 3. Hello World Workflow

Create `.github/workflows/hello-world.yml`:

```yaml
name: Hello World

on:
  push:
    branches: [main]
  workflow_dispatch: # Allow manual triggering

jobs:
  greet:
    name: Greeting Job
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Print hello message
        run: echo "Hello, World! 🌍"

      - name: Show runner info
        run: |
          echo "Runner OS: $RUNNER_OS"
          echo "Runner arch: $RUNNER_ARCH"
          echo "Workspace: $GITHUB_WORKSPACE"

      - name: Show git info
        run: |
          echo "Repository: $GITHUB_REPOSITORY"
          echo "Branch/Ref: $GITHUB_REF"
          echo "Commit SHA: $GITHUB_SHA"
          echo "Actor: $GITHUB_ACTOR"
```

Push this file to trigger the workflow:

```bash
git add .github/workflows/hello-world.yml
git commit -m "Add hello world workflow"
git push origin main
```

---

## 4. Viewing Workflow Runs with `gh`

Once the workflow triggers, use the `gh` CLI to inspect it:

```bash
# List recent workflow runs
gh run list

# List runs for a specific workflow
gh run list --workflow hello-world.yml

# Watch a run in real time (get RUN_ID from gh run list)
gh run watch <RUN_ID>

# View the logs of a completed run
gh run view <RUN_ID> --log

# View logs for a specific job
gh run view <RUN_ID> --job <JOB_ID> --log
```

### Example output of `gh run list`

```
STATUS  TITLE                    WORKFLOW      BRANCH  EVENT  ID          ELAPSED  AGE
✓       Add hello world workflow  Hello World  main    push   1234567890  12s      1m
```

### Triggering a manual run

Since the workflow has `workflow_dispatch:`, you can trigger it manually:

```bash
gh workflow run hello-world.yml

# Trigger on a specific branch
gh workflow run hello-world.yml --ref develop
```

---

## 5. Understanding Workflow Run Status

| Status                | Icon | Meaning                   |
| --------------------- | ---- | ------------------------- |
| `completed` / success | ✓    | All jobs passed           |
| `completed` / failure | ✗    | One or more jobs failed   |
| `in_progress`         | ●    | Currently running         |
| `queued`              | ○    | Waiting for a runner      |
| `cancelled`           | ⊘    | Manually cancelled        |
| `skipped`             | -    | Skipped due to conditions |

```bash
# Get the conclusion of the latest run
gh run list --workflow hello-world.yml --limit 1 --json conclusion --jq '.[0].conclusion'
```

---

## 6. A More Complete Example

Here is a workflow that demonstrates more features:

```yaml
name: Complete Hello World

on:
  push:
  pull_request:
  workflow_dispatch:

jobs:
  setup:
    name: Setup and Info
    runs-on: ubuntu-latest
    outputs:
      current-time: ${{ steps.time.outputs.time }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Get current time
        id: time
        run: echo "time=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> $GITHUB_OUTPUT

      - name: Display environment
        run: |
          echo "=== Runner Information ==="
          echo "OS: $RUNNER_OS"
          echo "Arch: $RUNNER_ARCH"
          echo "Temp: $RUNNER_TEMP"
          echo ""
          echo "=== GitHub Context ==="
          echo "Repo: $GITHUB_REPOSITORY"
          echo "Ref: $GITHUB_REF"
          echo "SHA: $GITHUB_SHA"
          echo "Actor: $GITHUB_ACTOR"
          echo "Event: $GITHUB_EVENT_NAME"
          echo "Workflow: $GITHUB_WORKFLOW"
          echo "Run ID: $GITHUB_RUN_ID"
          echo "Run Number: $GITHUB_RUN_NUMBER"

  greet:
    name: Greeting
    runs-on: ubuntu-latest
    needs: setup

    steps:
      - name: Hello from greet job
        run: |
          echo "Hello from the greet job!"
          echo "Setup ran at: ${{ needs.setup.outputs.current-time }}"

      - name: Farewell
        run: echo "Goodbye! Workflow complete."
```

---

## 7. Workflow Syntax Reference

### Using environment variables in steps

```yaml
steps:
  - name: Use env var
    env:
      MY_NAME: "GitHub Actions"
    run: echo "Hello, $MY_NAME"
```

### Giving steps an ID for later reference

```yaml
steps:
  - name: Generate value
    id: gen
    run: echo "result=42" >> $GITHUB_OUTPUT

  - name: Use the value
    run: echo "Result was ${{ steps.gen.outputs.result }}"
```

### Using `if` to conditionally run steps

```yaml
steps:
  - name: Only on main
    if: github.ref == 'refs/heads/main'
    run: echo "This is the main branch"
```

---

## Hands-on

1. Create a minimal hello-world workflow file using the CLI:

   ??? success "Solution"
   `bash
    mkdir -p .github/workflows
    cat > .github/workflows/hello-world.yml << 'EOF'
    name: Hello World
    on:
      push:
      workflow_dispatch:
    jobs:
      greet:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - run: echo "Hello, World!"
    EOF
    `

2. Validate the workflow YAML syntax with `python3` before pushing:

   ??? success "Solution"
   `bash
    python3 -c "
    import yaml, sys
    with open('.github/workflows/hello-world.yml') as f:
        yaml.safe_load(f)
    print('YAML is valid')
    "
    `

3. Run the workflow locally with `act` and observe the output:

   ??? success "Solution"
   `bash
    act push --workflows .github/workflows/hello-world.yml
    `

4. After pushing, view the most recent workflow run history with `gh`:

   ??? success "Solution"
   `bash
    git add .github/workflows/hello-world.yml
    git commit -m "Add hello world workflow"
    git push
    gh run list --workflow hello-world.yml --limit 5
    `

5. Check the syntax of a workflow file using `actionlint`:

   ??? success "Solution"
   `bash
    # Install actionlint if not present
    bash <(curl https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash) 2>/dev/null
    ./actionlint .github/workflows/hello-world.yml
    `

## Exercises

### Exercise 1: Create and Push the Hello World Workflow

```bash
mkdir -p .github/workflows
cat > .github/workflows/hello.yml << 'EOF'
name: Hello World
on:
  push:
  workflow_dispatch:
jobs:
  hello:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Hello, World!"
EOF
git add .github/workflows/hello.yml
git commit -m "Add hello world workflow"
git push
```

### Exercise 2: View the Run

```bash
gh run list --limit 3
gh run view --log
```

### Exercise 3: Add a Second Job

Modify the workflow to add a second job that runs after the first:

```yaml
jobs:
  hello:
    runs-on: ubuntu-latest
    steps:
      - run: echo "Job 1"
  goodbye:
    runs-on: ubuntu-latest
    needs: hello
    steps:
      - run: echo "Job 2 - runs after Job 1"
```

### Exercise 4: Trigger Manually

```bash
gh workflow run hello.yml
gh run list --workflow hello.yml
```

### Exercise 5: Validate YAML Locally

```bash
python3 -c "
import yaml, sys
with open('.github/workflows/hello.yml') as f:
    yaml.safe_load(f)
print('YAML is valid')
"
```

---

## Summary

- Workflow files must be placed in `.github/workflows/` with a `.yml` or `.yaml` extension for GitHub to discover and execute them
- Every workflow requires at minimum: `on` (trigger) and `jobs` (one job with at least one step); the `name` key is optional but recommended
- Jobs run in parallel by default; use `needs: [job-id]` to create sequential dependencies between jobs
- Steps within a job run sequentially and can either execute shell commands via `run:` or invoke published actions via `uses:`
- Use `gh run list`, `gh run view`, and `gh run watch` to monitor workflow execution status and logs from the terminal
- The `workflow_dispatch` trigger allows manual execution via `gh workflow run <name>` or the GitHub Actions UI
- Default environment variables like `GITHUB_SHA`, `GITHUB_REF`, `GITHUB_ACTOR`, and `GITHUB_REPOSITORY` are automatically available in every step
