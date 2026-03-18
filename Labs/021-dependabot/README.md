# Lab 021 - Dependabot

## Introduction

- Keeping dependencies up to date is one of the most important - and most tedious - parts of software maintenance.
- Outdated dependencies accumulate security vulnerabilities, miss bug fixes, and eventually become so far behind that upgrading them becomes a major project.
- **Dependabot** automates this by scanning your project's dependency files, detecting outdated packages, and opening pull requests to upgrade them.
- This lab covers Dependabot's two complementary features: **version updates** (proactive upgrades to newer versions) and **security alerts** (reactive notifications and PRs for known vulnerabilities).
- You'll learn how to configure `dependabot.yml`, group related updates, auto-merge low-risk PRs, and integrate Dependabot into your CI/CD workflows.

---

## Why Dependabot Matters

- **Security**: Dependabot integrates with the GitHub Advisory Database to surface packages with known CVEs
- **Freshness**: Automated PRs prevent the "big bang" upgrade problem where months of deferred updates must be done at once
- **Audit trail**: Every upgrade is a pull request with a diff, test results, and a link to the release notes
- **Low maintenance cost**: Once configured, Dependabot runs entirely hands-free

---

## 1. The `dependabot.yml` Configuration File

Dependabot is configured via `.github/dependabot.yml` in your repository root. The file specifies one or more **ecosystems** to monitor, along with scheduling and filtering options.

### Minimal Example

```yaml
version: 2

updates:
  - package-ecosystem: npm
    directory: "/"
    schedule:
      interval: weekly
```

### Full Reference Structure

```yaml
version: 2

updates:
  - package-ecosystem: <ecosystem>
    directory: <path-to-manifest>
    schedule:
      interval: daily | weekly | monthly
      day: monday | tuesday | ... | sunday # for weekly
      time: "HH:MM" # 24h UTC
      timezone: "America/New_York"
    open-pull-requests-limit: 10
    target-branch: main
    reviewers:
      - username-or-team
    assignees:
      - username
    labels:
      - dependencies
      - automerge
    commit-message:
      prefix: "chore"
      prefix-development: "chore"
      include: scope
    ignore:
      - dependency-name: "lodash"
        versions: ["4.x"]
    allow:
      - dependency-type: direct
    groups:
      <group-name>:
        patterns:
          - "*"
```

---

## 2. Supported Package Ecosystems

| `package-ecosystem` | Manifest File                                   | Notes                           |
| ------------------- | ----------------------------------------------- | ------------------------------- |
| `npm`               | `package.json`                                  | Also handles yarn, pnpm         |
| `pip`               | `requirements.txt`, `Pipfile`, `pyproject.toml` |                                 |
| `docker`            | `Dockerfile`                                    | Updates `FROM` image tags       |
| `github-actions`    | `.github/workflows/*.yml`                       | Updates `uses:` action versions |
| `maven`             | `pom.xml`                                       | Java Maven projects             |
| `gradle`            | `build.gradle`                                  | Java Gradle projects            |
| `bundler`           | `Gemfile`                                       | Ruby Gems                       |
| `cargo`             | `Cargo.toml`                                    | Rust crates                     |
| `gomod`             | `go.mod`                                        | Go modules                      |
| `composer`          | `composer.json`                                 | PHP                             |
| `nuget`             | `*.csproj`, `packages.config`                   | .NET                            |
| `terraform`         | `*.tf`                                          | Terraform providers and modules |
| `helm`              | `Chart.yaml`                                    | Helm charts                     |

### Example: Multiple Ecosystems

```yaml
version: 2

updates:
  - package-ecosystem: npm
    directory: "/"
    schedule:
      interval: weekly
      day: monday
      time: "09:00"
      timezone: "UTC"

  - package-ecosystem: docker
    directory: "/"
    schedule:
      interval: weekly

  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly

  - package-ecosystem: pip
    directory: "/backend"
    schedule:
      interval: daily

  - package-ecosystem: terraform
    directory: "/infra"
    schedule:
      interval: monthly
```

---

## 3. Schedule Options

```yaml
schedule:
  interval: daily        # Every day
  interval: weekly       # Once per week (defaults to Monday)
  interval: monthly      # First day of the month

# Weekly with specific day and time
schedule:
  interval: weekly
  day: wednesday
  time: "08:00"
  timezone: "Europe/London"
```

The `time` field accepts 24-hour UTC by default. Specify `timezone` to use a local time zone.

---

## 4. `open-pull-requests-limit`

By default Dependabot opens up to 5 PRs per ecosystem. Increase it to catch more outdated packages, or reduce it to avoid PR noise:

```yaml
- package-ecosystem: npm
  directory: "/"
  schedule:
    interval: daily
  open-pull-requests-limit: 20 # Allow more concurrent PRs

- package-ecosystem: docker
  directory: "/"
  schedule:
    interval: weekly
  open-pull-requests-limit: 2 # Limit Docker image PRs
```

Set to `0` to **disable** version updates for that ecosystem while keeping security alert PRs.

---

## 5. Reviewers and Assignees

Automatically request review from specific users or teams:

```yaml
- package-ecosystem: npm
  directory: "/"
  schedule:
    interval: weekly
  reviewers:
    - octocat
    - my-org/frontend-team # GitHub team in org/team format
  assignees:
    - dep-manager
```

---

## 6. Ignoring Specific Dependencies or Versions

```yaml
- package-ecosystem: npm
  directory: "/"
  schedule:
    interval: weekly
  ignore:
    # Ignore all updates for this package
    - dependency-name: "webpack"

    # Ignore only major version bumps
    - dependency-name: "react"
      update-types: ["version-update:semver-major"]

    # Ignore a specific version range
    - dependency-name: "lodash"
      versions: ["4.x", ">= 5.0.0, < 5.2.0"]
```

---

## 7. Grouping Updates

Groups let Dependabot batch related updates into a single PR instead of one PR per package - great for reducing review noise:

```yaml
- package-ecosystem: npm
  directory: "/"
  schedule:
    interval: weekly
  groups:
    # All ESLint-related packages in one PR
    eslint:
      patterns:
        - "eslint*"
        - "@typescript-eslint/*"

    # All AWS SDK packages together
    aws-sdk:
      patterns:
        - "@aws-sdk/*"

    # Production dependencies (major versions excluded)
    production-dependencies:
      dependency-type: production
      update-types:
        - minor
        - patch

    # Development tools
    dev-dependencies:
      dependency-type: development
      patterns:
        - "*"
```

---

## 8. Security Alerts vs Version Updates

Dependabot has two distinct modes:

### Security Updates (Automatic)

- Triggered automatically when a CVE is published for a dependency you use
- Creates a PR to upgrade to the first patched version
- Cannot be disabled via `dependabot.yml` - controlled in **Settings > Security > Dependabot alerts**
- Uses the GitHub Advisory Database and OSV

### Version Updates (Configured)

- Proactively checks for newer versions on your schedule
- Configured via `.github/dependabot.yml`
- Can be paused by setting `open-pull-requests-limit: 0`

Check security alerts via `gh`:

```bash
# List Dependabot security alerts for a repo
gh api repos/OWNER/REPO/dependabot/alerts \
  --jq '.[] | {number: .number, package: .dependency.package.name, severity: .security_vulnerability.severity, state: .state}'

# List only critical and high severity
gh api repos/OWNER/REPO/dependabot/alerts \
  --jq '.[] | select(.security_vulnerability.severity == "critical" or .security_vulnerability.severity == "high") | {package: .dependency.package.name, severity: .security_vulnerability.severity}'
```

---

## 9. Auto-Merging Dependabot PRs

For low-risk updates (patch bumps, dev dependency updates), you can auto-merge after CI passes. Create a workflow that runs on Dependabot PRs:

```yaml
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

      - name: Auto-merge patch and minor updates for dev dependencies
        if: |
          steps.metadata.outputs.update-type == 'version-update:semver-patch' ||
          (steps.metadata.outputs.update-type == 'version-update:semver-minor' &&
           steps.metadata.outputs.dependency-type == 'direct:development')
        run: gh pr merge --auto --squash "$PR_URL"
        env:
          PR_URL: ${{ github.event.pull_request.html_url }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Auto-approve patch updates
        if: steps.metadata.outputs.update-type == 'version-update:semver-patch'
        run: gh pr review --approve "$PR_URL"
        env:
          PR_URL: ${{ github.event.pull_request.html_url }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

The `dependabot/fetch-metadata` action provides:

- `update-type`: `version-update:semver-patch`, `version-update:semver-minor`, `version-update:semver-major`
- `dependency-type`: `direct:production`, `direct:development`, `indirect`
- `dependency-names`: comma-separated list of updated packages

---

## 10. Dependabot and Private Registries

For private npm registries, Docker registries, or Maven repos, configure credentials in `dependabot.yml`:

```yaml
version: 2

registries:
  my-npm-registry:
    type: npm-registry
    url: https://npm.mycompany.com
    token: ${{ secrets.NPM_TOKEN }}

  my-docker-registry:
    type: docker-registry
    url: registry.mycompany.com
    username: ${{ secrets.REGISTRY_USER }}
    password: ${{ secrets.REGISTRY_PASSWORD }}

updates:
  - package-ecosystem: npm
    directory: "/"
    schedule:
      interval: weekly
    registries:
      - my-npm-registry

  - package-ecosystem: docker
    directory: "/"
    schedule:
      interval: weekly
    registries:
      - my-docker-registry
```

---

## 11. Complete Real-World `dependabot.yml`

```yaml
version: 2

updates:
  # GitHub Actions - weekly on Mondays
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

  # npm - weekly, grouped to reduce noise
  - package-ecosystem: npm
    directory: "/"
    schedule:
      interval: weekly
      day: tuesday
      time: "08:00"
      timezone: "UTC"
    open-pull-requests-limit: 10
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

  # Docker - monthly
  - package-ecosystem: docker
    directory: "/"
    schedule:
      interval: monthly
    labels:
      - dependencies
      - docker

  # Python backend
  - package-ecosystem: pip
    directory: "/backend"
    schedule:
      interval: weekly
      day: wednesday
    open-pull-requests-limit: 5
    labels:
      - dependencies
      - python
```

---

## Hands-on

1. Create a `.github/dependabot.yml` that monitors the `github-actions` ecosystem with a weekly schedule:

   ??? success "Solution"
   `bash
    mkdir -p .github
    cat > .github/dependabot.yml << 'EOF'
    version: 2
    updates:
      - package-ecosystem: github-actions
        directory: "/"
        schedule:
          interval: weekly
          day: monday
          time: "08:00"
          timezone: "UTC"
    EOF
    git add .github/dependabot.yml && git commit -m "ci: add Dependabot for GitHub Actions"
    `

2. Add an npm ecosystem entry with a weekly schedule to the existing `dependabot.yml`:

   ??? success "Solution"
   `bash
    printf '\n  - package-ecosystem: npm\n    directory: "/"\n    schedule:\n      interval: weekly\n      day: tuesday\n    open-pull-requests-limit: 10\n' >> .github/dependabot.yml
    git add .github/dependabot.yml && git commit -m "ci: add npm Dependabot updates"
    `

3. List all open Dependabot pull requests in a repository:

   ??? success "Solution"
   `bash
    gh pr list \
      --repo OWNER/REPO \
      --author app/dependabot \
      --state open \
      --json number,title,createdAt \
      --jq '.[] | "\(.number) \(.title)"'
    `

4. Check Dependabot security alerts using `gh api` and filter by severity:

   ??? success "Solution"
   `bash
    gh api repos/OWNER/REPO/dependabot/alerts \
      --jq '.[] | select(.security_vulnerability.severity == "critical" or .security_vulnerability.severity == "high") | {number: .number, package: .dependency.package.name, severity: .security_vulnerability.severity}'
    `

5. Add a group to the npm ecosystem entry that batches all minor and patch updates together:

   ??? success "Solution"
   `bash
    python3 -c "
    import pathlib
    f = pathlib.Path('.github/dependabot.yml')
    content = f.read_text()
    group = '\n    groups:\n      minor-and-patch:\n        update-types:\n          - minor\n          - patch\n'
    content = content.replace('open-pull-requests-limit: 10\n', 'open-pull-requests-limit: 10' + group)
    f.write_text(content)
    print('Updated dependabot.yml')
    "
    git add .github/dependabot.yml && git commit -m "ci: group minor and patch npm updates"
    `

## Exercises

### Exercise 1 - Basic Configuration

Create a `.github/dependabot.yml` for a Node.js project that monitors `npm` dependencies weekly and also keeps GitHub Actions up to date.

### Exercise 2 - Multi-Ecosystem Setup

Extend your `dependabot.yml` to also monitor Docker images. Add appropriate labels and limit Docker PRs to 2.

### Exercise 3 - Grouping

Add groups to the npm configuration so that all `@babel/*` packages update together, all `jest*` packages update together, and everything else updates individually.

### Exercise 4 - Auto-Merge Workflow

Create a `.github/workflows/dependabot-automerge.yml` that auto-approves and auto-merges patch-level updates from Dependabot after CI passes.

### Exercise 5 - Security Alerts

Use `gh api` to list the Dependabot security alerts for a public repository (e.g., a popular open source project). Filter for only high and critical severity.

---

## Summary

- Dependabot is configured via `.github/dependabot.yml` and supports over 15 package ecosystems
- `schedule.interval` can be `daily`, `weekly`, or `monthly`; `weekly` supports a specific `day` and `time`
- `open-pull-requests-limit: 0` pauses version updates while keeping security alert PRs active
- `groups:` batches related package updates into a single PR, reducing review fatigue
- Security updates are automatic and triggered by the GitHub Advisory Database, separate from version updates
- The `dependabot/fetch-metadata` action exposes update type and dependency type for conditional auto-merge logic
- Private registry credentials are stored as repository secrets and referenced in `dependabot.yml` with `${{ secrets.NAME }}`
