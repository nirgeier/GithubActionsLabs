#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 008 - Conditions Demo"

TMPDIR_LAB=$(mktemp -d)
mkdir -p "$TMPDIR_LAB/.github/workflows"

# ─── Branch-based conditions ─────────────────────────────────────────────────
section "1. Branch-Based Conditional Jobs"

cat >"$TMPDIR_LAB/.github/workflows/branch-conditions.yml" <<'WORKFLOW_EOF'
name: Branch-Based Conditions

on:
  push:
    branches: [main, develop, 'feature/**']

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Build complete on branch: ${{ github.ref_name }}"

  deploy-feature:
    runs-on: ubuntu-latest
    needs: build
    if: startsWith(github.ref, 'refs/heads/feature/')
    steps:
      - run: echo "Feature branch: deploying to dev environment"

  deploy-staging:
    runs-on: ubuntu-latest
    needs: build
    if: github.ref == 'refs/heads/develop'
    steps:
      - run: echo "Develop branch: deploying to staging"

  deploy-production:
    runs-on: ubuntu-latest
    needs: build
    if: github.ref == 'refs/heads/main'
    environment: production
    steps:
      - run: echo "Main branch: deploying to PRODUCTION"

  tag-release:
    runs-on: ubuntu-latest
    needs: build
    if: startsWith(github.ref, 'refs/tags/v')
    steps:
      - run: echo "Tag release: ${{ github.ref_name }}"
WORKFLOW_EOF

echo "branch-conditions.yml created."
cat "$TMPDIR_LAB/.github/workflows/branch-conditions.yml"

# ─── Status functions ─────────────────────────────────────────────────────────
section "2. Status Function Conditions"

cat >"$TMPDIR_LAB/.github/workflows/status-conditions.yml" <<'WORKFLOW_EOF'
name: Status Conditions

on:
  workflow_dispatch:

jobs:
  pipeline:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Step 1 - build
        id: build
        run: |
          echo "Building..."
          # exit 1  # uncomment to simulate failure

      - name: Step 2 - test (runs only if build succeeded)
        id: test
        run: echo "Testing..."

      - name: Step 3 - on failure: notify
        if: failure()
        run: |
          echo "FAILURE detected!"
          echo "Build status: ${{ steps.build.outcome }}"
          echo "Test status:  ${{ steps.test.outcome }}"

      - name: Step 4 - always: upload artifacts
        if: always()
        run: |
          echo "Uploading artifacts (always runs)"
          echo "Build: ${{ steps.build.outcome }}"
          echo "Test:  ${{ steps.test.outcome }}"

      - name: Step 5 - on success: notify team
        if: success()
        run: echo "All steps passed - notifying team of success"

      - name: Step 6 - cancelled handler
        if: cancelled()
        run: echo "Workflow was cancelled - releasing any acquired locks"
WORKFLOW_EOF

echo "status-conditions.yml created."

# ─── Event-based conditions ───────────────────────────────────────────────────
section "3. Event-Based Conditions"

cat >"$TMPDIR_LAB/.github/workflows/event-conditions.yml" <<'WORKFLOW_EOF'
name: Event-Based Conditions

on:
  push:
  pull_request:
  schedule:
    - cron: '0 2 * * *'
  workflow_dispatch:
    inputs:
      run-extended-tests:
        type: boolean
        default: false

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Always: Show event
        run: echo "Triggered by: ${{ github.event_name }}"

      - name: Push-only: lint
        if: github.event_name == 'push'
        run: echo "Running lint (push trigger)"

      - name: PR-only: check title
        if: github.event_name == 'pull_request'
        run: |
          echo "PR: ${{ github.event.pull_request.title }}"
          echo "Base: ${{ github.base_ref }} <- Head: ${{ github.head_ref }}"

      - name: Schedule-only: nightly deep scan
        if: github.event_name == 'schedule'
        run: echo "Running nightly deep security scan"

      - name: Manual only: extended tests
        if: github.event_name == 'workflow_dispatch' && inputs.run-extended-tests == true
        run: echo "Running extended test suite (manually requested)"

      - name: Push or dispatch: deploy
        if: github.event_name == 'push' || github.event_name == 'workflow_dispatch'
        run: echo "Deploying (push or manual)"

      - name: Multiple allowed events via fromJSON
        if: contains(fromJSON('["push","workflow_dispatch"]'), github.event_name)
        run: echo "Event is in the allowed list"
WORKFLOW_EOF

echo "event-conditions.yml created."

# ─── continue-on-error ───────────────────────────────────────────────────────
section "4. continue-on-error Examples"

cat >"$TMPDIR_LAB/.github/workflows/continue-on-error.yml" <<'WORKFLOW_EOF'
name: continue-on-error Demo

on:
  workflow_dispatch:

jobs:
  optional-checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Required step
        run: echo "This step must succeed"

      - name: Optional lint (failure tolerated)
        continue-on-error: true
        id: lint
        run: |
          echo "Running optional linter..."
          exit 1   # fails but won't stop the job

      - name: After optional step
        run: |
          echo "Continues despite lint failure"
          echo "Lint outcome: ${{ steps.lint.outcome }}"     # failure
          echo "Lint conclusion: ${{ steps.lint.conclusion }}" # success (because continue-on-error)

  with-timeout:
    runs-on: ubuntu-latest
    timeout-minutes: 5    # job-level timeout
    steps:
      - name: Step with timeout
        timeout-minutes: 2   # step-level timeout
        run: |
          echo "This step has a 2-minute timeout"
          # sleep 200  # uncomment to trigger timeout
WORKFLOW_EOF

echo "continue-on-error.yml created."

# ─── Job needs result conditions ─────────────────────────────────────────────
section "5. Job Conditions with needs Results"

cat >"$TMPDIR_LAB/.github/workflows/needs-conditions.yml" <<'WORKFLOW_EOF'
name: needs Result Conditions

on:
  push:
  workflow_dispatch:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo "Running tests..."
      # Uncomment to test failure path:
      # - run: exit 1

  deploy:
    runs-on: ubuntu-latest
    needs: test
    if: needs.test.result == 'success' && github.ref == 'refs/heads/main'
    steps:
      - run: echo "Deploying - tests passed on main"

  notify-success:
    runs-on: ubuntu-latest
    needs: [test, deploy]
    if: always() && needs.test.result == 'success' && needs.deploy.result == 'success'
    steps:
      - run: echo "All jobs succeeded - sending success notification"

  notify-failure:
    runs-on: ubuntu-latest
    needs: [test, deploy]
    if: always() && (needs.test.result == 'failure' || needs.deploy.result == 'failure')
    steps:
      - run: |
          echo "Pipeline failed!"
          echo "test result:   ${{ needs.test.result }}"
          echo "deploy result: ${{ needs.deploy.result }}"
WORKFLOW_EOF

echo "needs-conditions.yml created."

# ─── Validate all ─────────────────────────────────────────────────────────────
section "6. Validating All Workflow Files"

for f in "$TMPDIR_LAB/.github/workflows/"*.yml; do
  name=$(basename "$f")
  python3 -c "
import yaml
with open('$f') as fp:
    doc = yaml.safe_load(fp)
jobs = doc.get('jobs', {})
conditional_jobs = {j: job.get('if', None) for j, job in jobs.items() if job.get('if')}
print(f'  OK  $name  (conditional jobs: {list(conditional_jobs.keys())})')
" || echo "  FAIL  $name"
done

# ─── Condition logic summary ─────────────────────────────────────────────────
section "7. Condition Patterns Summary"

printf "\n  %-45s %s\n" "Pattern" "Use case"
printf "  %-45s %s\n" "────────────────────────────────────────" "────────────────────────────"
printf "  %-45s %s\n" "if: success()" "Default - runs only after success"
printf "  %-45s %s\n" "if: failure()" "Alert/cleanup on failure"
printf "  %-45s %s\n" "if: always()" "Unconditional (cleanup, upload)"
printf "  %-45s %s\n" "if: cancelled()" "Release locks on cancel"
printf "  %-45s %s\n" "if: github.ref == 'refs/heads/main'" "Main branch only"
printf "  %-45s %s\n" "if: startsWith(github.ref, 'refs/tags/v')" "Version tag releases"
printf "  %-45s %s\n" "if: github.event_name == 'push'" "Push events only"
printf "  %-45s %s\n" "if: needs.job.result == 'success'" "Upstream job succeeded"
printf "  %-45s %s\n" "continue-on-error: true" "Allow step failure (tolerated)"

# ─── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$TMPDIR_LAB"

section "Lab 008 - Demo Complete"
