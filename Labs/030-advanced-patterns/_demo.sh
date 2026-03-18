#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 030 - Advanced Patterns Demo"

# ─────────────────────────────────────────────────────────────
# 1. Dynamic matrix generation
# ─────────────────────────────────────────────────────────────
section "1. Dynamic Matrix Generation Workflow"

mkdir -p .github/workflows

cat >.github/workflows/lab030-dynamic-matrix.yml <<'YAML'
name: "Lab 030 - Dynamic Matrix"

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  # Step 1: Generate matrix at runtime
  generate-matrix:
    name: Generate Build Matrix
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.set-matrix.outputs.matrix }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Generate matrix from services directory
        id: set-matrix
        run: |
          # Find all service directories containing a package.json
          # In a real monorepo: find packages/ -name package.json -maxdepth 2
          # For demo, we create a synthetic list:

          SERVICES='["api","frontend","worker"]'

          echo "matrix={\"service\":${SERVICES}}" >> "$GITHUB_OUTPUT"
          echo "Generated matrix with services: $SERVICES"

  # Step 2: Fan out across the dynamic matrix
  build:
    name: Build ${{ matrix.service }}
    runs-on: ubuntu-latest
    needs: generate-matrix
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.generate-matrix.outputs.matrix) }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build ${{ matrix.service }}
        run: |
          echo "Building service: ${{ matrix.service }}"
          echo "  Version: $(git rev-parse --short HEAD)"
          echo "  Build complete!"
YAML

echo "Created: .github/workflows/lab030-dynamic-matrix.yml"

# ─────────────────────────────────────────────────────────────
# 2. repository_dispatch workflow
# ─────────────────────────────────────────────────────────────
section "2. Cross-Repo repository_dispatch Workflow"

cat >.github/workflows/lab030-dispatch-sender.yml <<'YAML'
name: "Lab 030 - Dispatch Sender"

on:
  push:
    branches: [main]

jobs:
  build:
    name: Build and Notify
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build
        run: echo "Build complete for SHA ${{ github.sha }}"

      - name: Trigger downstream deployment
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.CROSS_REPO_PAT }}
          script: |
            // Trigger a workflow in another (or same) repository
            await github.rest.repos.createDispatchEvent({
              owner: context.repo.owner,
              repo: context.repo.repo,   // change to target repo
              event_type: 'app-built',
              client_payload: {
                sha: context.sha,
                version: '1.0.0',
                environment: 'staging',
                triggered_by: context.actor,
                source_workflow: context.workflow
              }
            });
            core.info('Downstream deploy triggered via repository_dispatch');
YAML

cat >.github/workflows/lab030-dispatch-receiver.yml <<'YAML'
name: "Lab 030 - Dispatch Receiver"

on:
  repository_dispatch:
    types: [app-built]

jobs:
  deploy:
    name: Deploy (triggered by app-built)
    runs-on: ubuntu-latest

    steps:
      - name: Log received payload
        run: |
          echo "=== repository_dispatch payload ==="
          echo "  SHA:            ${{ github.event.client_payload.sha }}"
          echo "  Version:        ${{ github.event.client_payload.version }}"
          echo "  Environment:    ${{ github.event.client_payload.environment }}"
          echo "  Triggered by:   ${{ github.event.client_payload.triggered_by }}"
          echo "  Source workflow: ${{ github.event.client_payload.source_workflow }}"

      - name: Deploy to ${{ github.event.client_payload.environment }}
        run: |
          ENV="${{ github.event.client_payload.environment }}"
          echo "Deploying to $ENV..."
          echo "Deployment complete!"
YAML

echo "Created: .github/workflows/lab030-dispatch-sender.yml"
echo "Created: .github/workflows/lab030-dispatch-receiver.yml"

# ─────────────────────────────────────────────────────────────
# 3. Slash command handler
# ─────────────────────────────────────────────────────────────
section "3. Slash Command Handler Workflow"

cat >.github/workflows/lab030-slash-commands.yml <<'YAML'
name: "Lab 030 - Slash Commands"

on:
  issue_comment:
    types: [created]

permissions:
  issues: write
  pull-requests: write
  actions: write
  contents: read

jobs:
  slash-command:
    name: Handle Slash Command
    runs-on: ubuntu-latest
    # Only process comments starting with '/'
    if: startsWith(github.event.comment.body, '/')

    steps:
      - name: Parse command
        id: parse
        uses: actions/github-script@v7
        with:
          script: |
            const comment = context.payload.comment.body.trim();
            const parts   = comment.split(/\s+/);
            const command = parts[0].toLowerCase();
            const args    = parts.slice(1).join(' ');

            core.setOutput('command', command);
            core.setOutput('args', args);
            core.info(`Command: ${command}, Args: ${args}`);

      - name: Check authorization
        id: auth
        uses: actions/github-script@v7
        with:
          script: |
            const actor = context.payload.comment.user.login;
            try {
              const { data } = await github.rest.repos.getCollaboratorPermissionLevel({
                owner: context.repo.owner,
                repo: context.repo.repo,
                username: actor
              });
              const authorized = ['admin', 'maintain', 'write'].includes(data.permission);
              core.setOutput('authorized', authorized.toString());
              if (!authorized) {
                await github.rest.issues.createComment({
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  issue_number: context.payload.issue.number,
                  body: `⛔ @${actor}: You need write access to run slash commands.`
                });
              }
            } catch {
              core.setOutput('authorized', 'false');
            }

      - name: Handle /label command
        if: steps.parse.outputs.command == '/label' && steps.auth.outputs.authorized == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            const labelName = '${{ steps.parse.outputs.args }}'.trim();
            if (!labelName) {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: context.payload.issue.number,
                body: '❓ Usage: `/label <label-name>`'
              });
              return;
            }

            await github.rest.issues.addLabels({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.payload.issue.number,
              labels: [labelName]
            });

            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.payload.issue.number,
              body: `🏷️ Added label \`${labelName}\``
            });

      - name: Handle /deploy command
        if: steps.parse.outputs.command == '/deploy' && steps.auth.outputs.authorized == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            const env = '${{ steps.parse.outputs.args }}' || 'staging';
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.payload.issue.number,
              body: `🚀 Triggering deployment to **${env}**...`
            });
            // In a real scenario: trigger dispatch to deploy workflow

      - name: Handle /help command
        if: steps.parse.outputs.command == '/help' && steps.auth.outputs.authorized == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.payload.issue.number,
              body: [
                '## Available Slash Commands',
                '',
                '| Command | Description |',
                '|---------|-------------|',
                '| `/label <name>` | Add a label to this issue/PR |',
                '| `/deploy [env]` | Trigger deployment (default: staging) |',
                '| `/help` | Show this help message |',
              ].join('\n')
            });
YAML

echo "Created: .github/workflows/lab030-slash-commands.yml"

# ─────────────────────────────────────────────────────────────
# 4. Monorepo path filter workflow
# ─────────────────────────────────────────────────────────────
section "4. Monorepo Path Filter Workflow"

cat >.github/workflows/lab030-monorepo.yml <<'YAML'
name: "Lab 030 - Monorepo Path Filters"

on:
  push:
    branches: [main]
  pull_request:

jobs:
  # Detect what changed
  detect-changes:
    name: Detect Changed Packages
    runs-on: ubuntu-latest
    outputs:
      api:      ${{ steps.filter.outputs.api }}
      frontend: ${{ steps.filter.outputs.frontend }}
      worker:   ${{ steps.filter.outputs.worker }}
      shared:   ${{ steps.filter.outputs.shared }}
      infra:    ${{ steps.filter.outputs.infra }}

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Filter changed paths
        id: filter
        uses: dorny/paths-filter@v3
        with:
          filters: |
            api:
              - 'packages/api/**'
              - 'packages/shared/**'
            frontend:
              - 'packages/frontend/**'
              - 'packages/shared/**'
            worker:
              - 'packages/worker/**'
              - 'packages/shared/**'
            shared:
              - 'packages/shared/**'
            infra:
              - 'infra/**'
              - '.github/workflows/**'

  # Run jobs only for what changed
  api-ci:
    name: API CI
    needs: detect-changes
    if: needs.detect-changes.outputs.api == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          echo "Running API tests (packages/api changed)"
          # cd packages/api && npm ci && npm test

  frontend-ci:
    name: Frontend CI
    needs: detect-changes
    if: needs.detect-changes.outputs.frontend == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          echo "Running Frontend tests (packages/frontend changed)"
          # cd packages/frontend && npm ci && npm test

  worker-ci:
    name: Worker CI
    needs: detect-changes
    if: needs.detect-changes.outputs.worker == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          echo "Running Worker tests (packages/worker changed)"

  infra-validate:
    name: Infra Validate
    needs: detect-changes
    if: needs.detect-changes.outputs.infra == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          echo "Validating infrastructure (infra/ changed)"
          # terraform fmt -check && terraform validate
YAML

echo "Created: .github/workflows/lab030-monorepo.yml"

# ─────────────────────────────────────────────────────────────
# 5. Show dynamic matrix test file
# ─────────────────────────────────────────────────────────────
section "5. Dynamic Matrix from JSON File Example"

cat >/tmp/lab030-test-targets.json <<'JSON'
{
  "include": [
    { "os": "ubuntu-latest", "node": "18", "experimental": false },
    { "os": "ubuntu-latest", "node": "20", "experimental": false },
    { "os": "ubuntu-latest", "node": "22", "experimental": true  },
    { "os": "macos-latest",  "node": "20", "experimental": false }
  ]
}
JSON

echo "Example test-targets.json:"
cat /tmp/lab030-test-targets.json

echo ""
echo "Workflow step to load it as a dynamic matrix:"
echo ""
cat <<'SNIPPET'
- name: Load test matrix
  id: load
  run: echo "matrix=$(cat .github/test-targets.json)" >> "$GITHUB_OUTPUT"

test:
  needs: load-matrix
  strategy:
    fail-fast: false
    matrix: ${{ fromJson(needs.load-matrix.outputs.matrix) }}
  runs-on: ${{ matrix.os }}
SNIPPET

# ─────────────────────────────────────────────────────────────
# 6. Show repository_dispatch via curl
# ─────────────────────────────────────────────────────────────
section "6. Triggering repository_dispatch via REST API"

echo ""
echo "# From any CI system or script:"
echo 'curl -X POST \'
echo '  -H "Authorization: Bearer $GITHUB_TOKEN" \'
echo '  -H "Accept: application/vnd.github+json" \'
echo '  https://api.github.com/repos/OWNER/REPO/dispatches \'
echo "  -d '{\"event_type\":\"app-built\",\"client_payload\":{\"version\":\"1.5.0\",\"env\":\"staging\"}}'"

echo ""
echo "# Or using gh api:"
echo "gh api repos/OWNER/REPO/dispatches \\"
echo "  --method POST \\"
echo "  -f event_type=app-built \\"
echo "  -F client_payload='{\"version\":\"1.5.0\"}'"

# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────
section "Cleanup"
rm -f .github/workflows/lab030-dynamic-matrix.yml
rm -f .github/workflows/lab030-dispatch-sender.yml
rm -f .github/workflows/lab030-dispatch-receiver.yml
rm -f .github/workflows/lab030-slash-commands.yml
rm -f .github/workflows/lab030-monorepo.yml
rm -f /tmp/lab030-test-targets.json
echo "Demo files removed"

section "Lab 030 Complete"
echo "Key takeaways:"
echo "  - Dynamic matrices: generate-matrix job outputs JSON, downstream uses fromJson()"
echo "  - repository_dispatch with client_payload enables cross-workflow orchestration"
echo "  - Slash commands: issue_comment trigger + auth check + github.rest API calls"
echo "  - dorny/paths-filter detects monorepo changes; conditional jobs skip unaffected packages"
echo "  - Reusable workflows + needs: chains create readable release orchestration pipelines"
echo "  - Scheduled maintenance workflows handle stale issues, artifact cleanup, label sync"
