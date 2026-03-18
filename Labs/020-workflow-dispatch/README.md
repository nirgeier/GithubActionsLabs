# Lab 020 - Workflow Dispatch

## Introduction

- The `workflow_dispatch` event gives you the power to trigger GitHub Actions workflows manually - either from the GitHub web UI, the `gh` CLI, or the REST API.
- Unlike push or pull_request triggers that fire automatically, `workflow_dispatch` puts you in control of when a workflow runs and with what parameters.
- This lab covers how to define strongly-typed inputs for your manual workflows, how to use those inputs in steps, how to trigger runs programmatically with `gh workflow run`, and best practices for parameterizing workflows to support multiple environments, release types, and configurations.

---

## Why Manual Triggers Matter

Automated triggers (push, pull_request, schedule) cover most CI/CD scenarios, but there are situations where manual control is essential:

- **Release workflows** that should only run when explicitly approved
- **Database migrations** that need a human to confirm before execution
- **Debug workflows** that accept a verbose flag or a specific test filter
- **Deploy-on-demand** to staging or production without a code change
- **Operational runbooks** implemented as workflows (e.g., cache flush, user provisioning)

`workflow_dispatch` makes all of these possible while keeping full audit trails in GitHub's workflow run history.

---

## 1. The `workflow_dispatch` Event

To make a workflow manually triggerable, add `workflow_dispatch` to the `on:` block:

```yaml
on:
  workflow_dispatch:
```

This alone is sufficient. The workflow will appear in the **Actions** tab of your repository under the **Run workflow** button. No inputs are required.

You can combine it with other triggers:

```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:
```

---

## 2. Defining Inputs

The `inputs:` key under `workflow_dispatch` lets you declare parameters that users must supply (or that have defaults). Each input has a name, description, type, and optionally a default and required flag.

### Input Types

| Type          | Description                                               |
| ------------- | --------------------------------------------------------- |
| `string`      | Free-form text input                                      |
| `boolean`     | Checkbox, resolves to `'true'` or `'false'`               |
| `choice`      | Drop-down list of predefined options                      |
| `environment` | Drop-down of your repo's configured GitHub Environments   |
| `number`      | Numeric input (GitHub converts it to a string internally) |

### Full Example with All Input Types

```yaml
name: Release Workflow

on:
  workflow_dispatch:
    inputs:
      version:
        description: "Release version (e.g. 1.2.3)"
        type: string
        required: true

      environment:
        description: "Target deployment environment"
        type: environment
        required: true

      release_type:
        description: "Type of release"
        type: choice
        required: true
        default: patch
        options:
          - patch
          - minor
          - major
          - hotfix

      dry_run:
        description: "Perform a dry run without making changes"
        type: boolean
        default: false

      extra_flags:
        description: "Additional CLI flags to pass to the deploy script"
        type: string
        required: false
        default: ""

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - name: Print inputs
        run: |
          echo "Version:      ${{ inputs.version }}"
          echo "Environment:  ${{ inputs.environment }}"
          echo "Release type: ${{ inputs.release_type }}"
          echo "Dry run:      ${{ inputs.dry_run }}"
          echo "Extra flags:  ${{ inputs.extra_flags }}"

      - name: Checkout
        uses: actions/checkout@v4

      - name: Run deploy script
        run: |
          ./scripts/deploy.sh \
            --version "${{ inputs.version }}" \
            --env "${{ inputs.environment }}" \
            --type "${{ inputs.release_type }}" \
            ${{ inputs.dry_run == 'true' && '--dry-run' || '' }} \
            ${{ inputs.extra_flags }}
```

---

## 3. Required vs Optional Inputs

Setting `required: true` means GitHub will not allow the workflow to be dispatched without that value. If you omit `required`, the input is optional and you should always check whether it is empty before using it.

```yaml
inputs:
  ticket_number:
    description: "Jira ticket (e.g. ENG-1234)"
    type: string
    required: true # User MUST provide this

  notify_slack:
    description: "Post a Slack notification on completion"
    type: boolean
    default: false # Optional, defaults to false

  override_image:
    description: "Override the Docker image tag (leave blank to use latest)"
    type: string
    required: false # Truly optional, no default
```

When using optional string inputs with no default, guard against empty strings:

```yaml
- name: Conditionally override image
  if: inputs.override_image != ''
  run: echo "Using custom image: ${{ inputs.override_image }}"
```

---

## 4. Default Values

Defaults reduce friction for the most common use case while still allowing overrides:

```yaml
inputs:
  region:
    description: "AWS region"
    type: choice
    default: us-east-1
    options:
      - us-east-1
      - us-west-2
      - eu-west-1
      - ap-southeast-1

  log_level:
    description: "Log verbosity"
    type: choice
    default: info
    options:
      - debug
      - info
      - warn
      - error
```

---

## 5. Accessing Inputs in Steps

Inputs are accessible via the `inputs` context (preferred in reusable workflows and dispatch) or the `github.event.inputs` context (always available):

```yaml
steps:
  - name: Use inputs context (recommended)
    run: echo "Deploying version ${{ inputs.version }}"

  - name: Use github.event.inputs context (alternative)
    run: echo "Deploying version ${{ github.event.inputs.version }}"

  - name: Pass input to an action
    uses: some/action@v1
    with:
      version: ${{ inputs.version }}

  - name: Boolean check
    if: inputs.dry_run == 'true'
    run: echo "This is a dry run - no changes will be made"
```

> Note: Even `boolean` inputs arrive as the string `'true'` or `'false'` in `run:` steps. Always compare with the string value, not a raw boolean, in bash conditions.

---

## 6. Triggering from the GitHub UI

1. Navigate to your repository on GitHub.
2. Click the **Actions** tab.
3. Select the workflow from the left sidebar.
4. Click the **Run workflow** button (top-right of the workflow run list).
5. Fill in the input fields in the modal dialog.
6. Choose the branch to run on.
7. Click **Run workflow**.

The run will appear immediately in the workflow run list with a `workflow_dispatch` trigger badge.

---

## 7. Triggering with `gh workflow run`

The GitHub CLI provides `gh workflow run` for triggering dispatch workflows from the terminal or scripts:

```bash
# Trigger by workflow file name
gh workflow run release.yml \
  --repo owner/repo \
  --ref main \
  --field version=1.5.0 \
  --field environment=production \
  --field release_type=minor \
  --field dry_run=false

# Trigger by workflow ID
gh workflow run 12345678 --field version=1.5.0

# Pass inputs as JSON
gh workflow run release.yml \
  --repo owner/repo \
  --ref main \
  --json '{"version":"1.5.0","release_type":"minor","dry_run":"false"}'

# List workflows to find IDs
gh workflow list --repo owner/repo
```

After triggering, watch the run:

```bash
# Get the run ID of the most recent dispatch
gh run list --workflow release.yml --limit 1

# Watch the run live
gh run watch <run-id>

# View logs
gh run view <run-id> --log
```

---

## 8. Triggering via REST API

You can also trigger `workflow_dispatch` from any HTTP client or CI system using the GitHub REST API:

```bash
curl -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/OWNER/REPO/actions/workflows/release.yml/dispatches \
  -d '{
    "ref": "main",
    "inputs": {
      "version": "1.5.0",
      "release_type": "minor",
      "dry_run": "false"
    }
  }'
```

---

## 9. Advanced Pattern: Dispatch + Status Report

A common pattern is to have a dispatch workflow that reports its own status back:

```yaml
name: Parameterized Deploy

on:
  workflow_dispatch:
    inputs:
      service:
        description: "Microservice to deploy"
        type: choice
        required: true
        options: [api, frontend, worker, scheduler]
      tag:
        description: "Docker image tag"
        type: string
        required: true
      environment:
        description: "Target environment"
        type: environment
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Create deployment
        id: deployment
        uses: actions/github-script@v7
        with:
          script: |
            const deployment = await github.rest.repos.createDeployment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              ref: context.sha,
              environment: '${{ inputs.environment }}',
              description: 'Deploying ${{ inputs.service }}:${{ inputs.tag }}',
              auto_merge: false,
              required_contexts: []
            });
            core.setOutput('deployment_id', deployment.data.id);

      - name: Deploy service
        run: |
          echo "Deploying ${{ inputs.service }}:${{ inputs.tag }} to ${{ inputs.environment }}"
          # ./deploy.sh ${{ inputs.service }} ${{ inputs.tag }}

      - name: Update deployment status
        if: always()
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.repos.createDeploymentStatus({
              owner: context.repo.owner,
              repo: context.repo.repo,
              deployment_id: ${{ steps.deployment.outputs.deployment_id }},
              state: '${{ job.status }}' === 'success' ? 'success' : 'failure',
              description: 'Deployment ${{ job.status }}'
            });
```

---

## 10. Combining `workflow_dispatch` with `schedule`

You can have the same workflow run on a schedule AND be manually dispatchable. Inputs are only available for manual runs; scheduled runs use the defaults:

```yaml
on:
  schedule:
    - cron: "0 2 * * 1" # Every Monday at 02:00 UTC
  workflow_dispatch:
    inputs:
      dry_run:
        description: "Dry run mode"
        type: boolean
        default: false
      target:
        description: "Specific target (blank = all)"
        type: string
        default: ""

jobs:
  maintenance:
    runs-on: ubuntu-latest
    steps:
      - name: Determine run mode
        run: |
          if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            echo "Manual run triggered by ${{ github.actor }}"
          else
            echo "Scheduled run"
          fi
```

---

## Hands-on

1. Trigger a workflow with a string input using the `gh` CLI:

   ??? success "Solution"
   `bash
    gh workflow run release.yml \
      --repo OWNER/REPO \
      --ref main \
      --field version=1.0.0
    `

2. Trigger a workflow using a choice input and watch the run complete:

   ??? success "Solution"
   `bash
    gh workflow run release.yml \
      --repo OWNER/REPO \
      --ref main \
      --field release_type=minor
    gh run watch $(gh run list --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')
    `

3. List the most recent manual workflow runs filtered by the dispatch trigger:

   ??? success "Solution"
   `bash
    gh run list \
      --repo OWNER/REPO \
      --workflow release.yml \
      --json databaseId,displayTitle,status,createdAt,event \
      --jq '.[] | select(.event == "workflow_dispatch")'
    `

4. Trigger a workflow via the REST API using `curl` and pass JSON inputs:

   ??? success "Solution"
   `bash
    curl -X POST \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      https://api.github.com/repos/OWNER/REPO/actions/workflows/release.yml/dispatches \
      -d '{"ref":"main","inputs":{"version":"1.0.0","release_type":"patch","dry_run":"true"}}'
    `

5. Create a workflow that echoes all its inputs, trigger it, and view the full log:

   ??? success "Solution"
   `bash
    gh workflow run release.yml --repo OWNER/REPO --ref main \
      --field version=2.0.0 --field release_type=major --field dry_run=true
    RUN_ID=$(gh run list --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')
    gh run view "$RUN_ID" --log
    `

## Exercises

### Exercise 1 - Basic Manual Trigger

Create a workflow file `.github/workflows/greet.yml` that:

- Triggers on `workflow_dispatch`
- Has a required `name` string input
- Has a `language` choice input with options: english, spanish, french
- Prints a greeting in the chosen language using `if:` conditions

### Exercise 2 - Environment-Specific Deploy

Create a workflow that:

- Uses an `environment` type input
- Has a `dry_run` boolean input defaulting to `true`
- Simulates a deployment by printing the target environment
- Only runs the "real" deploy step when `dry_run` is `false`

### Exercise 3 - CLI Dispatch

Using `gh workflow run`, trigger your workflow from the terminal with:

- All required fields provided via `--field`
- Watch the run complete with `gh run watch`
- View the logs with `gh run view --log`

### Exercise 4 - Scheduled + Manual Workflow

Extend an existing workflow to support both `schedule` (daily at midnight) and `workflow_dispatch`. For the manual trigger, add a `force_full_scan` boolean input. Use `github.event_name` to print which trigger fired.

---

## Summary

- `workflow_dispatch` enables on-demand workflow execution from the UI, CLI, or REST API
- Inputs support five types: `string`, `boolean`, `choice`, `environment`, and `number`
- Required inputs block dispatch if omitted; optional inputs should use `default:` to minimize friction
- Boolean inputs arrive as the strings `'true'` or `'false'` - compare accordingly in bash
- `gh workflow run` with `--field` or `--json` is the fastest way to trigger parameterized runs from scripts
- The `inputs` context is preferred over `github.event.inputs` for clarity and reusable-workflow compatibility
- Combine `workflow_dispatch` with other triggers to support both automated and manual execution paths
