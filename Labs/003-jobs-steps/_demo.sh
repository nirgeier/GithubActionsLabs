#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 003 - Jobs and Steps Demo"

TMPDIR_LAB=$(mktemp -d)
mkdir -p "$TMPDIR_LAB/.github/workflows"

# ─── Multi-job workflow ───────────────────────────────────────────────────────
section "1. Multi-Job Workflow with Dependencies"

cat >"$TMPDIR_LAB/.github/workflows/pipeline.yml" <<'WORKFLOW_EOF'
name: CI/CD Pipeline

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  # ── Job 1: runs immediately ──────────────────────────────────────────────
  lint:
    name: Lint Code
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run linter
        run: echo "Linting complete - no issues found"

  # ── Job 2: runs immediately (parallel with lint) ─────────────────────────
  security-scan:
    name: Security Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run security scan
        run: echo "Security scan complete - no vulnerabilities found"

  # ── Job 3: waits for lint ────────────────────────────────────────────────
  build:
    name: Build
    runs-on: ubuntu-latest
    needs: lint
    outputs:
      artifact-name: ${{ steps.meta.outputs.artifact-name }}
      version: ${{ steps.meta.outputs.version }}
    steps:
      - uses: actions/checkout@v4

      - name: Generate build metadata
        id: meta
        run: |
          VERSION="1.0.${{ github.run_number }}"
          ARTIFACT="app-${VERSION}"
          echo "version=${VERSION}"       >> $GITHUB_OUTPUT
          echo "artifact-name=${ARTIFACT}" >> $GITHUB_OUTPUT
          echo "Generated version: ${VERSION}"

      - name: Build application
        run: |
          mkdir -p dist
          echo "app binary v${{ steps.meta.outputs.version }}" > dist/app
          echo "Build complete: ${{ steps.meta.outputs.artifact-name }}"

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: ${{ steps.meta.outputs.artifact-name }}
          path: dist/

  # ── Jobs 4 & 5: parallel testing, both wait for build ────────────────────
  test-unit:
    name: Unit Tests
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact-name }}
          path: dist/
      - name: Run unit tests
        run: |
          echo "Testing artifact: $(cat dist/app)"
          echo "Unit tests: 47 passed, 0 failed"

  test-integration:
    name: Integration Tests
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact-name }}
          path: dist/
      - name: Run integration tests
        run: echo "Integration tests: 12 passed, 0 failed"

  # ── Job 6: fan-in - waits for all previous ───────────────────────────────
  deploy:
    name: Deploy to Staging
    runs-on: ubuntu-latest
    needs: [build, test-unit, test-integration, security-scan]
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: ${{ needs.build.outputs.artifact-name }}
          path: dist/

      - name: Deploy
        run: |
          echo "Deploying version: ${{ needs.build.outputs.version }}"
          echo "All gates passed:"
          echo "  ✓ Lint"
          echo "  ✓ Security scan"
          echo "  ✓ Build"
          echo "  ✓ Unit tests"
          echo "  ✓ Integration tests"
          echo "Deployment complete!"
WORKFLOW_EOF

echo "Pipeline workflow created."
echo ""
echo "Job execution order:"
echo "  lint  ──────────────────────────────┐"
echo "  security-scan ──────────────────────┤"
echo "                                      ▼"
echo "                                    build"
echo "                                    ├──► test-unit"
echo "                                    └──► test-integration"
echo "                                         ▼"
echo "                                       deploy"

# ─── Step outputs demo ────────────────────────────────────────────────────────
section "2. Step Outputs and Job Outputs"

cat >"$TMPDIR_LAB/.github/workflows/outputs.yml" <<'WORKFLOW_EOF'
name: Step and Job Outputs

on:
  workflow_dispatch:

jobs:
  generate:
    runs-on: ubuntu-latest
    outputs:
      version:    ${{ steps.ver.outputs.version }}
      build-date: ${{ steps.date.outputs.date }}
      sha-short:  ${{ steps.sha.outputs.sha }}
    steps:
      - name: Generate version
        id: ver
        run: |
          VERSION="2.$(date +%Y%m%d).$(( RANDOM % 100 ))"
          echo "version=${VERSION}" >> $GITHUB_OUTPUT
          echo "Generated version: ${VERSION}"

      - name: Get build date
        id: date
        run: echo "date=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> $GITHUB_OUTPUT

      - name: Get short SHA
        id: sha
        run: echo "sha=$(echo ${{ github.sha }} | cut -c1-7)" >> $GITHUB_OUTPUT

      - name: Summary
        run: |
          echo "Version:    ${{ steps.ver.outputs.version }}"
          echo "Build date: ${{ steps.date.outputs.date }}"
          echo "SHA short:  ${{ steps.sha.outputs.sha }}"

  consume:
    runs-on: ubuntu-latest
    needs: generate
    steps:
      - name: Use job outputs
        run: |
          echo "Version:    ${{ needs.generate.outputs.version }}"
          echo "Build date: ${{ needs.generate.outputs.build-date }}"
          echo "SHA:        ${{ needs.generate.outputs.sha-short }}"
WORKFLOW_EOF

echo "Outputs workflow created."

# ─── Environment variables across steps ──────────────────────────────────────
section "3. GITHUB_ENV - Passing Env Vars Between Steps"

cat >"$TMPDIR_LAB/.github/workflows/env-passing.yml" <<'WORKFLOW_EOF'
name: Environment Variable Passing

on:
  workflow_dispatch:

jobs:
  demo:
    runs-on: ubuntu-latest
    env:
      JOB_ENV: "set at job level"
    steps:
      - name: Step 1 - set env via GITHUB_ENV
        run: |
          echo "BUILT_BY=GitHub Actions" >> $GITHUB_ENV
          echo "BUILD_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> $GITHUB_ENV

      - name: Step 2 - read env from previous step
        run: |
          echo "Built by:  $BUILT_BY"
          echo "Build time: $BUILD_TIME"
          echo "Job env:   $JOB_ENV"

      - name: Step 3 - step-level env (isolated)
        env:
          LOCAL_ONLY: "only visible in this step"
        run: echo "Local: $LOCAL_ONLY"

      - name: Step 4 - LOCAL_ONLY not visible here
        run: echo "LOCAL_ONLY is: '${LOCAL_ONLY:-<not set>}'"
WORKFLOW_EOF

echo "env-passing.yml created."

# ─── Validate all workflows ───────────────────────────────────────────────────
section "4. Validating All Workflow Files"

for f in "$TMPDIR_LAB/.github/workflows/"*.yml; do
  name=$(basename "$f")
  python3 -c "
import yaml
with open('$f') as fp:
    doc = yaml.safe_load(fp)
jobs = list(doc.get('jobs', {}).keys())
print(f'  OK  $name  (jobs: {jobs})')
" || echo "  FAIL  $name"
done

# ─── Show key concepts ────────────────────────────────────────────────────────
section "5. Key Concepts Summary"

echo "Jobs and Steps key patterns:"
echo ""
printf "  %-30s %s\n" "needs: job-id" "Sequential dependency"
printf "  %-30s %s\n" "needs: [job1, job2]" "Fan-in: wait for multiple jobs"
printf "  %-30s %s\n" "outputs:" "Expose step outputs to other jobs"
printf "  %-30s %s\n" "GITHUB_OUTPUT" "Set step output values"
printf "  %-30s %s\n" "GITHUB_ENV" "Set env vars for subsequent steps"
printf "  %-30s %s\n" "upload-artifact@v4" "Share files between jobs"
printf "  %-30s %s\n" "download-artifact@v4" "Consume files from other jobs"
printf "  %-30s %s\n" "timeout-minutes:" "Prevent runaway steps/jobs"
printf "  %-30s %s\n" "continue-on-error: true" "Allow step failure without failing job"

# ─── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$TMPDIR_LAB"

section "Lab 003 - Demo Complete"
