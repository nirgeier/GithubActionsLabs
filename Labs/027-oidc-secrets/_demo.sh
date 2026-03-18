#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 027 - OIDC and Secrets Demo"

# ─────────────────────────────────────────────────────────────
# 1. Create OIDC workflow for AWS
# ─────────────────────────────────────────────────────────────
section "1. Creating AWS OIDC Workflow"

mkdir -p .github/workflows

cat >.github/workflows/lab027-oidc-aws.yml <<'YAML'
name: "Lab 027 - AWS OIDC Authentication"

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  id-token: write    # REQUIRED: request OIDC token from GitHub
  contents: read

jobs:
  deploy-aws:
    name: Deploy via AWS OIDC
    runs-on: ubuntu-latest
    environment: production

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC - no static keys!)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
          role-session-name: GitHubActions-${{ github.run_id }}

      - name: Verify AWS identity
        run: aws sts get-caller-identity

      - name: Deploy to ECS
        run: |
          aws ecs update-service \
            --cluster prod-cluster \
            --service myapp \
            --force-new-deployment \
            --region us-east-1

      - name: Wait for deployment to stabilize
        run: |
          aws ecs wait services-stable \
            --cluster prod-cluster \
            --services myapp \
            --region us-east-1
YAML

echo "Created: .github/workflows/lab027-oidc-aws.yml"

# ─────────────────────────────────────────────────────────────
# 2. Create GCP OIDC workflow
# ─────────────────────────────────────────────────────────────
section "2. Creating GCP Workload Identity Federation Workflow"

cat >.github/workflows/lab027-oidc-gcp.yml <<'YAML'
name: "Lab 027 - GCP Workload Identity Federation"

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  deploy-gcp:
    name: Deploy via GCP OIDC
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Authenticate to GCP (Workload Identity Federation)
        id: auth
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Verify GCP identity
        run: gcloud auth list

      - name: Deploy to Cloud Run
        run: |
          gcloud run deploy myapp \
            --image gcr.io/${{ secrets.GCP_PROJECT_ID }}/myapp:${{ github.sha }} \
            --region us-central1 \
            --platform managed \
            --quiet

      - name: Get Cloud Run URL
        run: |
          gcloud run services describe myapp \
            --region us-central1 \
            --format 'value(status.url)'
YAML

echo "Created: .github/workflows/lab027-oidc-gcp.yml"

# ─────────────────────────────────────────────────────────────
# 3. Create Azure OIDC workflow
# ─────────────────────────────────────────────────────────────
section "3. Creating Azure Federated Identity Workflow"

cat >.github/workflows/lab027-oidc-azure.yml <<'YAML'
name: "Lab 027 - Azure OIDC Authentication"

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  deploy-azure:
    name: Deploy via Azure OIDC
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Log in to Azure (Federated Identity)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          # Note: client-id/tenant-id/subscription-id are identifiers, not secrets
          # but stored as secrets for clean YAML

      - name: Verify Azure identity
        run: az account show

      - name: Deploy to Azure Web App
        uses: azure/webapps-deploy@v3
        with:
          app-name: ${{ secrets.AZURE_APP_NAME }}
          slot-name: production

      - name: Logout from Azure
        if: always()
        run: az logout
YAML

echo "Created: .github/workflows/lab027-oidc-azure.yml"

# ─────────────────────────────────────────────────────────────
# 4. Show OIDC token structure
# ─────────────────────────────────────────────────────────────
section "4. OIDC Token Claims Reference"

echo ""
echo "A GitHub OIDC token (JWT) contains these claims:"
echo ""
cat <<'JSON'
{
  "iss": "https://token.actions.githubusercontent.com",
  "sub": "repo:my-org/my-repo:environment:production",
  "aud": "sts.amazonaws.com",
  "repository": "my-org/my-repo",
  "repository_owner": "my-org",
  "repository_visibility": "private",
  "ref": "refs/heads/main",
  "sha": "abc123def456...",
  "workflow": "Deploy to Production",
  "job_workflow_ref": "my-org/my-repo/.github/workflows/deploy.yml@refs/heads/main",
  "environment": "production",
  "actor": "octocat",
  "event_name": "push",
  "runner_environment": "github-hosted",
  "exp": 1700000000,
  "iat": 1699999400,
  "jti": "unique-token-id-per-job"
}
JSON

echo ""
echo "Key claims for trust policy restrictions:"
echo "  sub:         Uniquely identifies repo + ref/environment"
echo "  repository:  Restrict to a specific repository"
echo "  environment: Restrict to a specific GitHub Environment"
echo "  actor:       Who triggered the workflow"
echo "  jti:         Unique per job - prevents token reuse"

# ─────────────────────────────────────────────────────────────
# 5. Show AWS IAM trust policy examples
# ─────────────────────────────────────────────────────────────
section "5. AWS IAM Trust Policy Examples"

echo ""
echo "# Restrict to any ref in a specific repository:"
cat <<'JSON'
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:my-org/my-repo:*"
    }
  }
}
JSON

echo ""
echo "# Restrict to production environment only:"
cat <<'JSON'
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:my-org/my-repo:environment:production"
    }
  }
}
JSON

echo ""
echo "# Restrict to main branch only:"
cat <<'JSON'
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:sub": "repo:my-org/my-repo:ref:refs/heads/main"
    }
  }
}
JSON

# ─────────────────────────────────────────────────────────────
# 6. OIDC token inspection step
# ─────────────────────────────────────────────────────────────
section "6. Inspecting the OIDC Token (Debug Step)"

echo ""
echo "Add this step to inspect the OIDC token claims during debugging:"
echo ""
cat <<'YAML'
- name: Inspect OIDC token claims
  run: |
    TOKEN=$(curl -sS \
      -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" \
      | jq -r '.value')

    # Decode the JWT payload (base64url → JSON)
    echo "=== OIDC Token Claims ==="
    echo $TOKEN \
      | cut -d. -f2 \
      | tr '_-' '/+' \
      | base64 -d 2>/dev/null \
      | jq '{sub, iss, repository, environment, actor, ref, event_name}'
YAML

# ─────────────────────────────────────────────────────────────
# 7. Show comparison: OIDC vs static credentials
# ─────────────────────────────────────────────────────────────
section "7. OIDC vs Static Credentials Comparison"

echo ""
printf "%-30s %-25s %-25s\n" "PROPERTY" "STATIC KEYS" "OIDC"
printf "%-30s %-25s %-25s\n" "──────────────────────────" "───────────────────────" "───────────────────────"
printf "%-30s %-25s %-25s\n" "Credential lifetime" "Indefinite" "Job duration (~minutes)"
printf "%-30s %-25s %-25s\n" "Rotation required" "Yes (manual)" "Automatic"
printf "%-30s %-25s %-25s\n" "Stored in GitHub Secrets" "Yes" "No (only IDs)"
printf "%-30s %-25s %-25s\n" "Blast radius if leaked" "Until rotated" "Minutes (already expired)"
printf "%-30s %-25s %-25s\n" "Scope restriction" "IAM policy only" "IAM policy + trust policy"
printf "%-30s %-25s %-25s\n" "Cloud setup required" "Create IAM user/key" "Create IdP + role"

# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────
section "Cleanup"
rm -f .github/workflows/lab027-oidc-aws.yml
rm -f .github/workflows/lab027-oidc-gcp.yml
rm -f .github/workflows/lab027-oidc-azure.yml
echo "Demo files removed"

section "Lab 027 Complete"
echo "Key takeaways:"
echo "  - OIDC tokens are short-lived (job duration) - no static credentials to leak"
echo "  - permissions: id-token: write is required to request the OIDC token"
echo "  - AWS uses sts:AssumeRoleWithWebIdentity via aws-actions/configure-aws-credentials"
echo "  - GCP uses Workload Identity Federation via google-github-actions/auth"
echo "  - Azure uses Federated Identity Credentials via azure/login"
echo "  - Trust policies should restrict to specific repo + environment for least privilege"
