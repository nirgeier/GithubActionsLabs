#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 009 - Matrix Strategy Demo"

TMPDIR_LAB=$(mktemp -d)
mkdir -p "$TMPDIR_LAB/.github/workflows"

# ─── Basic matrix ─────────────────────────────────────────────────────────────
section "1. Basic Single-Dimension Matrix"

cat >"$TMPDIR_LAB/.github/workflows/basic-matrix.yml" <<'WORKFLOW_EOF'
name: Basic Matrix

on:
  push:
  workflow_dispatch:

jobs:
  test:
    name: Node.js ${{ matrix.node-version }}
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: ['18', '20', '22']

    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js ${{ matrix.node-version }}
        uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}

      - name: Show version
        run: |
          echo "Testing with Node.js: ${{ matrix.node-version }}"
          node --version
          npm --version
WORKFLOW_EOF

echo "basic-matrix.yml created - generates 3 jobs:"
echo "  test (Node.js 18)"
echo "  test (Node.js 20)"
echo "  test (Node.js 22)"

# ─── Multi-dimensional matrix ─────────────────────────────────────────────────
section "2. Multi-Dimensional Matrix (OS x Node.js)"

cat >"$TMPDIR_LAB/.github/workflows/multi-dim-matrix.yml" <<'WORKFLOW_EOF'
name: Multi-Dimensional Matrix

on:
  push:
  pull_request:

jobs:
  test:
    name: ${{ matrix.os }} / Node ${{ matrix.node-version }}
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os:
          - ubuntu-latest
          - windows-latest
          - macos-latest
        node-version:
          - '18'
          - '20'
        # 3 OS x 2 Node = 6 total jobs

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}

      - name: Platform and version info
        shell: bash
        run: |
          echo "OS:      ${{ matrix.os }}"
          echo "Node:    ${{ matrix.node-version }}"
          echo "Actual:  $(node --version)"
          echo "Runner:  ${{ runner.os }} (${{ runner.arch }})"
WORKFLOW_EOF

echo ""
echo "multi-dim-matrix.yml created - generates 6 jobs (Cartesian product):"
printf "  %-20s %-10s\n" "OS" "Node"
printf "  %-20s %-10s\n" "──────────────────" "────────"
for os in ubuntu-latest windows-latest macos-latest; do
  for node in 18 20; do
    printf "  %-20s %-10s\n" "$os" "$node"
  done
done

# ─── Matrix with include ──────────────────────────────────────────────────────
section "3. Matrix with include"

cat >"$TMPDIR_LAB/.github/workflows/matrix-include.yml" <<'WORKFLOW_EOF'
name: Matrix with Include

on:
  workflow_dispatch:

jobs:
  test:
    name: ${{ matrix.os }} / Node ${{ matrix.node-version }}${{ matrix.experimental && ' (experimental)' || '' }}
    runs-on: ${{ matrix.os }}
    continue-on-error: ${{ matrix.experimental == true }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest]
        node-version: ['18', '20']
        include:
          # Add entirely new combination not in the base grid
          - os: macos-latest
            node-version: '22'
            experimental: true

          # Augment all ubuntu-latest jobs with an extra variable
          - os: ubuntu-latest
            run-coverage: true

          # Augment Node 18 jobs with legacy flag
          - node-version: '18'
            npm-flags: "--legacy-peer-deps"

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}

      - name: Run tests
        run: |
          echo "OS: ${{ matrix.os }}"
          echo "Node: ${{ matrix.node-version }}"
          echo "Experimental: ${{ matrix.experimental || false }}"
          echo "npm flags: ${{ matrix.npm-flags || '(none)' }}"

      - name: Run coverage (ubuntu only)
        if: matrix.run-coverage == true
        run: echo "Running code coverage (ubuntu only)"

      - name: Experimental notice
        if: matrix.experimental == true
        run: echo "This combination is experimental - failure is tolerated"
WORKFLOW_EOF

echo "matrix-include.yml created."

# ─── Matrix with exclude ──────────────────────────────────────────────────────
section "4. Matrix with exclude"

cat >"$TMPDIR_LAB/.github/workflows/matrix-exclude.yml" <<'WORKFLOW_EOF'
name: Matrix with Exclude

on:
  workflow_dispatch:

jobs:
  test:
    name: ${{ matrix.os }} / Node ${{ matrix.node }}
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
        node: ['16', '18', '20']
        exclude:
          # Node 16 is EOL - skip on Windows and macOS
          - os: windows-latest
            node: '16'
          - os: macos-latest
            node: '16'
          # macOS + Node 18 has a known issue in our project
          - os: macos-latest
            node: '18'

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node }}
      - run: |
          echo "Running: ${{ matrix.os }} + Node ${{ matrix.node }}"
          node --version
WORKFLOW_EOF

echo ""
echo "matrix-exclude.yml created."
echo "Matrix after exclusions (from 9 combinations):"
echo "  Full grid (3 OS x 3 Node = 9):"
printf "  %-20s %-8s %-10s\n" "OS" "Node" "Status"
printf "  %-20s %-8s %-10s\n" "──────────────────" "──────" "────────"
declare -A excluded
excluded["windows-latest:16"]=1
excluded["macos-latest:16"]=1
excluded["macos-latest:18"]=1
for os in ubuntu-latest windows-latest macos-latest; do
  for node in 16 18 20; do
    key="${os}:${node}"
    if [[ -v "excluded[$key]" ]]; then
      printf "  %-20s %-8s %-10s\n" "$os" "$node" "EXCLUDED"
    else
      printf "  %-20s %-8s %-10s\n" "$os" "$node" "RUNS"
    fi
  done
done

# ─── fail-fast and max-parallel ──────────────────────────────────────────────
section "5. fail-fast and max-parallel"

cat >"$TMPDIR_LAB/.github/workflows/matrix-control.yml" <<'WORKFLOW_EOF'
name: Matrix Control

on:
  workflow_dispatch:

jobs:
  # fail-fast: false - all jobs run even if one fails
  # max-parallel: 2 - only 2 concurrent jobs
  test:
    name: ${{ matrix.os }} / ${{ matrix.lang }}
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false      # don't cancel on first failure
      max-parallel: 2       # limit concurrency
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
        lang: [node, python, go]
        # 9 total jobs, max 2 concurrent

    steps:
      - run: echo "Testing ${{ matrix.lang }} on ${{ matrix.os }}"
WORKFLOW_EOF

echo "matrix-control.yml created."

# ─── Dynamic matrix ───────────────────────────────────────────────────────────
section "6. Dynamic Matrix with fromJSON"

cat >"$TMPDIR_LAB/.github/workflows/dynamic-matrix.yml" <<'WORKFLOW_EOF'
name: Dynamic Matrix

on:
  push:
  workflow_dispatch:

jobs:
  # Job 1: compute the matrix based on branch/event
  compute-matrix:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.build-matrix.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4

      - name: Determine matrix based on branch
        id: build-matrix
        run: |
          if [ "${{ github.ref }}" = "refs/heads/main" ]; then
            # Full matrix for main: all OS x all Node versions
            MATRIX='{
              "os": ["ubuntu-latest", "windows-latest", "macos-latest"],
              "node": ["18", "20", "22"]
            }'
          elif echo "${{ github.ref }}" | grep -q "refs/heads/develop"; then
            # Medium matrix for develop
            MATRIX='{
              "os": ["ubuntu-latest", "windows-latest"],
              "node": ["18", "20"]
            }'
          else
            # Minimal matrix for feature branches
            MATRIX='{
              "os": ["ubuntu-latest"],
              "node": ["20"]
            }'
          fi
          # Compact to single line for GITHUB_OUTPUT
          COMPACT=$(echo "$MATRIX" | tr -d '\n' | tr -s ' ')
          echo "matrix=${COMPACT}" >> $GITHUB_OUTPUT
          echo "Selected matrix for ref ${{ github.ref }}:"
          echo "$MATRIX"

  # Job 2: run the dynamic matrix
  test:
    needs: compute-matrix
    name: ${{ matrix.os }} / Node ${{ matrix.node }}
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix: ${{ fromJSON(needs.compute-matrix.outputs.matrix) }}

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node }}
      - run: |
          echo "OS:   ${{ matrix.os }}"
          echo "Node: ${{ matrix.node }}"
          node --version
WORKFLOW_EOF

echo "dynamic-matrix.yml created."

# ─── Validate all ─────────────────────────────────────────────────────────────
section "7. Validating All Workflow Files"

for f in "$TMPDIR_LAB/.github/workflows/"*.yml; do
  name=$(basename "$f")
  python3 -c "
import yaml, json
with open('$f') as fp:
    doc = yaml.safe_load(fp)
for job_name, job in doc.get('jobs', {}).items():
    strategy = job.get('strategy', {})
    if strategy:
        m = strategy.get('matrix', {})
        ff = strategy.get('fail-fast', True)
        mp = strategy.get('max-parallel', 'unlimited')
        keys = list(m.keys()) if isinstance(m, dict) else ['(dynamic)']
        print(f'  OK  $name  job={job_name}  matrix_keys={keys}  fail-fast={ff}  max-parallel={mp}')
    else:
        print(f'  OK  $name  job={job_name}  (no matrix)')
" || echo "  FAIL  $name"
done

# ─── Matrix concept summary ───────────────────────────────────────────────────
section "8. Matrix Strategy Summary"

printf "\n  %-30s %s\n" "Concept" "Description"
printf "  %-30s %s\n" "────────────────────────────" "────────────────────────────────────"
printf "  %-30s %s\n" "strategy.matrix.KEY: [...]" "Define axis values"
printf "  %-30s %s\n" "multiple keys" "Cartesian product of all combinations"
printf "  %-30s %s\n" "include:" "Add combinations or augment existing ones"
printf "  %-30s %s\n" "exclude:" "Remove specific combinations"
printf "  %-30s %s\n" "fail-fast: false" "Run all jobs even if one fails"
printf "  %-30s %s\n" "max-parallel: N" "Limit concurrent matrix jobs"
printf "  %-30s %s\n" "continue-on-error: expr" "Allow specific jobs to fail (experimental)"
printf "  %-30s %s\n" "fromJSON(needs.job.outputs)" "Dynamic matrix from previous job output"

# ─── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$TMPDIR_LAB"

section "Lab 009 - Demo Complete"
