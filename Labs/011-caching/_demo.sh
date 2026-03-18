#!/usr/bin/env bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

# =============================================================================
# Lab 011 - Caching Demo
# Demonstrates: workflow YAML examples for Node.js and Python caching,
#               cache key patterns, and restore-key fallback strategies
# =============================================================================

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$LAB_DIR/workflow-examples"

print_header "Lab 011 - Caching"
print_info "This demo generates workflow YAML files demonstrating caching strategies."

mkdir -p "$WORKFLOW_DIR"

# -----------------------------------------------------------------------------
# 1. Node.js caching workflow
# -----------------------------------------------------------------------------
print_step "Creating Node.js caching workflow..."

cat >"$WORKFLOW_DIR/nodejs-cache.yml" <<'EOF'
name: Node.js Workflow with Caching

on:
  push:
    branches: [main, develop]
  pull_request:

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: ['18', '20', '22']

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      # Method 1: Built-in cache via setup-node (recommended)
      - name: Setup Node.js ${{ matrix.node-version }} with cache
        uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
          cache: 'npm'   # Caches ~/.npm automatically

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test

      - name: Build
        run: npm run build

  # Demonstrate manual cache control with cache-hit output
  build-with-manual-cache:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Cache node_modules
        id: cache-node-modules
        uses: actions/cache@v4
        with:
          path: node_modules
          key: ${{ runner.os }}-node20-modules-${{ hashFiles('package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-node20-modules-
            ${{ runner.os }}-node20-

      - name: Install dependencies (only on cache miss)
        if: steps.cache-node-modules.outputs.cache-hit != 'true'
        run: npm ci

      - name: Report cache status
        run: |
          echo "Cache hit: ${{ steps.cache-node-modules.outputs.cache-hit }}"
          if [ "${{ steps.cache-node-modules.outputs.cache-hit }}" == "true" ]; then
            echo "Skipped npm ci - restored from cache!"
          else
            echo "Cache miss - installed fresh dependencies"
          fi

      - name: Run build
        run: npm run build
EOF

print_success "Created: $WORKFLOW_DIR/nodejs-cache.yml"

# -----------------------------------------------------------------------------
# 2. Python caching workflow
# -----------------------------------------------------------------------------
print_step "Creating Python caching workflow..."

cat >"$WORKFLOW_DIR/python-cache.yml" <<'EOF'
name: Python Workflow with Caching

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test-with-setup-python-cache:
    name: Python (built-in cache)
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ['3.11', '3.12']

    steps:
      - uses: actions/checkout@v4

      # Method 1: Built-in cache via setup-python
      - name: Setup Python ${{ matrix.python-version }} with cache
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
          cache: 'pip'
          cache-dependency-path: |
            requirements.txt
            requirements-dev.txt

      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install -r requirements-dev.txt

      - name: Run tests
        run: pytest --tb=short

  test-with-manual-pip-cache:
    name: Python (manual cache)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      # Method 2: Manual pip cache control
      - name: Cache pip packages
        id: pip-cache
        uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: ${{ runner.os }}-pip-${{ hashFiles('requirements*.txt') }}
          restore-keys: |
            ${{ runner.os }}-pip-

      - name: Install dependencies
        run: pip install -r requirements.txt -r requirements-dev.txt

      - name: Run tests
        run: pytest

  test-with-venv-cache:
    name: Python (virtualenv cache)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      # Method 3: Cache the entire virtualenv
      # Fastest on hit, but platform-specific
      - name: Cache virtualenv
        id: venv-cache
        uses: actions/cache@v4
        with:
          path: .venv
          key: ${{ runner.os }}-venv-py3.12-${{ hashFiles('requirements*.txt') }}

      - name: Create virtualenv and install (cache miss only)
        if: steps.venv-cache.outputs.cache-hit != 'true'
        run: |
          python -m venv .venv
          .venv/bin/pip install --upgrade pip
          .venv/bin/pip install -r requirements.txt

      - name: Run tests in virtualenv
        run: |
          source .venv/bin/activate
          pytest
EOF

print_success "Created: $WORKFLOW_DIR/python-cache.yml"

# -----------------------------------------------------------------------------
# 3. Multi-language caching workflow
# -----------------------------------------------------------------------------
print_step "Creating multi-language caching workflow..."

cat >"$WORKFLOW_DIR/multi-language-cache.yml" <<'EOF'
name: Multi-Language Monorepo Cache

on: [push]

jobs:
  frontend:
    name: Frontend (Node.js)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: frontend/package-lock.json
      - run: cd frontend && npm ci && npm run build && npm test

  backend-python:
    name: Backend Python
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
          cache: 'pip'
          cache-dependency-path: backend/requirements.txt
      - run: |
          cd backend
          pip install -r requirements.txt
          pytest

  backend-java:
    name: Backend Java
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
          cache: 'maven'   # or 'gradle'
      - run: cd java-service && mvn --batch-mode clean verify

  backend-gradle:
    name: Backend Gradle
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
          cache: 'gradle'
      - name: Cache Gradle wrapper
        uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: ${{ runner.os }}-gradle-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
          restore-keys: |
            ${{ runner.os }}-gradle-
      - run: cd gradle-service && ./gradlew build
EOF

print_success "Created: $WORKFLOW_DIR/multi-language-cache.yml"

# -----------------------------------------------------------------------------
# 4. Demonstrate cache key computation locally
# -----------------------------------------------------------------------------
print_step "Demonstrating cache key hash computation..."

DEMO_DIR=$(mktemp -d)
trap 'rm -rf "$DEMO_DIR"' EXIT

# Simulate package-lock.json
cat >"$DEMO_DIR/package-lock.json" <<'PKGJSON'
{
  "name": "demo-app",
  "version": "1.0.0",
  "lockfileVersion": 3,
  "dependencies": {
    "express": { "version": "4.18.2" },
    "lodash": { "version": "4.17.21" }
  }
}
PKGJSON

# Simulate requirements.txt
cat >"$DEMO_DIR/requirements.txt" <<'REQTXT'
flask==3.0.0
pytest==7.4.3
requests==2.31.0
REQTXT

LOCK_HASH=$(sha256sum "$DEMO_DIR/package-lock.json" | cut -c1-16)
REQ_HASH=$(sha256sum "$DEMO_DIR/requirements.txt" | cut -c1-16)
OS="Linux"

print_info "Example cache key computation (simulating hashFiles()):"
echo ""
echo "  package-lock.json hash : $LOCK_HASH..."
echo "  requirements.txt hash  : $REQ_HASH..."
echo ""
echo "  Resulting Node.js cache key:"
echo "    $OS-node-$LOCK_HASH..."
echo ""
echo "  Resulting Python cache key:"
echo "    $OS-pip-$REQ_HASH..."
echo ""

# Simulate lock file change
echo '    "axios": { "version": "1.6.0" }' >>"$DEMO_DIR/package-lock.json"
NEW_HASH=$(sha256sum "$DEMO_DIR/package-lock.json" | cut -c1-16)

print_info "After adding a new dependency to package-lock.json:"
echo "  Old hash : $LOCK_HASH..."
echo "  New hash : $NEW_HASH..."
echo "  → Cache MISS - npm ci will run fresh"
echo "  → Old cache used as restore-key fallback: $OS-node-"
echo ""

# -----------------------------------------------------------------------------
# 5. Cache eviction and limits
# -----------------------------------------------------------------------------
print_step "Displaying cache limits and eviction rules..."

print_info "GitHub Actions Cache Limits:"
echo ""
echo "  Per-entry limit    : 10 GB"
echo "  Per-repo total     : 10 GB"
echo "  Eviction policy    : Least Recently Used (LRU)"
echo "  Auto-expiry        : Entries not accessed in 7 days are deleted"
echo ""
print_info "Cache Scope Rules:"
echo ""
echo "  Push to branch A   → reads Branch A caches, then default branch caches"
echo "  Pull Request       → reads base branch caches (read-only for fork PRs)"
echo "  Default branch     → reads any branch's caches (global fallback)"
echo ""

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
echo "  - Use setup-node/setup-python/setup-java 'cache:' for zero-config caching"
echo "  - Always include runner.os and hashFiles() in your cache key"
echo "  - Add restore-keys for fallback to partial cache on key miss"
echo "  - Use cache-hit output to skip install steps on exact cache hit"
