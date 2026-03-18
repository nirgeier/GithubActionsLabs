# Lab 024 - CD Pipeline

## Introduction

- **Continuous Deployment (CD)** takes a passing CI build and automatically promotes it through deployment environments - typically staging (or dev), followed by production.
- The key challenges in CD are: ensuring you never deploy broken code, giving humans the opportunity to approve changes before they reach production, and recovering quickly when something goes wrong.
- This lab builds a complete CD pipeline that chains off CI, deploys to staging with automated smoke tests, gates production with an environment approval, demonstrates blue-green and rolling deployment patterns, and triggers automatic rollback on failure.

---

## CD Pipeline Philosophy

A good CD pipeline has these properties:

- **Only deploys green builds**: CD is triggered by CI success, never by a raw push
- **Staging validates assumptions**: Automated smoke tests on staging catch issues CI missed
- **Production requires approval**: Human eyes on the "go" button for production
- **Rollback is automated**: If production health checks fail, the previous version is restored
- **Everything is auditable**: GitHub Deployments API tracks every deployment with actor, timestamp, and status

---

## 1. Triggering CD from CI

The cleanest pattern is to trigger CD via `workflow_run`, which fires when another workflow completes:

```yaml
name: CD Pipeline

on:
  workflow_run:
    workflows: ["CI Pipeline"]
    types: [completed]
    branches: [main]

jobs:
  check-ci:
    runs-on: ubuntu-latest
    if: github.event.workflow_run.conclusion == 'success'
    steps:
      - run: echo "CI passed, proceeding with deployment"
```

Alternatively, chain them in a single workflow using `needs:` and trigger on push to main:

```yaml
on:
  push:
    branches: [main]

jobs:
  ci:
    # ... CI jobs ...

  deploy-staging:
    needs: [lint, test, build]
    # ...
```

---

## 2. Complete CD Workflow

```yaml
name: CD Pipeline

on:
  workflow_run:
    workflows: ["CI Pipeline"]
    types: [completed]
    branches: [main]

permissions:
  contents: read
  deployments: write
  packages: read
  id-token: write # for OIDC

env:
  IMAGE: ghcr.io/${{ github.repository }}

jobs:
  # ─────────────────────────────────────────────
  # Guard: only proceed if CI passed
  # ─────────────────────────────────────────────
  check-ci:
    name: Check CI Status
    runs-on: ubuntu-latest
    if: github.event.workflow_run.conclusion == 'success'
    outputs:
      sha: ${{ github.event.workflow_run.head_sha }}
    steps:
      - run: echo "Deploying SHA ${{ github.event.workflow_run.head_sha }}"

  # ─────────────────────────────────────────────
  # JOB 1: Deploy to Staging
  # ─────────────────────────────────────────────
  deploy-staging:
    name: Deploy to Staging
    runs-on: ubuntu-latest
    needs: check-ci
    environment:
      name: staging
      url: https://staging.myapp.com

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
              description: 'CD: staging deploy'
            });
            core.setOutput('id', data.id);

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_STAGING_ROLE_ARN }}
          aws-region: us-east-1

      - name: Deploy to ECS (staging)
        run: |
          aws ecs update-service \
            --cluster staging-cluster \
            --service myapp-staging \
            --force-new-deployment \
            --region us-east-1

      - name: Wait for stable deployment
        run: |
          aws ecs wait services-stable \
            --cluster staging-cluster \
            --services myapp-staging \
            --region us-east-1

      - name: Run smoke tests
        id: smoke
        run: |
          echo "Running smoke tests against staging..."
          curl --fail --retry 3 --retry-delay 5 https://staging.myapp.com/health
          curl --fail https://staging.myapp.com/api/version

      - name: Update deployment status (success)
        if: success()
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.repos.createDeploymentStatus({
              owner: context.repo.owner,
              repo: context.repo.repo,
              deployment_id: ${{ steps.deployment.outputs.id }},
              state: 'success',
              environment_url: 'https://staging.myapp.com',
              description: 'Staging deployment successful'
            });

      - name: Update deployment status (failure)
        if: failure()
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.repos.createDeploymentStatus({
              owner: context.repo.owner,
              repo: context.repo.repo,
              deployment_id: ${{ steps.deployment.outputs.id }},
              state: 'failure',
              description: 'Staging deployment failed'
            });

  # ─────────────────────────────────────────────
  # JOB 2: Deploy to Production (requires approval)
  # ─────────────────────────────────────────────
  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: deploy-staging
    environment:
      name: production # This environment has required reviewers configured
      url: https://myapp.com

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
              required_contexts: [],
              description: 'CD: production deploy'
            });
            core.setOutput('id', data.id);

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_PROD_ROLE_ARN }}
          aws-region: us-east-1

      - name: Deploy to production (blue-green)
        run: |
          # Update the "blue" target group with the new image
          aws ecs update-service \
            --cluster prod-cluster \
            --service myapp-production \
            --force-new-deployment \
            --region us-east-1

      - name: Wait for stable deployment
        id: wait-stable
        run: |
          aws ecs wait services-stable \
            --cluster prod-cluster \
            --services myapp-production \
            --region us-east-1

      - name: Production health check
        id: health
        run: |
          for i in 1 2 3 4 5; do
            if curl --fail --silent https://myapp.com/health; then
              echo "Health check passed"
              exit 0
            fi
            sleep 10
          done
          echo "Health check failed after 5 attempts"
          exit 1

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
              environment_url: 'https://myapp.com',
            });

  # ─────────────────────────────────────────────
  # JOB 3: Rollback on production failure
  # ─────────────────────────────────────────────
  rollback-production:
    name: Rollback Production
    runs-on: ubuntu-latest
    needs: deploy-production
    if: failure()

    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_PROD_ROLE_ARN }}
          aws-region: us-east-1

      - name: Rollback ECS service to previous task definition
        run: |
          # Get the previous task definition revision
          CURRENT=$(aws ecs describe-services \
            --cluster prod-cluster \
            --services myapp-production \
            --query 'services[0].taskDefinition' \
            --output text)
          PREV_REV=$(( $(echo $CURRENT | grep -oP ':\d+$' | tr -d ':') - 1 ))
          FAMILY=$(echo $CURRENT | cut -d: -f1 | awk -F/ '{print $NF}')
          PREV_TASK="${FAMILY}:${PREV_REV}"
          echo "Rolling back to $PREV_TASK"
          aws ecs update-service \
            --cluster prod-cluster \
            --service myapp-production \
            --task-definition "$PREV_TASK"

      - name: Notify team of rollback
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": ":rotating_light: *Production rollback triggered!*\nRepo: ${{ github.repository }}\nActor: ${{ github.actor }}\n<${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View run>"
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK

  # ─────────────────────────────────────────────
  # JOB 4: Notify on success
  # ─────────────────────────────────────────────
  notify-success:
    name: Notify Successful Deployment
    runs-on: ubuntu-latest
    needs: deploy-production
    if: success()

    steps:
      - name: Post success notification
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": ":white_check_mark: *Production deployment successful!*\nVersion: ${{ needs.check-ci.outputs.sha }}\nDeployed by: ${{ github.actor }}"
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK
```

---

## 3. Blue-Green Deployment Pattern

Blue-green deployments maintain two identical production environments. Traffic switches between them atomically:

```yaml
- name: Blue-green deploy via ALB listener rule
  run: |
    # Determine current active color
    CURRENT=$(aws elbv2 describe-listener-rules \
      --listener-arn ${{ secrets.ALB_LISTENER_ARN }} \
      --query 'Rules[?Priority==`1`].Actions[0].TargetGroupArn' \
      --output text)

    BLUE_TG=${{ secrets.BLUE_TARGET_GROUP_ARN }}
    GREEN_TG=${{ secrets.GREEN_TARGET_GROUP_ARN }}

    if [ "$CURRENT" = "$BLUE_TG" ]; then
      NEW_TG=$GREEN_TG
      echo "Switching from blue to green"
    else
      NEW_TG=$BLUE_TG
      echo "Switching from green to blue"
    fi

    # Deploy new version to inactive environment first
    aws ecs update-service \
      --cluster prod-cluster \
      --service "myapp-$([ '$NEW_TG' = '$BLUE_TG' ] && echo blue || echo green)" \
      --force-new-deployment

    # Wait for new version to be healthy
    sleep 30

    # Switch traffic
    aws elbv2 modify-listener \
      --listener-arn ${{ secrets.ALB_LISTENER_ARN }} \
      --default-actions Type=forward,TargetGroupArn=$NEW_TG
```

---

## 4. Rolling Deployment Pattern

Rolling deployments update instances incrementally, reducing risk while avoiding the need for double infrastructure:

```yaml
- name: Rolling deploy to Kubernetes
  run: |
    # Update the image in the deployment
    kubectl set image deployment/myapp \
      myapp=ghcr.io/${{ github.repository }}:${{ github.sha }} \
      --record

    # Monitor the rollout
    kubectl rollout status deployment/myapp --timeout=5m

- name: Rollback on failure
  if: failure()
  run: kubectl rollout undo deployment/myapp
```

---

## 5. Manual Rollback Workflow

Provide an on-demand rollback workflow triggered by dispatch:

```yaml
name: Manual Rollback

on:
  workflow_dispatch:
    inputs:
      environment:
        description: "Environment to roll back"
        type: environment
        required: true
      version:
        description: "Version to roll back to (blank = previous)"
        type: string
        required: false

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
          else
            echo "Rolling back to version ${{ inputs.version }}"
          fi

      - name: Execute rollback
        run: |
          echo "Rolling back ${{ inputs.environment }}..."
          # Implement environment-specific rollback logic here
```

---

## 6. Deployment Tracking with GitHub Deployments API

The GitHub Deployments API provides a full audit trail. Key states: `pending`, `in_progress`, `success`, `failure`, `inactive`:

```bash
# List deployments for a repo
gh api repos/OWNER/REPO/deployments \
  --jq '.[] | {id, environment, sha: .sha[0:7], created_at}'

# Get deployment statuses for a specific deployment
gh api repos/OWNER/REPO/deployments/DEPLOY_ID/statuses \
  --jq '.[] | {state, description, created_at}'
```

---

## Hands-on

1. Create a workflow that deploys to staging on every push to `main` using `echo` to simulate the deployment:

   ??? success "Solution"
   `bash
    mkdir -p .github/workflows
    cat > .github/workflows/cd.yml << 'EOF'
    name: CD Pipeline
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
          - uses: actions/checkout@v4
          - run: echo "Deploying SHA $GITHUB_SHA to staging"
    EOF
    git add .github/workflows/cd.yml && git commit -m "cd: deploy to staging on push to main"
    `

2. Add a production job with an `environment: production` gate requiring a manual reviewer:

   ??? success "Solution"
   `bash
    gh api repos/OWNER/REPO/environments/production \
      --method PUT \
      --field wait_timer=0
    `

3. Write a manual rollback workflow triggered by `workflow_dispatch` with an environment input:

   ??? success "Solution"
   `bash
    cat > .github/workflows/rollback.yml << 'EOF'
    name: Manual Rollback
    on:
      workflow_dispatch:
        inputs:
          environment:
            description: "Environment to roll back"
            type: environment
            required: true
          version:
            description: "Version to roll back to (blank = previous)"
            type: string
            required: false
    jobs:
      rollback:
        runs-on: ubuntu-latest
        environment: ${{ inputs.environment }}
        steps:
          - run: echo "Rolling back to ${{ inputs.version || 'previous' }}"
    EOF
    git add .github/workflows/rollback.yml && git commit -m "cd: add manual rollback workflow"
    `

4. Check the deployment history for a repository using `gh api`:

   ??? success "Solution"
   `bash
    gh api repos/OWNER/REPO/deployments \
      --jq '.[] | {id, environment, sha: .sha[0:7], created_at, creator: .creator.login}'
    `

5. Set a deployment status to `success` for the most recent deployment using `gh api`:

   ??? success "Solution"
   `bash
    DEPLOY_ID=$(gh api repos/OWNER/REPO/deployments --jq '.[0].id')
    gh api repos/OWNER/REPO/deployments/${DEPLOY_ID}/statuses \
      --method POST \
      -f state=success \
      -f description="Deployment completed successfully" \
      -f environment_url=https://staging.example.com
    `

## Exercises

### Exercise 1 - Staging + Production Chain

Create a CD workflow with two jobs: `deploy-staging` and `deploy-production`. Gate production with a GitHub Environment that requires a reviewer. Simulate deployment with `echo` commands.

### Exercise 2 - Smoke Tests

Add a smoke test step to your staging deployment that uses `curl` to check a health endpoint. Make the production deployment depend on staging smoke tests passing.

### Exercise 3 - Rollback

Add a `rollback-production` job that runs only when `deploy-production` fails. Have it print the rollback steps and post a mock notification.

### Exercise 4 - Deployment API

Use `actions/github-script` to create a GitHub Deployment at the start of your staging job and update its status to `success` or `failure` at the end.

### Exercise 5 - Manual Rollback

Create a separate `rollback.yml` workflow triggered by `workflow_dispatch` with an `environment` input and a `version` input. Verify it appears in the Actions UI with the expected input fields.

---

## Summary

- `workflow_run` with `conclusion == 'success'` is the cleanest way to trigger CD only after CI passes
- GitHub Environments with required reviewers provide a human approval gate before production deploys
- Smoke tests on staging (health endpoints, API checks) catch integration issues that unit tests miss
- Blue-green deployments switch traffic atomically, enabling instant rollback by pointing back to the previous target group
- Rolling deployments update instances gradually; `kubectl rollout undo` or ECS task definition downgrades are the rollback mechanism
- The GitHub Deployments API (`repos/{owner}/{repo}/deployments`) provides an auditable log of every deployment with actor, SHA, environment, and status
- A dedicated `rollback.yml` with `workflow_dispatch` ensures any team member can initiate rollback without running the full pipeline
