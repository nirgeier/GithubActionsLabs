#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 001 - First Workflow Demo"

TMPDIR_LAB=$(mktemp -d)
mkdir -p "$TMPDIR_LAB/.github/workflows"

# ─── Create Hello World workflow ──────────────────────────────────────────────
section "1. Creating Hello World Workflow"

cat >"$TMPDIR_LAB/.github/workflows/hello-world.yml" <<'WORKFLOW_EOF'
name: Hello World

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  greet:
    name: Greeting Job
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Print hello message
        run: echo "Hello, World!"

      - name: Show runner info
        run: |
          echo "Runner OS:   $RUNNER_OS"
          echo "Runner Arch: $RUNNER_ARCH"
          echo "Workspace:   $GITHUB_WORKSPACE"

      - name: Show git context
        run: |
          echo "Repository:  $GITHUB_REPOSITORY"
          echo "Branch/Ref:  $GITHUB_REF"
          echo "Commit SHA:  $GITHUB_SHA"
          echo "Actor:       $GITHUB_ACTOR"
          echo "Event:       $GITHUB_EVENT_NAME"
          echo "Run ID:      $GITHUB_RUN_ID"
WORKFLOW_EOF

echo "Workflow file contents:"
echo "────────────────────────────────────────"
cat "$TMPDIR_LAB/.github/workflows/hello-world.yml"
echo "────────────────────────────────────────"

# ─── Validate YAML syntax ─────────────────────────────────────────────────────
section "2. Validating YAML Syntax with python3"

python3 -c "
import yaml, sys
try:
    with open('$TMPDIR_LAB/.github/workflows/hello-world.yml') as f:
        doc = yaml.safe_load(f)
    print('YAML is VALID.')
    print('Top-level keys:', list(doc.keys()))
    print('Jobs defined:  ', list(doc.get('jobs', {}).keys()))
    print('Trigger events:', list(doc.get('on', {}).keys()) if isinstance(doc.get('on'), dict) else doc.get('on'))
except yaml.YAMLError as e:
    print('YAML ERROR:', e)
    sys.exit(1)
" || true

# ─── Create a multi-job workflow ──────────────────────────────────────────────
section "3. Creating Multi-Job Workflow (sequential with needs:)"

cat >"$TMPDIR_LAB/.github/workflows/multi-job.yml" <<'WORKFLOW_EOF'
name: Multi-Job Example

on:
  push:
  workflow_dispatch:

jobs:
  setup:
    name: Setup
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.ver.outputs.version }}
    steps:
      - name: Get version
        id: ver
        run: echo "version=1.0.0" >> $GITHUB_OUTPUT

  build:
    name: Build
    runs-on: ubuntu-latest
    needs: setup
    steps:
      - name: Build application
        run: echo "Building version ${{ needs.setup.outputs.version }}..."

  test:
    name: Test
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Run tests
        run: echo "Testing version ${{ needs.setup.outputs.version }}..."

  deploy:
    name: Deploy
    runs-on: ubuntu-latest
    needs: [build, test]
    steps:
      - name: Deploy application
        run: echo "Deploying - both build and test passed!"
WORKFLOW_EOF

echo "Multi-job workflow created."
python3 -c "
import yaml
with open('$TMPDIR_LAB/.github/workflows/multi-job.yml') as f:
    doc = yaml.safe_load(f)
jobs = doc.get('jobs', {})
print('Jobs and their dependencies:')
for name, job in jobs.items():
    needs = job.get('needs', 'none')
    print(f'  {name}: needs={needs}')
" || true

# ─── Show gh commands for viewing runs ────────────────────────────────────────
section "4. gh Commands for Viewing Workflow Runs"

echo "Commands you would use after pushing a workflow:"
echo ""
echo "  gh run list                              # List recent runs"
echo "  gh run list --workflow hello-world.yml   # Filter by workflow"
echo "  gh run view <RUN_ID>                     # View run summary"
echo "  gh run view <RUN_ID> --log               # View full logs"
echo "  gh run watch <RUN_ID>                    # Watch run in real time"
echo "  gh workflow run hello-world.yml          # Manually trigger"
echo ""

# Show actual run list if we have gh auth
if command_exists gh; then
  echo "Current workflow runs in this repository (if any):"
  gh run list --limit 5 || true
fi

# ─── Demonstrate act local runner usage ───────────────────────────────────────
section "5. Running Locally with act"

echo "If you have act and Docker installed, you can run:"
echo ""
echo "  cd your-repo"
echo "  act                                  # Run default push event"
echo "  act push                             # Run push event explicitly"
echo "  act workflow_dispatch                # Run manual trigger"
echo "  act --list                           # List available jobs"
echo "  act --job greet                      # Run specific job only"
echo "  act --dry-run                        # Show what would run (no execution)"
echo ""

if command_exists act; then
  echo "act is available. Checking version:"
  act --version || true
else
  echo "act is not installed - install with: brew install act"
fi

# ─── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$TMPDIR_LAB"

section "Lab 001 - Demo Complete"
echo "You now know how to create, validate, and monitor GitHub Actions workflows."
