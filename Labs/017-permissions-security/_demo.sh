#!/usr/bin/env bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

# =============================================================================
# Lab 017 - Permissions and Security Demo
# Demonstrates: permissions block, SHA pinning patterns, security workflow examples
# =============================================================================

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$LAB_DIR/workflow-examples"

print_header "Lab 017 - Permissions and Security"
print_info "This demo generates workflow YAML files demonstrating permissions and security patterns."

mkdir -p "$WORKFLOW_DIR"

# -----------------------------------------------------------------------------
# 1. Minimal permissions workflow
# -----------------------------------------------------------------------------
print_step "Creating minimal-permissions workflow..."

cat >"$WORKFLOW_DIR/minimal-permissions.yml" <<'EOF'
name: Minimal Permissions Workflow

on:
  push:
    branches: [main]
  pull_request:

# STEP 1: Deny all permissions at workflow level
permissions: {}

jobs:
  # Each job declares only what it actually needs
  lint:
    name: Lint
    runs-on: ubuntu-latest
    permissions:
      contents: read   # Only need to checkout
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - uses: actions/setup-node@39370e3970a6d050c480ffad4ff0ed4d3fdee5af  # v4.1.0
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci && npm run lint

  test:
    name: Test
    runs-on: ubuntu-latest
    permissions:
      contents: read   # Only need to checkout
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - uses: actions/setup-node@39370e3970a6d050c480ffad4ff0ed4d3fdee5af  # v4.1.0
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci && npm test

  pr-comment:
    name: PR Comment
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    permissions:
      contents: read        # For checkout
      pull-requests: write  # For posting the comment
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - uses: actions/github-script@60a0d83039c74a4aee543508d2ffcb1c3799cdea  # v7.0.1
        with:
          script: |
            github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.payload.pull_request.number,
              body: 'CI passed! All checks green.'
            })

  release:
    name: Release
    runs-on: ubuntu-latest
    needs: [lint, test]
    if: github.ref == 'refs/heads/main'
    permissions:
      contents: write   # For creating tags and releases
      packages: write   # For GitHub Packages
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - run: echo "Would publish release here"
EOF

print_success "Created: $WORKFLOW_DIR/minimal-permissions.yml"

# -----------------------------------------------------------------------------
# 2. SHA pinning examples
# -----------------------------------------------------------------------------
print_step "Creating SHA-pinned workflow examples..."

cat >"$WORKFLOW_DIR/sha-pinned-actions.yml" <<'EOF'
name: SHA-Pinned Actions (Secure)

on: [push]

permissions:
  contents: read

# ============================================================
# All third-party action references are pinned to an immutable
# commit SHA instead of a mutable tag like @v4.
# The human-readable tag is preserved as a comment.
# ============================================================

jobs:
  secure-build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      # actions/checkout pinned to SHA
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      # actions/setup-node pinned to SHA
      - uses: actions/setup-node@39370e3970a6d050c480ffad4ff0ed4d3fdee5af  # v4.1.0
        with:
          node-version: '20'
          cache: 'npm'

      # actions/cache pinned to SHA
      - uses: actions/cache@d4323d4df104b026a6aa633fdb11d772de78408d  # v4.2.1
        with:
          path: ~/.npm
          key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}

      - run: npm ci && npm test

      # actions/upload-artifact pinned to SHA
      - uses: actions/upload-artifact@65c4c4a1ddee5b72f698fdd19549f0f0fb45cf08  # v4.6.1
        if: always()
        with:
          name: test-results
          path: test-results/

  codeql:
    runs-on: ubuntu-latest
    permissions:
      actions: read
      contents: read
      security-events: write
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      # github/codeql-action pinned to SHA
      - uses: github/codeql-action/init@e675ced7a7522a761fc9c8eb26682c8b27c9dab9  # v3.28.0
        with:
          languages: javascript, typescript

      - uses: github/codeql-action/autobuild@e675ced7a7522a761fc9c8eb26682c8b27c9dab9  # v3.28.0

      - uses: github/codeql-action/analyze@e675ced7a7522a761fc9c8eb26682c8b27c9dab9  # v3.28.0
        with:
          category: '/language:javascript'
EOF

print_success "Created: $WORKFLOW_DIR/sha-pinned-actions.yml"

# -----------------------------------------------------------------------------
# 3. pull_request_target safe pattern
# -----------------------------------------------------------------------------
print_step "Creating pull_request_target safe-pattern workflow..."

cat >"$WORKFLOW_DIR/pr-target-safe.yml" <<'EOF'
# =============================================================
# SAFE pull_request_target usage
#
# pull_request_target runs with write access to the BASE repo,
# even for fork PRs. This is powerful but dangerous.
#
# SAFE rules:
#   1. NEVER checkout PR head code in a pull_request_target workflow
#   2. Only work with PR METADATA (labels, comments, etc.)
#   3. If you MUST build PR code, do it in a SEPARATE pull_request workflow
#      and share results via artifacts or commit statuses.
# =============================================================
name: Safe PR Target Workflow

on: pull_request_target

permissions: {}

jobs:
  # SAFE: Only modifies labels - does NOT checkout or run PR code
  label-pr:
    name: Auto-label PR
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write   # Only needs to write PR labels
    steps:
      - uses: actions/github-script@60a0d83039c74a4aee543508d2ffcb1c3799cdea  # v7.0.1
        with:
          script: |
            const pr = context.payload.pull_request;
            const labels = [];

            // Label based on PR title
            if (pr.title.startsWith('fix:') || pr.title.startsWith('Fix:')) {
              labels.push('bug');
            } else if (pr.title.startsWith('feat:') || pr.title.startsWith('Feature:')) {
              labels.push('enhancement');
            } else if (pr.title.startsWith('docs:')) {
              labels.push('documentation');
            }

            if (labels.length > 0) {
              await github.rest.issues.addLabels({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: pr.number,
                labels,
              });
              core.info(`Applied labels: ${labels.join(', ')}`);
            }

  # SAFE: Welcome message for first-time contributors (metadata only)
  welcome-first-timer:
    name: Welcome First-Time Contributors
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
      issues: write
    steps:
      - uses: actions/github-script@60a0d83039c74a4aee543508d2ffcb1c3799cdea  # v7.0.1
        with:
          script: |
            const pr = context.payload.pull_request;
            const { owner, repo } = context.repo;

            // Check if this is the author's first PR
            const { data: prs } = await github.rest.pulls.list({
              owner, repo,
              state: 'all',
              head: `${pr.user.login}:`,
            });

            if (prs.length <= 1) {
              await github.rest.issues.createComment({
                owner, repo,
                issue_number: pr.number,
                body: `Welcome to the project, @${pr.user.login}! 🎉 Thank you for your first contribution.`,
              });
            }

# DANGEROUS example - DO NOT USE:
# jobs:
#   run-pr-code:
#     runs-on: ubuntu-latest
#     steps:
#       - uses: actions/checkout@v4
#         with:
#           ref: ${{ github.event.pull_request.head.sha }}  # ATTACKER CONTROLLED!
#       - run: npm test  # RUNS ATTACKER CODE WITH WRITE PERMISSIONS!
EOF

print_success "Created: $WORKFLOW_DIR/pr-target-safe.yml"

# -----------------------------------------------------------------------------
# 4. Dependency review workflow
# -----------------------------------------------------------------------------
print_step "Creating dependency review workflow..."

cat >"$WORKFLOW_DIR/dependency-review.yml" <<'EOF'
name: Dependency Review

on: pull_request

permissions:
  contents: read
  pull-requests: write

jobs:
  dependency-review:
    name: Dependency Review
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2

      - uses: actions/dependency-review-action@67d4f4b543f4d2b3b9f35e8b16a55f225451db7a  # v4.5.0
        with:
          # Fail the check if any dependency has a vulnerability of this severity or higher
          fail-on-severity: moderate
          # Post a summary comment on the PR
          comment-summary-in-pr: always
          # Block dependencies with these licenses
          deny-licenses: GPL-2.0, AGPL-3.0
          # Allow known safe advisories to be ignored
          # allow-ghsas: GHSA-xxxx-yyyy-zzzz
EOF

print_success "Created: $WORKFLOW_DIR/dependency-review.yml"

# -----------------------------------------------------------------------------
# 5. Demonstrate SHA lookup for common actions
# -----------------------------------------------------------------------------
print_step "Demonstrating SHA lookup for action pinning..."

print_info "How to find the SHA for a specific action tag:"
echo ""
echo "  # Using git ls-remote:"
echo "  git ls-remote https://github.com/actions/checkout.git refs/tags/v4"
echo ""
echo "  # Using gh CLI:"
echo "  gh api repos/actions/checkout/git/refs/tags/v4"
echo ""
echo "  # Using curl:"
echo "  curl -s https://api.github.com/repos/actions/checkout/git/refs/tags/v4 | jq '.object.sha'"
echo ""

if command -v gh &>/dev/null; then
  print_info "Looking up current SHA for actions/checkout@v4..."
  SHA=$(gh api repos/actions/checkout/git/refs/tags/v4 --jq '.object.sha' 2>/dev/null || echo "N/A")
  echo "  actions/checkout v4 tag SHA: $SHA"
  echo "  Usage: uses: actions/checkout@$SHA  # v4"
else
  print_info "gh CLI not available - showing pre-known SHA examples:"
  echo "  actions/checkout@v4  → 11bd71901bbe5b1630ceea73d27597364c9af683"
  echo "  actions/setup-node@v4 → 39370e3970a6d050c480ffad4ff0ed4d3fdee5af"
fi

# -----------------------------------------------------------------------------
# 6. Security checklist audit
# -----------------------------------------------------------------------------
print_step "Running security checklist on generated workflows..."

ISSUES=0

for wf in "$WORKFLOW_DIR"/*.yml; do
  WF_NAME=$(basename "$wf")
  print_info "Auditing: $WF_NAME"

  # Check for write-all permissions
  if grep -q "permissions: write-all" "$wf" 2>/dev/null; then
    echo "  [WARN] Found 'permissions: write-all' - consider restricting"
    ISSUES=$((ISSUES + 1))
  fi

  # Check for mutable action tags (non-SHA references)
  MUTABLE_REFS=$(grep -E "uses: [^@]+@v[0-9]" "$wf" 2>/dev/null | grep -v "#" || true)
  if [ -n "$MUTABLE_REFS" ]; then
    echo "  [WARN] Mutable action tag references found (consider pinning to SHA):"
    echo "$MUTABLE_REFS" | while read -r line; do echo "    $line"; done
    ISSUES=$((ISSUES + 1))
  fi

  # Check for hardcoded tokens
  if grep -qiE "(token|secret|password)\s*=\s*['\"][a-zA-Z0-9_-]{10,}" "$wf" 2>/dev/null; then
    echo "  [ERROR] Potential hardcoded secret found!"
    ISSUES=$((ISSUES + 1))
  else
    echo "  [OK] No hardcoded secrets detected"
  fi

  # Check permissions block exists
  if grep -q "permissions:" "$wf" 2>/dev/null; then
    echo "  [OK] permissions block found"
  else
    echo "  [INFO] No permissions block - using repository defaults"
  fi
done

echo ""
if [ $ISSUES -gt 0 ]; then
  print_info "Audit found $ISSUES potential issues - review the warnings above"
else
  print_success "Audit complete - no critical issues found"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_header "Demo Complete"
print_success "Generated workflow files in: $WORKFLOW_DIR"
echo ""
print_info "Files created:"
ls -1 "$WORKFLOW_DIR/"
echo ""
print_info "Security checklist:"
echo "  [x] Use permissions: {} at workflow level, grant minimally per job"
echo "  [x] Pin third-party actions to commit SHAs"
echo "  [x] Never checkout PR code in pull_request_target"
echo "  [x] Use Dependency Review Action on pull_request"
echo "  [x] Reference secrets via \${{ secrets.NAME }} - never hardcode"
echo "  [x] Use OIDC instead of static cloud credentials"
