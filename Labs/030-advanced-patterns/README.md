# Lab 030 - Advanced Patterns

## Introduction

- This final lab covers advanced GitHub Actions techniques that address real-world complexity: generating matrix strategies dynamically at runtime, chaining workflows across repositories with `repository_dispatch`, implementing slash commands via `issue_comment`, optimizing monorepo pipelines with path-based triggers, orchestrating complex multi-workflow systems, and automating repository maintenance on schedules.
- These patterns appear in mature CI/CD systems where the basic building blocks (triggers, jobs, actions) need to be combined in sophisticated ways to handle scale, flexibility, and automation requirements.

---

## 1. Dynamic Matrix Generation

Static matrices are limited to values known at workflow authoring time. Dynamic matrices generate their strategies from runtime data - a file listing changed services, an API response, or a script output.

### Pattern: Generate Matrix from a Script

```yaml
name: Dynamic Matrix

on:
  push:
    branches: [main]

jobs:
  # Step 1: Generate the matrix
  generate-matrix:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.set-matrix.outputs.matrix }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Generate matrix from changed services
        id: set-matrix
        run: |
          # Find all service directories that have a Dockerfile
          SERVICES=$(find services/ -name Dockerfile -maxdepth 2 \
            | xargs dirname \
            | xargs -I{} basename {} \
            | jq -R . | jq -sc .)

          echo "matrix={\"service\":${SERVICES}}" >> "$GITHUB_OUTPUT"
          echo "Generated matrix: $SERVICES"

  # Step 2: Fan out across the dynamic matrix
  build:
    needs: generate-matrix
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.generate-matrix.outputs.matrix) }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build ${{ matrix.service }}
        run: |
          echo "Building service: ${{ matrix.service }}"
          docker build -t myapp/${{ matrix.service }}:latest \
            services/${{ matrix.service }}/
```

### Pattern: Matrix from JSON File

```yaml
- name: Load test matrix from JSON
  id: load-matrix
  run: |
    MATRIX=$(cat .github/test-matrix.json)
    echo "matrix=$MATRIX" >> "$GITHUB_OUTPUT"
```

`.github/test-matrix.json`:

```json
{
  "include": [
    { "os": "ubuntu-latest", "node": "18", "experimental": false },
    { "os": "ubuntu-latest", "node": "20", "experimental": false },
    { "os": "macos-latest", "node": "20", "experimental": false },
    { "os": "windows-latest", "node": "20", "experimental": true }
  ]
}
```

### Pattern: Matrix from Changed Files (Monorepo)

```yaml
- name: Detect changed packages
  id: changed
  run: |
    # Get list of changed files vs main
    git fetch origin main --depth=1
    CHANGED=$(git diff --name-only origin/main...HEAD)

    # Extract unique top-level package directories that changed
    PACKAGES=$(echo "$CHANGED" \
      | grep '^packages/' \
      | cut -d/ -f2 \
      | sort -u \
      | jq -R . | jq -sc .)

    echo "packages=$PACKAGES" >> "$GITHUB_OUTPUT"
    echo "Changed packages: $PACKAGES"
```

---

## 2. Workflow Chaining with `repository_dispatch`

`repository_dispatch` lets one workflow trigger another workflow - even in a different repository. It's GitHub's native mechanism for cross-workflow orchestration.

### Sender Workflow

```yaml
name: CI Pipeline

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Build and test
        run: echo "Build and tests passed"

  trigger-downstream:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Trigger deployment pipeline
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.CROSS_REPO_PAT }}
          script: |
            await github.rest.repos.createDispatchEvent({
              owner: 'my-org',
              repo: 'deployment-repo',
              event_type: 'app-built',
              client_payload: {
                sha: context.sha,
                version: '1.5.0',
                environment: 'staging',
                triggered_by: context.actor,
                source_repo: context.repo.repo
              }
            });
            console.log('Downstream pipeline triggered');
```

### Receiver Workflow (in deployment-repo)

```yaml
name: Deploy (triggered by app-built)

on:
  repository_dispatch:
    types: [app-built]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Read payload
        run: |
          echo "SHA: ${{ github.event.client_payload.sha }}"
          echo "Version: ${{ github.event.client_payload.version }}"
          echo "Target env: ${{ github.event.client_payload.environment }}"
          echo "Triggered by: ${{ github.event.client_payload.triggered_by }}"

      - name: Deploy
        run: |
          echo "Deploying version ${{ github.event.client_payload.version }} to ${{ github.event.client_payload.environment }}"
```

---

## 3. Slash Commands via `issue_comment`

Implement ChatOps-style slash commands that respond to comments on issues and PRs:

```yaml
name: Slash Commands

on:
  issue_comment:
    types: [created]

permissions:
  issues: write
  pull-requests: write
  contents: read
  actions: write

jobs:
  handle-command:
    runs-on: ubuntu-latest
    # Only process comments that start with '/'
    if: startsWith(github.event.comment.body, '/')

    steps:
      - name: Parse command
        id: parse
        uses: actions/github-script@v7
        with:
          script: |
            const comment = context.payload.comment.body.trim();
            const [command, ...args] = comment.split(/\s+/);
            core.setOutput('command', command.toLowerCase());
            core.setOutput('args', args.join(' '));
            core.setOutput('actor', context.payload.comment.user.login);

      - name: Check authorization
        id: auth
        uses: actions/github-script@v7
        with:
          script: |
            const actor = '${{ steps.parse.outputs.actor }}';
            const { data: perm } = await github.rest.repos.getCollaboratorPermissionLevel({
              owner: context.repo.owner,
              repo: context.repo.repo,
              username: actor
            });
            const authorized = ['admin', 'maintain', 'write'].includes(perm.permission);
            core.setOutput('authorized', authorized.toString());
            if (!authorized) {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: context.payload.issue.number,
                body: `⛔ @${actor} You don't have permission to run slash commands.`
              });
            }

      - name: Handle /deploy command
        if: steps.parse.outputs.command == '/deploy' && steps.auth.outputs.authorized == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            const args = '${{ steps.parse.outputs.args }}';
            const env = args || 'staging';

            // Acknowledge the command
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.payload.issue.number,
              body: `🚀 Deploying to **${env}**... [View run](${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId})`
            });

            // Trigger the deployment workflow
            await github.rest.actions.createWorkflowDispatch({
              owner: context.repo.owner,
              repo: context.repo.repo,
              workflow_id: 'deploy.yml',
              ref: 'main',
              inputs: { environment: env }
            });

      - name: Handle /rerun command
        if: steps.parse.outputs.command == '/rerun' && steps.auth.outputs.authorized == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            const prNumber = context.payload.issue.number;
            // Get the latest commit on the PR
            const { data: pr } = await github.rest.pulls.get({
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: prNumber
            });

            // Get failed check runs for the latest commit
            const { data: checks } = await github.rest.checks.listForRef({
              owner: context.repo.owner,
              repo: context.repo.repo,
              ref: pr.head.sha,
              status: 'completed',
              filter: 'latest'
            });

            const failedRuns = checks.check_runs.filter(r => r.conclusion === 'failure');
            console.log(`Re-running ${failedRuns.length} failed check(s)`);

            for (const run of failedRuns) {
              await github.rest.checks.rerequestRun({
                owner: context.repo.owner,
                repo: context.repo.repo,
                check_run_id: run.id
              });
            }

            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: prNumber,
              body: `♻️ Re-running ${failedRuns.length} failed check(s).`
            });
```

---

## 4. Monorepo Path-Based Job Triggering

In a monorepo, run only the jobs relevant to what changed:

```yaml
name: Monorepo CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  # Detect what changed
  changes:
    runs-on: ubuntu-latest
    outputs:
      api: ${{ steps.filter.outputs.api }}
      frontend: ${{ steps.filter.outputs.frontend }}
      worker: ${{ steps.filter.outputs.worker }}
      infra: ${{ steps.filter.outputs.infra }}
      shared: ${{ steps.filter.outputs.shared }}

    steps:
      - uses: actions/checkout@v4
      - name: Detect changes
        id: filter
        uses: dorny/paths-filter@v3
        with:
          filters: |
            api:
              - 'services/api/**'
              - 'packages/shared/**'
            frontend:
              - 'services/frontend/**'
              - 'packages/shared/**'
            worker:
              - 'services/worker/**'
              - 'packages/shared/**'
            infra:
              - 'infra/**'
              - '.github/workflows/**'
            shared:
              - 'packages/shared/**'

  api-ci:
    needs: changes
    if: needs.changes.outputs.api == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: cd services/api && npm ci && npm test

  frontend-ci:
    needs: changes
    if: needs.changes.outputs.frontend == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: cd services/frontend && npm ci && npm test

  worker-ci:
    needs: changes
    if: needs.changes.outputs.worker == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: cd services/worker && npm ci && npm test

  infra-validate:
    needs: changes
    if: needs.changes.outputs.infra == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: cd infra && terraform fmt -check && terraform validate
```

---

## 5. Scheduled Repository Maintenance

```yaml
name: Repository Maintenance

on:
  schedule:
    - cron: "0 3 * * 0" # Weekly on Sunday at 03:00 UTC
  workflow_dispatch:

permissions:
  issues: write
  pull-requests: write

jobs:
  stale-issues:
    name: Mark Stale Issues
    runs-on: ubuntu-latest

    steps:
      - name: Mark stale issues and PRs
        uses: actions/stale@v9
        with:
          stale-issue-message: |
            This issue has been automatically marked as stale because it has not had recent activity.
            It will be closed in 14 days if no further activity occurs. If this issue is still relevant,
            please comment to keep it open.
          stale-pr-message: |
            This pull request has been automatically marked as stale because it has not had
            recent activity. Please update the PR or it will be closed in 7 days.
          close-issue-message: "This issue was closed due to inactivity. Please reopen if still relevant."
          days-before-stale: 60
          days-before-close: 14
          days-before-pr-stale: 30
          days-before-pr-close: 7
          stale-issue-label: stale
          stale-pr-label: stale
          exempt-issue-labels: pinned,security,in-progress
          exempt-pr-labels: pinned,work-in-progress

  cleanup-old-artifacts:
    name: Clean Up Old Artifacts
    runs-on: ubuntu-latest

    steps:
      - name: Delete artifacts older than 30 days
        uses: actions/github-script@v7
        with:
          script: |
            const cutoff = new Date();
            cutoff.setDate(cutoff.getDate() - 30);

            const artifacts = await github.paginate(github.rest.actions.listArtifactsForRepo, {
              owner: context.repo.owner,
              repo: context.repo.repo,
              per_page: 100
            });

            let deleted = 0;
            for (const artifact of artifacts) {
              if (new Date(artifact.created_at) < cutoff) {
                await github.rest.actions.deleteArtifact({
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  artifact_id: artifact.id
                });
                deleted++;
              }
            }
            console.log(`Deleted ${deleted} old artifacts`);

  label-sync:
    name: Sync Labels
    runs-on: ubuntu-latest

    steps:
      - name: Sync labels from config
        uses: actions/github-script@v7
        with:
          script: |
            const desiredLabels = [
              { name: 'bug',           color: 'd73a4a', description: 'Something is broken' },
              { name: 'enhancement',   color: 'a2eeef', description: 'New feature or request' },
              { name: 'documentation', color: '0075ca', description: 'Documentation improvements' },
              { name: 'dependencies',  color: '0366d6', description: 'Dependency updates' },
              { name: 'stale',         color: 'e4e669', description: 'No recent activity' },
              { name: 'in-progress',   color: 'fbca04', description: 'Currently being worked on' },
            ];

            const { data: currentLabels } = await github.rest.issues.listLabelsForRepo({
              owner: context.repo.owner,
              repo: context.repo.repo
            });

            for (const label of desiredLabels) {
              const existing = currentLabels.find(l => l.name === label.name);
              if (existing) {
                if (existing.color !== label.color || existing.description !== label.description) {
                  await github.rest.issues.updateLabel({
                    owner: context.repo.owner,
                    repo: context.repo.repo,
                    name: label.name,
                    color: label.color,
                    description: label.description
                  });
                  console.log(`Updated label: ${label.name}`);
                }
              } else {
                await github.rest.issues.createLabel({
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  ...label
                });
                console.log(`Created label: ${label.name}`);
              }
            }
```

---

## 6. Composite Orchestration with Multiple Reusable Workflows

```yaml
name: Full Release Orchestration

on:
  workflow_dispatch:
    inputs:
      version:
        type: string
        required: true

jobs:
  validate:
    uses: ./.github/workflows/validate.yml
    with:
      version: ${{ inputs.version }}
    secrets: inherit

  build:
    needs: validate
    uses: ./.github/workflows/build.yml
    with:
      version: ${{ inputs.version }}
    secrets: inherit

  publish-packages:
    needs: build
    uses: ./.github/workflows/publish.yml
    with:
      version: ${{ inputs.version }}
    secrets: inherit

  deploy-staging:
    needs: publish-packages
    uses: ./.github/workflows/deploy.yml
    with:
      environment: staging
      version: ${{ inputs.version }}
    secrets: inherit

  integration-tests:
    needs: deploy-staging
    uses: ./.github/workflows/integration-tests.yml
    with:
      target_url: https://staging.myapp.com
    secrets: inherit

  deploy-production:
    needs: integration-tests
    uses: ./.github/workflows/deploy.yml
    with:
      environment: production
      version: ${{ inputs.version }}
    secrets: inherit

  announce:
    needs: deploy-production
    runs-on: ubuntu-latest
    steps:
      - name: Announce release
        run: echo "Release ${{ inputs.version }} deployed to production"
```

---

## Hands-on

1. Create a workflow that generates a matrix dynamically from a shell script output using `fromJSON`:

   ??? success "Solution"
   `bash
    cat > .github/workflows/dynamic-matrix.yml << 'EOF'
    name: Dynamic Matrix
    on: [workflow_dispatch]
    jobs:
      generate:
        runs-on: ubuntu-latest
        outputs:
          matrix: ${{ steps.set.outputs.matrix }}
        steps:
          - uses: actions/checkout@v4
          - id: set
            run: |
              SERVICES=$(find services/ -maxdepth 1 -mindepth 1 -type d | xargs -I{} basename {} | jq -R . | jq -sc .)
              echo "matrix={\"service\":${SERVICES}}" >> "$GITHUB_OUTPUT"
      build:
        needs: generate
        runs-on: ubuntu-latest
        strategy:
          matrix: ${{ fromJson(needs.generate.outputs.matrix) }}
        steps:
          - run: echo "Building ${{ matrix.service }}"
    EOF
    git add .github/workflows/dynamic-matrix.yml && git commit -m "ci: generate matrix dynamically from services/"
    `

2. Write a slash command handler that responds to `/label <name>` comments on issues:

   ??? success "Solution"
   `bash
    cat > .github/workflows/slash-label.yml << 'EOF'
    name: Slash Label
    on:
      issue_comment:
        types: [created]
    permissions:
      issues: write
    jobs:
      label:
        runs-on: ubuntu-latest
        if: startsWith(github.event.comment.body, '/label ')
        steps:
          - uses: actions/github-script@v7
            with:
              script: |
                const body = context.payload.comment.body.trim();
                const label = body.replace('/label ', '').trim();
                await github.rest.issues.addLabels({
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  issue_number: context.payload.issue.number,
                  labels: [label]
                });
    EOF
    git add .github/workflows/slash-label.yml && git commit -m "ci: add slash label command handler"
    `

3. Add path-based filters in a monorepo so only relevant jobs trigger on changes to `src/`:

   ??? success "Solution"
   `bash
    cat > .github/workflows/monorepo-ci.yml << 'EOF'
    name: Monorepo CI
    on:
      push:
        paths:
          - 'src/api/**'
          - 'src/frontend/**'
    jobs:
      changes:
        runs-on: ubuntu-latest
        outputs:
          api: ${{ steps.filter.outputs.api }}
          frontend: ${{ steps.filter.outputs.frontend }}
        steps:
          - uses: actions/checkout@v4
          - id: filter
            uses: dorny/paths-filter@v3
            with:
              filters: |
                api:
                  - 'src/api/**'
                frontend:
                  - 'src/frontend/**'
      api-test:
        needs: changes
        if: needs.changes.outputs.api == 'true'
        runs-on: ubuntu-latest
        steps:
          - run: echo "Running API tests"
      frontend-test:
        needs: changes
        if: needs.changes.outputs.frontend == 'true'
        runs-on: ubuntu-latest
        steps:
          - run: echo "Running frontend tests"
    EOF
    git add .github/workflows/monorepo-ci.yml && git commit -m "ci: add path-based monorepo filters"
    `

4. Chain two workflows using `repository_dispatch` and verify the payload arrives:

   ??? success "Solution"
   `bash
    gh api repos/OWNER/REPO/dispatches \
      --method POST \
      -H "Accept: application/vnd.github+json" \
      -f event_type=app-built \
      -f 'client_payload[sha]=abc1234' \
      -f 'client_payload[environment]=staging'
    gh run list --workflow deploy.yml --limit 3
    `

5. Write a scheduled maintenance workflow that closes issues with the `stale` label older than 90 days:

   ??? success "Solution"
   `bash
    cat > .github/workflows/maintenance.yml << 'EOF'
    name: Maintenance
    on:
      schedule:
        - cron: "0 3 * * 0"
      workflow_dispatch:
    permissions:
      issues: write
    jobs:
      close-stale:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/github-script@v7
            with:
              script: |
                const cutoff = new Date();
                cutoff.setDate(cutoff.getDate() - 90);
                const issues = await github.paginate(github.rest.issues.listForRepo, {
                  owner: context.repo.owner, repo: context.repo.repo,
                  state: "open", labels: "stale", per_page: 100
                });
                for (const issue of issues) {
                  if (new Date(issue.updated_at) < cutoff) {
                    await github.rest.issues.update({
                      owner: context.repo.owner, repo: context.repo.repo,
                      issue_number: issue.number, state: "closed"
                    });
                    console.log("Closed stale issue #" + issue.number);
                  }
                }
    EOF
    git add .github/workflows/maintenance.yml && git commit -m "ci: add scheduled stale issue cleanup"
    `

## Exercises

### Exercise 1 - Dynamic Matrix

Create a workflow with a `generate-matrix` job that reads a JSON file (`test-targets.json`) and outputs it as a matrix for a downstream `test` job.

### Exercise 2 - Cross-Repo Dispatch

Set up two workflows: a sender in one repo that calls `repository_dispatch`, and a receiver in another (or the same) repo that logs the `client_payload`. Verify end-to-end using `gh run watch`.

### Exercise 3 - Slash Command

Implement `/label <label-name>` as a slash command: any collaborator commenting `/label bug` on an issue should cause the workflow to add the `bug` label.

### Exercise 4 - Monorepo Filter

Set up a monorepo with two packages (`packages/api/` and `packages/frontend/`). Create a workflow that only runs the API tests when `packages/api/` changes and frontend tests when `packages/frontend/` changes.

### Exercise 5 - Maintenance Workflow

Create a scheduled workflow that runs weekly and closes any issues with the `stale` label that were last updated more than 90 days ago.

---

## Summary

- Dynamic matrices use a `generate-matrix` job that outputs JSON, then reference `fromJson(needs.job.outputs.matrix)` in the downstream job's `strategy.matrix`
- `repository_dispatch` with a `client_payload` is the standard mechanism for cross-repository and cross-workflow orchestration
- Slash commands are implemented by triggering on `issue_comment` events, checking authorization via `getCollaboratorPermissionLevel`, and dispatching workflows or calling API methods
- `dorny/paths-filter` detects which parts of a monorepo changed, enabling conditional job execution that skips unaffected packages
- Chaining reusable workflows with `uses: ./.github/workflows/name.yml` and `needs:` creates readable, maintainable release orchestration pipelines
- Scheduled maintenance workflows (stale issue management, artifact cleanup, label sync) keep repositories organized without manual effort
- `github.paginate()` is essential in maintenance scripts to process repositories with hundreds of issues, PRs, or artifacts reliably
