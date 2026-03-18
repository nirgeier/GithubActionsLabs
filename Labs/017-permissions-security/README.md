# Lab 017 - Permissions and Security

## Introduction

- GitHub Actions workflows run with significant privileges by default.
- Without careful configuration, a compromised or malicious workflow could exfiltrate secrets, push malicious code, or create unauthorized releases.
- This lab covers how to apply the principle of least privilege, pin third-party actions to specific commit SHAs, and audit your workflows for common security pitfalls.

---

## `GITHUB_TOKEN` Permissions

Every workflow run receives an automatically generated `GITHUB_TOKEN` that grants access to the repository. By default (as of 2023), public repositories have **read** permissions and private repositories may have **write** permissions depending on the organization setting.

### Default Permission Scopes

The `GITHUB_TOKEN` can have these permission scopes:

| Scope                 | Description                        |
| --------------------- | ---------------------------------- |
| `actions`             | Manage workflow runs and artifacts |
| `checks`              | Read/write check runs              |
| `contents`            | Repository contents, commits, tags |
| `deployments`         | Manage deployments                 |
| `id-token`            | Request OIDC tokens                |
| `issues`              | Read/write issues and comments     |
| `packages`            | Read/write GitHub Packages         |
| `pages`               | Manage GitHub Pages                |
| `pull-requests`       | Read/write PRs and PR reviews      |
| `repository-projects` | Read/write projects                |
| `security-events`     | Read/write security events         |
| `statuses`            | Read/write commit statuses         |

---

## The `permissions` Block

### Workflow-Level Permissions

```yaml
name: CI

on: [push]

# Set minimal permissions for the entire workflow
permissions:
  contents: read
  pull-requests: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm test
```

### Job-Level Permissions

Job-level permissions override workflow-level:

```yaml
name: CI

on: [push]

# Deny everything by default
permissions: {}

jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read # Only what this job needs
    steps:
      - uses: actions/checkout@v4
      - run: npm test

  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: write # Needed for creating releases
      packages: write # Needed for GitHub Packages
    steps:
      - uses: actions/checkout@v4
      - run: npm publish
```

### `read-all` and `write-all`

```yaml
# Grant read access to all scopes (useful for analysis workflows)
permissions: read-all

# Grant write access to all scopes (avoid unless necessary)
permissions: write-all
```

---

## Minimal Permissions Principle

Always request only the permissions the job actually needs:

```yaml
# Bad - overly broad
permissions: write-all

# Good - minimal
permissions:
  contents: read       # For checkout
  pull-requests: write # For adding PR comments
  checks: write        # For creating check runs
```

### Common Job Permission Patterns

```yaml
# Checkout and read-only work
permissions:
  contents: read

# Create a GitHub Release
permissions:
  contents: write

# Comment on a PR
permissions:
  pull-requests: write
  contents: read

# Publish to GitHub Container Registry
permissions:
  packages: write
  contents: read

# Request an OIDC token (for cloud deployments)
permissions:
  id-token: write
  contents: read

# Code scanning and security events
permissions:
  security-events: write
  contents: read
  actions: read
```

---

## Third-Party Action Security: Pinning to SHA

When you reference a third-party action with a mutable tag like `@v4`, the action's code could change without warning. **Pin actions to their full commit SHA** for reproducibility and protection against supply-chain attacks.

```yaml
# Insecure - tag can be moved or deleted
- uses: actions/checkout@v4

# Secure - pinned to an immutable SHA
- uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
```

### Finding a SHA for a Tag

```bash
# Find the SHA for a specific tag
git ls-remote https://github.com/actions/checkout.git refs/tags/v4

# Or use the GitHub API
gh api repos/actions/checkout/git/refs/tags/v4
```

### Pinning with a Version Comment

Keep the human-readable version as a comment:

```yaml
steps:
  - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
  - uses: actions/setup-node@39370e3970a6d050c480ffad4ff0ed4d3fdee5af # v4.1.0
  - uses: actions/cache@d4323d4df104b026a6aa633fdb11d772de78408d # v4.2.1
```

---

## Complete Secure Workflow Example

```yaml
name: Secure CI Pipeline

on:
  push:
    branches: [main]
  pull_request:

# Deny all permissions by default; grant only what each job needs
permissions: {}

jobs:
  lint:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: actions/setup-node@39370e3970a6d050c480ffad4ff0ed4d3fdee5af # v4.1.0
        with:
          node-version: "20"
          cache: "npm"
      - run: npm ci && npm run lint

  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: actions/setup-node@39370e3970a6d050c480ffad4ff0ed4d3fdee5af # v4.1.0
        with:
          node-version: "20"
          cache: "npm"
      - run: npm ci && npm test

  codeql-analysis:
    runs-on: ubuntu-latest
    permissions:
      actions: read
      contents: read
      security-events: write # Required for CodeQL
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: github/codeql-action/init@e675ced7a7522a761fc9c8eb26682c8b27c9dab9 # v3.28.0
        with:
          languages: javascript
      - uses: github/codeql-action/autobuild@e675ced7a7522a761fc9c8eb26682c8b27c9dab9 # v3.28.0
      - uses: github/codeql-action/analyze@e675ced7a7522a761fc9c8eb26682c8b27c9dab9 # v3.28.0

  release:
    runs-on: ubuntu-latest
    needs: [lint, test]
    if: github.ref == 'refs/heads/main'
    permissions:
      contents: write # For creating releases
      packages: write # For publishing packages
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - run: npm publish
```

---

## `pull-request-target` Risks

`pull_request_target` runs in the context of the **base** repository, with write permissions, even for PRs from forks. This is dangerous if you checkout the PR's code:

```yaml
# DANGEROUS - do not do this
on: pull_request_target
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha }} # Attacker-controlled code!
      - run: npm test # Runs attacker code with write permissions!
```

### Safe `pull_request_target` Pattern

```yaml
# SAFE - do not checkout the PR code in a pull_request_target workflow
on: pull_request_target

jobs:
  label:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
    steps:
      # Only work with metadata - no code checkout
      - uses: actions/github-script@60a0d83039c74a4aee543508d2ffcb1c3799cdea # v7.0.1
        with:
          script: |
            github.rest.issues.addLabels({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.payload.pull_request.number,
              labels: ['needs-review']
            })
```

---

## Dependency Review Action

The Dependency Review Action blocks PRs that introduce vulnerable dependencies:

```yaml
name: Dependency Review

on: pull_request

permissions:
  contents: read
  pull-requests: write

jobs:
  dependency-review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: actions/dependency-review-action@67d4f4b543f4d2b3b9f35e8b16a55f225451db7a # v4.5.0
        with:
          fail-on-severity: moderate
          comment-summary-in-pr: true
          deny-licenses: GPL-2.0, AGPL-3.0
```

---

## Secret Scanning Concepts

Never hardcode secrets in workflow files:

```yaml
# Bad - hardcoded secret
- run: ./deploy.sh --token "ghp_abc123secretvalue"

# Good - use encrypted secrets
- run: ./deploy.sh --token "${{ secrets.DEPLOY_TOKEN }}"

# Good - reference secret from environment
  env:
    DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
  run: ./deploy.sh --token "$DEPLOY_TOKEN"
```

### `git-secrets` in Workflows

```yaml
- name: Scan for secrets
  run: |
    git secrets --install
    git secrets --register-aws
    git secrets --scan
```

---

## Environment-Level Secret Protection

Combine environment protection rules with permissions:

```yaml
jobs:
  deploy-production:
    runs-on: ubuntu-latest
    environment: production # Requires manual approval
    permissions:
      id-token: write # For OIDC cloud auth
      contents: read
    steps:
      - uses: aws-actions/configure-aws-credentials@sts # OIDC, no static keys
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
```

---

## Hands-on

1. Add `permissions: contents: read` at the workflow level to restrict the default `GITHUB_TOKEN` scope:

   ??? success "Solution"
   `bash
    cat > .github/workflows/secure-ci.yml << 'EOF'
    name: Secure CI
    on: push
    permissions:
      contents: read
    jobs:
      test:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - run: echo "Running with read-only token"
    EOF
    `

2. Pin `actions/checkout` to its full commit SHA instead of the `v4` tag, adding the tag as a comment:

   ??? success "Solution"
   `bash
    SHA=$(git ls-remote https://github.com/actions/checkout.git refs/tags/v4 | awk '{print $1}')
    echo "Pinned SHA: $SHA"
    sed -i "s|uses: actions/checkout@v4|uses: actions/checkout@${SHA} # v4|g" \
      .github/workflows/secure-ci.yml
    git diff .github/workflows/secure-ci.yml
    `

3. Add a dependency-review workflow that blocks PRs introducing dependencies with severity `moderate` or higher:

   ??? success "Solution"
   `bash
    cat > .github/workflows/dependency-review.yml << 'EOF'
    name: Dependency Review
    on: pull_request
    permissions:
      contents: read
      pull-requests: write
    jobs:
      review:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: actions/dependency-review-action@v4
            with:
              fail-on-severity: moderate
              comment-summary-in-pr: true
    EOF
    `

4. Use `gh api` to check the default permissions for `GITHUB_TOKEN` in your repository:

   ??? success "Solution"
   `bash
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    gh api repos/$REPO/actions/permissions \
      | jq '{default_workflow_permissions, can_approve_pull_request_reviews}'
    `

5. Verify that a workflow using only `permissions: contents: read` cannot push a commit back to the repository:

   ??? success "Solution"
   `bash
    cat > .github/workflows/read-only-push-test.yml << 'EOF'
    name: Read Only Push Test
    on: workflow_dispatch
    permissions:
      contents: read
    jobs:
      try-push:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - run: |
              git config user.email "ci@example.com"
              git config user.name "CI"
              echo "test" >> README.md
              git add README.md
              git commit -m "test push"
              git push || echo "Push failed as expected with read-only token"
    EOF
    gh workflow run read-only-push-test.yml
    RUN_ID=$(gh run list --workflow read-only-push-test.yml --limit 1 --json databaseId -q '.[0].databaseId')
    gh run watch "$RUN_ID"
    gh run view "$RUN_ID" --log | grep -i "push failed"
    `

## Exercises

### Exercise 1 - Permissions Audit

Take an existing workflow and audit its permissions. Apply `permissions: {}` at the workflow level and add only the required scope to each job.

### Exercise 2 - SHA Pinning

Pin all third-party actions in a workflow to their commit SHA. Use `git ls-remote` to find the current SHA for each tag.

### Exercise 3 - Dependency Review

Add the Dependency Review Action to a repository that has a `pull_request` workflow. Introduce a vulnerable dependency and verify the action blocks the PR.

### Exercise 4 - `pull_request_target` Audit

Identify which of your workflows use `pull_request_target`. Verify they do not checkout PR code with write permissions.

### Exercise 5 - OIDC for Cloud Auth

Replace static AWS/Azure/GCP credentials in a workflow with OIDC-based authentication. Compare the permission set required.

---

## Summary

- The `permissions` block restricts the `GITHUB_TOKEN` to only the scopes a job actually needs; set `permissions: {}` at the workflow level and grant minimally at the job level
- Pinning third-party actions to a full commit SHA (e.g., `uses: actions/checkout@abc1234`) prevents supply-chain attacks where a tag is silently moved to malicious code
- `pull_request_target` runs with write access to the base repo and should never checkout or execute untrusted PR code
- The Dependency Review Action blocks PRs that introduce dependencies with known vulnerabilities or disallowed licenses
- Secrets should always be referenced through `${{ secrets.NAME }}` and never hardcoded in workflow YAML or scripts
- OIDC-based cloud authentication (id-token: write) eliminates the need for long-lived static credentials in secrets
- Setting `permissions: read-all` at the workflow level is safer than the default `write-all` for workflows that do not need to write to the repository
