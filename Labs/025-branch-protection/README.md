# Lab 025 - Branch Protection

## Introduction

**Branch protection rules** enforce quality gates at the Git level, preventing anyone - including repository admins - from merging code that hasn't passed your required checks, received the necessary reviews, or been approved by the right people. This lab covers configuring branch protection via the GitHub API using `gh api`, understanding every available protection option, and building workflows that work harmoniously with those protections.

---

## Why Branch Protection Matters

Without branch protection, a single `git push -f` or a hasty merge can bypass every quality gate your CI pipeline enforces. Branch protection rules make your standards enforceable:

- Require all tests to pass before merge
- Prevent force-pushes that rewrite shared history
- Enforce code reviews from domain owners
- Mandate signed commits for auditability
- Keep history linear for clean `git log` and bisect operations

---

## 1. GitHub Branch Protection Architecture

Branch protection rules are configured at the repository level and apply to one or more branches by name or glob pattern. Rules can be configured:

- Via the GitHub web UI (Settings > Branches)
- Via the GitHub REST API (used by `gh api`)
- Via Infrastructure-as-Code tools (Terraform `github_branch_protection` resource)
- Via `gh api` in automated scripts and workflows

---

## 2. Configuring Branch Protection with `gh api`

The REST endpoint for branch protection is:

```
PUT /repos/{owner}/{repo}/branches/{branch}/protection
```

### Minimal Protection (require CI checks)

```bash
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
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF
```

### Read Current Protection

```bash
gh api \
  -H "Accept: application/vnd.github+json" \
  /repos/OWNER/REPO/branches/main/protection \
  | jq .
```

### Remove Protection (use with care)

```bash
gh api \
  --method DELETE \
  -H "Accept: application/vnd.github+json" \
  /repos/OWNER/REPO/branches/main/protection
```

---

## 3. Required Status Checks

`required_status_checks` ensures the branch can only be merged when specified CI jobs have passed:

```json
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "CI Pipeline / lint",
      "CI Pipeline / test (18)",
      "CI Pipeline / test (20)",
      "CI Pipeline / build"
    ]
  }
}
```

- **`strict: true`**: The branch must be up to date with the base branch before merging (prevents "works on my branch" merges)
- **`strict: false`**: Checks must pass but the branch doesn't need to be up to date
- **`contexts`**: Exact names of the required checks (job names as they appear in the Checks tab)

### Using the Checks API (v2)

The newer `required_status_checks` format uses `checks` instead of `contexts` for more precise matching:

```bash
gh api \
  --method PUT \
  /repos/OWNER/REPO/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "checks": [
      { "context": "CI Pipeline / lint" },
      { "context": "CI Pipeline / test (18)", "app_id": 15368 },
      { "context": "CI Pipeline / build" }
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
EOF
```

---

## 4. Required Pull Request Reviews

```json
{
  "required_pull_request_reviews": {
    "dismissal_restrictions": {
      "users": ["lead-developer"],
      "teams": ["my-org/senior-engineers"]
    },
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 2,
    "require_last_push_approval": true
  }
}
```

| Field                             | Description                                    |
| --------------------------------- | ---------------------------------------------- |
| `dismiss_stale_reviews`           | Remove approvals when new commits are pushed   |
| `require_code_owner_reviews`      | Require approval from CODEOWNERS entries       |
| `required_approving_review_count` | Number of approvals needed (0–6)               |
| `require_last_push_approval`      | The last person to push cannot be the approver |
| `dismissal_restrictions`          | Who can dismiss reviews                        |

### CODEOWNERS File

Create `.github/CODEOWNERS` to automatically request review from domain owners:

```
# Global owners
*                   @my-org/core-team

# Infrastructure
infra/              @my-org/platform-team
*.tf                @my-org/platform-team

# Frontend
src/frontend/       @my-org/frontend-team
*.css               @my-org/frontend-team

# Security-sensitive files
.github/            @my-org/security-team
**/secrets.*        @my-org/security-team
```

---

## 5. Push Restrictions

Limit who can push directly to the branch (bypassing PR requirement):

```json
{
  "restrictions": {
    "users": ["release-bot"],
    "teams": ["my-org/release-team"],
    "apps": ["my-github-app"]
  }
}
```

Set `restrictions` to `null` to allow anyone with write access to push.

---

## 6. Linear History

Requiring linear history prevents merge commits and forces contributors to rebase:

```json
{
  "required_linear_history": true,
  "allow_force_pushes": false
}
```

This keeps `git log --oneline` readable and makes `git bisect` accurate. Enforce it alongside a squash-merge or rebase-merge policy in the repository settings.

---

## 7. Signed Commits

Require that all commits on the protected branch are GPG-signed or verified by GitHub:

```bash
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  /repos/OWNER/REPO/branches/main/protection/required_signatures
```

Verify the setting:

```bash
gh api \
  /repos/OWNER/REPO/branches/main/protection/required_signatures \
  --jq '.enabled'
```

Remove the requirement:

```bash
gh api \
  --method DELETE \
  /repos/OWNER/REPO/branches/main/protection/required_signatures
```

---

## 8. Bypass Lists (GitHub Enterprise / Fine-Grained Tokens)

In GitHub Enterprise and some org plans, you can define bypass actors - users, teams, or apps that can bypass the protection rules:

```json
{
  "bypass_pull_request_allowances": {
    "users": ["emergency-bot"],
    "teams": ["my-org/security-incident-response"],
    "apps": []
  }
}
```

---

## 9. Workflow to Enforce Protection via IaC

Automate branch protection setup when a new repository is created:

```yaml
name: Configure Branch Protection

on:
  workflow_dispatch:
    inputs:
      repo:
        description: "Repository (owner/repo)"
        type: string
        required: true

jobs:
  configure:
    runs-on: ubuntu-latest
    steps:
      - name: Apply branch protection to main
        env:
          GH_TOKEN: ${{ secrets.ADMIN_PAT }}
        run: |
          REPO="${{ inputs.repo }}"
          gh api \
            --method PUT \
            -H "Accept: application/vnd.github+json" \
            /repos/${REPO}/branches/main/protection \
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
          echo "Branch protection applied to ${REPO}/main"
```

---

## 10. Status Check Badge in README

Show the live CI status badge for the protected branch:

```markdown
## Build Status

| Check         | Status                                                                                          |
| ------------- | ----------------------------------------------------------------------------------------------- |
| CI Pipeline   | ![CI](https://github.com/OWNER/REPO/actions/workflows/ci.yml/badge.svg?branch=main)             |
| Security Scan | ![Security](https://github.com/OWNER/REPO/actions/workflows/security.yml/badge.svg?branch=main) |
```

---

## 11. Listing and Auditing Branch Protection

```bash
# List all protected branches
gh api /repos/OWNER/REPO/branches \
  --jq '.[] | select(.protected == true) | .name'

# Full protection details for main
gh api /repos/OWNER/REPO/branches/main/protection | jq .

# Check required status checks
gh api /repos/OWNER/REPO/branches/main/protection/required_status_checks \
  --jq '.contexts'

# Check if admins are enforced
gh api /repos/OWNER/REPO/branches/main/protection \
  --jq '.enforce_admins.enabled'

# Check if signed commits are required
gh api /repos/OWNER/REPO/branches/main/protection/required_signatures \
  --jq '.enabled'
```

---

## Hands-on

1. Enable branch protection on `main` requiring a status check named `CI / test` using `gh api`:

   ??? success "Solution"
   `bash
    gh api repos/OWNER/REPO/branches/main/protection \
      --method PUT \
      -H "Accept: application/vnd.github+json" \
      -f 'required_status_checks[strict]=true' \
      -f 'required_status_checks[contexts][]=CI / test' \
      -f 'enforce_admins=true' \
      -f 'restrictions=null'
    `

2. Add a required review count of 1 to the existing branch protection rule:

   ??? success "Solution"
   `bash
    gh api repos/OWNER/REPO/branches/main/protection \
      --method PUT \
      -H "Accept: application/vnd.github+json" \
      --input - << 'EOF'
    {"required_status_checks":{"strict":true,"contexts":["CI / test"]},"enforce_admins":true,"required_pull_request_reviews":{"dismiss_stale_reviews":true,"required_approving_review_count":1},"restrictions":null}
    EOF
    `

3. Test that a direct push to a protected `main` branch is rejected:

   ??? success "Solution"
   `bash
    git checkout main
    echo "test" >> README.md
    git add README.md && git commit -m "test: direct push to main"
    git push origin main
    `

4. List current branch protection rules for all protected branches using `gh api`:

   ??? success "Solution"
   `bash
    gh api repos/OWNER/REPO/branches \
      --jq '.[] | select(.protected == true) | .name'
    gh api repos/OWNER/REPO/branches/main/protection \
      --jq '{contexts: .required_status_checks.contexts, reviews: .required_pull_request_reviews.required_approving_review_count}'
    `

5. Add the CI workflow jobs as required status checks on `main`:

   ??? success "Solution"
   `bash
    gh api repos/OWNER/REPO/branches/main/protection/required_status_checks/contexts \
      --method POST \
      -H "Accept: application/vnd.github+json" \
      -f 'contexts[]=CI Pipeline / lint' \
      -f 'contexts[]=CI Pipeline / test' \
      -f 'contexts[]=CI Pipeline / build'
    `

## Exercises

### Exercise 1 - Apply Basic Protection

Using `gh api`, apply branch protection to a test repository's `main` branch that requires at least one status check named `CI / test` and one PR review. Verify it with another `gh api` GET call.

### Exercise 2 - CODEOWNERS

Create a `.github/CODEOWNERS` file that assigns your GitHub username as owner of all `*.yml` files. Open a PR that modifies a YAML file and verify that your review is automatically requested.

### Exercise 3 - Strict Mode

Enable `strict: true` on required status checks. Create a PR, push a commit to `main` after the PR is opened, and observe that the PR now requires the branch to be updated before merging.

### Exercise 4 - Signed Commits

Enable required signed commits on a branch. Attempt to push an unsigned commit and observe the rejection. Configure GPG signing in your local Git config and retry.

### Exercise 5 - IaC Protection Workflow

Create a `workflow_dispatch` workflow that applies a standardized branch protection configuration to any repository in your organization. Test it on a fresh repository.

---

## Summary

- Branch protection rules are applied with `gh api --method PUT /repos/{owner}/{repo}/branches/{branch}/protection`
- `required_status_checks.strict: true` prevents merging branches that are behind main, closing the TOCTOU gap
- `dismiss_stale_reviews: true` ensures PR approvals are invalidated when new commits are pushed
- The `.github/CODEOWNERS` file maps file patterns to required reviewers, automatically adding them to PRs
- `required_linear_history: true` enforces squash or rebase merges, keeping the default branch history clean
- Required signed commits ensure every commit on the protected branch is cryptographically verified
- A `workflow_dispatch` workflow that calls `gh api` is a simple way to apply consistent branch protection as code across many repositories
