#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 007 - Expressions Demo"

TMPDIR_LAB=$(mktemp -d)
mkdir -p "$TMPDIR_LAB/.github/workflows"

# ─── Operators workflow ───────────────────────────────────────────────────────
section "1. Comparison and Logical Operators"

cat >"$TMPDIR_LAB/.github/workflows/operators.yml" <<'WORKFLOW_EOF'
name: Expression Operators

on:
  push:
  workflow_dispatch:

jobs:
  operators:
    runs-on: ubuntu-latest
    steps:
      - name: Comparison operators
        run: |
          echo "=== Comparison ==="
          echo "ref == main: ${{ github.ref == 'refs/heads/main' }}"
          echo "event != push: ${{ github.event_name != 'push' }}"
          echo "run_number >= 1: ${{ github.run_number >= 1 }}"

      - name: Logical operators
        run: |
          echo "=== Logical ==="
          echo "push AND main: ${{ github.event_name == 'push' && github.ref == 'refs/heads/main' }}"
          echo "push OR dispatch: ${{ github.event_name == 'push' || github.event_name == 'workflow_dispatch' }}"
          echo "NOT cancelled: ${{ !cancelled() }}"

      - name: Only on push
        if: github.event_name == 'push'
        run: echo "This step runs only on push events"

      - name: Not on schedule
        if: github.event_name != 'schedule'
        run: echo "This step runs on any event except schedule"
WORKFLOW_EOF

echo "operators.yml created."

# ─── Functions workflow ───────────────────────────────────────────────────────
section "2. Built-in Functions"

cat >"$TMPDIR_LAB/.github/workflows/functions.yml" <<'WORKFLOW_EOF'
name: Expression Functions

on:
  push:
  workflow_dispatch:

jobs:
  string-functions:
    runs-on: ubuntu-latest
    steps:
      - name: contains()
        run: |
          echo "ref contains 'main': ${{ contains(github.ref, 'main') }}"
          echo "actor is in list: ${{ contains(fromJSON('["alice","github-actions[bot]"]'), github.actor) }}"

      - name: startsWith() and endsWith()
        run: |
          echo "ref starts with 'refs/heads/': ${{ startsWith(github.ref, 'refs/heads/') }}"
          echo "ref ends with '/main': ${{ endsWith(github.ref, '/main') }}"

      - name: format()
        run: |
          MSG="${{ format('Workflow {0} run #{1} by {2}', github.workflow, github.run_number, github.actor) }}"
          echo "Formatted: $MSG"

      - name: toJSON() and fromJSON()
        env:
          GITHUB_CTX_PARTIAL: ${{ toJSON(runner) }}
        run: |
          echo "Runner as JSON:"
          echo "$GITHUB_CTX_PARTIAL" | python3 -m json.tool 2>/dev/null || echo "$GITHUB_CTX_PARTIAL"

  hash-function:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: hashFiles() for cache key
        run: |
          echo "Hash of workflow files: ${{ hashFiles('.github/workflows/**') }}"

      - name: Use hashFiles in cache key
        uses: actions/cache@v4
        with:
          path: ~/.npm
          key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-node-
WORKFLOW_EOF

echo "functions.yml created."

# ─── Status functions workflow ────────────────────────────────────────────────
section "3. Status Functions"

cat >"$TMPDIR_LAB/.github/workflows/status-functions.yml" <<'WORKFLOW_EOF'
name: Status Check Functions

on:
  workflow_dispatch:

jobs:
  demo:
    runs-on: ubuntu-latest
    steps:
      - name: Step 1 - may succeed or fail
        id: step1
        run: |
          echo "Running step 1..."
          exit 0   # change to exit 1 to test failure path

      - name: On success only (implicit)
        run: echo "This is the happy path"

      - name: Explicit success check
        if: success()
        run: echo "success() returned true"

      - name: Only on failure
        if: failure()
        run: echo "Something went wrong!"

      - name: Always runs
        if: always()
        run: |
          echo "always() = true"
          echo "Step 1 outcome: ${{ steps.step1.outcome }}"
          echo "Step 1 conclusion: ${{ steps.step1.conclusion }}"

      - name: On cancellation
        if: cancelled()
        run: echo "Workflow was cancelled"
WORKFLOW_EOF

echo "status-functions.yml created."

# ─── Ternary patterns workflow ────────────────────────────────────────────────
section "4. Ternary-Like Patterns"

cat >"$TMPDIR_LAB/.github/workflows/ternary-patterns.yml" <<'WORKFLOW_EOF'
name: Ternary Patterns

on:
  push:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, staging, prod]
        default: dev

env:
  # Ternary: condition && true_value || false_value
  DEPLOY_ENV: ${{ inputs.environment || (github.ref == 'refs/heads/main' && 'production' || 'staging') }}
  IS_RELEASE:  ${{ startsWith(github.ref, 'refs/tags/v') && 'true' || 'false' }}

jobs:
  ternary-demo:
    runs-on: ubuntu-latest
    steps:
      - name: Show ternary results
        run: |
          echo "Deploy env:  ${{ env.DEPLOY_ENV }}"
          echo "Is release:  ${{ env.IS_RELEASE }}"

      - name: Use inline ternary in step
        run: |
          TARGET="${{ github.ref == 'refs/heads/main' && 'prod' || 'dev' }}"
          echo "Target environment: $TARGET"

      - name: Version tag or latest
        run: |
          VERSION="${{ startsWith(github.ref, 'refs/tags/') && github.ref_name || 'latest' }}"
          echo "Version: $VERSION"
WORKFLOW_EOF

echo "ternary-patterns.yml created."

# ─── fromJSON dynamic matrix ─────────────────────────────────────────────────
section "5. Dynamic Matrix with fromJSON"

cat >"$TMPDIR_LAB/.github/workflows/dynamic-matrix.yml" <<'WORKFLOW_EOF'
name: Dynamic Matrix with fromJSON

on:
  push:
  workflow_dispatch:

jobs:
  set-matrix:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.matrix.outputs.value }}
    steps:
      - name: Build matrix dynamically
        id: matrix
        run: |
          # Could be based on changed files, branch, inputs, etc.
          if [ "${{ github.ref }}" = "refs/heads/main" ]; then
            MATRIX='{"os":["ubuntu-latest","windows-latest","macos-latest"],"node":["18","20"]}'
          else
            MATRIX='{"os":["ubuntu-latest"],"node":["20"]}'
          fi
          echo "value=${MATRIX}" >> $GITHUB_OUTPUT
          echo "Matrix: $MATRIX"

  test:
    needs: set-matrix
    runs-on: ${{ matrix.os }}
    strategy:
      matrix: ${{ fromJSON(needs.set-matrix.outputs.matrix) }}
    steps:
      - name: Run tests
        run: |
          echo "OS:   ${{ matrix.os }}"
          echo "Node: ${{ matrix.node }}"
WORKFLOW_EOF

echo "dynamic-matrix.yml created."

# ─── Validate all workflows ───────────────────────────────────────────────────
section "6. Validating All Workflow Files"

for f in "$TMPDIR_LAB/.github/workflows/"*.yml; do
  name=$(basename "$f")
  python3 -c "
import yaml
with open('$f') as fp:
    doc = yaml.safe_load(fp)
print(f'  OK  $name')
" || echo "  FAIL  $name"
done

# ─── Quick local expression demos ────────────────────────────────────────────
section "7. Local Demo: bash equivalents of expression functions"

echo "Simulating expression function behavior locally:"
echo ""

# contains()
REF="refs/heads/main"
if [[ "$REF" == *"main"* ]]; then
  echo "  contains('$REF', 'main') = true"
fi

# startsWith()
if [[ "$REF" == refs/heads/* ]]; then
  echo "  startsWith('$REF', 'refs/heads/') = true"
fi

# endsWith()
if [[ "$REF" == */main ]]; then
  echo "  endsWith('$REF', '/main') = true"
fi

# format()
WORKFLOW="My Workflow"
RUN=42
ACTOR="octocat"
FORMATTED="Workflow $WORKFLOW run #$RUN by $ACTOR"
echo "  format('Workflow {0} run #{1} by {2}', ...) = '$FORMATTED'"

# hashFiles()
HASH=$(echo "sample-content" | sha256sum | cut -c1-64)
echo "  hashFiles() = '${HASH}' (SHA-256 of file contents)"

# ─── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$TMPDIR_LAB"

section "Lab 007 - Demo Complete"
