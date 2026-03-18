#!/usr/bin/env bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

# =============================================================================
# Lab 014 - Composite Actions Demo
# Demonstrates: creating a composite action.yml and a workflow that uses it
# =============================================================================

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$LAB_DIR/demo-output"
ACTION_DIR="$OUTPUT_DIR/.github/actions/node-ci-setup"
WORKFLOW_DIR="$OUTPUT_DIR/.github/workflows"

print_header "Lab 014 - Composite Actions"
print_info "This demo generates a sample composite action and a workflow that uses it."

mkdir -p "$ACTION_DIR" "$WORKFLOW_DIR"

# -----------------------------------------------------------------------------
# 1. Create the composite action
# -----------------------------------------------------------------------------
print_step "Creating composite action: .github/actions/node-ci-setup/action.yml..."

cat >"$ACTION_DIR/action.yml" <<'EOF'
# =============================================================
# Composite Action: node-ci-setup
# Bundles checkout + Node.js setup + dependency install + optional lint
# =============================================================
name: Node.js CI Setup
description: >
  Sets up Node.js with dependency caching, installs dependencies,
  and optionally runs lint. Returns the Node.js version and cache status.

# ---- INPUTS ----
inputs:
  node-version:
    description: 'Node.js version to install (e.g. 18, 20, 22)'
    required: false
    default: '20'

  package-manager:
    description: 'Package manager to use: npm | yarn | pnpm'
    required: false
    default: 'npm'

  install-command:
    description: 'Dependency install command (overrides package-manager default)'
    required: false
    default: ''

  working-directory:
    description: 'Directory to run commands in (for monorepos)'
    required: false
    default: '.'

  run-lint:
    description: 'Whether to run lint after install (true/false)'
    required: false
    default: 'false'

  lint-command:
    description: 'Lint command to run (when run-lint is true)'
    required: false
    default: 'npm run lint'

# ---- OUTPUTS ----
outputs:
  node-version-used:
    description: 'The exact Node.js version that was installed'
    value: ${{ steps.setup-node.outputs.node-version }}

  cache-hit:
    description: 'true if the dependency cache was restored (no install needed)'
    value: ${{ steps.setup-node.outputs.cache-hit }}

# ---- STEPS ----
runs:
  using: composite
  steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Setup Node.js
      id: setup-node
      uses: actions/setup-node@v4
      with:
        node-version: ${{ inputs.node-version }}
        cache: ${{ inputs.package-manager }}
        cache-dependency-path: ${{ inputs.working-directory }}/package-lock.json

    - name: Determine install command
      id: resolve-install
      shell: bash
      run: |
        # Use explicit override if provided, otherwise use package-manager default
        CUSTOM="${{ inputs.install-command }}"
        if [ -n "$CUSTOM" ]; then
          echo "cmd=$CUSTOM" >> "$GITHUB_OUTPUT"
        else
          case "${{ inputs.package-manager }}" in
            yarn) echo "cmd=yarn install --frozen-lockfile" >> "$GITHUB_OUTPUT" ;;
            pnpm) echo "cmd=pnpm install --frozen-lockfile" >> "$GITHUB_OUTPUT" ;;
            *)    echo "cmd=npm ci" >> "$GITHUB_OUTPUT" ;;
          esac
        fi

    - name: Install dependencies
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      run: ${{ steps.resolve-install.outputs.cmd }}

    - name: Run lint
      if: inputs.run-lint == 'true'
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      run: ${{ inputs.lint-command }}
EOF

print_success "Created: $ACTION_DIR/action.yml"

# -----------------------------------------------------------------------------
# 2. Create a simple greeter composite action
# -----------------------------------------------------------------------------
print_step "Creating simple composite action: .github/actions/greet/action.yml..."

mkdir -p "$OUTPUT_DIR/.github/actions/greet"

cat >"$OUTPUT_DIR/.github/actions/greet/action.yml" <<'EOF'
name: Greet User
description: Prints a greeting and outputs the message

inputs:
  name:
    description: 'Name to greet'
    required: true
  language:
    description: 'Language for greeting: english | spanish | french'
    required: false
    default: 'english'

outputs:
  message:
    description: 'The greeting message that was printed'
    value: ${{ steps.greet.outputs.message }}

runs:
  using: composite
  steps:
    - name: Generate greeting
      id: greet
      shell: bash
      run: |
        NAME="${{ inputs.name }}"
        case "${{ inputs.language }}" in
          spanish) MSG="Hola, $NAME!" ;;
          french)  MSG="Bonjour, $NAME!" ;;
          *)       MSG="Hello, $NAME!" ;;
        esac
        echo "message=$MSG" >> "$GITHUB_OUTPUT"
        echo "$MSG"
EOF

print_success "Created: $OUTPUT_DIR/.github/actions/greet/action.yml"

# -----------------------------------------------------------------------------
# 3. Create a workflow that uses both composite actions
# -----------------------------------------------------------------------------
print_step "Creating workflow that uses the composite actions..."

cat >"$WORKFLOW_DIR/ci-using-composite.yml" <<'EOF'
# =============================================================
# Workflow that uses composite actions defined in .github/actions/
# =============================================================
name: CI using Composite Actions

on:
  push:
    branches: [main, develop]
  pull_request:

jobs:
  # ---- Use the greet action ----
  greet:
    name: Greet
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Greet in English
        id: en
        uses: ./.github/actions/greet
        with:
          name: 'World'
          language: english

      - name: Greet in Spanish
        id: es
        uses: ./.github/actions/greet
        with:
          name: 'Mundo'
          language: spanish

      - name: Show greeting outputs
        run: |
          echo "English: ${{ steps.en.outputs.message }}"
          echo "Spanish: ${{ steps.es.outputs.message }}"

  # ---- Use the node-ci-setup composite action ----
  test:
    name: Test
    runs-on: ubuntu-latest
    steps:
      - name: Setup Node.js CI environment
        id: setup
        uses: ./.github/actions/node-ci-setup
        with:
          node-version: '20'
          package-manager: 'npm'
          working-directory: '.'
          run-lint: 'true'

      - name: Print setup outputs
        run: |
          echo "Node.js version: ${{ steps.setup.outputs.node-version-used }}"
          echo "Cache hit: ${{ steps.setup.outputs.cache-hit }}"

      - name: Run tests
        run: npm test

  # ---- Matrix usage - same composite action, multiple versions ----
  test-matrix:
    name: Test Node.js ${{ matrix.node-version }}
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: ['18', '20', '22']
    steps:
      - name: Setup CI environment
        id: setup
        uses: ./.github/actions/node-ci-setup
        with:
          node-version: ${{ matrix.node-version }}
          run-lint: ${{ matrix.node-version == '20' && 'true' || 'false' }}

      - name: Run tests
        run: npm test

      - name: Report
        run: echo "Tests passed on Node.js ${{ steps.setup.outputs.node-version-used }}"

  # ---- Build job using the same setup action ----
  build:
    name: Build
    runs-on: ubuntu-latest
    needs: test
    steps:
      - name: Setup CI environment
        uses: ./.github/actions/node-ci-setup
        with:
          node-version: '20'

      - name: Build
        run: npm run build

      - uses: actions/upload-artifact@v4
        with:
          name: dist
          path: dist/
EOF

print_success "Created: $WORKFLOW_DIR/ci-using-composite.yml"

# -----------------------------------------------------------------------------
# 4. Show action.yml validation (check for required fields)
# -----------------------------------------------------------------------------
print_step "Validating composite action structure..."

validate_action_yml() {
  local file="$1"
  local name
  name=$(basename "$(dirname "$file")")
  print_info "Validating: $name/action.yml"

  # Check required fields
  local valid=true
  for field in "name:" "description:" "runs:" "using: composite"; do
    if grep -q "$field" "$file"; then
      echo "  [OK] $field"
    else
      echo "  [MISSING] $field"
      valid=false
    fi
  done

  # Check that all run steps have shell:
  local run_count shell_count
  run_count=$(grep -c "^\s*run:" "$file" || true)
  shell_count=$(grep -c "shell:" "$file" || true)
  if [ "$run_count" -gt 0 ] && [ "$shell_count" -ge "$run_count" ]; then
    echo "  [OK] All run steps have shell: specified ($shell_count shell declarations)"
  elif [ "$run_count" -gt 0 ]; then
    echo "  [WARN] $run_count run steps but only $shell_count shell declarations (some may be missing shell:)"
  fi

  $valid && print_success "$name/action.yml looks valid" || print_info "Fix missing fields before use"
}

validate_action_yml "$ACTION_DIR/action.yml"
echo ""
validate_action_yml "$OUTPUT_DIR/.github/actions/greet/action.yml"
echo ""

# -----------------------------------------------------------------------------
# 5. Show directory tree of generated files
# -----------------------------------------------------------------------------
print_step "Final directory structure..."

print_info "Generated composite action files:"
find "$OUTPUT_DIR" -type f | sort | while read -r f; do
  echo "  ${f#$OUTPUT_DIR/}"
done

# -----------------------------------------------------------------------------
# 6. Summary of usage patterns
# -----------------------------------------------------------------------------
print_step "Composite action usage reference..."

print_info "Same-repository action reference:"
echo '  - uses: ./.github/actions/node-ci-setup'
echo '    with:'
echo '      node-version: "20"'
echo ""
print_info "Public repository action reference:"
echo '  - uses: my-org/my-actions/node-ci-setup@v1'
echo '    with:'
echo '      node-version: "20"'
echo ""
print_info "Version pinning strategies:"
echo "  @v1          - floating major version tag (recommended for consumers)"
echo "  @v1.2.3      - pinned exact release"
echo "  @main        - latest commit (unstable)"
echo "  @abc1234def  - pinned SHA (most secure)"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_header "Demo Complete"
print_success "Generated composite action and workflow files in: $OUTPUT_DIR"
