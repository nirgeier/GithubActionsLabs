#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 024 - CD Pipeline Demo"

# ─────────────────────────────────────────────────────────────
# 1. Create staging + production CD workflow
# ─────────────────────────────────────────────────────────────
section "1. Creating Staging + Production CD Pipeline"

mkdir -p .github/workflows

cat >.github/workflows/lab024-cd.yml <<'YAML'
name: "Lab 024 - CD Pipeline"

on:
  workflow_run:
    workflows: ["Lab 023 - CI Pipeline"]
    types: [completed]
    branches: [main]

permissions:
  contents: read
  deployments: write
  id-token: write

jobs:
  # Guard: only proceed when CI passed
  check-ci:
    name: Verify CI Passed
    runs-on: ubuntu-latest
    if: github.event.workflow_run.conclusion == 'success'
    outputs:
      sha: ${{ github.event.workflow_run.head_sha }}
    steps:
      - run: |
          echo "CI passed for SHA: ${{ github.event.workflow_run.head_sha }}"
          echo "Proceeding with deployment..."

  # ── Deploy to Staging ─────────────────────────────────────
  deploy-staging:
    name: Deploy to Staging
    runs-on: ubuntu-latest
    needs: check-ci
    environment:
      name: staging
      url: https://staging.example.com

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          ref: ${{ needs.check-ci.outputs.sha }}

      - name: Create GitHub Deployment
        id: deployment
        uses: actions/github-script@v7
        with:
          script: |
            const { data } = await github.rest.repos.createDeployment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              ref: '${{ needs.check-ci.outputs.sha }}',
              environment: 'staging',
              auto_merge: false,
              required_contexts: [],
              description: 'CD Pipeline - staging deploy'
            });
            core.setOutput('id', data.id);

      - name: Deploy to staging
        run: |
          echo "Deploying SHA ${{ needs.check-ci.outputs.sha }} to staging..."
          echo "  Image: ghcr.io/${{ github.repository }}:sha-${{ needs.check-ci.outputs.sha }}"
          echo "  Cluster: staging-cluster"
          # In a real pipeline: aws ecs update-service --cluster staging-cluster ...

      - name: Run smoke tests
        run: |
          echo "Running smoke tests against https://staging.example.com ..."
          echo "  GET /health → 200 OK"
          echo "  GET /api/version → 200 OK"
          echo "  Smoke tests passed!"
          # In a real pipeline: curl --fail https://staging.example.com/health

      - name: Update deployment status
        if: always()
        uses: actions/github-script@v7
        with:
          script: |
            const state = '${{ job.status }}' === 'success' ? 'success' : 'failure';
            await github.rest.repos.createDeploymentStatus({
              owner: context.repo.owner,
              repo: context.repo.repo,
              deployment_id: ${{ steps.deployment.outputs.id }},
              state,
              environment_url: 'https://staging.example.com',
              description: `Staging deploy ${state}`
            });

  # ── Deploy to Production (requires approval) ──────────────
  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: [check-ci, deploy-staging]
    environment:
      name: production
      url: https://example.com

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          ref: ${{ needs.check-ci.outputs.sha }}

      - name: Create GitHub Deployment
        id: deployment
        uses: actions/github-script@v7
        with:
          script: |
            const { data } = await github.rest.repos.createDeployment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              ref: '${{ needs.check-ci.outputs.sha }}',
              environment: 'production',
              auto_merge: false,
              required_contexts: []
            });
            core.setOutput('id', data.id);

      - name: Deploy to production
        run: |
          echo "Deploying to PRODUCTION..."
          echo "  SHA: ${{ needs.check-ci.outputs.sha }}"
          echo "  Approved by: ${{ github.actor }}"
          echo "  Deployment strategy: blue-green"

      - name: Production health check
        id: health
        run: |
          echo "Running production health checks..."
          echo "  Attempt 1/5: GET https://example.com/health → 200 OK"
          echo "  Health check passed!"

      - name: Update deployment status
        if: always()
        uses: actions/github-script@v7
        with:
          script: |
            const state = '${{ job.status }}' === 'success' ? 'success' : 'failure';
            await github.rest.repos.createDeploymentStatus({
              owner: context.repo.owner,
              repo: context.repo.repo,
              deployment_id: ${{ steps.deployment.outputs.id }},
              state,
              environment_url: 'https://example.com'
            });

  # ── Rollback on production failure ────────────────────────
  rollback:
    name: Rollback Production
    runs-on: ubuntu-latest
    needs: deploy-production
    if: failure()

    steps:
      - name: Execute rollback
        run: |
          echo "ALERT: Production deployment failed - initiating rollback"
          echo "  Rolling back to previous task definition..."
          echo "  Previous deployment restored"
          # In a real pipeline: aws ecs update-service --task-definition previous-revision

      - name: Notify team
        run: |
          echo "ROLLBACK NOTIFICATION sent to #incidents Slack channel"
          # In a real pipeline: call Slack webhook with rollback details
YAML

echo "Created: .github/workflows/lab024-cd.yml"

# ─────────────────────────────────────────────────────────────
# 2. Create rollback workflow
# ─────────────────────────────────────────────────────────────
section "2. Creating Manual Rollback Workflow"

cat >.github/workflows/lab024-rollback.yml <<'YAML'
name: "Lab 024 - Manual Rollback"

on:
  workflow_dispatch:
    inputs:
      environment:
        description: "Environment to roll back"
        type: environment
        required: true
      version:
        description: "Version/SHA to roll back to (blank = previous)"
        type: string
        required: false
      reason:
        description: "Reason for rollback (for audit log)"
        type: string
        required: true

jobs:
  rollback:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}

    steps:
      - name: Determine rollback target
        id: target
        run: |
          if [ -z "${{ inputs.version }}" ]; then
            echo "Rolling back to previous deployment"
            echo "version=previous" >> "$GITHUB_OUTPUT"
          else
            echo "Rolling back to version: ${{ inputs.version }}"
            echo "version=${{ inputs.version }}" >> "$GITHUB_OUTPUT"
          fi

      - name: Execute rollback
        run: |
          echo "=========================================="
          echo "  ROLLBACK INITIATED"
          echo "=========================================="
          echo "  Environment: ${{ inputs.environment }}"
          echo "  Target:      ${{ steps.target.outputs.version }}"
          echo "  Reason:      ${{ inputs.reason }}"
          echo "  Triggered by: ${{ github.actor }}"
          echo ""
          echo "  [simulated] Updating service to previous version..."
          echo "  [simulated] Waiting for service to stabilize..."
          echo "  [simulated] Health check passed"
          echo "  Rollback completed successfully"

      - name: Create rollback record
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `Rollback: ${{ inputs.environment }} - ${new Date().toISOString().split('T')[0]}`,
              body: `**Rollback executed**\n\n- **Environment:** ${{ inputs.environment }}\n- **Target version:** ${{ steps.target.outputs.version }}\n- **Reason:** ${{ inputs.reason }}\n- **Executed by:** @${{ github.actor }}\n- **Run:** [View](${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }})`,
              labels: ['rollback', 'ops']
            });
YAML

echo "Created: .github/workflows/lab024-rollback.yml"

# ─────────────────────────────────────────────────────────────
# 3. Blue-green deployment reference
# ─────────────────────────────────────────────────────────────
section "3. Deployment Strategy Reference"

echo ""
echo "Blue-Green Deployment:"
echo "  - Two identical environments (blue, green)"
echo "  - Traffic switches atomically via load balancer"
echo "  - Instant rollback by switching back"
echo "  - Zero downtime during deployment"
echo "  - Requires 2x infrastructure cost"

echo ""
echo "Rolling Deployment:"
echo "  - Instances updated one-by-one or in batches"
echo "  - No extra infrastructure needed"
echo "  - In-flight requests handled by old or new version during transition"
echo "  - kubectl rollout undo for Kubernetes rollback"

echo ""
echo "Canary Deployment:"
echo "  - Small percentage of traffic to new version"
echo "  - Monitor error rates and latency"
echo "  - Gradually increase or roll back based on metrics"

# ─────────────────────────────────────────────────────────────
# 4. Deployment tracking with gh api
# ─────────────────────────────────────────────────────────────
section "4. GitHub Deployments API Reference"

echo ""
echo "# List recent deployments:"
echo "gh api repos/OWNER/REPO/deployments \\"
echo "  --jq '.[] | {id, environment, sha: .sha[0:7], creator: .creator.login, created_at}'"

echo ""
echo "# Get statuses for a deployment:"
echo "gh api repos/OWNER/REPO/deployments/DEPLOY_ID/statuses \\"
echo "  --jq '.[] | {state, description, created_at}'"

echo ""
echo "# List deployments for a specific environment:"
echo "gh api 'repos/OWNER/REPO/deployments?environment=production' \\"
echo "  --jq '.[0] | {id, sha: .sha[0:7], created_at}'"

# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────
section "Cleanup"
rm -f .github/workflows/lab024-cd.yml
rm -f .github/workflows/lab024-rollback.yml
echo "Demo files removed"

section "Lab 024 Complete"
echo "Key takeaways:"
echo "  - workflow_run triggers CD only after CI succeeds"
echo "  - GitHub Environments with required reviewers gate production deployments"
echo "  - Smoke tests on staging catch issues CI missed"
echo "  - The Deployments API provides full audit trail in GitHub UI"
echo "  - A dedicated rollback workflow enables safe, audited recovery"
