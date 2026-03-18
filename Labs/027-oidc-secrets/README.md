# Lab 027 - OIDC and Secrets

## Introduction

- **OpenID Connect (OIDC)** enables GitHub Actions workflows to authenticate to cloud providers like AWS, GCP, and Azure **without storing long-lived credentials as secrets**.
- Instead of a static access key that never expires, your workflow receives a short-lived OIDC token from GitHub's identity provider, exchanges it for a cloud credential that expires when the job ends, and performs its work.
- This lab covers how OIDC tokens work, how to configure trust relationships on AWS, GCP, and Azure, the required workflow permissions, and why this approach is significantly more secure than static credentials.

---

## Why OIDC Is Better Than Static Credentials

### The Problem with Long-Lived Secrets

When you store `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in GitHub Secrets:

- The key is valid indefinitely until manually rotated
- If leaked via a log, a forked PR, or a compromised runner, it can be used from anywhere
- Rotation requires coordinating between the cloud IAM system and GitHub Secrets
- There's no automatic expiry - a compromised key stays compromised until someone notices

### OIDC Solves This

- Credentials are valid only for the duration of the workflow job (typically minutes)
- No static credentials to leak, rotate, or audit
- The cloud provider's trust policy specifies exactly which repository, branch, or environment can request credentials
- Fully auditable: cloud provider logs show the GitHub OIDC claims in every authentication event

---

## 1. OIDC Token Structure

When a job has `id-token: write` permission, GitHub's OIDC provider issues a JWT that contains claims about the workflow run:

```json
{
  "iss": "https://token.actions.githubusercontent.com",
  "sub": "repo:my-org/my-repo:ref:refs/heads/main",
  "aud": "https://github.com/my-org",
  "repository": "my-org/my-repo",
  "repository_owner": "my-org",
  "repository_visibility": "private",
  "ref": "refs/heads/main",
  "sha": "abc123...",
  "workflow": "Deploy to Production",
  "job_workflow_ref": "my-org/my-repo/.github/workflows/deploy.yml@refs/heads/main",
  "environment": "production",
  "actor": "octocat",
  "event_name": "push",
  "runner_environment": "github-hosted"
}
```

Cloud providers can restrict access based on any of these claims. The most important for security:

- **`sub`**: Uniquely identifies the repository, owner, and ref/environment
- **`environment`**: Can restrict a role to only be assumed from a specific GitHub Environment
- **`repository`**: Limits to a single repository
- **`repository_owner`**: Limits to an organization

---

## 2. Required Permissions

Any job that needs an OIDC token must declare:

```yaml
permissions:
  id-token: write # Request OIDC token from GitHub
  contents: read # Usually also needed for checkout
```

This can be set at the workflow level (applies to all jobs) or per-job.

---

## 3. AWS Federation with OIDC

### Step 1: Create an IAM Identity Provider in AWS

```bash
# Create the OIDC provider (one-time setup per AWS account)
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"
```

### Step 2: Create an IAM Role with Trust Policy

Save as `trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:my-org/my-repo:*"
        }
      }
    }
  ]
}
```

For production-only access (restricts to the `production` environment):

```json
{
  "StringEquals": {
    "token.actions.githubusercontent.com:sub": "repo:my-org/my-repo:environment:production"
  }
}
```

```bash
aws iam create-role \
  --role-name GitHubActionsDeployRole \
  --assume-role-policy-document file://trust-policy.json

aws iam attach-role-policy \
  --role-name GitHubActionsDeployRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess
```

### Step 3: Workflow Using OIDC

```yaml
name: Deploy to AWS

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsDeployRole
          aws-region: us-east-1
          role-session-name: GitHubActions-${{ github.run_id }}

      - name: Deploy to ECS
        run: |
          aws ecs update-service \
            --cluster prod-cluster \
            --service myapp \
            --force-new-deployment

      - name: Verify deployment
        run: aws ecs wait services-stable --cluster prod-cluster --services myapp
```

---

## 4. GCP Federation with OIDC (Workload Identity Federation)

### Setup (one-time in GCP)

```bash
# Create a Workload Identity Pool
gcloud iam workload-identity-pools create "github-pool" \
  --project="my-gcp-project" \
  --location="global" \
  --display-name="GitHub Actions Pool"

# Create a provider within the pool
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project="my-gcp-project" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub Actions Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Allow the GitHub repo to impersonate a service account
gcloud iam service-accounts add-iam-policy-binding \
  "deploy-sa@my-gcp-project.iam.gserviceaccount.com" \
  --project="my-gcp-project" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/my-org/my-repo"
```

### GCP Workflow

```yaml
name: Deploy to GCP

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Authenticate to GCP (OIDC)
        id: auth
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider
          service_account: deploy-sa@my-gcp-project.iam.gserviceaccount.com

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Deploy to Cloud Run
        run: |
          gcloud run deploy myapp \
            --image gcr.io/my-gcp-project/myapp:${{ github.sha }} \
            --region us-central1 \
            --platform managed

      - name: Verify deployment
        run: |
          gcloud run services describe myapp \
            --region us-central1 \
            --format 'value(status.url)'
```

---

## 5. Azure Federation with OIDC

### Setup (one-time in Azure)

```bash
# Create a federated credential on an App Registration or Managed Identity
az ad app federated-credential create \
  --id APP_OBJECT_ID \
  --parameters '{
    "name": "github-actions-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:my-org/my-repo:ref:refs/heads/main",
    "description": "GitHub Actions main branch",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### Azure Workflow

```yaml
name: Deploy to Azure

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Log in to Azure (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Deploy to Azure Web App
        uses: azure/webapps-deploy@v3
        with:
          app-name: myapp
          slot-name: production

      - name: Azure logout
        if: always()
        run: az logout
```

Note: For Azure, the client-id, tenant-id, and subscription-id are not sensitive (they're identifiers, not secrets) but are stored in secrets for tidiness.

---

## 6. OIDC Token Inspection

You can inspect the raw OIDC token during development to understand its claims:

```yaml
- name: Get OIDC token for inspection
  run: |
    TOKEN=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r '.value')
    # Decode the JWT payload (middle section)
    echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq .
```

---

## 7. Per-Job OIDC Rotation

Each job in a workflow gets a **separate OIDC token** with its own `jti` (JWT ID) claim, ensuring tokens cannot be reused across jobs:

```yaml
jobs:
  job1:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
    environment: staging
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.STAGING_ROLE_ARN }}
          aws-region: us-east-1
      # This token is only valid for job1's duration

  job2:
    runs-on: ubuntu-latest
    needs: job1
    permissions:
      id-token: write
    environment: production
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.PROD_ROLE_ARN }}
          aws-region: us-east-1
      # A completely new token is issued for job2
```

---

## Hands-on

1. Write a workflow step that requests an OIDC token and prints its `sub` claim:

   ??? success "Solution"
   `bash
    cat > .github/workflows/oidc-inspect.yml << 'EOF'
    name: OIDC Inspect
    on: [workflow_dispatch]
    permissions:
      id-token: write
      contents: read
    jobs:
      inspect:
        runs-on: ubuntu-latest
        steps:
          - name: Get and print OIDC subject claim
            run: |
              TOKEN=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
                "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r '.value')
              echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq -r '.sub'
    EOF
    git add .github/workflows/oidc-inspect.yml && git commit -m "ci: add OIDC token inspection workflow"
    `

2. Add `permissions: id-token: write` to a workflow and verify the token is issued:

   ??? success "Solution"
   `bash
    cat > .github/workflows/oidc-check.yml << 'EOF'
    name: OIDC Check
    on: [workflow_dispatch]
    permissions:
      id-token: write
      contents: read
    jobs:
      check:
        runs-on: ubuntu-latest
        steps:
          - run: echo "ACTIONS_ID_TOKEN_REQUEST_URL=$ACTIONS_ID_TOKEN_REQUEST_URL"
    EOF
    git add .github/workflows/oidc-check.yml && git commit -m "ci: verify id-token permission"
    `

3. Decode the JWT payload of an OIDC token using `python3` to inspect all claims:

   ??? success "Solution"
   `bash
    TOKEN=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r '.value')
    python3 -c "
    import base64, json, sys
    payload = sys.argv[1].split('.')[1]
    payload += '=' * (4 - len(payload) % 4)
    print(json.dumps(json.loads(base64.b64decode(payload)), indent=2))
    " "$TOKEN"
    `

4. Write the AWS OIDC federation workflow using `aws-actions/configure-aws-credentials` and print the caller identity:

   ??? success "Solution"
   `bash
    cat > .github/workflows/aws-oidc.yml << 'EOF'
    name: AWS OIDC
    on: [workflow_dispatch]
    permissions:
      id-token: write
      contents: read
    jobs:
      deploy:
        runs-on: ubuntu-latest
        steps:
          - uses: aws-actions/configure-aws-credentials@v4
            with:
              role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
              aws-region: us-east-1
          - run: aws sts get-caller-identity
    EOF
    git add .github/workflows/aws-oidc.yml && git commit -m "ci: add AWS OIDC federation workflow"
    `

5. List the OIDC claims available from the GitHub context by decoding the full JWT payload:

   ??? success "Solution"
   `bash
    TOKEN=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=sts.amazonaws.com" | jq -r '.value')
    echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool | grep -E '"(sub|iss|aud|repository|ref|sha|workflow|actor|environment)"'
    `

## Exercises

### Exercise 1 - OIDC Token Inspection

Add a step to a workflow that retrieves and decodes the OIDC JWT payload. Identify the `sub`, `iss`, `repository`, and `environment` claims.

### Exercise 2 - AWS Setup

Set up an AWS IAM Identity Provider for GitHub Actions OIDC. Create an IAM role with a trust policy restricted to a specific repository. Use it in a workflow that runs `aws sts get-caller-identity`.

### Exercise 3 - Environment Restriction

Modify the AWS trust policy to only allow role assumption from the `production` GitHub Environment. Verify that a job without the `environment:` key cannot assume the role.

### Exercise 4 - Multi-Cloud Comparison

Create a workflow with three jobs: one each for AWS, GCP, and Azure. Each job authenticates with OIDC and prints the authenticated identity. Compare the setup complexity.

---

## Summary

- OIDC eliminates long-lived cloud credentials by issuing short-lived tokens that expire when the job ends
- `permissions: id-token: write` is required at the job or workflow level to request an OIDC token
- The OIDC `sub` claim encodes the exact source: `repo:{owner}/{repo}:environment:{env}` or `ref:refs/heads/{branch}`
- AWS uses `sts:AssumeRoleWithWebIdentity`; GCP uses Workload Identity Federation; Azure uses Federated Credentials on an App Registration
- Trust policies on the cloud provider side should be as narrow as possible - restrict to specific repositories, branches, or environments
- Each job in a workflow receives a distinct OIDC token (unique `jti`), preventing token reuse across jobs
- OIDC tokens can be decoded locally with `base64 -d` to inspect claims during setup and debugging
