#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 005 - Environment Variables Demo"

TMPDIR_LAB=$(mktemp -d)
mkdir -p "$TMPDIR_LAB/.github/workflows"

# ─── All env scopes ───────────────────────────────────────────────────────────
section "1. Workflow, Job, and Step-Level env"

cat >"$TMPDIR_LAB/.github/workflows/env-scopes.yml" <<'WORKFLOW_EOF'
name: Environment Variable Scopes

on:
  push:
  workflow_dispatch:

env:
  WORKFLOW_VAR: "set at workflow level"
  SHARED_VAR: "workflow-level value"      # will be overridden

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      JOB_VAR: "set at job level"
      SHARED_VAR: "job-level value"       # overrides workflow-level

    steps:
      - name: Show all scopes
        env:
          STEP_VAR: "set at step level"
          SHARED_VAR: "step-level value"  # overrides job-level
        run: |
          echo "Workflow var: $WORKFLOW_VAR"
          echo "Job var:      $JOB_VAR"
          echo "Step var:     $STEP_VAR"
          echo "Shared var:   $SHARED_VAR   (step-level wins)"

      - name: After step - STEP_VAR is gone
        run: |
          echo "Job var still here: $JOB_VAR"
          echo "Step var:           '${STEP_VAR:-<not set>}'"
          echo "Shared var:         $SHARED_VAR   (back to job-level)"
WORKFLOW_EOF

echo "env-scopes.yml created."
cat "$TMPDIR_LAB/.github/workflows/env-scopes.yml"

# ─── GITHUB_ENV dynamic vars ──────────────────────────────────────────────────
section "2. GITHUB_ENV - Passing Variables Between Steps"

cat >"$TMPDIR_LAB/.github/workflows/github-env.yml" <<'WORKFLOW_EOF'
name: GITHUB_ENV Demo

on:
  workflow_dispatch:

jobs:
  demo:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Step 1 - Set dynamic variables
        run: |
          BUILD_ID="build-$(date +%s)"
          SHORT_SHA=$(echo "$GITHUB_SHA" | cut -c1-7)
          BUILD_DATE=$(date -u '+%Y-%m-%d')

          echo "BUILD_ID=${BUILD_ID}"     >> $GITHUB_ENV
          echo "SHORT_SHA=${SHORT_SHA}"   >> $GITHUB_ENV
          echo "BUILD_DATE=${BUILD_DATE}" >> $GITHUB_ENV

          echo "Variables written to GITHUB_ENV:"
          echo "  BUILD_ID:   ${BUILD_ID}"
          echo "  SHORT_SHA:  ${SHORT_SHA}"
          echo "  BUILD_DATE: ${BUILD_DATE}"

      - name: Step 2 - Consume the dynamic variables
        run: |
          echo "BUILD_ID:   $BUILD_ID"
          echo "SHORT_SHA:  $SHORT_SHA"
          echo "BUILD_DATE: $BUILD_DATE"

      - name: Step 3 - Use env context in expressions
        run: |
          echo "Via env context: ${{ env.BUILD_ID }}"
          echo "Via shell var:   $BUILD_ID"
WORKFLOW_EOF

echo "github-env.yml created."

# ─── Default GitHub variables ─────────────────────────────────────────────────
section "3. Default GitHub Environment Variables"

cat >"$TMPDIR_LAB/.github/workflows/default-vars.yml" <<'WORKFLOW_EOF'
name: Default Environment Variables

on:
  push:
  workflow_dispatch:

jobs:
  print-defaults:
    runs-on: ubuntu-latest
    steps:
      - name: Repository metadata
        run: |
          echo "=== Repository ==="
          echo "GITHUB_REPOSITORY:       $GITHUB_REPOSITORY"
          echo "GITHUB_REPOSITORY_OWNER: $GITHUB_REPOSITORY_OWNER"
          echo "GITHUB_WORKSPACE:        $GITHUB_WORKSPACE"
          echo "GITHUB_SERVER_URL:       $GITHUB_SERVER_URL"
          echo "GITHUB_API_URL:          $GITHUB_API_URL"

      - name: Git and event metadata
        run: |
          echo "=== Git / Event ==="
          echo "GITHUB_SHA:          $GITHUB_SHA"
          echo "GITHUB_REF:          $GITHUB_REF"
          echo "GITHUB_REF_NAME:     $GITHUB_REF_NAME"
          echo "GITHUB_REF_TYPE:     $GITHUB_REF_TYPE"
          echo "GITHUB_EVENT_NAME:   $GITHUB_EVENT_NAME"
          echo "GITHUB_ACTOR:        $GITHUB_ACTOR"
          echo "GITHUB_HEAD_REF:     ${GITHUB_HEAD_REF:-<not a PR>}"
          echo "GITHUB_BASE_REF:     ${GITHUB_BASE_REF:-<not a PR>}"

      - name: Workflow metadata
        run: |
          echo "=== Workflow ==="
          echo "GITHUB_WORKFLOW:     $GITHUB_WORKFLOW"
          echo "GITHUB_RUN_ID:       $GITHUB_RUN_ID"
          echo "GITHUB_RUN_NUMBER:   $GITHUB_RUN_NUMBER"
          echo "GITHUB_RUN_ATTEMPT:  $GITHUB_RUN_ATTEMPT"

      - name: Runner metadata
        run: |
          echo "=== Runner ==="
          echo "RUNNER_OS:           $RUNNER_OS"
          echo "RUNNER_ARCH:         $RUNNER_ARCH"
          echo "RUNNER_NAME:         $RUNNER_NAME"
          echo "RUNNER_TEMP:         $RUNNER_TEMP"
          echo "RUNNER_TOOL_CACHE:   $RUNNER_TOOL_CACHE"
WORKFLOW_EOF

echo "default-vars.yml created."

# ─── GITHUB_PATH demo ─────────────────────────────────────────────────────────
section "4. GITHUB_PATH - Adding to PATH"

cat >"$TMPDIR_LAB/.github/workflows/github-path.yml" <<'WORKFLOW_EOF'
name: GITHUB_PATH Demo

on:
  workflow_dispatch:

jobs:
  demo:
    runs-on: ubuntu-latest
    steps:
      - name: Install custom tool
        run: |
          mkdir -p "$HOME/custom-bin"
          cat > "$HOME/custom-bin/my-tool" << 'SCRIPT'
          #!/bin/bash
          echo "my-tool v1.0.0 - custom tool installed during workflow"
          SCRIPT
          chmod +x "$HOME/custom-bin/my-tool"
          echo "Installed to: $HOME/custom-bin/my-tool"

      - name: Add to PATH
        run: echo "$HOME/custom-bin" >> $GITHUB_PATH

      - name: Use the custom tool
        run: |
          echo "PATH includes: $HOME/custom-bin"
          my-tool
          which my-tool
WORKFLOW_EOF

echo "github-path.yml created."

# ─── Validate all workflows ───────────────────────────────────────────────────
section "5. Validating All Workflow Files"

for f in "$TMPDIR_LAB/.github/workflows/"*.yml; do
  name=$(basename "$f")
  python3 -c "
import yaml
with open('$f') as fp:
    doc = yaml.safe_load(fp)
env_keys = list((doc.get('env') or {}).keys())
print(f'  OK  $name  (workflow-level env: {env_keys})')
" || echo "  FAIL  $name"
done

# ─── Quick local demo of env scoping ─────────────────────────────────────────
section "6. Local Demo: env Scope Priority"

export SHARED_VAR="workflow-level"
echo "Initial:         SHARED_VAR=${SHARED_VAR}"

(
  export SHARED_VAR="job-level"
  echo "Inside job:      SHARED_VAR=${SHARED_VAR}"

  (
    export SHARED_VAR="step-level"
    echo "Inside step:     SHARED_VAR=${SHARED_VAR}"
  )

  echo "After step:      SHARED_VAR=${SHARED_VAR} (back to job-level)"
)

echo "After job:       SHARED_VAR=${SHARED_VAR} (back to workflow-level)"

unset SHARED_VAR

# ─── Summary table ────────────────────────────────────────────────────────────
section "7. Variable Sources Comparison"

printf "\n  %-25s %-30s %s\n" "Source" "Access Syntax" "Purpose"
printf "  %-25s %-30s %s\n" "────────────────────" "──────────────────────────" "──────────────────────────"
printf "  %-25s %-30s %s\n" "env: (workflow)" "\$VAR or \${{ env.VAR }}" "Shared across all jobs/steps"
printf "  %-25s %-30s %s\n" "env: (job)" "\$VAR or \${{ env.VAR }}" "Job-scoped configuration"
printf "  %-25s %-30s %s\n" "env: (step)" "\$VAR or \${{ env.VAR }}" "Step-scoped configuration"
printf "  %-25s %-30s %s\n" "GITHUB_ENV file" "\$VAR (next steps)" "Dynamic runtime values"
printf "  %-25s %-30s %s\n" "Default vars" "\$GITHUB_SHA etc." "Auto-injected by GitHub"
printf "  %-25s %-30s %s\n" "inputs:" "\${{ inputs.NAME }}" "Manual dispatch params"
printf "  %-25s %-30s %s\n" "vars context" "\${{ vars.NAME }}" "Repo/org config (non-secret)"
printf "  %-25s %-30s %s\n" "secrets context" "\${{ secrets.NAME }}" "Sensitive values (masked)"

# ─── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$TMPDIR_LAB"

section "Lab 005 - Demo Complete"
