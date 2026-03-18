#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 021 - Dependabot Demo"

# ─────────────────────────────────────────────────────────────
# 1. Create a sample dependabot.yml
# ─────────────────────────────────────────────────────────────
section "1. Creating .github/dependabot.yml"

mkdir -p .github

cat >.github/dependabot.yml <<'YAML'
version: 2

updates:
  # ── GitHub Actions ──────────────────────────────────────────
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
      day: monday
      time: "08:00"
      timezone: "UTC"
    labels:
      - dependencies
      - github-actions
    commit-message:
      prefix: "ci"

  # ── npm / Node.js ────────────────────────────────────────────
  - package-ecosystem: npm
    directory: "/"
    schedule:
      interval: weekly
      day: tuesday
      time: "08:00"
      timezone: "UTC"
    open-pull-requests-limit: 10
    reviewers:
      - maintainer-username
    labels:
      - dependencies
      - javascript
    commit-message:
      prefix: "chore"
      include: scope
    groups:
      aws-sdk:
        patterns:
          - "@aws-sdk/*"
      testing:
        patterns:
          - "jest*"
          - "@testing-library/*"
          - "vitest*"
      linting:
        patterns:
          - "eslint*"
          - "prettier*"
          - "@typescript-eslint/*"
    ignore:
      - dependency-name: "node"
        update-types: ["version-update:semver-major"]

  # ── Docker ───────────────────────────────────────────────────
  - package-ecosystem: docker
    directory: "/"
    schedule:
      interval: monthly
    open-pull-requests-limit: 2
    labels:
      - dependencies
      - docker

  # ── Python backend ───────────────────────────────────────────
  - package-ecosystem: pip
    directory: "/backend"
    schedule:
      interval: weekly
      day: wednesday
    open-pull-requests-limit: 5
    labels:
      - dependencies
      - python

  # ── Terraform ────────────────────────────────────────────────
  - package-ecosystem: terraform
    directory: "/infra"
    schedule:
      interval: monthly
    labels:
      - dependencies
      - infrastructure
YAML

echo "Created: .github/dependabot.yml"
echo ""
cat .github/dependabot.yml

# ─────────────────────────────────────────────────────────────
# 2. Create auto-merge workflow
# ─────────────────────────────────────────────────────────────
section "2. Creating Dependabot Auto-Merge Workflow"

mkdir -p .github/workflows

cat >.github/workflows/dependabot-automerge.yml <<'YAML'
name: Auto-merge Dependabot PRs

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: write
  pull-requests: write

jobs:
  auto-merge:
    runs-on: ubuntu-latest
    if: github.actor == 'dependabot[bot]'

    steps:
      - name: Fetch Dependabot metadata
        id: metadata
        uses: dependabot/fetch-metadata@v2
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}

      - name: Print update info
        run: |
          echo "Package(s): ${{ steps.metadata.outputs.dependency-names }}"
          echo "Update type: ${{ steps.metadata.outputs.update-type }}"
          echo "Dependency type: ${{ steps.metadata.outputs.dependency-type }}"

      - name: Auto-approve patch updates
        if: steps.metadata.outputs.update-type == 'version-update:semver-patch'
        run: gh pr review --approve "$PR_URL"
        env:
          PR_URL: ${{ github.event.pull_request.html_url }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Auto-merge patch and minor dev-dependency updates
        if: |
          steps.metadata.outputs.update-type == 'version-update:semver-patch' ||
          (steps.metadata.outputs.update-type == 'version-update:semver-minor' &&
           steps.metadata.outputs.dependency-type == 'direct:development')
        run: gh pr merge --auto --squash "$PR_URL"
        env:
          PR_URL: ${{ github.event.pull_request.html_url }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
YAML

echo "Created: .github/workflows/dependabot-automerge.yml"

# ─────────────────────────────────────────────────────────────
# 3. Show gh api commands for security alerts
# ─────────────────────────────────────────────────────────────
section "3. Security Alerts - gh api Examples"

echo ""
echo "# List all Dependabot security alerts:"
echo "gh api repos/OWNER/REPO/dependabot/alerts \\"
echo "  --jq '.[] | {number, package: .dependency.package.name, severity: .security_vulnerability.severity, state}'"

echo ""
echo "# Filter by severity (critical and high only):"
echo "gh api repos/OWNER/REPO/dependabot/alerts \\"
echo "  --jq '.[] | select(.security_vulnerability.severity == \"critical\" or .security_vulnerability.severity == \"high\") | {package: .dependency.package.name, severity: .security_vulnerability.severity, cvss: .security_vulnerability.cvss_score}'"

echo ""
echo "# Count alerts by severity:"
echo "gh api repos/OWNER/REPO/dependabot/alerts \\"
echo "  --jq 'group_by(.security_vulnerability.severity) | map({severity: .[0].security_vulnerability.severity, count: length})'"

echo ""
echo "# Dismiss a false-positive alert:"
echo "gh api --method PATCH repos/OWNER/REPO/dependabot/alerts/ALERT_NUMBER \\"
echo "  -f dismissed_reason='tolerable_risk' \\"
echo "  -f dismissed_comment='This dependency is used only in tests'"

# ─────────────────────────────────────────────────────────────
# 4. Live demo if gh is available
# ─────────────────────────────────────────────────────────────
section "4. Live Security Alerts Demo (if gh configured)"

if command_exists gh && gh auth status >/dev/null 2>&1; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  if [ -n "$REPO" ]; then
    echo "Checking Dependabot alerts for: $REPO"
    gh api "repos/${REPO}/dependabot/alerts" \
      --jq '.[] | {number, package: .dependency.package.name, severity: .security_vulnerability.severity, state}' \
      2>/dev/null || echo "(No alerts found or Dependabot not enabled for this repo)"
  fi
else
  echo "(gh not authenticated - showing command reference only)"
fi

# ─────────────────────────────────────────────────────────────
# 5. Ecosystem reference
# ─────────────────────────────────────────────────────────────
section "5. Supported Ecosystems Reference"

echo ""
printf "%-20s %-30s\n" "ECOSYSTEM" "MANIFEST FILE"
printf "%-20s %-30s\n" "─────────────────" "─────────────────────────────"
printf "%-20s %-30s\n" "npm" "package.json"
printf "%-20s %-30s\n" "pip" "requirements.txt / pyproject.toml"
printf "%-20s %-30s\n" "docker" "Dockerfile"
printf "%-20s %-30s\n" "github-actions" ".github/workflows/*.yml"
printf "%-20s %-30s\n" "maven" "pom.xml"
printf "%-20s %-30s\n" "gradle" "build.gradle"
printf "%-20s %-30s\n" "bundler" "Gemfile"
printf "%-20s %-30s\n" "cargo" "Cargo.toml"
printf "%-20s %-30s\n" "gomod" "go.mod"
printf "%-20s %-30s\n" "terraform" "*.tf"

# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────
section "Cleanup"
rm -f .github/dependabot.yml
rm -f .github/workflows/dependabot-automerge.yml
echo "Demo files removed"

section "Lab 021 Complete"
echo "Key takeaways:"
echo "  - dependabot.yml lives in .github/ and configures version updates"
echo "  - 'groups' batch related packages into single PRs"
echo "  - open-pull-requests-limit: 0 pauses version updates"
echo "  - dependabot/fetch-metadata exposes update-type for auto-merge logic"
echo "  - Security updates are automatic and separate from version updates"
