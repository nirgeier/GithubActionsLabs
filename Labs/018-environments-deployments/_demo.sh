#!/usr/bin/env bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

# =============================================================================
# Lab 018 - Environments and Deployments Demo
# Demonstrates: workflow YAML with staging and production environment deployments
# =============================================================================

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$LAB_DIR/workflow-examples"

print_header "Lab 018 - Environments and Deployments"
print_info "This demo generates workflow YAML files demonstrating GitHub Environments."

mkdir -p "$WORKFLOW_DIR"

# -----------------------------------------------------------------------------
# 1. Full staging → production deployment pipeline
# -----------------------------------------------------------------------------
print_step "Creating staging/production deployment pipeline..."

cat >"$WORKFLOW_DIR/deploy-pipeline.yml" <<'EOF'
# =============================================================
# Full Deployment Pipeline
#
# Flow: test → build → deploy-staging → deploy-production
#
# Environment configuration (set up in GitHub UI):
#   staging:
#     - No required reviewers (automatic)
#     - Branch filter: main, develop
#
#   production:
#     - Required reviewers: @platform-team
#     - Wait timer: 10 minutes
#     - Branch filter: main only
# =============================================================
name: Deploy Pipeline

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      target-env:
        description: 'Target environment'
        required: true
        type: choice
        options:
          - staging
          - production
        default: staging

permissions: {}

jobs:
  # ---- CI phase ----
  test:
    name: Test
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci && npm test

  build:
    name: Build
    runs-on: ubuntu-latest
    needs: test
    permissions:
      contents: read
    outputs:
      artifact-name: dist-${{ github.sha }}
      version: ${{ steps.version.outputs.value }}
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Get version
        id: version
        run: |
          VERSION=$(node -p "require('./package.json').version" 2>/dev/null || echo "0.0.0")
          echo "value=$VERSION" >> "$GITHUB_OUTPUT"

      - run: npm ci && npm run build

      - uses: actions/upload-artifact@v4
        with:
          name: dist-${{ github.sha }}
          path: dist/
          retention-days: 30

  # ---- Staging deployment ----
  deploy-staging:
    name: Deploy to Staging
    runs-on: ubuntu-latest
    needs: build
    # Skip staging for manual production-only deploys
    if: >
      github.event_name == 'push' ||
      (github.event_name == 'workflow_dispatch' && github.event.inputs.target-env != 'production')

    environment:
      name: staging
      url: ${{ steps.deploy.outputs.app-url }}

    permissions:
      contents: read
      deployments: write

    steps:
      - uses: actions/checkout@v4

      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact-name }}
          path: dist/

      - name: Deploy to staging
        id: deploy
        env:
          DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}          # staging environment secret
          API_URL: ${{ vars.API_URL }}                       # staging environment variable
          DEPLOY_REGION: ${{ vars.DEPLOY_REGION }}           # staging environment variable
          APP_VERSION: ${{ needs.build.outputs.version }}
        run: |
          echo "=== Staging Deployment ==="
          echo "Version     : $APP_VERSION"
          echo "API URL     : $API_URL"
          echo "Region      : $DEPLOY_REGION"
          echo "Deploying..."

          # In real workflow:
          # ./scripts/deploy.sh \
          #   --env staging \
          #   --region "$DEPLOY_REGION" \
          #   --token "$DEPLOY_TOKEN" \
          #   --version "$APP_VERSION"

          echo "app-url=https://staging.example.com" >> "$GITHUB_OUTPUT"
          echo "Deployment to staging complete!"

      - name: Run smoke tests
        run: |
          echo "Running smoke tests..."
          # curl -sf "${{ steps.deploy.outputs.app-url }}/health" | jq .
          echo "Smoke tests passed!"

      - name: Report staging URL
        run: |
          echo "Staging deployment: ${{ steps.deploy.outputs.app-url }}"

  # ---- Production deployment (requires approval) ----
  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: [build, deploy-staging]
    if: >
      always() &&
      (needs.deploy-staging.result == 'success' || needs.deploy-staging.result == 'skipped') &&
      (
        github.ref == 'refs/heads/main' ||
        github.event.inputs.target-env == 'production'
      )

    # 'production' environment has required reviewers and wait timer configured in GitHub UI
    environment:
      name: production
      url: ${{ steps.deploy.outputs.app-url }}

    permissions:
      contents: read
      deployments: write

    steps:
      - uses: actions/checkout@v4

      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact-name }}
          path: dist/

      - name: Deploy to production
        id: deploy
        env:
          DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}          # production environment secret
          API_URL: ${{ vars.API_URL }}                       # production environment variable
          DEPLOY_REGION: ${{ vars.DEPLOY_REGION }}           # production environment variable
          REPLICA_COUNT: ${{ vars.REPLICA_COUNT }}           # production environment variable
          APP_VERSION: ${{ needs.build.outputs.version }}
        run: |
          echo "=== Production Deployment ==="
          echo "Version      : $APP_VERSION"
          echo "API URL      : $API_URL"
          echo "Region       : $DEPLOY_REGION"
          echo "Replicas     : $REPLICA_COUNT"
          echo "Deploying..."

          # In real workflow:
          # ./scripts/deploy.sh \
          #   --env production \
          #   --region "$DEPLOY_REGION" \
          #   --replicas "$REPLICA_COUNT" \
          #   --token "$DEPLOY_TOKEN" \
          #   --version "$APP_VERSION"

          echo "app-url=https://www.example.com" >> "$GITHUB_OUTPUT"
          echo "Production deployment complete!"

      - name: Verify deployment
        run: |
          echo "Verifying production..."
          # curl -sf "${{ steps.deploy.outputs.app-url }}/health"
          echo "Health check passed!"

  # ---- Post-deployment notification ----
  notify:
    name: Deployment Notification
    runs-on: ubuntu-latest
    needs: [deploy-staging, deploy-production]
    if: always()
    permissions: {}
    steps:
      - name: Deployment summary
        run: |
          echo "=== Deployment Summary ==="
          echo "Staging    : ${{ needs.deploy-staging.result }}"
          echo "Production : ${{ needs.deploy-production.result }}"
EOF

print_success "Created: $WORKFLOW_DIR/deploy-pipeline.yml"

# -----------------------------------------------------------------------------
# 2. Rollback workflow
# -----------------------------------------------------------------------------
print_step "Creating rollback workflow..."

cat >"$WORKFLOW_DIR/rollback.yml" <<'EOF'
name: Rollback Deployment

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to roll back'
        required: true
        type: choice
        options:
          - staging
          - production
      target-sha:
        description: 'Commit SHA to roll back to'
        required: true
        type: string
      reason:
        description: 'Reason for rollback'
        required: true
        type: string

permissions: {}

jobs:
  rollback:
    name: Rollback ${{ github.event.inputs.environment }}
    runs-on: ubuntu-latest
    environment: ${{ github.event.inputs.environment }}
    permissions:
      contents: read
      deployments: write

    steps:
      - name: Validate target SHA
        run: |
          echo "Rolling back to SHA: ${{ github.event.inputs.target-sha }}"
          echo "Reason: ${{ github.event.inputs.reason }}"
          echo "Triggered by: ${{ github.actor }}"

      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.inputs.target-sha }}

      - name: Build rollback artifact
        run: |
          npm ci && npm run build

      - name: Deploy rollback
        env:
          DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
        run: |
          echo "Deploying rollback to ${{ github.event.inputs.environment }}"
          # ./scripts/deploy.sh \
          #   --env "${{ github.event.inputs.environment }}" \
          #   --sha "${{ github.event.inputs.target-sha }}"
          echo "Rollback complete!"
EOF

print_success "Created: $WORKFLOW_DIR/rollback.yml"

# -----------------------------------------------------------------------------
# 3. Multi-region deployment
# -----------------------------------------------------------------------------
print_step "Creating multi-region deployment workflow..."

cat >"$WORKFLOW_DIR/multi-region-deploy.yml" <<'EOF'
name: Multi-Region Deployment

on:
  push:
    branches: [main]

permissions: {}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    outputs:
      artifact: dist-${{ github.sha }}
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm run build
      - uses: actions/upload-artifact@v4
        with:
          name: dist-${{ github.sha }}
          path: dist/

  deploy-staging-us:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: staging-us
      url: https://us-staging.example.com
    permissions:
      deployments: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact }}
          path: dist/
      - run: echo "Deploying to US staging - Region: ${{ vars.REGION }}"

  deploy-staging-eu:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: staging-eu
      url: https://eu-staging.example.com
    permissions:
      deployments: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact }}
          path: dist/
      - run: echo "Deploying to EU staging - Region: ${{ vars.REGION }}"

  # Production deploys to all regions, but requires approval first
  deploy-production:
    needs: [deploy-staging-us, deploy-staging-eu]
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://www.example.com
    permissions:
      deployments: write
    strategy:
      max-parallel: 1
      matrix:
        region: [us-east-1, eu-west-1, ap-southeast-1]
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact }}
          path: dist/
      - name: Deploy to ${{ matrix.region }}
        env:
          DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
        run: echo "Deploying to production region: ${{ matrix.region }}"
EOF

print_success "Created: $WORKFLOW_DIR/multi-region-deploy.yml"

# -----------------------------------------------------------------------------
# 4. Demonstrate environment management via gh CLI
# -----------------------------------------------------------------------------
print_step "Demonstrating gh CLI environment management..."

print_info "GitHub CLI commands for managing environments:"
echo ""
echo "  # List environments in a repository"
echo "  gh api repos/owner/repo/environments | jq '.environments[].name'"
echo ""
echo "  # Create/update an environment with a wait timer"
echo "  gh api repos/owner/repo/environments/production -X PUT \\"
echo "    --field wait_timer=10 \\"
echo "    --field prevent_self_review=true"
echo ""
echo "  # View deployment history for an environment"
echo "  gh api repos/owner/repo/deployments?environment=production"
echo ""
echo "  # List recent deployments"
echo "  gh api repos/owner/repo/deployments | jq '.[] | {id: .id, env: .environment, sha: .sha, created: .created_at}'"
echo ""

if command -v gh &>/dev/null; then
  print_info "Checking if gh is authenticated to show environment info..."
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "")
  if [ -n "$REPO" ]; then
    print_info "Environments in $REPO:"
    gh api "repos/$REPO/environments" --jq '.environments[].name' 2>/dev/null || print_info "(no environments found or access denied)"
  fi
fi

# -----------------------------------------------------------------------------
# 5. Explain environment variables vs secrets
# -----------------------------------------------------------------------------
print_step "Explaining environments context..."

print_info "Context availability by scope:"
echo ""
echo "  Scope              | secrets.X | vars.X"
echo "  -------------------|-----------|-------"
echo "  Repository level   | Yes       | Yes"
echo "  Environment level  | Yes*      | Yes*"
echo "  Organization level | Yes       | Yes"
echo ""
echo "  * Environment-level values OVERRIDE repository-level values of the same name"
echo ""
print_info "Example: DATABASE_URL for different environments"
echo "  staging environment    → DATABASE_URL = postgresql://...staging-db..."
echo "  production environment → DATABASE_URL = postgresql://...prod-db..."
echo ""
echo "  Workflow code is IDENTICAL - just 'secrets.DATABASE_URL'"
echo "  GitHub injects the right value based on environment: staging/production"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_header "Demo Complete"
print_success "Generated workflow files in: $WORKFLOW_DIR"
echo ""
print_info "Files created:"
ls -1 "$WORKFLOW_DIR/"
echo ""
print_info "Environment setup checklist:"
echo "  1. Create environments in Settings > Environments"
echo "  2. Add required reviewers to production"
echo "  3. Set wait timer (optional)"
echo "  4. Configure branch protection (main branch only for production)"
echo "  5. Add environment-specific secrets (DEPLOY_TOKEN, DATABASE_URL, etc.)"
echo "  6. Add environment variables (REGION, REPLICA_COUNT, API_URL, etc.)"
