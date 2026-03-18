#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 002 - Triggers and Events Demo"

TMPDIR_LAB=$(mktemp -d)
mkdir -p "$TMPDIR_LAB/.github/workflows"

# ─── Push trigger examples ────────────────────────────────────────────────────
section "1. Push Trigger Variants"

cat >"$TMPDIR_LAB/.github/workflows/push-trigger.yml" <<'WORKFLOW_EOF'
name: Push Trigger Example

on:
  push:
    branches:
      - main
      - develop
      - 'release/**'
      - '!hotfix/**'
    paths:
      - 'src/**'
      - '*.go'
      - '!docs/**'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Push to ${{ github.ref }} triggered this workflow"
WORKFLOW_EOF

echo "push-trigger.yml created."
cat "$TMPDIR_LAB/.github/workflows/push-trigger.yml"

# ─── Pull request trigger ─────────────────────────────────────────────────────
section "2. Pull Request Trigger"

cat >"$TMPDIR_LAB/.github/workflows/pr-trigger.yml" <<'WORKFLOW_EOF'
name: Pull Request CI

on:
  pull_request:
    branches: [main]
    types:
      - opened
      - synchronize
      - reopened

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate PR
        run: |
          echo "PR number: ${{ github.event.pull_request.number }}"
          echo "PR title:  ${{ github.event.pull_request.title }}"
          echo "Base ref:  ${{ github.base_ref }}"
          echo "Head ref:  ${{ github.head_ref }}"
WORKFLOW_EOF

echo "pr-trigger.yml created."

# ─── Schedule trigger ─────────────────────────────────────────────────────────
section "3. Schedule Trigger (Cron Examples)"

cat >"$TMPDIR_LAB/.github/workflows/schedule.yml" <<'WORKFLOW_EOF'
name: Scheduled Jobs

on:
  schedule:
    - cron: '0 2 * * *'       # Nightly at 2 AM UTC
    - cron: '0 9 * * 1-5'     # Weekdays at 9 AM UTC

jobs:
  nightly:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          echo "Triggered at: $(date -u)"
          echo "Event: ${{ github.event_name }}"
WORKFLOW_EOF

echo ""
echo "Cron expression reference:"
echo "  ┌─ minute (0-59)"
echo "  │ ┌─ hour (0-23)"
echo "  │ │ ┌─ day of month (1-31)"
echo "  │ │ │ ┌─ month (1-12)"
echo "  │ │ │ │ ┌─ day of week (0-6)"
echo "  │ │ │ │ │"
echo "  * * * * *"
echo ""
echo "Common cron patterns:"
printf "  %-25s %s\n" "'0 * * * *'" "Every hour"
printf "  %-25s %s\n" "'*/15 * * * *'" "Every 15 minutes"
printf "  %-25s %s\n" "'0 0 * * *'" "Daily at midnight UTC"
printf "  %-25s %s\n" "'0 9 * * 1-5'" "Weekdays at 9 AM UTC"
printf "  %-25s %s\n" "'0 0 1 * *'" "Monthly on 1st at midnight"
printf "  %-25s %s\n" "'0 0 * * 0'" "Weekly on Sunday midnight"

# ─── Workflow dispatch ────────────────────────────────────────────────────────
section "4. Workflow Dispatch (Manual Trigger)"

cat >"$TMPDIR_LAB/.github/workflows/manual-deploy.yml" <<'WORKFLOW_EOF'
name: Manual Deploy

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        type: choice
        options: [staging, production]
        default: staging
      version:
        description: 'Version to deploy'
        required: true
        type: string
      dry-run:
        description: 'Dry run only'
        required: false
        type: boolean
        default: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy
        run: |
          echo "Environment: ${{ inputs.environment }}"
          echo "Version:     ${{ inputs.version }}"
          echo "Dry run:     ${{ inputs.dry-run }}"
          if [ "${{ inputs.dry-run }}" = "true" ]; then
            echo "DRY RUN - no actual deployment performed"
          else
            echo "DEPLOYING to ${{ inputs.environment }}..."
          fi
WORKFLOW_EOF

echo "manual-deploy.yml created."
echo ""
echo "Trigger manually with:"
echo "  gh workflow run manual-deploy.yml -f environment=staging -f version=1.0.0"

# ─── Repository dispatch ──────────────────────────────────────────────────────
section "5. Repository Dispatch (External Trigger)"

cat >"$TMPDIR_LAB/.github/workflows/repo-dispatch.yml" <<'WORKFLOW_EOF'
name: External Trigger

on:
  repository_dispatch:
    types: [deploy-staging, deploy-production, run-smoke-tests]

jobs:
  handle:
    runs-on: ubuntu-latest
    steps:
      - name: Handle event
        run: |
          echo "Event type: ${{ github.event.action }}"
          echo "Version:    ${{ github.event.client_payload.version }}"
          echo "Triggered by external system"
WORKFLOW_EOF

echo "repo-dispatch.yml created."
echo ""
echo "Send a repository_dispatch event with:"
echo "  gh api repos/{owner}/{repo}/dispatches \\"
echo "    --method POST \\"
echo "    -f event_type=deploy-staging \\"
echo "    -f client_payload='{\"version\":\"1.2.3\"}'"

# ─── Release trigger ──────────────────────────────────────────────────────────
section "6. Release Trigger"

cat >"$TMPDIR_LAB/.github/workflows/release.yml" <<'WORKFLOW_EOF'
name: Release Pipeline

on:
  release:
    types: [published]

jobs:
  build-release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build for release
        run: |
          echo "Building release: ${{ github.event.release.tag_name }}"
          echo "Release name:     ${{ github.event.release.name }}"
          echo "Pre-release:      ${{ github.event.release.prerelease }}"
WORKFLOW_EOF

echo "release.yml created."

# ─── Validate all created workflows ──────────────────────────────────────────
section "7. Validating All Workflow YAML Files"

for f in "$TMPDIR_LAB/.github/workflows/"*.yml; do
  name=$(basename "$f")
  python3 -c "
import yaml
with open('$f') as fp:
    doc = yaml.safe_load(fp)
triggers = list(doc.get('on', {}).keys()) if isinstance(doc.get('on'), dict) else [doc.get('on')]
print(f'  OK  $name  (triggers: {triggers})')
" || echo "  FAIL  $name"
done

# ─── Summary of all triggers ─────────────────────────────────────────────────
section "8. Trigger Summary"

echo "Trigger types demonstrated:"
printf "  %-25s %s\n" "push" "Code pushed to branches/tags"
printf "  %-25s %s\n" "pull_request" "PR lifecycle events"
printf "  %-25s %s\n" "schedule" "Cron-based schedule"
printf "  %-25s %s\n" "workflow_dispatch" "Manual trigger via UI or gh CLI"
printf "  %-25s %s\n" "repository_dispatch" "External API trigger"
printf "  %-25s %s\n" "release" "GitHub release published/created"

# ─── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$TMPDIR_LAB"

section "Lab 002 - Demo Complete"
