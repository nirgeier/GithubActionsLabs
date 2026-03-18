#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 006 - Secrets and Contexts Demo"

TMPDIR_LAB=$(mktemp -d)
mkdir -p "$TMPDIR_LAB/.github/workflows"

# ─── Context dump workflow ────────────────────────────────────────────────────
section "1. Context Dump Workflow"

cat >"$TMPDIR_LAB/.github/workflows/context-dump.yml" <<'WORKFLOW_EOF'
name: Context Dump

on:
  push:
  workflow_dispatch:

jobs:
  dump-contexts:
    runs-on: ubuntu-latest
    steps:
      - name: GitHub context (key properties)
        run: |
          echo "=== github context ==="
          echo "repository:   ${{ github.repository }}"
          echo "sha:          ${{ github.sha }}"
          echo "ref:          ${{ github.ref }}"
          echo "ref_name:     ${{ github.ref_name }}"
          echo "ref_type:     ${{ github.ref_type }}"
          echo "event_name:   ${{ github.event_name }}"
          echo "actor:        ${{ github.actor }}"
          echo "workflow:     ${{ github.workflow }}"
          echo "run_id:       ${{ github.run_id }}"
          echo "run_number:   ${{ github.run_number }}"
          echo "server_url:   ${{ github.server_url }}"

      - name: Runner context
        run: |
          echo "=== runner context ==="
          echo "os:         ${{ runner.os }}"
          echo "arch:       ${{ runner.arch }}"
          echo "name:       ${{ runner.name }}"
          echo "temp:       ${{ runner.temp }}"

      - name: Full github context dump (JSON)
        env:
          GITHUB_CONTEXT: ${{ toJSON(github) }}
        run: |
          echo "=== Full github context ==="
          echo "$GITHUB_CONTEXT" | python3 -m json.tool 2>/dev/null || echo "$GITHUB_CONTEXT"

      - name: Full runner context dump (JSON)
        env:
          RUNNER_CONTEXT: ${{ toJSON(runner) }}
        run: |
          echo "=== Full runner context ==="
          echo "$RUNNER_CONTEXT" | python3 -m json.tool 2>/dev/null || echo "$RUNNER_CONTEXT"
WORKFLOW_EOF

echo "context-dump.yml created."

# ─── Secrets usage workflow ───────────────────────────────────────────────────
section "2. Secrets Usage Workflow"

cat >"$TMPDIR_LAB/.github/workflows/secrets-usage.yml" <<'WORKFLOW_EOF'
name: Secrets Usage

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  use-secrets:
    runs-on: ubuntu-latest
    steps:
      - name: Use a secret as env var
        env:
          MY_API_KEY: ${{ secrets.MY_API_KEY }}
          DB_PASSWORD: ${{ secrets.DATABASE_PASSWORD }}
        run: |
          echo "API key length: ${#MY_API_KEY}"
          echo "API key value: $MY_API_KEY"    # GitHub will mask this as ***
          # Never print secrets - this is for demo only

      - name: Use GITHUB_TOKEN for API calls
        run: |
          echo "Making authenticated API call..."
          gh api user --jq '.login' || echo "(authentication would work with GITHUB_TOKEN)"
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Check if secret is set
        run: |
          if [ -z "${{ secrets.MY_API_KEY }}" ]; then
            echo "Secret MY_API_KEY is NOT set"
          else
            echo "Secret MY_API_KEY is set (value masked)"
          fi
WORKFLOW_EOF

echo "secrets-usage.yml created."

# ─── vars context workflow ────────────────────────────────────────────────────
section "3. vars Context Workflow"

cat >"$TMPDIR_LAB/.github/workflows/vars-context.yml" <<'WORKFLOW_EOF'
name: vars Context Demo

on:
  workflow_dispatch:
  push:

jobs:
  use-vars:
    runs-on: ubuntu-latest
    steps:
      - name: Use repository variables
        run: |
          echo "App name:     ${{ vars.APP_NAME }}"
          echo "Region:       ${{ vars.DEPLOY_REGION }}"
          echo "Max retries:  ${{ vars.MAX_RETRY_COUNT }}"

      - name: vars with fallback default
        run: |
          # Use || to provide a default if the var is not set
          REGION="${{ vars.DEPLOY_REGION || 'us-east-1' }}"
          echo "Region (with default): $REGION"
WORKFLOW_EOF

echo "vars-context.yml created."

# ─── steps context ────────────────────────────────────────────────────────────
section "4. steps Context Workflow"

cat >"$TMPDIR_LAB/.github/workflows/steps-context.yml" <<'WORKFLOW_EOF'
name: Steps Context Demo

on:
  workflow_dispatch:

jobs:
  steps-demo:
    runs-on: ubuntu-latest
    steps:
      - name: Generate output
        id: gen
        run: |
          echo "value=hello-world" >> $GITHUB_OUTPUT
          echo "count=42"          >> $GITHUB_OUTPUT
          echo "timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> $GITHUB_OUTPUT

      - name: Conditionally failing step
        id: maybe-fail
        continue-on-error: true
        run: |
          echo "This step might fail..."
          exit 0   # change to exit 1 to test failure handling

      - name: Reference previous steps
        run: |
          echo "=== steps context ==="
          echo "gen outputs.value:     ${{ steps.gen.outputs.value }}"
          echo "gen outputs.count:     ${{ steps.gen.outputs.count }}"
          echo "gen outputs.timestamp: ${{ steps.gen.outputs.timestamp }}"
          echo "gen outcome:           ${{ steps.gen.outcome }}"
          echo "gen conclusion:        ${{ steps.gen.conclusion }}"
          echo ""
          echo "maybe-fail outcome:    ${{ steps.maybe-fail.outcome }}"
          echo "maybe-fail conclusion: ${{ steps.maybe-fail.conclusion }}"
WORKFLOW_EOF

echo "steps-context.yml created."

# ─── GITHUB_TOKEN permissions ─────────────────────────────────────────────────
section "5. GITHUB_TOKEN Permissions Workflow"

cat >"$TMPDIR_LAB/.github/workflows/token-permissions.yml" <<'WORKFLOW_EOF'
name: GITHUB_TOKEN Permissions

on:
  push:
  workflow_dispatch:

# Restrict permissions for the entire workflow
permissions:
  contents: read

jobs:
  read-only:
    runs-on: ubuntu-latest
    # Inherits workflow-level: contents: read
    steps:
      - uses: actions/checkout@v4
      - run: echo "Can read the repo"

  needs-write:
    runs-on: ubuntu-latest
    # Override just for this job
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
      - name: Create or update a file
        run: |
          echo "This job can write to the repo"
          # git push would work here with contents: write
WORKFLOW_EOF

echo "token-permissions.yml created."

# ─── Set a secret with gh CLI ─────────────────────────────────────────────────
section "6. Setting Secrets with gh CLI"

echo "Commands to manage secrets:"
echo ""
echo "  # Set a secret from a string"
echo "  gh secret set MY_API_KEY --body 'sk-abc123xyz'"
echo ""
echo "  # Set a secret from a file"
echo "  gh secret set TLS_CERT < ./cert.pem"
echo ""
echo "  # Set interactively (prompted)"
echo "  gh secret set DATABASE_PASSWORD"
echo ""
echo "  # Set from environment variable"
echo "  echo \"\$MY_SECRET_VALUE\" | gh secret set MY_SECRET"
echo ""
echo "  # List all secret names (values are never shown)"
echo "  gh secret list"
echo ""
echo "  # Delete a secret"
echo "  gh secret delete OLD_SECRET"

# Show actual secrets if we have auth
if command_exists gh; then
  echo ""
  echo "Current repository secrets:"
  gh secret list 2>/dev/null || echo "  (not authenticated or no access)"
fi

# ─── Validate all workflows ───────────────────────────────────────────────────
section "7. Validating All Workflow Files"

for f in "$TMPDIR_LAB/.github/workflows/"*.yml; do
  name=$(basename "$f")
  python3 -c "
import yaml
with open('$f') as fp:
    doc = yaml.safe_load(fp)
print(f'  OK  $name')
" || echo "  FAIL  $name"
done

# ─── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$TMPDIR_LAB"

section "Lab 006 - Demo Complete"
