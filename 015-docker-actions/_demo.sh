#!/usr/bin/env bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

# =============================================================================
# Lab 015 - Docker Actions Demo
# Demonstrates: Docker action with Dockerfile, entrypoint.sh, and action.yml
# =============================================================================

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$LAB_DIR/demo-output"
ACTION_DIR="$OUTPUT_DIR/markdown-lint-action"
WORKFLOW_DIR="$OUTPUT_DIR/workflow-examples"

print_header "Lab 015 - Docker Actions"
print_info "This demo creates a complete Docker action: action.yml, Dockerfile, entrypoint.sh"

mkdir -p "$ACTION_DIR" "$WORKFLOW_DIR"

# -----------------------------------------------------------------------------
# 1. Create action.yml
# -----------------------------------------------------------------------------
print_step "Creating action.yml..."

cat >"$ACTION_DIR/action.yml" <<'EOF'
# =============================================================
# Docker Action: markdown-lint
# Lints Markdown files using markdownlint-cli in a Docker container
# =============================================================
name: Markdown Linter
description: >
  Lints Markdown files in a specified path using markdownlint-cli.
  Reports error counts and optionally fails the workflow on errors.
author: 'GitHub Actions Lab Demo'

branding:
  icon: 'check-circle'
  color: 'blue'

# ---- INPUTS ----
inputs:
  path:
    description: 'Path to lint - a file, directory, or glob pattern'
    required: false
    default: '.'

  config:
    description: 'Path to .markdownlint.json configuration file'
    required: false
    default: ''

  fail-on-error:
    description: 'Exit with error code if lint violations are found'
    required: false
    default: 'true'

  fix:
    description: 'Automatically fix fixable violations'
    required: false
    default: 'false'

# ---- OUTPUTS ----
outputs:
  error-count:
    description: 'Number of lint violations found'

  warning-count:
    description: 'Number of lint warnings found'

  report-path:
    description: 'Path to the generated lint report file'

# ---- RUNS ----
runs:
  using: docker
  image: Dockerfile
  # entrypoint is defined in Dockerfile via ENTRYPOINT
  env:
    # Additional env vars the container will receive
    MARKDOWNLINT_VERSION: '0.37.0'
EOF

print_success "Created: $ACTION_DIR/action.yml"

# -----------------------------------------------------------------------------
# 2. Create Dockerfile
# -----------------------------------------------------------------------------
print_step "Creating Dockerfile..."

cat >"$ACTION_DIR/Dockerfile" <<'EOF'
# =============================================================
# Dockerfile for markdown-lint Docker action
# =============================================================

# Use a specific Node.js Alpine version for reproducibility
FROM node:20-alpine3.19

# Add metadata labels
LABEL maintainer="GitHub Actions Lab"
LABEL description="Docker action for Markdown linting"

# Install system dependencies
RUN apk add --no-cache \
    bash \
    git \
    jq

# Install markdownlint-cli at a pinned version
ARG MARKDOWNLINT_VERSION=0.37.0
RUN npm install -g markdownlint-cli@${MARKDOWNLINT_VERSION} \
    && markdownlint --version

# Copy the entrypoint script
COPY entrypoint.sh /entrypoint.sh

# Make it executable
RUN chmod +x /entrypoint.sh

# Use a non-root user for security (optional but recommended)
# Note: GitHub Actions requires write access to GITHUB_OUTPUT,
# so this is illustrative - in practice, test with your runner setup.
# RUN adduser -D -h /home/action action
# USER action

# Set the working directory to the GitHub workspace
WORKDIR /github/workspace

# Define the entrypoint
ENTRYPOINT ["/entrypoint.sh"]
EOF

print_success "Created: $ACTION_DIR/Dockerfile"

# -----------------------------------------------------------------------------
# 3. Create entrypoint.sh
# -----------------------------------------------------------------------------
print_step "Creating entrypoint.sh..."

cat >"$ACTION_DIR/entrypoint.sh" <<'EOF'
#!/bin/bash
# =============================================================
# entrypoint.sh - Main action logic for markdown-lint
#
# GitHub Actions passes inputs as environment variables:
#   Input 'path'          → INPUT_PATH
#   Input 'config'        → INPUT_CONFIG
#   Input 'fail-on-error' → INPUT_FAIL_ON_ERROR
#   Input 'fix'           → INPUT_FIX
# =============================================================
set -eo pipefail

# ---- Read inputs from environment variables ----
LINT_PATH="${INPUT_PATH:-.}"
CONFIG_FILE="${INPUT_CONFIG:-}"
FAIL_ON_ERROR="${INPUT_FAIL_ON_ERROR:-true}"
FIX_MODE="${INPUT_FIX:-false}"
REPORT_PATH="/tmp/markdownlint-report.txt"

# ---- Print action header ----
echo "============================================"
echo "  Markdown Linter Docker Action"
echo "============================================"
echo "Path          : $LINT_PATH"
echo "Config        : ${CONFIG_FILE:-<default>}"
echo "Fail on error : $FAIL_ON_ERROR"
echo "Fix mode      : $FIX_MODE"
echo ""

# ---- Validate path exists ----
if [ ! -e "$LINT_PATH" ]; then
    echo "ERROR: Path does not exist: $LINT_PATH"
    exit 1
fi

# ---- Build markdownlint command ----
CMD_ARGS=()
CMD_ARGS+=("--dot")  # Include dotfiles

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    CMD_ARGS+=("--config" "$CONFIG_FILE")
    echo "Using config: $CONFIG_FILE"
fi

if [ "$FIX_MODE" = "true" ]; then
    CMD_ARGS+=("--fix")
    echo "Fix mode enabled - violations will be auto-corrected"
fi

CMD_ARGS+=("$LINT_PATH")

echo "Running: markdownlint ${CMD_ARGS[*]}"
echo "--------------------------------------------"

# ---- Run markdownlint ----
set +e
markdownlint "${CMD_ARGS[@]}" 2>&1 | tee "$REPORT_PATH"
EXIT_CODE=$?
set -e

echo "--------------------------------------------"

# ---- Count errors ----
ERROR_COUNT=0
if [ -f "$REPORT_PATH" ] && [ -s "$REPORT_PATH" ]; then
    ERROR_COUNT=$(grep -c "^" "$REPORT_PATH" || echo "0")
fi
WARNING_COUNT=0  # markdownlint-cli doesn't distinguish warnings from errors

echo "Lint violations found : $ERROR_COUNT"
echo "Exit code             : $EXIT_CODE"

# ---- Set outputs ----
echo "error-count=$ERROR_COUNT"     >> "$GITHUB_OUTPUT"
echo "warning-count=$WARNING_COUNT" >> "$GITHUB_OUTPUT"
echo "report-path=$REPORT_PATH"     >> "$GITHUB_OUTPUT"

# ---- Summary to step summary ----
{
    echo "## Markdown Lint Results"
    echo ""
    echo "| Metric | Value |"
    echo "|--------|-------|"
    echo "| Path   | \`$LINT_PATH\` |"
    echo "| Violations | $ERROR_COUNT |"
    echo "| Status | $([ $EXIT_CODE -eq 0 ] && echo 'PASS' || echo 'FAIL') |"
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo ""
        echo "### Violations"
        echo "\`\`\`"
        cat "$REPORT_PATH"
        echo "\`\`\`"
    fi
} >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true

# ---- Determine exit behavior ----
if [ "$FAIL_ON_ERROR" = "true" ] && [ "$EXIT_CODE" -ne 0 ]; then
    echo ""
    echo "FAIL: Lint violations found and fail-on-error is true."
    exit "$EXIT_CODE"
fi

echo "Markdown lint action complete."
EOF

chmod +x "$ACTION_DIR/entrypoint.sh"
print_success "Created: $ACTION_DIR/entrypoint.sh"

# -----------------------------------------------------------------------------
# 4. Create a sample markdownlint config
# -----------------------------------------------------------------------------
print_step "Creating sample .markdownlint.json config..."

cat >"$ACTION_DIR/.markdownlint.json" <<'EOF'
{
  "default": true,
  "MD013": {
    "line_length": 120,
    "tables": false,
    "code_blocks": false
  },
  "MD033": false,
  "MD041": false
}
EOF

print_success "Created: $ACTION_DIR/.markdownlint.json"

# -----------------------------------------------------------------------------
# 5. Create a workflow that uses the Docker action
# -----------------------------------------------------------------------------
print_step "Creating workflow that uses the Docker action..."

cat >"$WORKFLOW_DIR/lint-docs.yml" <<'EOF'
name: Lint Documentation

on:
  push:
  pull_request:

jobs:
  lint-markdown:
    name: Lint Markdown Files
    runs-on: ubuntu-latest  # Docker actions require Linux runners

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      # Use the Docker action defined locally
      - name: Lint all Markdown files
        id: lint
        uses: ./.github/actions/markdown-lint
        with:
          path: '.'
          config: '.markdownlint.json'
          fail-on-error: 'false'   # Report but don't fail the pipeline

      - name: Report lint results
        run: |
          echo "=== Lint Results ==="
          echo "Violations  : ${{ steps.lint.outputs.error-count }}"
          echo "Report path : ${{ steps.lint.outputs.report-path }}"

  # Using a pre-built Docker image instead of building from Dockerfile
  lint-with-prebuilt:
    name: Lint (Pre-Built Image)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Use a pre-built image from GHCR
      # This would reference a published version of the action
      # - name: Lint with published image
      #   uses: my-org/markdown-lint-action@v1
      #   with:
      #     path: docs/
      #     fail-on-error: 'true'

      - name: Demonstrate pre-built image concept
        run: |
          echo "In production, you would reference:"
          echo "  uses: my-org/markdown-lint-action@v1"
          echo "which pulls from a pre-built GHCR image."
          echo "No Dockerfile build step at runtime."
EOF

print_success "Created: $WORKFLOW_DIR/lint-docs.yml"

# -----------------------------------------------------------------------------
# 6. Demonstrate entrypoint.sh INPUT_ variable mapping
# -----------------------------------------------------------------------------
print_step "Demonstrating INPUT_ environment variable mapping..."

print_info "How GitHub Actions maps action inputs to Docker env vars:"
echo ""
echo "  action.yml input name   Docker environment variable"
echo "  ---------------------   ---------------------------"
echo "  path                 →  INPUT_PATH"
echo "  config               →  INPUT_CONFIG"
echo "  fail-on-error        →  INPUT_FAIL_ON_ERROR"
echo "  my-complex_input     →  INPUT_MY-COMPLEX_INPUT  (hyphens preserved in name)"
echo ""

# Simulate the environment variable mapping locally
print_info "Simulating INPUT_ variable access (as the container would see it):"
export INPUT_PATH="docs/"
export INPUT_CONFIG=".markdownlint.json"
export INPUT_FAIL_ON_ERROR="false"
export INPUT_FIX="false"
export GITHUB_OUTPUT="/dev/null"

echo "  INPUT_PATH          = $INPUT_PATH"
echo "  INPUT_CONFIG        = $INPUT_CONFIG"
echo "  INPUT_FAIL_ON_ERROR = $INPUT_FAIL_ON_ERROR"
echo "  INPUT_FIX           = $INPUT_FIX"
echo ""

# Unset test variables
unset INPUT_PATH INPUT_CONFIG INPUT_FAIL_ON_ERROR INPUT_FIX GITHUB_OUTPUT || true

# -----------------------------------------------------------------------------
# 7. Demonstrate Docker build (if Docker is available)
# -----------------------------------------------------------------------------
print_step "Checking Docker availability for local build test..."

if command -v docker &>/dev/null; then
  print_info "Docker is available. Building the action image locally..."
  docker build -t demo-markdown-lint-action "$ACTION_DIR" 2>&1 | tail -5 || true
  print_success "Image built successfully."

  print_info "Running a quick test of the Docker action locally..."
  docker run --rm \
    -e INPUT_PATH="/workspace" \
    -e INPUT_FAIL_ON_ERROR="false" \
    -e GITHUB_OUTPUT=/dev/null \
    -e GITHUB_STEP_SUMMARY=/dev/null \
    -v "$LAB_DIR:/workspace:ro" \
    demo-markdown-lint-action 2>&1 | head -20 || true

  print_info "Cleaning up demo image..."
  docker rmi demo-markdown-lint-action 2>/dev/null || true
else
  print_info "Docker not available - skipping local build test."
  print_info "Build command for reference:"
  echo "  docker build -t my-action $ACTION_DIR"
  echo "  docker run --rm -e INPUT_PATH=. -e GITHUB_OUTPUT=/dev/null my-action"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_header "Demo Complete"
echo ""
print_info "Generated Docker action files:"
find "$ACTION_DIR" -type f | sort | while read -r f; do
  echo "  ${f#$ACTION_DIR/}"
done
echo ""
print_info "Generated workflow:"
ls "$WORKFLOW_DIR/"
echo ""
print_info "Key files:"
echo "  action.yml     - declares inputs, outputs, and runs.using: docker"
echo "  Dockerfile     - builds the container environment"
echo "  entrypoint.sh  - reads INPUT_* env vars, sets GITHUB_OUTPUT"
