# Lab 005 - Environment Variables

## Introduction

- Environment variables in GitHub Actions carry configuration, metadata, and runtime values throughout your workflow.
- They can be set at three scopes - workflow, job, and step - and are accessed as standard Unix environment variables (`$VAR`) or through the `env` context (`${{ env.VAR }}`).
- GitHub also provides a set of **default environment variables** (like `GITHUB_SHA` and `GITHUB_REF`) that are automatically injected into every step.
- Understanding all these mechanisms is essential for writing flexible, maintainable workflows.

---

## 1. Variable Scope Levels

### Workflow-level `env`

Defined at the top of the workflow file, available to all jobs and all steps:

```yaml
name: Env Demo

on: [push]

env:
  APP_NAME: my-application
  BUILD_VERSION: "1.0.0"
  LOG_LEVEL: info

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Use workflow env
        run: |
          echo "App: $APP_NAME"
          echo "Version: $BUILD_VERSION"
          echo "Log level: $LOG_LEVEL"
```

### Job-level `env`

Defined inside a job, available to all steps in that job only:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      BUILD_TARGET: production
      OPTIMIZATION_LEVEL: "3"
    steps:
      - run: echo "Building with target=$BUILD_TARGET, opt=$OPTIMIZATION_LEVEL"

  test:
    runs-on: ubuntu-latest
    env:
      TEST_TIMEOUT: "30"
      TEST_PARALLEL: "4"
    steps:
      - run: echo "Testing with timeout=$TEST_TIMEOUT, parallel=$TEST_PARALLEL"
      # BUILD_TARGET is NOT available here - it's scoped to the build job
```

### Step-level `env`

Defined on a single step, available only within that step:

```yaml
steps:
  - name: Step with local env
    env:
      DATABASE_URL: postgres://localhost/mydb
      API_ENDPOINT: https://api.example.com/v1
    run: |
      echo "DB: $DATABASE_URL"
      echo "API: $API_ENDPOINT"

  - name: Next step - vars are gone
    run: |
      echo "DATABASE_URL: '${DATABASE_URL:-<not set>}'"  # empty
```

### Scope priority (highest to lowest)

When the same variable name is defined at multiple levels, the most specific scope wins:

```yaml
env:
  MY_VAR: "workflow-level" # lowest priority

jobs:
  demo:
    env:
      MY_VAR: "job-level" # overrides workflow-level
    steps:
      - env:
          MY_VAR: "step-level" # highest priority - wins
        run: echo "MY_VAR = $MY_VAR" # prints "step-level"
```

---

## 2. The `env` Context

You can also reference environment variables using the expression syntax `${{ env.VAR_NAME }}`. This is useful when you need to use an env var value in a YAML field that doesn't support shell expansion:

```yaml
env:
  DEPLOY_BUCKET: my-s3-bucket
  DEPLOY_REGION: us-east-1

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      # Using ${{ env.VAR }} in a 'with:' block (shell expansion doesn't work here)
      - name: Deploy to S3
        uses: some-action/s3-deploy@v1
        with:
          bucket: ${{ env.DEPLOY_BUCKET }}
          region: ${{ env.DEPLOY_REGION }}

      # Using ${{ env.VAR }} in an if condition
      - name: Conditional on env var
        if: env.LOG_LEVEL == 'debug'
        run: echo "Debug logging enabled"
```

---

## 3. GITHUB_ENV - Dynamic Environment Variables

The `GITHUB_ENV` file lets you set environment variables dynamically within a step that persist to all subsequent steps in the same job.

### Basic usage

```yaml
steps:
  - name: Set dynamic variables
    run: |
      echo "BUILD_ID=$(date +%s)" >> $GITHUB_ENV
      echo "GIT_SHORT_SHA=$(echo $GITHUB_SHA | cut -c1-7)" >> $GITHUB_ENV
      echo "BUILD_DATE=$(date -u '+%Y-%m-%d')" >> $GITHUB_ENV

  - name: Use dynamic variables
    run: |
      echo "Build ID:   $BUILD_ID"
      echo "Short SHA:  $GIT_SHORT_SHA"
      echo "Build date: $BUILD_DATE"
```

### Multi-line values

```yaml
steps:
  - name: Set multi-line variable
    run: |
      {
        echo "RELEASE_NOTES<<EOF"
        echo "## Changes"
        echo "- Feature A added"
        echo "- Bug B fixed"
        echo "EOF"
      } >> $GITHUB_ENV

  - name: Use multi-line variable
    run: echo "$RELEASE_NOTES"
```

### Setting env from command output

```yaml
steps:
  - name: Get versions
    run: |
      NODE_VER=$(node --version)
      NPM_VER=$(npm --version)
      echo "NODE_VERSION=${NODE_VER}" >> $GITHUB_ENV
      echo "NPM_VERSION=${NPM_VER}"   >> $GITHUB_ENV

  - name: Log versions
    run: |
      echo "Node: $NODE_VERSION"
      echo "npm:  $NPM_VERSION"
```

---

## 4. Default Environment Variables

GitHub automatically injects these into every step on every runner:

### Repository and workflow metadata

| Variable                  | Example Value                                         | Description                             |
| ------------------------- | ----------------------------------------------------- | --------------------------------------- |
| `GITHUB_REPOSITORY`       | `owner/repo-name`                                     | Repository full name                    |
| `GITHUB_REPOSITORY_OWNER` | `owner`                                               | Owner of the repository                 |
| `GITHUB_WORKSPACE`        | `/home/runner/work/repo/repo`                         | Checkout directory                      |
| `GITHUB_WORKFLOW`         | `CI Pipeline`                                         | Workflow name                           |
| `GITHUB_WORKFLOW_REF`     | `owner/repo/.github/workflows/ci.yml@refs/heads/main` | Full workflow ref                       |
| `GITHUB_RUN_ID`           | `1234567890`                                          | Unique run ID                           |
| `GITHUB_RUN_NUMBER`       | `42`                                                  | Sequential run number for this workflow |
| `GITHUB_RUN_ATTEMPT`      | `1`                                                   | Attempt number (increments on re-run)   |
| `GITHUB_ACTION`           | `run1` or action name                                 | Current action/step identifier          |

### Git and event metadata

| Variable                  | Example Value                              | Description                                         |
| ------------------------- | ------------------------------------------ | --------------------------------------------------- |
| `GITHUB_SHA`              | `ffac537e6cbbf934b08745a378932722df287a53` | Commit SHA that triggered the run                   |
| `GITHUB_REF`              | `refs/heads/main`                          | Branch or tag ref that triggered the run            |
| `GITHUB_REF_NAME`         | `main`                                     | Short name of the ref                               |
| `GITHUB_REF_TYPE`         | `branch` or `tag`                          | Type of ref                                         |
| `GITHUB_HEAD_REF`         | `feature/my-feature`                       | PR source branch (PRs only)                         |
| `GITHUB_BASE_REF`         | `main`                                     | PR target branch (PRs only)                         |
| `GITHUB_EVENT_NAME`       | `push`                                     | Event that triggered the workflow                   |
| `GITHUB_EVENT_PATH`       | `/github/workflow/event.json`              | Path to event payload JSON                          |
| `GITHUB_ACTOR`            | `octocat`                                  | User who triggered the workflow                     |
| `GITHUB_ACTOR_ID`         | `583231`                                   | Numeric user ID                                     |
| `GITHUB_TRIGGERING_ACTOR` | `octocat`                                  | User who actually triggered (may differ from actor) |

### Runner metadata

| Variable            | Example Value             | Description                        |
| ------------------- | ------------------------- | ---------------------------------- |
| `RUNNER_OS`         | `Linux`                   | Runner operating system            |
| `RUNNER_ARCH`       | `X64`                     | Runner CPU architecture            |
| `RUNNER_NAME`       | `Hosted Agent`            | Runner name                        |
| `RUNNER_TEMP`       | `/home/runner/work/_temp` | Temp directory (cleaned after job) |
| `RUNNER_TOOL_CACHE` | `/opt/hostedtoolcache`    | Tool cache directory               |

### Environment and token

| Variable             | Example Value                                                  | Description                        |
| -------------------- | -------------------------------------------------------------- | ---------------------------------- |
| `GITHUB_ENV`         | `/home/runner/work/_temp/_runner_file_commands/set_env_...`    | Path to env file                   |
| `GITHUB_OUTPUT`      | `/home/runner/work/_temp/_runner_file_commands/set_output_...` | Path to output file                |
| `GITHUB_PATH`        | `/home/runner/work/_temp/_runner_file_commands/add_path_...`   | Path to PATH file                  |
| `GITHUB_TOKEN`       | `ghs_...`                                                      | Auto-generated token (see Lab 006) |
| `GITHUB_SERVER_URL`  | `https://github.com`                                           | GitHub server URL                  |
| `GITHUB_API_URL`     | `https://api.github.com`                                       | GitHub API URL                     |
| `GITHUB_GRAPHQL_URL` | `https://api.github.com/graphql`                               | GitHub GraphQL URL                 |

---

## 5. Accessing Default Variables

```yaml
steps:
  - name: Show all default variables
    run: |
      echo "=== Repository ==="
      echo "Repo:      $GITHUB_REPOSITORY"
      echo "Owner:     $GITHUB_REPOSITORY_OWNER"
      echo "Workspace: $GITHUB_WORKSPACE"

      echo "=== Git/Event ==="
      echo "SHA:       $GITHUB_SHA"
      echo "Ref:       $GITHUB_REF"
      echo "Ref name:  $GITHUB_REF_NAME"
      echo "Ref type:  $GITHUB_REF_TYPE"
      echo "Event:     $GITHUB_EVENT_NAME"
      echo "Actor:     $GITHUB_ACTOR"

      echo "=== Workflow ==="
      echo "Workflow:  $GITHUB_WORKFLOW"
      echo "Run ID:    $GITHUB_RUN_ID"
      echo "Run #:     $GITHUB_RUN_NUMBER"
      echo "Attempt:   $GITHUB_RUN_ATTEMPT"

      echo "=== Runner ==="
      echo "OS:        $RUNNER_OS"
      echo "Arch:      $RUNNER_ARCH"
```

---

## 6. GITHUB_PATH - Adding to PATH

Append directories to `$PATH` for subsequent steps:

```yaml
steps:
  - name: Install custom tool to local bin
    run: |
      mkdir -p "$HOME/bin"
      echo '#!/bin/bash\necho "my-tool v1.0"' > "$HOME/bin/my-tool"
      chmod +x "$HOME/bin/my-tool"

  - name: Add to PATH
    run: echo "$HOME/bin" >> $GITHUB_PATH

  - name: Use the tool
    run: my-tool # now found because $HOME/bin is in PATH
```

---

## 7. env vs inputs vs vars vs secrets

| Source            | Access syntax              | Scope              | Purpose                               |
| ----------------- | -------------------------- | ------------------ | ------------------------------------- |
| `env:`            | `$VAR` or `${{ env.VAR }}` | workflow/job/step  | Configuration values in the YAML      |
| `GITHUB_ENV`      | `$VAR`                     | subsequent steps   | Dynamically set during job            |
| `inputs:`         | `${{ inputs.NAME }}`       | workflow run       | Manual dispatch parameters            |
| `vars` context    | `${{ vars.NAME }}`         | repository/org/env | Non-sensitive config stored in GitHub |
| `secrets` context | `${{ secrets.NAME }}`      | repository/org/env | Sensitive values (masked in logs)     |

---

## Complete Example

```yaml
name: Environment Variables Demo

on:
  push:
  workflow_dispatch:

env:
  APP_NAME: my-app # workflow scope
  VERSION: "2.0.0"

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      BUILD_MODE: production # job scope

    steps:
      - uses: actions/checkout@v4

      - name: Set dynamic variables
        run: |
          echo "BUILD_TIMESTAMP=$(date -u '+%Y%m%dT%H%M%SZ')" >> $GITHUB_ENV
          echo "SHORT_SHA=$(echo $GITHUB_SHA | cut -c1-7)"     >> $GITHUB_ENV

      - name: Build
        env:
          EXTRA_FLAGS: "--verbose" # step scope
        run: |
          echo "Building $APP_NAME v$VERSION"
          echo "Mode:      $BUILD_MODE"
          echo "Timestamp: $BUILD_TIMESTAMP"
          echo "SHA:       $SHORT_SHA"
          echo "Flags:     $EXTRA_FLAGS"
          echo "Triggered by: $GITHUB_ACTOR"
          echo "Event: $GITHUB_EVENT_NAME"
```

---

## Hands-on

1. Create a workflow that defines the same variable (`APP_ENV`) at the workflow level, job level, and step level, and prints which value wins:

   ??? success "Solution"
   `bash
    cat > .github/workflows/env-scopes.yml << 'EOF'
    name: Env Scope Demo
    on: [push]
    env:
      APP_ENV: workflow-level
    jobs:
      demo:
        runs-on: ubuntu-latest
        env:
          APP_ENV: job-level
        steps:
          - env:
              APP_ENV: step-level
            run: echo "APP_ENV=$APP_ENV"
    EOF
    `

2. Use `GITHUB_ENV` to pass a dynamically computed value from one step to the next:

   ??? success "Solution"
   `bash
    cat > .github/workflows/dynamic-env.yml << 'EOF'
    name: Dynamic Env
    on: [push]
    jobs:
      demo:
        runs-on: ubuntu-latest
        steps:
          - run: echo "BUILD_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> $GITHUB_ENV
          - run: echo "Build happened at $BUILD_TIME"
    EOF
    `

3. Create a workflow that sets a job-level env variable and uses the `env` context inside a `with:` block:

   ??? success "Solution"
   `bash
    cat > .github/workflows/env-context.yml << 'EOF'
    name: Env Context
    on: [push]
    env:
      ARTIFACT_NAME: my-build-artifact
    jobs:
      demo:
        runs-on: ubuntu-latest
        steps:
          - run: mkdir -p dist && echo "binary" > dist/app
          - uses: actions/upload-artifact@v4
            with:
              name: ${{ env.ARTIFACT_NAME }}
              path: dist/
    EOF
    `

4. Print all `GITHUB_*` default environment variables available in a step:

   ??? success "Solution"
   `bash
    cat > .github/workflows/list-defaults.yml << 'EOF'
    name: List Default Env Vars
    on: [workflow_dispatch]
    jobs:
      list:
        runs-on: ubuntu-latest
        steps:
          - run: env | grep '^GITHUB_' | sort
    EOF
    act workflow_dispatch --workflows .github/workflows/list-defaults.yml
    `

5. Use `GITHUB_ENV` to build a version string from `GITHUB_RUN_NUMBER` and the short commit SHA, then use it in a subsequent step:

   ??? success "Solution"
   `bash
    cat > .github/workflows/version-string.yml << 'EOF'
    name: Version String
    on: [push]
    jobs:
      version:
        runs-on: ubuntu-latest
        steps:
          - run: |
              SHORT_SHA=$(echo "$GITHUB_SHA" | cut -c1-7)
              echo "VERSION=1.0.${GITHUB_RUN_NUMBER}-${SHORT_SHA}" >> $GITHUB_ENV
          - run: echo "Artifact version: $VERSION"
    EOF
    `

## Exercises

### Exercise 1: Three-Level Env Scope

Create a workflow that defines the same variable at all three levels and demonstrates which value wins.

### Exercise 2: Dynamic Version String

Use `GITHUB_ENV` to build a version string from `GITHUB_RUN_NUMBER` and `GITHUB_SHA`, then use it in a subsequent step.

### Exercise 3: Print All Default Variables

Create a workflow that echoes every default `GITHUB_*` and `RUNNER_*` variable.

### Exercise 4: Add to PATH

Add a custom script to `$HOME/bin`, append it to `GITHUB_PATH`, and invoke it in the next step.

---

## Summary

- Environment variables can be defined at three scopes: workflow-level (available everywhere), job-level (available to all steps in that job), and step-level (available only in that step)
- When the same variable name is defined at multiple scopes, the most specific scope wins - step overrides job, job overrides workflow
- The `env` context (`${{ env.VAR }}`) allows using env variables in YAML fields like `with:` and `if:` where shell expansion (`$VAR`) does not work
- Writing `KEY=VALUE` to the `$GITHUB_ENV` file within a step makes that variable available to all subsequent steps in the same job
- GitHub automatically injects default variables like `GITHUB_SHA`, `GITHUB_REF`, `GITHUB_ACTOR`, `GITHUB_RUN_NUMBER`, and `RUNNER_OS` into every step
- Writing a directory path to `$GITHUB_PATH` appends it to `$PATH` for all subsequent steps in the job, enabling custom tool discovery
- For sensitive configuration use `secrets`, for non-sensitive repo/org configuration use `vars`, and for values derived at runtime use `GITHUB_ENV`
