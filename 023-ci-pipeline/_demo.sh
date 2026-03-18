#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 023 - CI Pipeline Demo"

# ─────────────────────────────────────────────────────────────
# 1. Create a complete CI pipeline YAML for Node.js
# ─────────────────────────────────────────────────────────────
section "1. Creating Complete Node.js CI Pipeline Workflow"

mkdir -p .github/workflows

cat >.github/workflows/lab023-ci.yml <<'YAML'
name: "Lab 023 - CI Pipeline"

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

# Cancel in-progress runs on the same branch
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read
  checks: write
  pull-requests: write
  security-events: write

jobs:
  # ── Job 1: Lint ──────────────────────────────────────────────
  lint:
    name: Lint & Type Check
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Run ESLint
        run: npm run lint -- --format=@microsoft/eslint-formatter-sarif --output-file eslint.sarif
        continue-on-error: true

      - name: Upload ESLint SARIF
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: eslint.sarif

      - name: Check Prettier formatting
        run: npm run format:check

      - name: TypeScript type check
        run: npm run typecheck

  # ── Job 2: Test (Node.js matrix) ────────────────────────────
  test:
    name: Test (Node ${{ matrix.node }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        node: ['18', '20', '22']

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Node.js ${{ matrix.node }}
        uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node }}
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Run tests with coverage
        run: |
          npm test -- \
            --coverage \
            --coverageReporters=lcov \
            --reporters=default \
            --reporters=jest-junit
        env:
          JEST_JUNIT_OUTPUT_DIR: ./reports
          JEST_JUNIT_OUTPUT_NAME: junit-node${{ matrix.node }}.xml

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results-node${{ matrix.node }}
          path: reports/junit-*.xml
          retention-days: 7

      - name: Upload coverage to Codecov
        if: matrix.node == '20'
        uses: codecov/codecov-action@v4
        with:
          token: ${{ secrets.CODECOV_TOKEN }}
          files: ./coverage/lcov.info
          flags: unit-node20
          fail_ci_if_error: false

      - name: Publish test report
        uses: dorny/test-reporter@v1
        if: always()
        with:
          name: "Jest Tests (Node ${{ matrix.node }})"
          path: reports/junit-*.xml
          reporter: jest-junit

  # ── Job 3: Build ─────────────────────────────────────────────
  build:
    name: Build
    runs-on: ubuntu-latest
    needs: [lint, test]

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Build
        run: npm run build
        env:
          NODE_ENV: production

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: build-${{ github.sha }}
          path: dist/
          retention-days: 7

      - name: Verify build output
        run: |
          echo "Build contents:"
          ls -lh dist/
          echo "Total size: $(du -sh dist/ | cut -f1)"

  # ── Job 4: Security Scan ─────────────────────────────────────
  security:
    name: Security Scan
    runs-on: ubuntu-latest
    needs: build

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: npm audit
        run: npm audit --audit-level=high
        continue-on-error: true

      - name: Check for known vulnerabilities (OWASP Dependency-Check)
        run: echo "Dependency check would run here with OWASP DC or Snyk"

  # ── Job 5: Notify on main failure ────────────────────────────
  notify-failure:
    name: Notify Failure
    runs-on: ubuntu-latest
    needs: [lint, test, build, security]
    if: failure() && github.ref == 'refs/heads/main'

    steps:
      - name: Create failure issue
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `CI Failed on main - Run #${context.runNumber}`,
              body: `The CI pipeline failed on \`main\`.\n\n**Run:** [#${context.runNumber}](${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId})\n**Commit:** ${context.sha.substring(0,7)}\n**Triggered by:** @${context.actor}`,
              labels: ['bug', 'ci-failure']
            });
YAML

echo "Created: .github/workflows/lab023-ci.yml"

# ─────────────────────────────────────────────────────────────
# 2. Create sample package.json scripts section
# ─────────────────────────────────────────────────────────────
section "2. Expected package.json Scripts"

echo ""
echo "Your package.json should have these scripts for the CI pipeline:"
cat <<'JSON'
{
  "scripts": {
    "lint": "eslint src/ --ext .ts,.tsx,.js",
    "lint:fix": "eslint src/ --ext .ts,.tsx,.js --fix",
    "format:check": "prettier --check 'src/**/*.{ts,tsx,js,json}'",
    "typecheck": "tsc --noEmit",
    "test": "jest --passWithNoTests",
    "test:watch": "jest --watch",
    "build": "tsc --project tsconfig.build.json",
    "build:watch": "tsc --watch --project tsconfig.build.json"
  }
}
JSON

# ─────────────────────────────────────────────────────────────
# 3. Show caching strategies
# ─────────────────────────────────────────────────────────────
section "3. Caching Strategies Reference"

echo ""
echo "# Built-in npm cache via setup-node (recommended):"
echo "  uses: actions/setup-node@v4"
echo "  with:"
echo "    node-version: '20'"
echo "    cache: npm          # handles ~/.npm automatically"

echo ""
echo "# Cache key for build outputs:"
echo "  key: \${{ runner.os }}-build-\${{ hashFiles('**/package-lock.json') }}-\${{ hashFiles('src/**') }}"

echo ""
echo "# Restore keys (fallback on cache miss):"
echo "  restore-keys: |"
echo "    \${{ runner.os }}-build-\${{ hashFiles('**/package-lock.json') }}-"
echo "    \${{ runner.os }}-build-"

# ─────────────────────────────────────────────────────────────
# 4. Show build status badges
# ─────────────────────────────────────────────────────────────
section "4. Build Status Badge Markdown"

echo ""
echo "Add these to your README.md:"
echo ""
echo "![CI](https://github.com/OWNER/REPO/actions/workflows/lab023-ci.yml/badge.svg)"
echo "![CI (main)](https://github.com/OWNER/REPO/actions/workflows/lab023-ci.yml/badge.svg?branch=main)"

# ─────────────────────────────────────────────────────────────
# 5. Concurrency group examples
# ─────────────────────────────────────────────────────────────
section "5. Concurrency Groups Reference"

echo ""
echo "# Cancel in-progress runs on same branch:"
echo "concurrency:"
echo "  group: ci-\${{ github.ref }}"
echo "  cancel-in-progress: true"
echo ""
echo "# Per-PR concurrency (safe for production branches):"
echo "concurrency:"
echo "  group: ci-pr-\${{ github.event.pull_request.number || github.ref }}"
echo "  cancel-in-progress: true"
echo ""
echo "# Sequential deployment (no cancel):"
echo "concurrency:"
echo "  group: deploy-\${{ github.ref }}"
echo "  cancel-in-progress: false"

# ─────────────────────────────────────────────────────────────
# 6. Run a quick local lint/test simulation
# ─────────────────────────────────────────────────────────────
section "6. Local CI Simulation (echo-based)"

echo ""
echo "Simulating CI pipeline stages..."
echo ""

echo "[lint]     Running ESLint..."
echo "[lint]     ✓ No linting errors"

echo "[lint]     Running Prettier check..."
echo "[lint]     ✓ All files formatted correctly"

echo "[test:18]  Installing deps (npm ci)..."
echo "[test:18]  Running Jest..."
echo "[test:18]  ✓ 42 tests passed, 0 failed, coverage 87%"

echo "[test:20]  Running Jest..."
echo "[test:20]  ✓ 42 tests passed, 0 failed, coverage 87%"

echo "[test:22]  Running Jest..."
echo "[test:22]  ✓ 42 tests passed, 0 failed, coverage 87%"

echo "[build]    Running tsc build..."
echo "[build]    ✓ Build succeeded (dist/ 1.2 MB)"

echo "[security] Running npm audit..."
echo "[security] ✓ No high/critical vulnerabilities found"

echo ""
echo "Pipeline complete: 5/5 jobs passed"

# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────
section "Cleanup"
rm -f .github/workflows/lab023-ci.yml
echo "Demo workflow file removed"

section "Lab 023 Complete"
echo "Key takeaways:"
echo "  - Parallel lint + test jobs, then sequential build + security"
echo "  - Matrix strategy tests multiple Node.js versions without duplication"
echo "  - fail-fast: false lets all matrix legs complete for full visibility"
echo "  - dorny/test-reporter converts JUnit XML into PR check annotations"
echo "  - concurrency: cancel-in-progress: true avoids wasted runner time"
