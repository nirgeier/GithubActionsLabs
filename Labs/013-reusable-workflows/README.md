# Lab 013 - Reusable Workflows

## Introduction

- Reusable workflows allow you to centralize and share workflow logic across repositories or across multiple callers in the same repository.
- Instead of copying and pasting complex job definitions, you define the workflow once in a called workflow file and invoke it from multiple places.
- This lab covers how to define reusable workflows with inputs, outputs, and secrets, and how to call them correctly.

---

## What Is a Reusable Workflow?

A reusable workflow is a regular workflow file that uses the `workflow_call` trigger. It can define:

- **Inputs** - parameters passed by the caller
- **Outputs** - values returned to the caller
- **Secrets** - sensitive values passed from the caller

Reusable workflows must be stored in `.github/workflows/` and triggered by `on: workflow_call`.

---

## Defining a Reusable Workflow - Callee

```yaml
# .github/workflows/reusable-build.yml
name: Reusable Build Workflow

on:
  workflow_call:
    inputs:
      node-version:
        description: "Node.js version to use"
        required: false
        type: string
        default: "20"
      environment:
        description: "Target environment"
        required: true
        type: string
    secrets:
      NPM_TOKEN:
        required: false
    outputs:
      artifact-name:
        description: "Name of the uploaded build artifact"
        value: ${{ jobs.build.outputs.artifact-name }}

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      artifact-name: ${{ steps.upload.outputs.artifact-id }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
      - run: npm ci
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
      - run: npm run build
      - id: upload
        uses: actions/upload-artifact@v4
        with:
          name: build-${{ inputs.environment }}-${{ github.sha }}
          path: dist/
```

---

## Input Types

Reusable workflows support four input types:

| Type      | Description          | Example                |
| --------- | -------------------- | ---------------------- |
| `string`  | A text value         | `'production'`         |
| `boolean` | True or false        | `true`                 |
| `number`  | A numeric value      | `3`                    |
| `choice`  | One of a defined set | `'debug' \| 'release'` |

```yaml
on:
  workflow_call:
    inputs:
      environment:
        type: string
        required: true

      run-lint:
        type: boolean
        required: false
        default: true

      retry-count:
        type: number
        required: false
        default: 3

      build-mode:
        type: string
        required: false
        default: "release"
        # Note: 'choice' type is only valid for workflow_dispatch
        # For workflow_call, use string with description listing options
```

---

## Defining Outputs

Workflow outputs are derived from job outputs:

```yaml
on:
  workflow_call:
    outputs:
      version:
        description: "The computed version string"
        value: ${{ jobs.build.outputs.version }}
      artifact-name:
        description: "Name of the uploaded artifact"
        value: ${{ jobs.build.outputs.artifact-name }}

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.version.outputs.value }}
      artifact-name: ${{ steps.upload.outputs.artifact-id }}
    steps:
      - id: version
        run: echo "value=$(cat VERSION)" >> "$GITHUB_OUTPUT"
      - id: upload
        uses: actions/upload-artifact@v4
        with:
          name: dist
          path: dist/
```

---

## Passing Secrets

### Method 1: Explicit Secret Passing

```yaml
# Caller
jobs:
  call-workflow:
    uses: org/repo/.github/workflows/reusable.yml@main
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
      DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}
```

```yaml
# Callee - declares which secrets it accepts
on:
  workflow_call:
    secrets:
      NPM_TOKEN:
        required: false
        description: "NPM authentication token"
      DEPLOY_KEY:
        required: true
        description: "SSH deploy key"
```

### Method 2: `secrets: inherit`

Passes **all** caller secrets automatically:

```yaml
# Caller
jobs:
  call-workflow:
    uses: org/repo/.github/workflows/reusable.yml@main
    secrets: inherit
```

This is convenient but less explicit. The called workflow can access any secret the caller has access to.

---

## Calling a Reusable Workflow - Caller

```yaml
# .github/workflows/ci.yml  (the caller)
name: CI Pipeline

on: [push, pull_request]

jobs:
  build:
    uses: ./.github/workflows/reusable-build.yml
    with:
      node-version: "20"
      environment: staging
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}

  deploy:
    needs: build
    uses: ./.github/workflows/reusable-deploy.yml
    with:
      artifact-name: ${{ needs.build.outputs.artifact-name }}
      environment: staging
    secrets: inherit
```

### Calling from Another Repository

```yaml
jobs:
  build:
    uses: my-org/shared-workflows/.github/workflows/build.yml@v2
    with:
      environment: production
    secrets:
      DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
```

The called workflow reference format is: `{owner}/{repo}/.github/workflows/{filename}@{ref}`

Valid refs: branch name, tag name, commit SHA.

---

## Full Example: Caller + Callee Pair

### Callee (`reusable-deploy.yml`)

```yaml
name: Reusable Deploy Workflow

on:
  workflow_call:
    inputs:
      environment:
        description: "Target environment: staging or production"
        required: true
        type: string
      artifact-name:
        description: "Name of the artifact to deploy"
        required: true
        type: string
      dry-run:
        description: "Run in dry-run mode without making changes"
        required: false
        type: boolean
        default: false
    secrets:
      DEPLOY_TOKEN:
        required: true
        description: "Authentication token for deployment target"
      SLACK_WEBHOOK:
        required: false
        description: "Slack webhook for deployment notifications"
    outputs:
      deployment-url:
        description: "URL of the deployed application"
        value: ${{ jobs.deploy.outputs.url }}
      deployment-id:
        description: "Unique identifier for this deployment"
        value: ${{ jobs.deploy.outputs.id }}

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    outputs:
      url: ${{ steps.deploy.outputs.url }}
      id: ${{ steps.deploy.outputs.id }}
    steps:
      - uses: actions/checkout@v4

      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: ${{ inputs.artifact-name }}
          path: dist/

      - name: Deploy to ${{ inputs.environment }}
        id: deploy
        env:
          DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
          DRY_RUN: ${{ inputs.dry-run }}
        run: |
          if [ "$DRY_RUN" = "true" ]; then
            echo "DRY RUN: would deploy to ${{ inputs.environment }}"
            echo "url=https://${{ inputs.environment }}.example.com" >> "$GITHUB_OUTPUT"
            echo "id=dry-run-$(date +%s)" >> "$GITHUB_OUTPUT"
          else
            echo "Deploying to ${{ inputs.environment }}..."
            # ./scripts/deploy.sh --env ${{ inputs.environment }} --token "$DEPLOY_TOKEN"
            echo "url=https://${{ inputs.environment }}.example.com" >> "$GITHUB_OUTPUT"
            echo "id=deploy-$(date +%s)" >> "$GITHUB_OUTPUT"
          fi

      - name: Notify Slack
        if: secrets.SLACK_WEBHOOK != '' && !inputs.dry-run
        run: |
          curl -X POST "${{ secrets.SLACK_WEBHOOK }}" \
            -H "Content-Type: application/json" \
            -d '{"text": "Deployed to ${{ inputs.environment }}: ${{ steps.deploy.outputs.url }}"}'
```

### Caller (`ci.yml`)

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:

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
    needs: test
    uses: ./.github/workflows/reusable-build.yml
    with:
      node-version: "20"
      environment: ${{ github.ref == 'refs/heads/main' && 'production' || 'staging' }}
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}

  deploy-staging:
    needs: build
    if: github.event_name == 'pull_request'
    uses: ./.github/workflows/reusable-deploy.yml
    with:
      environment: staging
      artifact-name: ${{ needs.build.outputs.artifact-name }}
      dry-run: false
    secrets:
      DEPLOY_TOKEN: ${{ secrets.STAGING_DEPLOY_TOKEN }}
      SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK }}

  deploy-production:
    needs: build
    if: github.ref == 'refs/heads/main'
    uses: ./.github/workflows/reusable-deploy.yml
    with:
      environment: production
      artifact-name: ${{ needs.build.outputs.artifact-name }}
      dry-run: false
    secrets: inherit
```

---

## Limitations of Reusable Workflows

1. **No step-level reuse** - you can only reuse at the job level
2. **No matrix in callee from caller** - the caller cannot drive matrix expansion in the callee
3. **Nesting depth** - up to 4 levels deep (callee can call another callee, up to 3 hops)
4. **Environment secrets** - if callee uses `environment:`, the caller must have access to those environment secrets
5. **`strategy.matrix` context** - the matrix context is not passed to reusable workflows
6. **Self-hosted runners** - callee workflow uses its own runner definitions, not the caller's
7. **Cannot use `continue-on-error`** at the caller job level for reusable workflows

---

## Nesting Reusable Workflows

Reusable workflows can call other reusable workflows (up to 4 levels total):

```yaml
# Level 1 caller
jobs:
  call-level-2:
    uses: ./.github/workflows/level-2.yml@main

# Level 2 - itself a reusable workflow that calls another
on:
  workflow_call:
jobs:
  call-level-3:
    uses: ./.github/workflows/level-3.yml@main
```

---

## Hands-on

1. Create a called (reusable) workflow at `.github/workflows/called.yml` that accepts a single `environment` string input and prints it:

   ??? success "Solution"
   `bash
    mkdir -p .github/workflows
    cat > .github/workflows/called.yml << 'EOF'
    name: Called Workflow
    on:
      workflow_call:
        inputs:
          environment:
            description: Target environment
            required: true
            type: string
    jobs:
      print:
        runs-on: ubuntu-latest
        steps:
          - run: echo "Deploying to ${{ inputs.environment }}"
    EOF
    `

2. Create a caller workflow that invokes `called.yml` and passes `environment: staging` as the input:

   ??? success "Solution"
   `bash
    cat > .github/workflows/caller.yml << 'EOF'
    name: Caller Workflow
    on: push
    jobs:
      call:
        uses: ./.github/workflows/called.yml
        with:
          environment: staging
    EOF
    git add .github/workflows/called.yml .github/workflows/caller.yml
    git commit -m "add reusable workflow pair"
    git push
    `

3. Add an output named `deployed-url` to the called workflow and read it in the caller with `needs.call.outputs.deployed-url`:

   ??? success "Solution"
   `bash
    cat > .github/workflows/called-with-output.yml << 'EOF'
    name: Called With Output
    on:
      workflow_call:
        inputs:
          environment:
            required: true
            type: string
        outputs:
          deployed-url:
            value: ${{ jobs.deploy.outputs.url }}
    jobs:
      deploy:
        runs-on: ubuntu-latest
        outputs:
          url: ${{ steps.set-url.outputs.url }}
        steps:
          - id: set-url
            run: echo "url=https://${{ inputs.environment }}.example.com" >> "$GITHUB_OUTPUT"
    EOF
    gh run view --log $(gh run list --limit 1 --json databaseId -q '.[0].databaseId')
    `

4. Use `secrets: inherit` in the caller so the called workflow receives all caller secrets automatically:

   ??? success "Solution"
   `bash
    cat > .github/workflows/caller-inherit.yml << 'EOF'
    name: Caller With Inherit
    on: push
    jobs:
      call:
        uses: ./.github/workflows/called.yml
        with:
          environment: production
        secrets: inherit
    EOF
    `

5. List all workflow files in the repository that declare `workflow_call` (i.e., reusable workflows) using `gh api` and `jq`:

   ??? success "Solution"
   `bash
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    gh api repos/$REPO/contents/.github/workflows \
      | jq -r '.[].name' \
      | while read f; do
          content=$(gh api repos/$REPO/contents/.github/workflows/$f | jq -r '.content' | base64 -d)
          echo "$content" | grep -q 'workflow_call' && echo "$f"
        done
    `

## Exercises

### Exercise 1 - Simple Callee/Caller

Create a reusable workflow that accepts `environment` (string) and `node-version` (string) inputs. Call it from a CI workflow.

### Exercise 2 - Outputs Pipeline

Create a callee that outputs a `version` string. In the caller, use that output in a subsequent job.

### Exercise 3 - Secret Forwarding

Practice both explicit secret passing and `secrets: inherit`. Verify the callee can access the secret.

### Exercise 4 - Cross-Repository Reuse

Call a reusable workflow from a different repository using `org/shared-workflows/.github/workflows/build.yml@main`.

### Exercise 5 - Nested Reuse

Create three workflow files: `ci.yml` → `build-workflow.yml` → `setup-workflow.yml`, each calling the next.

---

## Summary

- Reusable workflows use `on: workflow_call` and are called with `uses:` pointing to a `.github/workflows/*.yml` file at a specific ref
- Inputs accept `string`, `boolean`, and `number` types with optional defaults; outputs are mapped from job-level outputs
- Secrets are passed either explicitly per-secret or with `secrets: inherit` to forward all caller secrets automatically
- The caller accesses callee outputs via `needs.<job-id>.outputs.<output-name>` just like any other job output
- Reusable workflows can be in the same repository (`./.github/workflows/`) or a different one (`org/repo/.github/workflows/file.yml@ref`)
- Nesting is supported up to 4 levels deep, allowing hierarchical composition of complex pipelines
- Key limitations include no step-level reuse, no matrix driving from the caller, and callee environment secrets must be accessible to the caller
