# Lab 018 - Environments and Deployments

## Introduction

- GitHub Environments provide a mechanism to control and track deployments.
- An environment can require manual approval before a deployment proceeds, restrict which branches can deploy to it, hold environment-specific secrets and variables, and maintain a full deployment history.
- This lab covers creating environments, setting up protection rules, using environment-specific secrets and variables, and building a complete staging-to-production deployment pipeline.

---

## What Is a GitHub Environment?

An environment in GitHub is a named deployment target (e.g., `staging`, `production`) with:

- **Protection rules** - required reviewers, wait timers, branch restrictions
- **Secrets** - credentials specific to that environment (override repository secrets)
- **Variables** - non-secret configuration values for that environment
- **Deployment history** - a timeline of all deployments to that environment
- **Deployment status** - shown on PRs and commits

---

## Creating Environments

Environments are created in the repository settings:

1. Go to **Settings** > **Environments** > **New environment**
2. Name the environment (e.g., `staging`, `production`)
3. Configure protection rules

Or via the GitHub CLI:

```bash
gh api repos/owner/repo/environments/staging -X PUT \
  --field wait_timer=0 \
  --field prevent_self_review=false
```

---

## Using an Environment in a Workflow Job

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - run: echo "Deploying to production"
```

The `environment:` key can also specify a URL for the deployment:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://my-app.example.com
    steps:
      - run: ./deploy.sh
```

---

## Required Reviewers (Deployment Gates)

When a job targets an environment with required reviewers, the workflow pauses and waits for approval before the job runs.

```
Push to main → CI passes → Deploy to staging (auto) → Deploy to production (REQUIRES APPROVAL)
```

Configuration is done in the GitHub UI under environment settings. In the workflow, the job will simply reference the environment:

```yaml
jobs:
  deploy-production:
    runs-on: ubuntu-latest
    environment: production # This environment has required reviewers configured
    steps:
      - run: ./deploy.sh production
```

---

## Wait Timer

A wait timer delays the deployment by a specified number of minutes after the workflow run is triggered:

```yaml
# In environment settings: Wait timer = 10 minutes
# The job below will wait 10 minutes before starting
jobs:
  deploy-production:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - run: echo "Started after 10-minute wait timer"
```

---

## Environment-Specific Secrets and Variables

### Secrets

Environment secrets override repository secrets of the same name:

```yaml
jobs:
  deploy-staging:
    environment: staging
    steps:
      - run: deploy.sh --token "${{ secrets.API_TOKEN }}"
        # Uses STAGING API_TOKEN (from environment), overriding repo-level API_TOKEN

  deploy-production:
    environment: production
    steps:
      - run: deploy.sh --token "${{ secrets.API_TOKEN }}"
        # Uses PRODUCTION API_TOKEN
```

### Variables

Environment variables (non-secret config) are referenced via `vars` context:

```yaml
jobs:
  deploy:
    environment: production
    steps:
      - run: |
          echo "Deploying to region: ${{ vars.DEPLOY_REGION }}"
          echo "App version: ${{ vars.APP_VERSION }}"
          echo "Replica count: ${{ vars.REPLICA_COUNT }}"
```

---

## Branch Protection Rules for Environments

Restrict which branches can deploy to an environment. In environment settings, configure **Deployment branches**:

- **All branches** (default)
- **Protected branches only**
- **Selected branches** - specify branch name patterns like `main`, `release/*`

This ensures only trusted branches can trigger production deployments.

---

## Complete Staging → Production Pipeline

```yaml
name: Deploy Pipeline

on:
  push:
    branches: [main]

permissions: {}

jobs:
  test:
    name: Run Tests
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
    name: Build Application
    runs-on: ubuntu-latest
    needs: test
    permissions:
      contents: read
    outputs:
      artifact-name: ${{ steps.artifact.outputs.name }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci && npm run build
      - id: artifact
        run: echo "name=dist-${{ github.sha }}" >> "$GITHUB_OUTPUT"
      - uses: actions/upload-artifact@v4
        with:
          name: ${{ steps.artifact.outputs.name }}
          path: dist/
          retention-days: 7

  deploy-staging:
    name: Deploy to Staging
    runs-on: ubuntu-latest
    needs: build
    environment:
      name: staging
      url: ${{ steps.deploy.outputs.url }}
    permissions:
      contents: read
      deployments: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact-name }}
          path: dist/

      - name: Deploy to staging
        id: deploy
        env:
          DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
          API_URL: ${{ vars.API_URL }}
          REGION: ${{ vars.DEPLOY_REGION }}
        run: |
          echo "Deploying to staging..."
          echo "API URL  : $API_URL"
          echo "Region   : $REGION"
          # ./scripts/deploy.sh --env staging --region "$REGION"
          echo "url=https://staging.example.com" >> "$GITHUB_OUTPUT"

      - name: Run smoke tests
        run: |
          echo "Running smoke tests on staging..."
          # curl -sf https://staging.example.com/health

  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: deploy-staging
    # 'production' environment has:
    #   - required reviewers (manual approval gate)
    #   - wait timer of 10 minutes
    #   - branch filter: main only
    environment:
      name: production
      url: ${{ steps.deploy.outputs.url }}
    permissions:
      contents: read
      deployments: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact-name }}
          path: dist/

      - name: Deploy to production
        id: deploy
        env:
          DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
          API_URL: ${{ vars.API_URL }}
          REGION: ${{ vars.DEPLOY_REGION }}
        run: |
          echo "Deploying to production..."
          echo "API URL  : $API_URL"
          echo "Region   : $REGION"
          # ./scripts/deploy.sh --env production --region "$REGION"
          echo "url=https://www.example.com" >> "$GITHUB_OUTPUT"

      - name: Notify deployment
        run: echo "Production deployment complete: ${{ steps.deploy.outputs.url }}"
```

---

## Multi-Region Deployment with Environments

```yaml
name: Multi-Region Deploy

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      artifact: dist-${{ github.sha }}
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm run build
      - uses: actions/upload-artifact@v4
        with:
          name: dist-${{ github.sha }}
          path: dist/

  deploy-us-staging:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: staging-us
      url: https://us-staging.example.com
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact }}
          path: dist/
      - run: |
          echo "Deploying to US staging..."
          echo "Region: ${{ vars.REGION }}"

  deploy-eu-staging:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: staging-eu
      url: https://eu-staging.example.com
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact }}
          path: dist/
      - run: |
          echo "Deploying to EU staging..."
          echo "Region: ${{ vars.REGION }}"

  deploy-production:
    needs: [deploy-us-staging, deploy-eu-staging]
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://www.example.com
    strategy:
      matrix:
        region: [us-east-1, eu-west-1, ap-southeast-1]
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact }}
          path: dist/
      - run: echo "Deploying to ${{ matrix.region }}"
```

---

## Deployment Status in Pull Requests

When a job uses `environment:` and has `deployments: write` permission, GitHub automatically creates a deployment record visible in the PR's checks section.

The deployment status transitions through:

- `queued` → `in_progress` → `success` / `failure`

The URL specified in `environment.url` becomes a clickable link in the PR.

---

## Deployment History and Rollback

GitHub maintains a deployment history for each environment. You can:

1. View deployment history in the repository's **Deployments** tab
2. See which commit each deployment was built from
3. Use the GitHub API or UI to trigger a re-deployment of a previous commit

For rollback support in your pipeline:

```yaml
jobs:
  rollback:
    runs-on: ubuntu-latest
    environment: production
    if: ${{ github.event.inputs.rollback == 'true' }}
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.inputs.target-sha }}
      - run: ./scripts/deploy.sh --sha "${{ github.event.inputs.target-sha }}"
```

---

## Hands-on

1. Create a `staging` environment in your repository using `gh api`:

   ??? success "Solution"
   `bash
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    gh api repos/$REPO/environments/staging -X PUT \
      --field wait_timer=0 \
      --field prevent_self_review=false
    gh api repos/$REPO/environments | jq '.environments[].name'
    `

2. Add a required reviewer to the `production` environment using `gh api`:

   ??? success "Solution"
   `bash
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    ME=$(gh api user -q .login)
    USER_ID=$(gh api user -q .id)
    gh api repos/$REPO/environments/production -X PUT \
      --field wait_timer=0 \
      --field 'reviewers=[{"type":"User","id":'"$USER_ID"'}]'
    gh api repos/$REPO/environments/production | jq '.protection_rules'
    `

3. Write a workflow that deploys to `staging` automatically, then waits for `production` via its environment protection rules:

   ??? success "Solution"
   `bash
    cat > .github/workflows/deploy-pipeline.yml << 'EOF'
    name: Deploy Pipeline
    on:
      push:
        branches: [main]
    jobs:
      deploy-staging:
        runs-on: ubuntu-latest
        environment:
          name: staging
          url: https://staging.example.com
        steps:
          - run: echo "Deploying to staging"
      deploy-production:
        runs-on: ubuntu-latest
        needs: deploy-staging
        environment:
          name: production
          url: https://www.example.com
        steps:
          - run: echo "Deploying to production"
    EOF
    `

4. Check the deployment status of the latest run using `gh api deployments`:

   ??? success "Solution"
   `bash
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    gh api repos/$REPO/deployments \
      | jq '[.[] | {id, environment, created_at, ref}] | .[0:5]'
    gh api repos/$REPO/deployments/$(gh api repos/$REPO/deployments -q '.[0].id') \
      | jq '{environment, id}'
    `

5. List all secrets configured for the `staging` environment using `gh api`:

   ??? success "Solution"
   `bash
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    gh api repos/$REPO/environments/staging/secrets \
      | jq '.secrets[] | {name, created_at, updated_at}'
    `

## Exercises

### Exercise 1 - Create and Configure Environments

Using the GitHub UI:

1. Create `staging` and `production` environments
2. Add a required reviewer to `production`
3. Set a 5-minute wait timer on `production`
4. Restrict `production` to the `main` branch

### Exercise 2 - Environment Secrets

Add environment-specific `DEPLOY_TOKEN` and `DATABASE_URL` secrets to both staging and production. Verify the correct value is used in each environment job.

### Exercise 3 - Environment Variables

Add a `REPLICA_COUNT` variable to staging (set to `1`) and production (set to `3`). Print the value in a deployment step.

### Exercise 4 - Full Pipeline

Build a complete CI/CD pipeline with:

1. Test job
2. Build job producing an artifact
3. Staging deployment (auto-approve)
4. Production deployment (manual approval required)

### Exercise 5 - Deployment URL

Add a deployment URL to a job's `environment:` block. Verify it appears as a link in the GitHub PR checks and Deployments tab.

---

## Summary

- GitHub Environments (`environment: name`) attach protection rules, secrets, and variables to a specific deployment target and create a visible deployment record in the GitHub UI
- Required reviewers pause the workflow at the job level, requiring one or more named individuals or teams to approve before the job runs
- Wait timers introduce a mandatory delay (in minutes) between when the job is triggered and when it begins, allowing time for a potential abort
- Environment secrets override repository secrets of the same name, enabling different credentials per environment without changing the workflow file
- The `vars` context provides environment-level non-secret configuration (e.g., region, replica count, API URL)
- The `environment.url` field populates a clickable deployment link in the PR checks section and the Deployments tab
- Deployment history is automatically maintained per environment, enabling auditability and supporting rollback workflows
