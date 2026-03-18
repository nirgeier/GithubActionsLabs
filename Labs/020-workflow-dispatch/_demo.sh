#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 020 - Workflow Dispatch Demo"

# ─────────────────────────────────────────────────────────────
# 1. Create a sample workflow YAML with various input types
# ─────────────────────────────────────────────────────────────
section "1. Creating sample workflow_dispatch YAML"

WORKFLOW_DIR=".github/workflows"
WORKFLOW_FILE="$WORKFLOW_DIR/lab020-dispatch-demo.yml"

mkdir -p "$WORKFLOW_DIR"

cat >"$WORKFLOW_FILE" <<'YAML'
name: "Lab 020 - Workflow Dispatch Demo"

on:
  workflow_dispatch:
    inputs:
      version:
        description: "Release version (e.g. 1.2.3)"
        type: string
        required: true
        default: "1.0.0"

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
        description: "Perform a dry run (no real changes)"
        type: boolean
        default: true

      extra_flags:
        description: "Additional flags for deploy script (optional)"
        type: string
        required: false
        default: ""

jobs:
  dispatch-demo:
    runs-on: ubuntu-latest
    steps:
      - name: Print all inputs
        run: |
          echo "========================================"
          echo "  Workflow Dispatch Inputs Summary"
          echo "========================================"
          echo "  Version:      ${{ inputs.version }}"
          echo "  Environment:  ${{ inputs.environment }}"
          echo "  Release type: ${{ inputs.release_type }}"
          echo "  Dry run:      ${{ inputs.dry_run }}"
          echo "  Extra flags:  ${{ inputs.extra_flags }}"
          echo "  Triggered by: ${{ github.actor }}"
          echo "  Run ID:       ${{ github.run_id }}"
          echo "========================================"

      - name: Validate version format
        run: |
          VERSION="${{ inputs.version }}"
          if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "ERROR: Version '$VERSION' does not match semver format (x.y.z)"
            exit 1
          fi
          echo "Version format is valid: $VERSION"

      - name: Simulate deploy (dry run guard)
        run: |
          if [ "${{ inputs.dry_run }}" = "true" ]; then
            echo "[DRY RUN] Would deploy version ${{ inputs.version }} to ${{ inputs.environment }}"
            echo "[DRY RUN] Release type: ${{ inputs.release_type }}"
          else
            echo "[REAL] Deploying version ${{ inputs.version }} to ${{ inputs.environment }}"
            echo "[REAL] Release type: ${{ inputs.release_type }}"
          fi

      - name: Conditional step based on release_type
        if: inputs.release_type == 'major'
        run: |
          echo "Major release detected - running extended validation..."
          echo "  - Checking backwards compatibility"
          echo "  - Notifying stakeholders"
YAML

echo "Created: $WORKFLOW_FILE"
cat "$WORKFLOW_FILE"

# ─────────────────────────────────────────────────────────────
# 2. Show gh workflow run command examples
# ─────────────────────────────────────────────────────────────
section "2. gh workflow run - Command Examples"

echo ""
echo "# Trigger with --field flags (most readable):"
echo "gh workflow run lab020-dispatch-demo.yml \\"
echo "  --repo OWNER/REPO \\"
echo "  --ref main \\"
echo "  --field version=1.5.0 \\"
echo "  --field release_type=minor \\"
echo "  --field dry_run=false"

echo ""
echo "# Trigger with --json input:"
echo "gh workflow run lab020-dispatch-demo.yml \\"
echo "  --repo OWNER/REPO \\"
echo "  --ref main \\"
echo "  --json '{\"version\":\"1.5.0\",\"release_type\":\"minor\",\"dry_run\":\"false\"}'"

echo ""
echo "# List workflows to get IDs:"
echo "gh workflow list --repo OWNER/REPO"

echo ""
echo "# Watch a run after triggering:"
echo "gh run list --workflow lab020-dispatch-demo.yml --limit 1"
echo "gh run watch <run-id>"
echo "gh run view <run-id> --log"

# ─────────────────────────────────────────────────────────────
# 3. Show REST API trigger example
# ─────────────────────────────────────────────────────────────
section "3. REST API Trigger Example"

echo ""
echo "# Trigger via curl (works from any CI or script):"
echo 'curl -X POST \'
echo '  -H "Authorization: Bearer $GITHUB_TOKEN" \'
echo '  -H "Accept: application/vnd.github+json" \'
echo '  https://api.github.com/repos/OWNER/REPO/actions/workflows/lab020-dispatch-demo.yml/dispatches \'
echo "  -d '{\"ref\":\"main\",\"inputs\":{\"version\":\"1.5.0\",\"release_type\":\"minor\",\"dry_run\":\"false\"}}'"

# ─────────────────────────────────────────────────────────────
# 4. Demonstrate how defaults work (no inputs required)
# ─────────────────────────────────────────────────────────────
section "4. Input Defaults and Context"

echo ""
echo "In the workflow YAML, the 'inputs' context is used like:"
echo '  ${{ inputs.version }}          → string input value'
echo '  ${{ inputs.dry_run }}          → "true" or "false" (always a string)'
echo '  ${{ inputs.release_type }}     → selected choice option'
echo '  ${{ github.event.inputs.* }}  → alternative context (same values)'

echo ""
echo "Boolean check in bash:"
echo '  if [ "${{ inputs.dry_run }}" = "true" ]; then'
echo '    echo "This is a dry run"'
echo "  fi"

echo ""
echo "Boolean check in expressions (conditions):"
echo "  if: inputs.dry_run == 'true'"

# ─────────────────────────────────────────────────────────────
# 5. Show current workflows if gh is available
# ─────────────────────────────────────────────────────────────
section "5. List Existing Workflows (if gh is configured)"

if command_exists gh && gh auth status >/dev/null 2>&1; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  if [ -n "$REPO" ]; then
    echo "Workflows in $REPO:"
    gh workflow list --repo "$REPO" || true
  else
    echo "(Not inside a GitHub repository)"
  fi
else
  echo "(gh CLI not authenticated - skipping live demo)"
  echo "Run 'gh auth login' to enable live workflow listing"
fi

# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────
section "Cleanup"
rm -f "$WORKFLOW_FILE"
echo "Removed demo workflow file: $WORKFLOW_FILE"

section "Lab 020 Complete"
echo "Key takeaways:"
echo "  - workflow_dispatch triggers manual runs from UI, CLI, or REST API"
echo "  - Input types: string, boolean, choice, environment, number"
echo "  - Boolean inputs are strings ('true'/'false') in bash steps"
echo "  - Use gh workflow run --field or --json to dispatch from scripts"
