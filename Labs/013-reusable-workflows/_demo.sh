#!/usr/bin/env bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

# =============================================================================
# Lab 013 - Reusable Workflows Demo
# Demonstrates: caller and callee workflow YAML pair with inputs/outputs/secrets
# =============================================================================

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$LAB_DIR/workflow-examples"

print_header "Lab 013 - Reusable Workflows"
print_info "This demo generates a caller/callee workflow pair demonstrating inputs, outputs, and secrets."

mkdir -p "$WORKFLOW_DIR"

# -----------------------------------------------------------------------------
# 1. Callee: reusable build workflow
# -----------------------------------------------------------------------------
print_step "Creating callee: reusable-build.yml..."

cat >"$WORKFLOW_DIR/reusable-build.yml" <<'EOF'
# ============================================================
# CALLEE WORKFLOW - reusable-build.yml
# This workflow is called by other workflows via workflow_call.
# ============================================================
name: Reusable - Build

on:
  workflow_call:
    # ------- INPUTS -------
    inputs:
      node-version:
        description: 'Node.js version (e.g. 20, 22)'
        required: false
        type: string
        default: '20'

      environment:
        description: 'Target environment: staging | production'
        required: true
        type: string

      run-lint:
        description: 'Whether to run the linter'
        required: false
        type: boolean
        default: true

      artifact-retention-days:
        description: 'Days to retain the build artifact'
        required: false
        type: number
        default: 7

    # ------- SECRETS -------
    secrets:
      NPM_TOKEN:
        required: false
        description: 'NPM authentication token for private packages'

    # ------- OUTPUTS -------
    outputs:
      artifact-name:
        description: 'Name of the uploaded build artifact'
        value: ${{ jobs.build.outputs.artifact-name }}
      version:
        description: 'Application version built'
        value: ${{ jobs.build.outputs.version }}

jobs:
  lint:
    if: ${{ inputs.run-lint }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
          cache: 'npm'
      - run: npm ci
      - run: npm run lint

  build:
    runs-on: ubuntu-latest
    needs: [lint]
    # 'needs' only applies when lint runs; if run-lint is false, lint is skipped
    # Use 'always()' to ensure build runs when lint is skipped
    if: always() && (needs.lint.result == 'success' || needs.lint.result == 'skipped')

    outputs:
      artifact-name: ${{ steps.artifact-meta.outputs.name }}
      version: ${{ steps.get-version.outputs.version }}

    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
          cache: 'npm'

      - name: Install dependencies
        run: npm ci
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}

      - name: Get application version
        id: get-version
        run: |
          VERSION=$(node -p "require('./package.json').version" 2>/dev/null || echo "0.0.0")
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
          echo "Version: $VERSION"

      - name: Build application
        run: npm run build
        env:
          NODE_ENV: ${{ inputs.environment }}

      - name: Compute artifact name
        id: artifact-meta
        run: |
          ARTIFACT_NAME="build-${{ inputs.environment }}-${{ github.sha }}"
          echo "name=$ARTIFACT_NAME" >> "$GITHUB_OUTPUT"
          echo "Artifact name: $ARTIFACT_NAME"

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: ${{ steps.artifact-meta.outputs.name }}
          path: dist/
          retention-days: ${{ inputs.artifact-retention-days }}
EOF

print_success "Created: $WORKFLOW_DIR/reusable-build.yml"

# -----------------------------------------------------------------------------
# 2. Callee: reusable deploy workflow
# -----------------------------------------------------------------------------
print_step "Creating callee: reusable-deploy.yml..."

cat >"$WORKFLOW_DIR/reusable-deploy.yml" <<'EOF'
# ============================================================
# CALLEE WORKFLOW - reusable-deploy.yml
# ============================================================
name: Reusable - Deploy

on:
  workflow_call:
    inputs:
      environment:
        required: true
        type: string
        description: 'Target environment'
      artifact-name:
        required: true
        type: string
        description: 'Name of the artifact to deploy'
      dry-run:
        required: false
        type: boolean
        default: false
        description: 'Run without making real changes'
      version:
        required: false
        type: string
        default: 'unknown'
        description: 'Application version being deployed'

    secrets:
      DEPLOY_TOKEN:
        required: true
        description: 'Deployment authentication token'
      SLACK_WEBHOOK:
        required: false
        description: 'Slack webhook URL for notifications'

    outputs:
      deployment-url:
        description: 'URL of the deployed application'
        value: ${{ jobs.deploy.outputs.url }}
      deployment-id:
        description: 'Deployment tracking ID'
        value: ${{ jobs.deploy.outputs.id }}

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    outputs:
      url: ${{ steps.do-deploy.outputs.url }}
      id: ${{ steps.do-deploy.outputs.id }}

    steps:
      - uses: actions/checkout@v4

      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: ${{ inputs.artifact-name }}
          path: dist/

      - name: Verify artifact
        run: |
          echo "Artifact contents:"
          ls -la dist/
          echo "Deploying version: ${{ inputs.version }}"
          echo "Target: ${{ inputs.environment }}"
          echo "Dry run: ${{ inputs.dry-run }}"

      - name: Deploy to ${{ inputs.environment }}
        id: do-deploy
        env:
          DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
        run: |
          DEPLOY_ID="deploy-$(date +%Y%m%d%H%M%S)"
          DEPLOY_URL="https://${{ inputs.environment }}.example.com"

          if [ "${{ inputs.dry-run }}" = "true" ]; then
            echo "DRY RUN - skipping actual deployment"
          else
            echo "Deploying to ${{ inputs.environment }}..."
            # ./scripts/deploy.sh --env "${{ inputs.environment }}" --token "$DEPLOY_TOKEN"
          fi

          echo "id=$DEPLOY_ID" >> "$GITHUB_OUTPUT"
          echo "url=$DEPLOY_URL" >> "$GITHUB_OUTPUT"

      - name: Notify Slack
        if: ${{ secrets.SLACK_WEBHOOK != '' }}
        run: |
          STATUS="Deployed ${{ inputs.version }} to ${{ inputs.environment }}"
          URL="${{ steps.do-deploy.outputs.url }}"
          echo "Sending Slack notification: $STATUS ($URL)"
          # curl -X POST "${{ secrets.SLACK_WEBHOOK }}" \
          #   -H "Content-Type: application/json" \
          #   -d "{\"text\": \"$STATUS - $URL\"}"
EOF

print_success "Created: $WORKFLOW_DIR/reusable-deploy.yml"

# -----------------------------------------------------------------------------
# 3. Caller: full CI/CD pipeline
# -----------------------------------------------------------------------------
print_step "Creating caller: ci-cd-pipeline.yml..."

cat >"$WORKFLOW_DIR/ci-cd-pipeline.yml" <<'EOF'
# ============================================================
# CALLER WORKFLOW - ci-cd-pipeline.yml
# Calls the reusable build and deploy workflows above.
# ============================================================
name: CI/CD Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:

jobs:
  # Direct steps in the caller (not reusable)
  unit-tests:
    name: Unit Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci && npm test

  # Call the reusable build workflow
  build-staging:
    name: Build (Staging)
    needs: unit-tests
    if: github.event_name == 'pull_request'
    uses: ./.github/workflows/reusable-build.yml
    with:
      node-version: '20'
      environment: staging
      run-lint: true
      artifact-retention-days: 3
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
      # SLACK_WEBHOOK not passed - it's optional in the callee

  build-production:
    name: Build (Production)
    needs: unit-tests
    if: github.ref == 'refs/heads/main'
    uses: ./.github/workflows/reusable-build.yml
    with:
      node-version: '20'
      environment: production
      run-lint: true
      artifact-retention-days: 30
    secrets: inherit   # Forward ALL secrets from this workflow

  # Deploy staging (from PR builds)
  deploy-staging:
    name: Deploy to Staging
    needs: build-staging
    if: github.event_name == 'pull_request'
    uses: ./.github/workflows/reusable-deploy.yml
    with:
      environment: staging
      # Read output from the build job
      artifact-name: ${{ needs.build-staging.outputs.artifact-name }}
      version: ${{ needs.build-staging.outputs.version }}
      dry-run: false
    secrets:
      DEPLOY_TOKEN: ${{ secrets.STAGING_DEPLOY_TOKEN }}
      SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK }}

  # Deploy production (from main branch builds)
  deploy-production:
    name: Deploy to Production
    needs: build-production
    if: github.ref == 'refs/heads/main'
    uses: ./.github/workflows/reusable-deploy.yml
    with:
      environment: production
      artifact-name: ${{ needs.build-production.outputs.artifact-name }}
      version: ${{ needs.build-production.outputs.version }}
      dry-run: false
    secrets: inherit

  # Use the deployment outputs in a subsequent job
  post-deploy:
    name: Post-Deploy Verification
    needs: [deploy-staging, deploy-production]
    if: always() && (needs.deploy-staging.result == 'success' || needs.deploy-production.result == 'success')
    runs-on: ubuntu-latest
    steps:
      - name: Report deployment results
        run: |
          echo "=== Deployment Summary ==="
          echo "Staging URL  : ${{ needs.deploy-staging.outputs.deployment-url }}"
          echo "Prod URL     : ${{ needs.deploy-production.outputs.deployment-url }}"
          echo "Staging ID   : ${{ needs.deploy-staging.outputs.deployment-id }}"
          echo "Prod ID      : ${{ needs.deploy-production.outputs.deployment-id }}"
EOF

print_success "Created: $WORKFLOW_DIR/ci-cd-pipeline.yml"

# -----------------------------------------------------------------------------
# 4. Cross-repo caller example
# -----------------------------------------------------------------------------
print_step "Creating cross-repository caller example..."

cat >"$WORKFLOW_DIR/cross-repo-caller.yml" <<'EOF'
# ============================================================
# CROSS-REPOSITORY CALLER
# Calls a shared reusable workflow from another repository.
# ============================================================
name: CI using Shared Org Workflows

on: [push, pull_request]

jobs:
  # Call a reusable workflow from a shared-workflows repository
  build:
    uses: my-org/shared-workflows/.github/workflows/node-build.yml@v2
    with:
      node-version: '20'
      environment: staging
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}

  # Call the latest version by branch
  deploy:
    needs: build
    uses: my-org/shared-workflows/.github/workflows/deploy.yml@main
    with:
      artifact-name: ${{ needs.build.outputs.artifact-name }}
      environment: staging
    secrets: inherit

  # Call a pinned SHA for maximum reproducibility
  security-scan:
    uses: my-org/shared-workflows/.github/workflows/security.yml@abc1234def5678
    with:
      scan-type: 'full'
    secrets: inherit
EOF

print_success "Created: $WORKFLOW_DIR/cross-repo-caller.yml"

# -----------------------------------------------------------------------------
# 5. Visualize the workflow structure
# -----------------------------------------------------------------------------
print_step "Visualizing the workflow structure..."

print_info "Reusable workflow relationship diagram:"
echo ""
echo "  ci-cd-pipeline.yml (CALLER)"
echo "  ├── unit-tests (direct job)"
echo "  ├── build-staging ──uses──► reusable-build.yml (CALLEE)"
echo "  │                               └── inputs: node-version, environment, run-lint"
echo "  │                               └── secrets: NPM_TOKEN"
echo "  │                               └── outputs: artifact-name, version"
echo "  ├── build-production ──uses──► reusable-build.yml (same callee)"
echo "  ├── deploy-staging ──uses──► reusable-deploy.yml (CALLEE)"
echo "  │                               └── inputs: environment, artifact-name, version"
echo "  │                               └── secrets: DEPLOY_TOKEN, SLACK_WEBHOOK"
echo "  │                               └── outputs: deployment-url, deployment-id"
echo "  ├── deploy-production ──uses──► reusable-deploy.yml"
echo "  └── post-deploy (direct job, reads deploy outputs)"
echo ""

print_info "Key syntax differences:"
echo ""
echo "  Caller side:"
echo "    uses: ./.github/workflows/reusable-build.yml  # same repo"
echo "    uses: org/repo/.github/workflows/build.yml@main  # other repo"
echo "    with:  # inputs"
echo "    secrets:  # explicit or 'inherit'"
echo ""
echo "  Callee side:"
echo "    on: workflow_call:  # the trigger"
echo "    inputs:  # define accepted inputs"
echo "    secrets:  # declare required/optional secrets"
echo "    outputs:  # map job outputs to workflow outputs"
echo ""

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_header "Demo Complete"
print_success "Generated workflow files in: $WORKFLOW_DIR"
echo ""
print_info "Files created:"
ls -1 "$WORKFLOW_DIR/"
