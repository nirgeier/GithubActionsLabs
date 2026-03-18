#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 004 - Runners Demo"

TMPDIR_LAB=$(mktemp -d)
mkdir -p "$TMPDIR_LAB/.github/workflows"

# ─── Single runner examples ───────────────────────────────────────────────────
section "1. Single Runner Workflow Examples"

cat >"$TMPDIR_LAB/.github/workflows/single-runners.yml" <<'WORKFLOW_EOF'
name: Single Runner Examples

on:
  workflow_dispatch:

jobs:
  linux:
    name: Ubuntu Runner
    runs-on: ubuntu-latest
    steps:
      - name: Runner info
        run: |
          echo "OS:      $RUNNER_OS"
          echo "Arch:    $RUNNER_ARCH"
          echo "Name:    $RUNNER_NAME"
          cat /etc/os-release | grep -E "^(NAME|VERSION)="

  windows:
    name: Windows Runner
    runs-on: windows-latest
    steps:
      - name: Runner info
        shell: pwsh
        run: |
          Write-Host "OS:   $env:RUNNER_OS"
          Write-Host "Arch: $env:RUNNER_ARCH"
          (Get-ComputerInfo).WindowsProductName

  macos:
    name: macOS Runner
    runs-on: macos-latest
    steps:
      - name: Runner info
        run: |
          echo "OS:   $RUNNER_OS"
          echo "Arch: $RUNNER_ARCH"
          sw_vers
WORKFLOW_EOF

echo "single-runners.yml created."

# ─── Multi-OS matrix ──────────────────────────────────────────────────────────
section "2. Multi-OS Matrix Workflow"

cat >"$TMPDIR_LAB/.github/workflows/multi-os-matrix.yml" <<'WORKFLOW_EOF'
name: Multi-OS Matrix

on:
  push:
  pull_request:

jobs:
  test:
    name: Test - ${{ matrix.os }}
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os:
          - ubuntu-latest
          - ubuntu-22.04
          - windows-latest
          - macos-latest
          - macos-13

    steps:
      - uses: actions/checkout@v4

      - name: System info
        shell: bash
        run: |
          echo "Runner OS:   ${{ runner.os }}"
          echo "Runner Arch: ${{ runner.arch }}"
          echo "GITHUB_SHA:  ${GITHUB_SHA:0:7}"

      - name: Linux-specific step
        if: runner.os == 'Linux'
        run: |
          echo "Linux: $(uname -a)"
          lscpu | grep -E "^(Architecture|CPU\(s\)|Model name)"

      - name: macOS-specific step
        if: runner.os == 'macOS'
        run: |
          echo "macOS: $(uname -a)"
          sysctl -n machdep.cpu.brand_string

      - name: Windows-specific step
        if: runner.os == 'Windows'
        shell: pwsh
        run: |
          Write-Host "Windows: $([System.Environment]::OSVersion.VersionString)"
WORKFLOW_EOF

echo "multi-os-matrix.yml created."

# ─── Runner labels for self-hosted ────────────────────────────────────────────
section "3. Self-Hosted Runner Label Examples"

cat >"$TMPDIR_LAB/.github/workflows/self-hosted-labels.yml" <<'WORKFLOW_EOF'
name: Self-Hosted Runner Examples

on:
  workflow_dispatch:

jobs:
  # Use any self-hosted runner
  any-self-hosted:
    runs-on: self-hosted
    steps:
      - run: echo "Running on a self-hosted runner"

  # Require specific labels (runner must have ALL labels)
  linux-x64:
    runs-on: [self-hosted, linux, x64]
    steps:
      - run: echo "Linux x64 self-hosted runner"

  # Organization runner group
  prod-runner:
    runs-on:
      group: production-runners
      labels: [linux, x64]
    steps:
      - run: echo "Production runner group"

  # Dynamic runner label from variable
  dynamic-runner:
    runs-on: ${{ vars.RUNNER_LABEL || 'ubuntu-latest' }}
    steps:
      - run: echo "Runner: ${{ runner.name }}"
WORKFLOW_EOF

echo "self-hosted-labels.yml created."

# ─── Pre-installed software check ────────────────────────────────────────────
section "4. Checking Pre-installed Software (ubuntu-latest)"

cat >"$TMPDIR_LAB/.github/workflows/check-software.yml" <<'WORKFLOW_EOF'
name: Check Pre-installed Software

on:
  workflow_dispatch:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - name: Languages
        run: |
          echo "=== Languages & Runtimes ==="
          echo "Node.js:  $(node --version)"
          echo "Python:   $(python3 --version)"
          echo "Ruby:     $(ruby --version)"
          echo "Go:       $(go version)"
          echo ".NET:     $(dotnet --version)"
          echo "Java:     $(java -version 2>&1 | head -1)"
          echo "PHP:      $(php --version | head -1)"

      - name: Build tools
        run: |
          echo "=== Build Tools ==="
          echo "Make:     $(make --version | head -1)"
          echo "CMake:    $(cmake --version | head -1)"
          echo "Docker:   $(docker --version)"
          echo "git:      $(git --version)"

      - name: Cloud CLIs
        run: |
          echo "=== Cloud CLIs ==="
          aws --version 2>&1  || echo "aws: not installed"
          az --version 2>&1 | head -1 || echo "az: not installed"
          gcloud --version 2>&1 | head -1 || echo "gcloud: not installed"

      - name: Disk space
        run: |
          echo "=== Disk Space ==="
          df -h /
WORKFLOW_EOF

echo "check-software.yml created."

# ─── Caching demo ─────────────────────────────────────────────────────────────
section "5. Dependency Caching Example"

cat >"$TMPDIR_LAB/.github/workflows/caching.yml" <<'WORKFLOW_EOF'
name: Dependency Caching

on: [push]

jobs:
  build-with-cache:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Method 1: Built-in cache in setup actions
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      # Method 2: Manual cache
      - name: Cache pip packages
        uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: ${{ runner.os }}-pip-${{ hashFiles('requirements.txt') }}
          restore-keys: |
            ${{ runner.os }}-pip-

      - name: Install dependencies (uses cache if hit)
        run: |
          npm ci          # npm install but uses lockfile
          pip install -r requirements.txt || true
WORKFLOW_EOF

echo "caching.yml created."

# ─── Validate all workflows ───────────────────────────────────────────────────
section "6. Validating All Workflow Files"

for f in "$TMPDIR_LAB/.github/workflows/"*.yml; do
  name=$(basename "$f")
  python3 -c "
import yaml
with open('$f') as fp:
    doc = yaml.safe_load(fp)
jobs = {name: job.get('runs-on', '?') for name, job in doc.get('jobs', {}).items()}
print(f'  OK  $name')
for j, r in jobs.items():
    print(f'       job={j}  runs-on={r}')
" || echo "  FAIL  $name"
done

# ─── Runner comparison table ──────────────────────────────────────────────────
section "7. Runner Comparison Summary"

printf "\n  %-20s %-12s %-6s %-8s %s\n" "Label" "OS" "vCPUs" "RAM" "Notes"
printf "  %-20s %-12s %-6s %-8s %s\n" "─────────────────" "───────────" "─────" "───────" "─────"
printf "  %-20s %-12s %-6s %-8s %s\n" "ubuntu-latest" "Ubuntu 22.04" "4" "16 GB" "Most common"
printf "  %-20s %-12s %-6s %-8s %s\n" "windows-latest" "Win Server 22" "4" "16 GB" ".NET, WinAPI"
printf "  %-20s %-12s %-6s %-8s %s\n" "macos-latest" "macOS 14" "3" "7 GB" "iOS/macOS builds"
printf "  %-20s %-12s %-6s %-8s %s\n" "self-hosted" "Custom" "?" "?" "Your own infra"

# ─── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$TMPDIR_LAB"

section "Lab 004 - Demo Complete"
