#!/usr/bin/env bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

# =============================================================================
# Lab 010 - Artifacts Demo
# Demonstrates: creating workflow YAML for artifact upload/download between jobs
# =============================================================================

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$LAB_DIR/workflow-examples"

print_header "Lab 010 - Artifacts"
print_info "This demo generates workflow YAML files showing artifact upload/download patterns."

mkdir -p "$WORKFLOW_DIR"

# -----------------------------------------------------------------------------
# 1. Basic two-job artifact passing workflow
# -----------------------------------------------------------------------------
print_step "Creating basic artifact upload/download workflow..."

cat >"$WORKFLOW_DIR/basic-artifacts.yml" <<'EOF'
name: Basic Artifact Upload and Download

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    name: Build and Upload Artifact
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Build application
        run: |
          mkdir -p dist
          echo "Compiled app binary" > dist/app
          echo '{"version": "1.0.0", "sha": "${{ github.sha }}"}' > dist/build-info.json
          echo "Build complete. Files in dist/:"
          ls -la dist/

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: build-output-${{ github.run_number }}
          path: dist/
          retention-days: 7

  test:
    name: Download Artifact and Test
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Download build artifact
        uses: actions/download-artifact@v4
        with:
          name: build-output-${{ github.run_number }}
          path: dist/

      - name: Verify artifact contents
        run: |
          echo "Downloaded artifact contents:"
          ls -la dist/
          echo ""
          echo "App binary:"
          cat dist/app
          echo ""
          echo "Build info:"
          cat dist/build-info.json

  deploy:
    name: Deploy from Artifact
    runs-on: ubuntu-latest
    needs: [build, test]
    steps:
      - name: Download build artifact
        uses: actions/download-artifact@v4
        with:
          name: build-output-${{ github.run_number }}
          path: dist/

      - name: Deploy application
        run: |
          echo "Deploying application from artifact..."
          echo "Binary: $(cat dist/app)"
          echo "Version: $(cat dist/build-info.json)"
          echo "Deployment complete!"
EOF

print_success "Created: $WORKFLOW_DIR/basic-artifacts.yml"

# -----------------------------------------------------------------------------
# 2. Multi-platform matrix artifact workflow
# -----------------------------------------------------------------------------
print_step "Creating multi-platform matrix artifact workflow..."

cat >"$WORKFLOW_DIR/matrix-artifacts.yml" <<'EOF'
name: Multi-Platform Build Artifacts

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    name: Build on ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
        include:
          - os: ubuntu-latest
            artifact-name: linux-amd64
            binary-ext: ""
          - os: windows-latest
            artifact-name: windows-amd64
            binary-ext: ".exe"
          - os: macos-latest
            artifact-name: darwin-amd64
            binary-ext: ""
    runs-on: ${{ matrix.os }}
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Build binary
        shell: bash
        run: |
          mkdir -p dist
          echo "Binary for ${{ runner.os }}" > dist/app${{ matrix.binary-ext }}
          echo "Built ${{ matrix.artifact-name }}"

      - name: Upload platform artifact
        uses: actions/upload-artifact@v4
        with:
          name: dist-${{ matrix.artifact-name }}
          path: dist/
          retention-days: 7

  package-release:
    name: Package All Platforms
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Download all platform artifacts
        uses: actions/download-artifact@v4
        # Omitting 'name' downloads ALL artifacts into subdirectories

      - name: Inspect downloaded structure
        run: |
          echo "Downloaded artifact structure:"
          find . -type f | sort

      - name: Create unified release package
        run: |
          mkdir -p release
          cp dist-linux-amd64/app          release/app-linux-amd64    2>/dev/null || true
          cp dist-windows-amd64/app.exe    release/app-windows-amd64.exe 2>/dev/null || true
          cp dist-darwin-amd64/app         release/app-darwin-amd64   2>/dev/null || true

          echo "Release package contents:"
          ls -la release/

      - name: Upload release artifact
        uses: actions/upload-artifact@v4
        with:
          name: release-all-platforms
          path: release/
          retention-days: 90
EOF

print_success "Created: $WORKFLOW_DIR/matrix-artifacts.yml"

# -----------------------------------------------------------------------------
# 3. Test results workflow - always upload even on failure
# -----------------------------------------------------------------------------
print_step "Creating test-results artifact workflow with conditional upload..."

cat >"$WORKFLOW_DIR/test-results-artifacts.yml" <<'EOF'
name: Test Results Artifacts

on:
  push:
  pull_request:

jobs:
  unit-tests:
    name: Unit Tests
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: npm ci

      - name: Run unit tests
        run: |
          npm run test:unit -- \
            --reporter=junit \
            --outputFile=test-results/unit.xml \
            --coverage \
            --coverageDirectory=coverage/
        continue-on-error: true
        id: unit_tests

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()   # Upload EVEN if tests failed
        with:
          name: test-results-unit
          path: test-results/
          retention-days: 14

      - name: Upload coverage report
        uses: actions/upload-artifact@v4
        if: steps.unit_tests.outcome == 'success'   # Only on success
        with:
          name: coverage-report
          path: coverage/
          retention-days: 14

      - name: Fail job if tests failed
        if: steps.unit_tests.outcome == 'failure'
        run: exit 1

  integration-tests:
    name: Integration Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - name: Run integration tests
        run: npm run test:integration -- --reporter=junit --outputFile=test-results/integration.xml
        continue-on-error: true
        id: int_tests

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results-integration
          path: test-results/
          retention-days: 14

  publish-results:
    name: Publish Test Reports
    runs-on: ubuntu-latest
    needs: [unit-tests, integration-tests]
    if: always()
    steps:
      - name: Download all test results
        uses: actions/download-artifact@v4
        with:
          pattern: test-results-*
          merge-multiple: true
          path: all-test-results/

      - name: List all collected results
        run: |
          echo "All test result files:"
          find all-test-results/ -type f | sort
EOF

print_success "Created: $WORKFLOW_DIR/test-results-artifacts.yml"

# -----------------------------------------------------------------------------
# 4. Show gh CLI commands for artifact management
# -----------------------------------------------------------------------------
print_step "Demonstrating gh CLI artifact commands..."

print_info "GitHub CLI commands for working with artifacts:"
echo ""
echo "  # List workflow runs for a repo"
echo "  gh run list --repo owner/repo --limit 10"
echo ""
echo "  # View details of a specific run (shows artifact names)"
echo "  gh run view <run-id> --repo owner/repo"
echo ""
echo "  # Download all artifacts from a run"
echo "  gh run download <run-id> --repo owner/repo"
echo ""
echo "  # Download a specific artifact by name"
echo "  gh run download <run-id> --name build-output --repo owner/repo"
echo ""
echo "  # Download to a custom directory"
echo "  gh run download <run-id> --name build-output --dir ./my-artifacts/ --repo owner/repo"
echo ""
echo "  # List artifacts via API"
echo "  gh api repos/owner/repo/actions/runs/<run-id>/artifacts"
echo ""

# Check if gh is available and show real data if possible
if command -v gh &>/dev/null; then
  print_info "gh CLI is available. Checking for recent runs (if authenticated)..."
  gh run list --limit 5 2>/dev/null || print_info "Not authenticated or no runs found - skipping live demo."
else
  print_info "gh CLI not found. Install it from https://cli.github.com/ to use these commands."
fi

# -----------------------------------------------------------------------------
# 5. Demonstrate artifact size and naming constraints
# -----------------------------------------------------------------------------
print_step "Demonstrating artifact naming and compression..."

DEMO_DIR=$(mktemp -d)
trap 'rm -rf "$DEMO_DIR"' EXIT

# Create sample files to show compression benefit
mkdir -p "$DEMO_DIR/dist"
for i in {1..5}; do
  dd if=/dev/urandom bs=1k count=10 2>/dev/null | base64 >"$DEMO_DIR/dist/file-$i.txt"
done

UNCOMPRESSED=$(du -sh "$DEMO_DIR/dist" | cut -f1)
tar -czf "$DEMO_DIR/dist.tar.gz" -C "$DEMO_DIR" dist
COMPRESSED=$(du -sh "$DEMO_DIR/dist.tar.gz" | cut -f1)

print_info "Compression benefit example:"
echo "  Uncompressed dist/ size : $UNCOMPRESSED"
echo "  Compressed .tar.gz size : $COMPRESSED"
echo ""
print_info "Artifact naming rules:"
echo "  Good names : build-output, test-results-unit, dist-linux-amd64-v1.2.3"
echo "  Bad names  : ../escape, path/with/slash, name\\with\\backslash"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_header "Demo Complete"
print_success "Generated workflow files in: $WORKFLOW_DIR"
echo ""
print_info "Files created:"
ls -1 "$WORKFLOW_DIR/"
echo ""
print_info "Key takeaways:"
echo "  - Use actions/upload-artifact@v4 to persist build outputs"
echo "  - Use actions/download-artifact@v4 in downstream jobs"
echo "  - Always use 'if: always()' for test-result uploads"
echo "  - Set retention-days to match the artifact's purpose"
echo "  - Use 'gh run download' to fetch artifacts locally"
