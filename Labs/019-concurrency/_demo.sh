#!/usr/bin/env bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

# =============================================================================
# Lab 019 - Concurrency Demo
# Demonstrates: workflow YAML examples showing different concurrency group patterns
# =============================================================================

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$LAB_DIR/workflow-examples"

print_header "Lab 019 - Concurrency"
print_info "This demo generates workflow YAML files demonstrating concurrency group patterns."

mkdir -p "$WORKFLOW_DIR"

# -----------------------------------------------------------------------------
# 1. Basic CI cancellation workflow
# -----------------------------------------------------------------------------
print_step "Creating basic CI cancel-in-progress workflow..."

cat >"$WORKFLOW_DIR/ci-cancel-stale.yml" <<'EOF'
# =============================================================
# Pattern 1: Cancel stale CI runs
#
# When you push multiple commits quickly, only the latest
# commit's CI run matters. Older runs are cancelled.
#
# Concurrency group includes:
#   - github.workflow   : prevents cross-workflow interference
#   - github.ref        : per-branch isolation
# =============================================================
name: CI (Cancel Stale Runs)

on:
  push:
  pull_request:

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true   # Cancel the older run, start the new one immediately

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci && npm run lint

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci && npm test

  build:
    runs-on: ubuntu-latest
    needs: [lint, test]
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm run build
EOF

print_success "Created: $WORKFLOW_DIR/ci-cancel-stale.yml"

# -----------------------------------------------------------------------------
# 2. PR-scoped concurrency
# -----------------------------------------------------------------------------
print_step "Creating PR-scoped concurrency workflow..."

cat >"$WORKFLOW_DIR/pr-concurrency.yml" <<'EOF'
# =============================================================
# Pattern 2: Per-PR concurrency
#
# Each PR gets its own concurrency group based on PR number.
# Pushing new commits to the PR cancels the previous check run.
# Different PRs do NOT affect each other.
# =============================================================
name: PR Checks

on:
  pull_request:
    types: [opened, synchronize, reopened]

concurrency:
  group: pr-checks-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci && npm run lint && npm test && npm run build

  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run security scan
        run: echo "Scanning PR code for vulnerabilities..."
EOF

print_success "Created: $WORKFLOW_DIR/pr-concurrency.yml"

# -----------------------------------------------------------------------------
# 3. Deployment queueing workflow
# -----------------------------------------------------------------------------
print_step "Creating deployment queueing workflow..."

cat >"$WORKFLOW_DIR/deploy-queue.yml" <<'EOF'
# =============================================================
# Pattern 3: Deployment queueing - never cancel, always complete
#
# Deployments must complete in order. If two pushes happen
# quickly, the second waits for the first to finish.
#
# cancel-in-progress: false ensures the current deployment
# is not interrupted mid-flight.
# =============================================================
name: Deploy (Queue Don't Cancel)

on:
  push:
    branches: [main]

permissions: {}

jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    # Test jobs: cancel stale runs (only care about latest)
    concurrency:
      group: test-${{ github.ref }}
      cancel-in-progress: true
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm test

  deploy-staging:
    runs-on: ubuntu-latest
    needs: test
    permissions:
      deployments: write
    environment:
      name: staging
      url: https://staging.example.com
    # Staging: queue, never cancel
    concurrency:
      group: deploy-staging
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to staging
        run: |
          echo "Starting staging deployment..."
          echo "SHA: ${{ github.sha }}"
          # Simulate work
          sleep 5
          echo "Staging deployment complete!"

  deploy-production:
    runs-on: ubuntu-latest
    needs: deploy-staging
    permissions:
      deployments: write
    environment:
      name: production
      url: https://www.example.com
    # Production: separate group, queue, never cancel
    concurrency:
      group: deploy-production
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to production
        run: |
          echo "Starting production deployment..."
          echo "SHA: ${{ github.sha }}"
          sleep 5
          echo "Production deployment complete!"
EOF

print_success "Created: $WORKFLOW_DIR/deploy-queue.yml"

# -----------------------------------------------------------------------------
# 4. Conditional cancel-in-progress workflow
# -----------------------------------------------------------------------------
print_step "Creating conditional concurrency workflow..."

cat >"$WORKFLOW_DIR/conditional-concurrency.yml" <<'EOF'
# =============================================================
# Pattern 4: Conditional cancel-in-progress
#
# On feature branches and PRs: cancel stale runs (fast feedback)
# On main branch: queue runs (don't cancel - every main commit matters)
#
# Uses expression: ${{ github.ref != 'refs/heads/main' }}
# =============================================================
name: CI/CD with Conditional Concurrency

on:
  push:
    branches: [main, develop, 'feature/**', 'fix/**']
  pull_request:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci && npm run lint

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci && npm test

  deploy:
    runs-on: ubuntu-latest
    needs: [lint, test]
    if: github.ref == 'refs/heads/main'
    # Deploy has its own separate concurrency group regardless of branch
    concurrency:
      group: deploy-production
      cancel-in-progress: false   # Always complete production deploys
    environment: production
    steps:
      - uses: actions/checkout@v4
      - run: echo "Deploying to production..."
EOF

print_success "Created: $WORKFLOW_DIR/conditional-concurrency.yml"

# -----------------------------------------------------------------------------
# 5. Manual deploy with per-environment concurrency
# -----------------------------------------------------------------------------
print_step "Creating manual deploy with per-environment concurrency..."

cat >"$WORKFLOW_DIR/manual-deploy-concurrency.yml" <<'EOF'
# =============================================================
# Pattern 5: Manual workflow_dispatch with environment concurrency
#
# Each environment has its own concurrency group.
# Multiple staging deploys can queue up independently of production.
# =============================================================
name: Manual Deploy

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        type: choice
        options:
          - staging
          - production
      version:
        description: 'Version to deploy (e.g. v1.2.3)'
        required: true
        type: string

permissions: {}

jobs:
  deploy:
    runs-on: ubuntu-latest
    # Concurrency group is per-environment - staging and production don't block each other
    concurrency:
      group: manual-deploy-${{ github.event.inputs.environment }}
      # Production: queue (never cancel). Staging: also queue for manual deploys.
      cancel-in-progress: false
    environment: ${{ github.event.inputs.environment }}
    permissions:
      deployments: write
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.inputs.version }}

      - name: Deploy ${{ github.event.inputs.version }} to ${{ github.event.inputs.environment }}
        env:
          DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
        run: |
          echo "Manual deploy requested by: ${{ github.actor }}"
          echo "Environment : ${{ github.event.inputs.environment }}"
          echo "Version     : ${{ github.event.inputs.version }}"
          echo "Deploying..."
          # ./scripts/deploy.sh --env "${{ github.event.inputs.environment }}" \
          #                     --version "${{ github.event.inputs.version }}"
          echo "Deploy complete!"
EOF

print_success "Created: $WORKFLOW_DIR/manual-deploy-concurrency.yml"

# -----------------------------------------------------------------------------
# 6. Full strategy reference workflow
# -----------------------------------------------------------------------------
print_step "Creating complete concurrency strategy reference..."

cat >"$WORKFLOW_DIR/full-concurrency-strategy.yml" <<'EOF'
# =============================================================
# Pattern 6: Full concurrency strategy reference
#
# This workflow demonstrates multiple concurrency patterns
# working together in a single pipeline.
# =============================================================
name: Full CI/CD Concurrency Strategy

on:
  push:
    branches: [main, develop, 'release/**']
  pull_request:
  workflow_dispatch:

# Workflow-level: cancel stale runs on everything except main
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}

jobs:
  # ---- CI jobs: follow workflow-level cancel-in-progress ----
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Lint..."

  test-unit:
    name: Unit Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Unit tests..."

  test-integration:
    name: Integration Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Integration tests..."

  # ---- Staging: job-level queue, never cancel ----
  deploy-staging:
    name: Deploy Staging
    runs-on: ubuntu-latest
    needs: [lint, test-unit, test-integration]
    if: github.ref == 'refs/heads/develop' || github.ref == 'refs/heads/main'
    concurrency:
      group: deploy-staging          # Shared staging queue
      cancel-in-progress: false      # Queue; don't cancel staging deploys
    environment:
      name: staging
      url: https://staging.example.com
    steps:
      - uses: actions/checkout@v4
      - run: echo "Deploying to staging..."

  # ---- Smoke tests: cancel if staging is re-deployed ----
  smoke-tests:
    name: Smoke Tests
    runs-on: ubuntu-latest
    needs: deploy-staging
    concurrency:
      group: smoke-tests-staging     # Separate from deploy group
      cancel-in-progress: true       # Cancel stale smoke tests
    steps:
      - uses: actions/checkout@v4
      - run: echo "Running smoke tests against staging..."

  # ---- Production: job-level queue, separate group, never cancel ----
  deploy-production:
    name: Deploy Production
    runs-on: ubuntu-latest
    needs: [smoke-tests]
    if: github.ref == 'refs/heads/main'
    concurrency:
      group: deploy-production       # Completely independent from staging
      cancel-in-progress: false      # Never cancel production deploys
    environment:
      name: production
      url: https://www.example.com
    steps:
      - uses: actions/checkout@v4
      - run: echo "Deploying to production..."
EOF

print_success "Created: $WORKFLOW_DIR/full-concurrency-strategy.yml"

# -----------------------------------------------------------------------------
# 7. Visualize the concurrency patterns
# -----------------------------------------------------------------------------
print_step "Visualizing concurrency scenarios..."

print_info "Pattern behavior comparison:"
echo ""
echo "  Scenario: 3 rapid pushes to main"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │ cancel-in-progress: true                                        │"
echo "  │                                                                 │"
echo "  │  Push 1 → Run 1 starts ─────────── CANCELLED                   │"
echo "  │  Push 2 → Run 2 starts ──── CANCELLED                          │"
echo "  │  Push 3 → Run 3 starts ─────────────────────────── COMPLETES   │"
echo "  │                                                                 │"
echo "  │  Result: Fast, only latest commit CI matters                    │"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │ cancel-in-progress: false                                       │"
echo "  │                                                                 │"
echo "  │  Push 1 → Deploy 1 starts ──────────────────── COMPLETES       │"
echo "  │  Push 2 → Deploy 2 QUEUED            ──────────── COMPLETES    │"
echo "  │  Push 3 → Deploy 3 QUEUED                 ────────── COMPLETES │"
echo "  │                                                                 │"
echo "  │  Result: All deploys run in order, nothing is lost              │"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""

print_info "Group naming best practices:"
echo ""
echo "  CI checks       : ci-\${{ github.workflow }}-\${{ github.ref }}"
echo "  PR checks       : pr-\${{ github.event.pull_request.number }}"
echo "  Staging deploy  : deploy-staging"
echo "  Prod deploy     : deploy-production"
echo "  Manual deploy   : deploy-manual-\${{ inputs.environment }}"
echo ""

print_info "Decision guide:"
echo ""
echo "  Is this a deployment?       → cancel-in-progress: false"
echo "  Is this production?         → cancel-in-progress: false (mandatory)"
echo "  Is this a CI check?         → cancel-in-progress: true"
echo "  Is this a PR check?         → cancel-in-progress: true"
echo "  Is this on main branch?     → cancel-in-progress: false"
echo "  Is this on a feature branch? → cancel-in-progress: true"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_header "Demo Complete"
print_success "Generated workflow files in: $WORKFLOW_DIR"
echo ""
print_info "Files created:"
ls -1 "$WORKFLOW_DIR/"
echo ""
print_info "Key patterns generated:"
echo "  1. ci-cancel-stale.yml         - cancel stale CI runs"
echo "  2. pr-concurrency.yml          - per-PR isolation"
echo "  3. deploy-queue.yml            - queue deployments"
echo "  4. conditional-concurrency.yml - cancel on branches, queue on main"
echo "  5. manual-deploy-concurrency.yml - per-environment manual deploys"
echo "  6. full-concurrency-strategy.yml - complete real-world strategy"
