# Lab 007 - Expressions

## Introduction

- GitHub Actions **expressions** let you compute values, evaluate conditions, and transform data dynamically within your workflow files.
- They are evaluated at runtime by the GitHub Actions engine and can appear in almost any YAML value field.
- Expressions are enclosed in `${{ ...
- }}` and support a rich set of operators and built-in functions.
- This lab covers the full expression syntax, all built-in functions, and practical patterns you will use daily.

---

## 1. Expression Syntax

Expressions are written inside `${{ }}` delimiters:

```yaml
# In a 'run' command
- run: echo "SHA is ${{ github.sha }}"

# In an 'if' condition
- if: github.event_name == 'push'
  run: echo "This is a push event"

# In a 'with' parameter
- uses: actions/checkout@v4
  with:
    ref: ${{ github.head_ref }}

# In an env variable
env:
  SHORT_SHA: ${{ github.sha }}

# In a 'name' field
- name: Deploy to ${{ inputs.environment }}
```

Expressions are evaluated **before** the step runs, so the runner sees the resolved value.

---

## 2. Literals

Expressions support four literal types:

```yaml
# Boolean
- if: true
- if: false

# Number (integer or float)
- run: echo "${{ 42 }}"
- run: echo "${{ 3.14 }}"

# String (single quotes only inside expressions)
- run: echo "${{ 'hello world' }}"

# null
- if: ${{ github.head_ref != null }}
```

---

## 3. Operators

### Comparison operators

```yaml
# Equal
- if: github.ref == 'refs/heads/main'

# Not equal
- if: github.event_name != 'schedule'

# Less than / greater than
- if: github.run_number < 100

# Less/greater than or equal
- if: github.run_number >= 10
```

### Logical operators

```yaml
# AND
- if: github.event_name == 'push' && github.ref == 'refs/heads/main'

# OR
- if: github.event_name == 'push' || github.event_name == 'workflow_dispatch'

# NOT
- if: "!cancelled()"
- if: "! contains(github.ref, 'refs/tags/')"
```

### Grouping with parentheses

```yaml
- if: (github.event_name == 'push' || github.event_name == 'workflow_dispatch') && github.ref == 'refs/heads/main'
```

### Property access

```yaml
# Dot notation
${{ github.repository }}

# Index notation (for arrays and objects with special characters)
${{ github['repository'] }}
${{ steps['my-step'].outputs.value }}
```

---

## 4. Functions

### `contains(searchIn, searchString)`

Returns `true` if the first argument contains the second.

```yaml
# Check if a string contains a substring
- if: contains(github.ref, 'refs/tags/')
  run: echo "This is a tag push"

# Check if an array contains a value
- if: contains(github.event.labels.*.name, 'bug')
  run: echo "PR has the bug label"

# Check actor
- if: contains(fromJSON('["alice","bob"]'), github.actor)
  run: echo "Trusted actor"
```

### `startsWith(searchString, searchValue)`

```yaml
- if: startsWith(github.ref, 'refs/tags/v')
  run: echo "Version tag push"

- if: startsWith(github.head_ref, 'feature/')
  run: echo "Feature branch PR"
```

### `endsWith(searchString, searchValue)`

```yaml
- if: endsWith(github.repository, '-test')
  run: echo "Test repository"
```

### `format(string, ...args)`

String interpolation with `{0}`, `{1}`, etc.:

```yaml
- run: echo "${{ format('Deploying {0} to {1}', inputs.version, inputs.environment) }}"

- name: ${{ format('Build {0}', matrix.os) }}
  run: echo "Building on ${{ matrix.os }}"

# Escaping braces in format strings
- run: echo "${{ format('{{literal braces}} and {0}', 'value') }}"
# Output: {literal braces} and value
```

### `join(array, separator)`

```yaml
# Join array items with a separator
- run: echo "${{ join(matrix.os, ', ') }}"
# If matrix.os = [ubuntu-latest, windows-latest]: "ubuntu-latest, windows-latest"

- run: echo "${{ join(github.event.labels.*.name, ', ') }}"
# Joins label names with commas
```

### `toJSON(value)`

Converts any value to a JSON string:

```yaml
- env:
    GITHUB_CTX: ${{ toJSON(github) }}
  run: echo "$GITHUB_CTX" | python3 -m json.tool

- run: echo "${{ toJSON(matrix) }}"
```

### `fromJSON(value)`

Parses a JSON string into an object or array:

```yaml
# Create an array from JSON
- if: contains(fromJSON('["push","workflow_dispatch"]'), github.event_name)
  run: echo "Acceptable event"

# Use in matrix (dynamic matrix)
jobs:
  dynamic-matrix:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.set-matrix.outputs.matrix }}
    steps:
      - id: set-matrix
        run: |
          echo 'matrix={"os":["ubuntu-latest","windows-latest"]}' >> $GITHUB_OUTPUT

  build:
    needs: dynamic-matrix
    strategy:
      matrix: ${{ fromJSON(needs.dynamic-matrix.outputs.matrix) }}
    runs-on: ${{ matrix.os }}
    steps:
      - run: echo "Running on ${{ matrix.os }}"
```

### `hashFiles(pattern)`

Returns the SHA-256 hash of a set of files - perfect for cache keys:

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.npm
    key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}

- uses: actions/cache@v4
  with:
    path: ~/.cache/pip
    key: ${{ runner.os }}-pip-${{ hashFiles('requirements*.txt') }}

# Hash multiple files
    key: ${{ runner.os }}-deps-${{ hashFiles('package-lock.json', 'yarn.lock') }}
```

---

## 5. Status Check Functions

These functions check the status of the current workflow run. They are typically used in `if:` conditions on jobs and steps.

### `success()`

Returns `true` if all previous steps/jobs completed successfully. This is the **default** behavior when no `if:` is specified.

```yaml
steps:
  - run: echo "Step 1"
  - run: echo "Step 2 - only runs if Step 1 succeeded" # implicit success()
  - if: success()
    run: echo "Explicit success check"
```

### `failure()`

Returns `true` if any previous step in the job failed:

```yaml
steps:
  - run: exit 1 # this fails

  - if: failure()
    name: Cleanup on failure
    run: |
      echo "Something failed - running cleanup"
      # notify Slack, clean temp files, etc.
```

### `always()`

Always returns `true`, regardless of success or failure. Use for cleanup steps that must run unconditionally:

```yaml
steps:
  - run: ./run-tests.sh

  - name: Upload test results
    if: always() # upload even if tests failed
    uses: actions/upload-artifact@v4
    with:
      name: test-results
      path: test-output/
```

### `cancelled()`

Returns `true` if the workflow run was cancelled:

```yaml
steps:
  - if: cancelled()
    run: echo "Workflow was cancelled - notify team"
```

### Combining status functions

```yaml
steps:
  - name: Run tests
    id: tests
    run: ./test.sh

  - name: On failure only
    if: failure()
    run: echo "Tests failed"

  - name: On success or cancelled (but not failure)
    if: success() || cancelled()
    run: echo "Not a failure"

  - name: Always - even after cancel
    if: always()
    run: echo "This always runs"
```

---

## 6. Ternary-Like Patterns

GitHub Actions doesn't have a ternary operator but you can achieve the same result with `&&` and `||`:

```yaml
# Ternary pattern: condition && value_if_true || value_if_false
- run: echo "${{ github.event_name == 'push' && 'push event' || 'other event' }}"

# Practical: choose environment based on branch
env:
  ENVIRONMENT: ${{ github.ref == 'refs/heads/main' && 'production' || 'staging' }}

# Choose deploy target
- run: |
    TARGET="${{ startsWith(github.ref, 'refs/tags/') && 'prod' || 'dev' }}"
    echo "Deploying to: $TARGET"
```

---

## 7. Expressions in `if` Conditions

When using expressions in `if:`, you can omit the `${{ }}` wrapper:

```yaml
steps:
  # These are equivalent:
  - if: ${{ github.event_name == 'push' }}
    run: echo "Push event"

  - if: github.event_name == 'push'
    run: echo "Push event (no wrapper needed)"

  # Functions require the wrapper in some contexts:
  - if: ${{ contains(github.ref, 'main') }}
    run: echo "Main ref"
```

---

## 8. Complete Expression Examples

```yaml
name: Expressions Demo

on:
  push:
    branches: [main, develop, 'feature/**']
    tags: ['v*.*.*']
  pull_request:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, staging, prod]
        default: dev
      debug:
        type: boolean
        default: false

env:
  IS_MAIN: ${{ github.ref == 'refs/heads/main' }}
  IS_TAG: ${{ startsWith(github.ref, 'refs/tags/') }}
  SHORT_SHA: ${{ github.sha }}
  DEPLOY_ENV: ${{ inputs.environment || (github.ref == 'refs/heads/main' && 'production' || 'staging') }}

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Debug mode info
        if: inputs.debug == true
        run: |
          echo "=== DEBUG MODE ==="
          echo "Event:       ${{ github.event_name }}"
          echo "Ref:         ${{ github.ref }}"
          echo "Is main:     ${{ env.IS_MAIN }}"
          echo "Is tag:      ${{ env.IS_TAG }}"
          echo "Deploy env:  ${{ env.DEPLOY_ENV }}"

      - name: Format version string
        id: version
        run: |
          VERSION="${{ format('{0}@{1}', github.ref_name, github.sha) }}"
          echo "version=${VERSION}" >> $GITHUB_OUTPUT
          echo "Version: ${VERSION}"

      - name: Check required label on PR
        if: github.event_name == 'pull_request' && contains(github.event.labels.*.name, 'ready-for-review')
        run: echo "PR is labeled ready-for-review - proceeding with full CI"

      - name: Tag release step
        if: startsWith(github.ref, 'refs/tags/v')
        run: echo "This is a version tag: ${{ github.ref_name }}"

  deploy:
    runs-on: ubuntu-latest
    needs: build
    if: github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/')
    steps:
      - name: Deploy
        run: echo "Deploying to ${{ env.DEPLOY_ENV }}"

      - name: Post-deploy notification
        if: success()
        run: echo "Deployment succeeded"

      - name: Failure cleanup
        if: failure()
        run: echo "Deploy failed - sending alert"
```

---

## Hands-on

1. Write a step that uses `contains()` to run only when the branch name includes the word `feature`:

   ??? success "Solution"
   `bash
    cat > .github/workflows/contains-demo.yml << 'EOF'
    name: Contains Demo
    on: [push]
    jobs:
      check:
        runs-on: ubuntu-latest
        steps:
          - if: contains(github.ref, 'feature')
            run: echo "This is a feature branch"
          - if: "!contains(github.ref, 'feature')"
            run: echo "Not a feature branch"
    EOF
    `

2. Use `format()` to build a dynamic string that combines the repo name and run number:

   ??? success "Solution"
   `bash
    cat > .github/workflows/format-demo.yml << 'EOF'
    name: Format Demo
    on: [push]
    jobs:
      build:
        runs-on: ubuntu-latest
        steps:
          - run: echo "${{ format('Build {0} #{1}', github.repository, github.run_number) }}"
    EOF
    `

3. Use `toJSON()` to print the entire `runner` context as a JSON object:

   ??? success "Solution"
   `bash
    cat > .github/workflows/tojson-demo.yml << 'EOF'
    name: toJSON Demo
    on: [workflow_dispatch]
    jobs:
      dump:
        runs-on: ubuntu-latest
        steps:
          - env:
              RUNNER_CTX: ${{ toJSON(runner) }}
            run: echo "$RUNNER_CTX" | python3 -m json.tool
    EOF
    `

4. Write a ternary-like expression using `&&` and `||` to set `ENVIRONMENT` to `production` on `main` and `staging` elsewhere:

   ??? success "Solution"
   `bash
    cat > .github/workflows/ternary-demo.yml << 'EOF'
    name: Ternary Demo
    on: [push]
    jobs:
      deploy:
        runs-on: ubuntu-latest
        env:
          ENVIRONMENT: ${{ github.ref == 'refs/heads/main' && 'production' || 'staging' }}
        steps:
          - run: echo "Target environment is $ENVIRONMENT"
    EOF
    `

5. Use `hashFiles()` to generate a cache key based on `package-lock.json`:

   ??? success "Solution"
   `bash
    cat > .github/workflows/hashfiles-demo.yml << 'EOF'
    name: hashFiles Cache Key
    on: [push]
    jobs:
      cache:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: actions/cache@v4
            with:
              path: ~/.npm
              key: ${{ runner.os }}-npm-${{ hashFiles('**/package-lock.json') }}
          - run: echo "Cache key computed from package-lock.json hash"
    EOF
    `

## Exercises

### Exercise 1: Use `contains()` for Branch Check

Create a step that only runs if the ref contains `feature`:

```yaml
- if: contains(github.ref, 'feature')
  run: echo "Feature branch"
```

### Exercise 2: Use `format()` for Dynamic Names

```yaml
- name: ${{ format('Deploy to {0}', inputs.environment) }}
  run: echo "Deploying..."
```

### Exercise 3: Dynamic Cache Keys with `hashFiles()`

```yaml
- uses: actions/cache@v4
  with:
    path: node_modules
    key: ${{ runner.os }}-npm-${{ hashFiles('package-lock.json') }}
```

### Exercise 4: Status Function Chain

Create a workflow where:

- Step 1 always runs
- Step 2 runs only if Step 1 succeeded
- Step 3 runs only if Step 1 failed
- Step 4 always runs (cleanup)

---

## Summary

- Expressions use `${{ ... }}` syntax and can appear in most YAML value fields; in `if:` conditions the wrapper is optional for simple comparisons
- Comparison operators (`==`, `!=`, `<`, `>`) and logical operators (`&&`, `||`, `!`) work intuitively, with parentheses for grouping complex conditions
- `contains()`, `startsWith()`, and `endsWith()` perform string and array membership checks - essential for branch/tag/event filtering
- `format('template {0} {1}', val1, val2)` provides string interpolation with positional placeholders for building dynamic step names and messages
- `toJSON()` and `fromJSON()` convert between expression values and JSON strings, enabling dynamic matrix generation and structured context inspection
- `hashFiles('**/package-lock.json')` returns a deterministic hash of file contents, making it the ideal cache key component for dependency caching
- Status functions `success()`, `failure()`, `always()`, and `cancelled()` enable conditional cleanup steps and notifications based on the outcome of previous steps
