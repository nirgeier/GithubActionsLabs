#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 000 - Setup: Tool Verification"

# ─── Check gh CLI ─────────────────────────────────────────────────────────────
section "1. GitHub CLI (gh) Version"
if command_exists gh; then
  gh --version
else
  echo "gh CLI is NOT installed."
  echo "Install it with: brew install gh  (macOS)"
  echo "Or visit: https://cli.github.com"
fi

# ─── Check act ────────────────────────────────────────────────────────────────
section "2. act (Local Runner) Version"
if command_exists act; then
  act --version
else
  echo "act is NOT installed."
  echo "Install it with: brew install act  (macOS)"
  echo "Or visit: https://github.com/nektos/act"
fi

# ─── Check Docker ─────────────────────────────────────────────────────────────
section "3. Docker Status (required by act)"
if command_exists docker; then
  docker --version
  docker info >/dev/null 2>&1 && echo "Docker daemon is running." || echo "Docker daemon is NOT running - start Docker Desktop."
else
  echo "Docker is NOT installed."
  echo "Install it from: https://www.docker.com/products/docker-desktop"
fi

# ─── Check git ────────────────────────────────────────────────────────────────
section "4. Git Version"
git --version
echo "Git user: $(git config --global user.name || echo '(not set)')"
echo "Git email: $(git config --global user.email || echo '(not set)')"

# ─── gh auth status ───────────────────────────────────────────────────────────
section "5. GitHub Authentication Status"
gh auth status || true

# ─── GitHub API access ────────────────────────────────────────────────────────
section "6. GitHub API Access Check"
gh api rate_limit --jq '.rate | "Remaining: \(.remaining)/\(.limit) - Resets at: \(.reset | todate)"' || true

# ─── Create a sample workflow YAML ────────────────────────────────────────────
section "7. Creating a Sample Workflow YAML"

TMPDIR_LAB=$(mktemp -d)
mkdir -p "$TMPDIR_LAB/.github/workflows"

cat >"$TMPDIR_LAB/.github/workflows/hello-world.yml" <<'WORKFLOW_EOF'
name: Hello World

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  greet:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Say Hello
        run: echo "Hello, GitHub Actions!"

      - name: Show context
        run: |
          echo "Repo:  $GITHUB_REPOSITORY"
          echo "Ref:   $GITHUB_REF"
          echo "SHA:   $GITHUB_SHA"
          echo "Actor: $GITHUB_ACTOR"
WORKFLOW_EOF

echo "Sample workflow created at: $TMPDIR_LAB/.github/workflows/hello-world.yml"
echo ""
cat "$TMPDIR_LAB/.github/workflows/hello-world.yml"

# ─── Validate the YAML ────────────────────────────────────────────────────────
section "8. Validating the Sample Workflow YAML"
if command_exists python3; then
  python3 -c "
import yaml, sys
with open('$TMPDIR_LAB/.github/workflows/hello-world.yml') as f:
    yaml.safe_load(f)
print('YAML syntax is VALID.')
" || true
else
  echo "python3 not found - skipping YAML validation."
fi

# ─── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$TMPDIR_LAB"

section "Lab 000 - Setup Complete"
echo "All tools checked. You are ready to start the GitHub Actions labs!"
