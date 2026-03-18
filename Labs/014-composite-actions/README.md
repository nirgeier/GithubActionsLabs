# Lab 014 - Composite Actions

## Introduction

- Composite actions let you bundle multiple workflow steps into a single reusable unit that can be referenced like any other action.
- Unlike reusable workflows (which operate at the job level), composite actions operate at the **step** level - you can use them anywhere you would use a step.
- This lab covers how to author `action.yml` files for composite actions, define inputs and outputs, and call them from workflows.

---

## What Is a Composite Action?

A composite action is defined by an `action.yml` (or `action.yaml`) file that specifies:

- A set of **inputs** the action accepts
- A set of **outputs** the action produces
- A series of **steps** to execute

The `runs.using` value is set to `"composite"`.

```yaml
# action.yml
name: My Composite Action
description: Does something useful
runs:
  using: composite
  steps:
    - name: Do something
      shell: bash
      run: echo "Hello from composite action"
```

---

## `action.yml` Structure

```yaml
name: Setup and Build
description: Sets up Node.js, installs dependencies, and builds the project

inputs:
  node-version:
    description: "Node.js version to use"
    required: false
    default: "20"
  working-directory:
    description: "Directory to run commands in"
    required: false
    default: "."
  build-command:
    description: "The build command to run"
    required: false
    default: "npm run build"

outputs:
  artifact-path:
    description: "Path to the generated build artifact"
    value: ${{ steps.build.outputs.artifact-path }}

runs:
  using: composite
  steps:
    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: ${{ inputs.node-version }}
        cache: "npm"
        cache-dependency-path: ${{ inputs.working-directory }}/package-lock.json

    - name: Install dependencies
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      run: npm ci

    - name: Build
      id: build
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      run: |
        ${{ inputs.build-command }}
        echo "artifact-path=${{ inputs.working-directory }}/dist" >> "$GITHUB_OUTPUT"
```

---

## Inputs and Outputs

### Inputs

```yaml
inputs:
  environment:
    description: "Target environment"
    required: true

  timeout:
    description: "Timeout in seconds"
    required: false
    default: "60"

  debug:
    description: "Enable debug logging"
    required: false
    default: "false"
```

Access inputs in steps with `${{ inputs.<name> }}`.

### Outputs

Outputs must be mapped from step outputs using `${{ steps.<step-id>.outputs.<name> }}`:

```yaml
outputs:
  version:
    description: "The computed version"
    value: ${{ steps.get-version.outputs.version }}
```

```yaml
runs:
  using: composite
  steps:
    - id: get-version
      shell: bash
      run: echo "version=$(cat VERSION)" >> "$GITHUB_OUTPUT"
```

---

## Important: `shell:` Is Required

Every `run:` step inside a composite action **must** specify `shell:`. This is unlike workflow steps where `bash` is the default.

```yaml
runs:
  using: composite
  steps:
    - name: Run on bash
      shell: bash
      run: echo "Hello from bash"

    - name: Run on PowerShell (Windows)
      shell: pwsh
      run: Write-Host "Hello from PowerShell"

    - name: Run Python
      shell: python
      run: print("Hello from Python")
```

---

## Using Other Actions Inside Composite Actions

Composite steps can call other actions using `uses:`:

```yaml
runs:
  using: composite
  steps:
    - name: Checkout
      uses: actions/checkout@v4

    - name: Setup Node
      uses: actions/setup-node@v4
      with:
        node-version: ${{ inputs.node-version }}

    - name: Custom step
      shell: bash
      run: npm run build
```

---

## Referencing the Action from a Workflow

### Same Repository

Place `action.yml` in a directory within your repository:

```
.github/
  actions/
    setup-and-build/
      action.yml
```

Then reference it with a relative path:

```yaml
steps:
  - uses: ./.github/actions/setup-and-build
    with:
      node-version: "20"
      working-directory: frontend/
```

### From a Public Repository

If the action lives at the root of a public repository, reference it as:

```yaml
steps:
  - uses: my-org/my-action-repo@v1
    with:
      some-input: value
```

If the action is in a subdirectory:

```yaml
steps:
  - uses: my-org/my-action-repo/path/to/action@v1
```

---

## Complete Example: Composite Action for Node.js CI Setup

### Directory Structure

```
.github/
  actions/
    node-ci-setup/
      action.yml
  workflows/
    ci.yml
```

### `action.yml`

```yaml
name: Node.js CI Setup
description: >
  Checks out code, sets up Node.js with caching,
  installs dependencies, and optionally runs lint.

inputs:
  node-version:
    description: "Node.js version"
    required: false
    default: "20"
  install-command:
    description: "Command to install dependencies"
    required: false
    default: "npm ci"
  run-lint:
    description: "Run lint after install"
    required: false
    default: "false"
  working-directory:
    description: "Working directory"
    required: false
    default: "."

outputs:
  node-version-used:
    description: "Actual Node.js version installed"
    value: ${{ steps.setup-node.outputs.node-version }}
  cache-hit:
    description: "Whether the npm cache was hit"
    value: ${{ steps.setup-node.outputs.cache-hit }}

runs:
  using: composite
  steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Setup Node.js with cache
      id: setup-node
      uses: actions/setup-node@v4
      with:
        node-version: ${{ inputs.node-version }}
        cache: "npm"
        cache-dependency-path: ${{ inputs.working-directory }}/package-lock.json

    - name: Install dependencies
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      run: ${{ inputs.install-command }}

    - name: Run lint
      if: inputs.run-lint == 'true'
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      run: npm run lint
```

### Workflow using the composite action (`ci.yml`)

```yaml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Setup Node.js environment
        id: setup
        uses: ./.github/actions/node-ci-setup
        with:
          node-version: "20"
          run-lint: "true"

      - name: Report setup results
        run: |
          echo "Node version used: ${{ steps.setup.outputs.node-version-used }}"
          echo "Cache hit: ${{ steps.setup.outputs.cache-hit }}"

      - name: Run tests
        run: npm test

      - name: Build
        run: npm run build
```

---

## Versioning Actions with Tags

When publishing a composite action to a public repository, use Git tags for stable versioning:

```bash
# Create a release tag
git tag -a v1.0.0 -m "Initial release"
git push origin v1.0.0

# Create a major version tag (floating)
git tag -f v1 -m "v1 latest"
git push origin v1 --force
```

Users can then pin to:

- `@v1.0.0` - exact version
- `@v1` - latest v1.x.x (floating)
- `@main` - latest main (less stable)
- `@abc1234` - exact SHA (most reproducible)

---

## Composite Action with Environment Variables

```yaml
runs:
  using: composite
  steps:
    - name: Set shared environment
      shell: bash
      run: |
        echo "DEPLOYMENT_ENV=${{ inputs.environment }}" >> "$GITHUB_ENV"
        echo "BUILD_VERSION=${{ inputs.version }}" >> "$GITHUB_ENV"

    - name: Use environment
      shell: bash
      run: |
        echo "Deploying $BUILD_VERSION to $DEPLOYMENT_ENV"
```

---

## Hands-on

1. Create an `action.yml` at `.github/actions/greet/action.yml` with one `name` input and two `shell: bash` steps that print a greeting:

   ??? success "Solution"
   `bash
    mkdir -p .github/actions/greet
    cat > .github/actions/greet/action.yml << 'EOF'
    name: Greet
    description: Prints a greeting
    inputs:
      name:
        description: Who to greet
        required: true
    outputs:
      message:
        description: The greeting message
        value: ${{ steps.greet.outputs.message }}
    runs:
      using: composite
      steps:
        - id: greet
          shell: bash
          run: |
            MSG="Hello, ${{ inputs.name }}!"
            echo "$MSG"
            echo "message=$MSG" >> "$GITHUB_OUTPUT"
    EOF
    `

2. Reference the composite action from a workflow using `uses: ./.github/actions/greet`:

   ??? success "Solution"
   `bash
    cat > .github/workflows/use-greet.yml << 'EOF'
    name: Use Greet Action
    on: push
    jobs:
      greet:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - id: g
            uses: ./.github/actions/greet
            with:
              name: GitHub Actions
          - run: echo "Got message: ${{ steps.g.outputs.message }}"
    EOF
    `

3. Add an `output` to the composite action that exposes the greeting string and print it in the calling workflow:

   ??? success "Solution"
   `bash
    gh workflow run use-greet.yml
    RUN_ID=$(gh run list --workflow use-greet.yml --limit 1 --json databaseId -q '.[0].databaseId')
    gh run watch "$RUN_ID"
    gh run view "$RUN_ID" --log | grep "Got message"
    `

4. Add `shell: bash` explicitly to a `run:` step in the composite action and verify it is required (remove it to see the error):

   ??? success "Solution"
   `bash
    cat > .github/actions/greet/action.yml << 'EOF'
    name: Greet
    description: Demonstrates required shell in composite
    inputs:
      name:
        required: true
        description: Name to greet
    runs:
      using: composite
      steps:
        - name: Step without shell will error
          shell: bash
          run: echo "Shell is required in composite actions"
        - name: Explicit bash step
          shell: bash
          run: echo "Hello, ${{ inputs.name }}!"
    EOF
    `

5. Pin the `actions/checkout` reference inside the composite action to its full commit SHA instead of a tag:

   ??? success "Solution"
   `bash
    SHA=$(git ls-remote https://github.com/actions/checkout.git refs/tags/v4 | awk '{print $1}')
    echo "SHA for actions/checkout v4: $SHA"
    sed -i "s|uses: actions/checkout@v4|uses: actions/checkout@$SHA|g" .github/actions/greet/action.yml
    git diff .github/actions/greet/action.yml
    `

## Exercises

### Exercise 1 - Basic Composite Action

Create a composite action at `.github/actions/greet/action.yml` that:

1. Accepts a `name` input
2. Prints "Hello, {name}!"
3. Outputs a `message` with the greeting

### Exercise 2 - Node.js Setup Action

Create a composite action that wraps checkout + setup-node + npm ci. Use it in three different jobs in the same workflow.

### Exercise 3 - Multi-Step with Outputs

Build a composite action that:

1. Reads the `version` field from `package.json`
2. Outputs it as `version`
3. Is used by a workflow job that tags the release

### Exercise 4 - Cross-Platform Composite

Write a composite action that handles both `bash` and `pwsh` steps to work on Linux, macOS, and Windows.

### Exercise 5 - Published Action

Publish your composite action to a public GitHub repository and call it from a separate repository using the `org/repo@v1` reference.

---

## Summary

- Composite actions are defined in `action.yml` with `runs.using: composite` and bundle multiple steps into a single reusable unit callable from any workflow step
- Every `run:` step in a composite action must specify `shell:` explicitly - there is no default shell
- Inputs are accessed via `${{ inputs.<name> }}` and outputs must be mapped from step outputs using `value: ${{ steps.<id>.outputs.<name> }}`
- Composite actions can call other actions with `uses:` inside their steps, enabling composition of existing actions
- Same-repo actions are referenced by path (`./.github/actions/my-action`); public actions use `owner/repo@ref` or `owner/repo/subdir@ref`
- Use semver tags (`v1`, `v1.0.0`) to version published actions so consumers can pin to stable releases
- Composite actions are ideal for DRY-ing up repeated setup steps (checkout, language setup, install) without the overhead of a full reusable workflow
