#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 025 - Branch Protection Demo"

# ─────────────────────────────────────────────────────────────
# 1. Show the full branch protection API call
# ─────────────────────────────────────────────────────────────
section "1. Full Branch Protection Configuration (gh api)"

echo ""
echo "# Apply comprehensive branch protection to 'main':"
cat <<'SCRIPT'
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  /repos/OWNER/REPO/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "CI Pipeline / lint",
      "CI Pipeline / test (18)",
      "CI Pipeline / test (20)",
      "CI Pipeline / build"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1,
    "require_last_push_approval": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF
SCRIPT

# ─────────────────────────────────────────────────────────────
# 2. Show GET / READ commands
# ─────────────────────────────────────────────────────────────
section "2. Reading Branch Protection Settings"

echo ""
echo "# Get full protection details:"
echo "gh api /repos/OWNER/REPO/branches/main/protection | jq ."

echo ""
echo "# Check specific settings:"
echo "gh api /repos/OWNER/REPO/branches/main/protection \\"
echo "  --jq '{enforce_admins: .enforce_admins.enabled, required_reviews: .required_pull_request_reviews.required_approving_review_count}'"

echo ""
echo "# Check required status checks:"
echo "gh api /repos/OWNER/REPO/branches/main/protection/required_status_checks \\"
echo "  --jq '.contexts'"

echo ""
echo "# Check if signed commits are required:"
echo "gh api /repos/OWNER/REPO/branches/main/protection/required_signatures \\"
echo "  --jq '.enabled'"

# ─────────────────────────────────────────────────────────────
# 3. Required signed commits
# ─────────────────────────────────────────────────────────────
section "3. Required Signed Commits"

echo ""
echo "# Enable required signed commits:"
echo "gh api \\"
echo "  --method POST \\"
echo "  -H \"Accept: application/vnd.github+json\" \\"
echo "  /repos/OWNER/REPO/branches/main/protection/required_signatures"

echo ""
echo "# Verify it's enabled:"
echo "gh api /repos/OWNER/REPO/branches/main/protection/required_signatures \\"
echo "  --jq '.enabled'"

echo ""
echo "# Disable required signed commits:"
echo "gh api \\"
echo "  --method DELETE \\"
echo "  /repos/OWNER/REPO/branches/main/protection/required_signatures"

# ─────────────────────────────────────────────────────────────
# 4. Create sample CODEOWNERS file
# ─────────────────────────────────────────────────────────────
section "4. Creating Sample .github/CODEOWNERS"

mkdir -p .github

cat >.github/CODEOWNERS <<'CODEOWNERS'
# CODEOWNERS - Auto-assign reviewers based on file patterns
# Format: <pattern> <owner1> [owner2] ...

# Global fallback - all files
*                       @my-org/core-team

# Infrastructure and IaC
infra/                  @my-org/platform-team
*.tf                    @my-org/platform-team
docker-compose*.yml     @my-org/platform-team

# GitHub Actions workflows (security-sensitive)
.github/                @my-org/security-team

# Frontend
src/frontend/           @my-org/frontend-team
*.css                   @my-org/frontend-team
*.scss                  @my-org/frontend-team

# API / Backend
src/api/                @my-org/backend-team
src/services/           @my-org/backend-team

# Database migrations (always require DBA review)
db/migrations/          @my-org/dba-team @my-org/backend-team

# Package dependencies
package.json            @my-org/security-team @my-org/core-team
package-lock.json       @my-org/security-team
requirements.txt        @my-org/security-team
CODEOWNERS

echo "Created: .github/CODEOWNERS"
cat .github/CODEOWNERS

# ─────────────────────────────────────────────────────────────
# 5. Create a workflow to apply branch protection via IaC
# ─────────────────────────────────────────────────────────────
section "5. Branch Protection as Code Workflow"

mkdir -p .github/workflows

cat >.github/workflows/lab025-apply-protection.yml <<'YAML'
name: "Lab 025 - Apply Branch Protection"

on:
  workflow_dispatch:
    inputs:
      repo:
        description: "Repository (owner/repo)"
        type: string
        required: true
      branch:
        description: "Branch to protect"
        type: string
        required: true
        default: "main"

jobs:
  apply-protection:
    runs-on: ubuntu-latest

    steps:
      - name: Apply branch protection
        env:
          GH_TOKEN: ${{ secrets.ADMIN_PAT }}
        run: |
          REPO="${{ inputs.repo }}"
          BRANCH="${{ inputs.branch }}"

          echo "Applying branch protection to ${REPO}/${BRANCH}..."

          gh api \
            --method PUT \
            -H "Accept: application/vnd.github+json" \
            "/repos/${REPO}/branches/${BRANCH}/protection" \
            --input - <<'EOF'
          {
            "required_status_checks": {
              "strict": true,
              "contexts": ["CI / lint", "CI / test", "CI / build"]
            },
            "enforce_admins": true,
            "required_pull_request_reviews": {
              "dismiss_stale_reviews": true,
              "require_code_owner_reviews": false,
              "required_approving_review_count": 1
            },
            "restrictions": null,
            "required_linear_history": true,
            "allow_force_pushes": false,
            "allow_deletions": false,
            "required_conversation_resolution": true
          }
          EOF

          echo "Branch protection applied to ${REPO}/${BRANCH}"

      - name: Verify applied settings
        env:
          GH_TOKEN: ${{ secrets.ADMIN_PAT }}
        run: |
          gh api \
            "/repos/${{ inputs.repo }}/branches/${{ inputs.branch }}/protection" \
            --jq '{
              enforce_admins: .enforce_admins.enabled,
              required_approvals: .required_pull_request_reviews.required_approving_review_count,
              dismiss_stale_reviews: .required_pull_request_reviews.dismiss_stale_reviews,
              strict_status_checks: .required_status_checks.strict,
              required_checks: .required_status_checks.contexts,
              linear_history: .required_linear_history,
              allow_force_push: .allow_force_pushes.enabled
            }'
YAML

echo "Created: .github/workflows/lab025-apply-protection.yml"

# ─────────────────────────────────────────────────────────────
# 6. Live demo if gh is authenticated
# ─────────────────────────────────────────────────────────────
section "6. Live Branch Protection Check (if gh configured)"

if command_exists gh && gh auth status >/dev/null 2>&1; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  if [ -n "$REPO" ]; then
    echo "Checking branch protection for: $REPO"

    # List protected branches
    echo ""
    echo "Protected branches:"
    gh api "repos/${REPO}/branches" \
      --jq '.[] | select(.protected == true) | .name' 2>/dev/null || echo "(none)"

    # Show protection for main if it exists
    echo ""
    echo "Protection details for 'main' (if configured):"
    gh api "repos/${REPO}/branches/main/protection" 2>/dev/null |
      jq '{
            enforce_admins: .enforce_admins.enabled,
            required_approvals: (.required_pull_request_reviews.required_approving_review_count // "not set"),
            allow_force_push: .allow_force_pushes.enabled
          }' 2>/dev/null || echo "(no protection on main, or branch does not exist)"
  fi
else
  echo "(gh not authenticated - showing reference only)"
fi

# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────
section "Cleanup"
rm -f .github/CODEOWNERS
rm -f .github/workflows/lab025-apply-protection.yml
echo "Demo files removed"

section "Lab 025 Complete"
echo "Key takeaways:"
echo "  - Branch protection is configured via PUT /repos/{owner}/{repo}/branches/{branch}/protection"
echo "  - 'strict: true' requires PRs to be up to date before merging"
echo "  - 'dismiss_stale_reviews' removes approvals when new commits are pushed"
echo "  - CODEOWNERS in .github/ auto-assigns reviewers based on file patterns"
echo "  - Required signed commits enforced via POST .../required_signatures"
