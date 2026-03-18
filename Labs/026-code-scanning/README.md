# Lab 026 - Code Scanning

## Introduction

- **Code scanning** automatically analyzes your code for security vulnerabilities and coding errors using static analysis.
- GitHub's native code scanning is powered by **CodeQL** - a semantic code analysis engine developed by GitHub Security Lab that treats code as data and runs queries to find vulnerabilities.
- This lab covers setting up CodeQL in GitHub Actions, understanding SARIF output, using different query suites, writing custom queries, uploading results from third-party tools, and managing security alerts through the GitHub API.

---

## What Is CodeQL?

CodeQL works by building a queryable database from your source code (a snapshot of the program's structure and data flow), then running a set of security queries against that database. Unlike pattern-matching linters, CodeQL understands data flow: it can trace a user-controlled input from an HTTP request parameter all the way to a SQL query and flag it as an injection vulnerability, even across multiple function calls.

CodeQL supports: JavaScript/TypeScript, Python, Java, C/C++, C#, Go, Ruby, Swift, and Kotlin.

---

## 1. Basic CodeQL Workflow

```yaml
name: CodeQL Analysis

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
  schedule:
    - cron: "0 3 * * 1" # Weekly on Monday at 03:00 UTC

permissions:
  contents: read
  security-events: write # Required to upload SARIF results
  actions: read

jobs:
  analyze:
    name: Analyze (${{ matrix.language }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        language: [javascript-typescript, python]

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Initialize CodeQL
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
          queries: security-extended

      - name: Auto-build
        uses: github/codeql-action/autobuild@v3

      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@v3
        with:
          category: "/language:${{ matrix.language }}"
```

---

## 2. Language Configuration

Specify one or more languages in the `init` step. Use a matrix for multiple languages to run them in parallel:

```yaml
strategy:
  matrix:
    include:
      - language: javascript-typescript
        build-mode: none
      - language: python
        build-mode: none
      - language: java-kotlin
        build-mode: autobuild
      - language: go
        build-mode: autobuild
```

### Build Modes

| Mode        | Description                                     |
| ----------- | ----------------------------------------------- |
| `none`      | No build required (interpreted languages)       |
| `autobuild` | CodeQL automatically detects and runs the build |
| `manual`    | You provide the build commands                  |

For `manual` build mode:

```yaml
- name: Initialize CodeQL
  uses: github/codeql-action/init@v3
  with:
    languages: java-kotlin
    build-mode: manual

- name: Build
  run: |
    mvn clean package -DskipTests

- name: Perform CodeQL Analysis
  uses: github/codeql-action/analyze@v3
```

---

## 3. Query Suites

CodeQL ships with several query suites that trade coverage for speed:

| Suite                   | Description                                          | Run time |
| ----------------------- | ---------------------------------------------------- | -------- |
| `default`               | Curated set of high-confidence security queries      | Fast     |
| `security-extended`     | All security queries including lower-confidence ones | Moderate |
| `security-and-quality`  | Security + code quality queries                      | Slower   |
| `security-experimental` | Experimental queries (may have false positives)      | Varies   |

```yaml
- name: Initialize CodeQL
  uses: github/codeql-action/init@v3
  with:
    languages: javascript-typescript
    queries: security-extended,+security-and-quality
    # '+' prefix means: add to the default suite instead of replacing it
```

---

## 4. Custom CodeQL Queries

You can write custom `.ql` query files and include them in the analysis:

```yaml
- name: Initialize CodeQL
  uses: github/codeql-action/init@v3
  with:
    languages: javascript-typescript
    queries: security-extended
    config-file: .github/codeql/codeql-config.yml
```

`.github/codeql/codeql-config.yml`:

```yaml
name: "Custom CodeQL Config"

queries:
  - name: Security extended queries
    uses: security-extended
  - name: Custom queries
    uses: ./.github/codeql/custom-queries

# Paths to exclude from analysis
paths-ignore:
  - node_modules
  - dist
  - coverage
  - "**/*.test.js"
  - "**/*.spec.ts"

# Paths to include (overrides paths-ignore)
paths:
  - src
  - lib
```

Example custom query (`.github/codeql/custom-queries/hardcoded-secret.ql`):

```ql
/**
 * @name Hardcoded secret in configuration
 * @description Detects hardcoded passwords and API keys in configuration objects
 * @kind problem
 * @problem.severity error
 * @security-severity 8.0
 * @id js/hardcoded-secret
 * @tags security
 */

import javascript

from Property p, string name
where
  p.getName().regexpMatch("(?i)(password|secret|token|api_?key|auth)")
  and p.getInit() instanceof StringLiteral
  and p.getInit().(StringLiteral).getValue().length() > 4
select p, "Possible hardcoded secret in property '" + name + "'"
```

---

## 5. SARIF Output Format

CodeQL outputs results in **SARIF** (Static Analysis Results Interchange Format) - a JSON-based standard for sharing static analysis results. The `analyze` action automatically uploads SARIF to GitHub's code scanning API.

You can also download the generated SARIF file for further processing:

```yaml
- name: Perform CodeQL Analysis
  uses: github/codeql-action/analyze@v3
  with:
    output: results/codeql-results.sarif
    upload: false # Don't auto-upload; we'll handle it

- name: Process SARIF
  run: |
    # Count findings by severity
    cat results/codeql-results.sarif | \
      jq '[.runs[].results[] | .level] | group_by(.) | map({level: .[0], count: length})'

- name: Upload SARIF
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: results/codeql-results.sarif
    category: codeql-custom
```

---

## 6. Uploading Third-Party SARIF Results

Any static analysis tool that outputs SARIF can post results to GitHub code scanning. This creates a unified security view:

```yaml
name: Security Scan (Third-Party Tools)

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read
  security-events: write

jobs:
  semgrep:
    name: Semgrep SAST
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Run Semgrep
        uses: returntocorp/semgrep-action@v1
        with:
          config: >-
            p/security-audit
            p/secrets
            p/owasp-top-ten
          generateSarif: "1"

      - name: Upload Semgrep SARIF
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: semgrep.sarif
          category: semgrep

  eslint:
    name: ESLint Security
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Run ESLint with SARIF output
        run: |
          npm run lint -- \
            --format @microsoft/eslint-formatter-sarif \
            --output-file eslint-results.sarif
        continue-on-error: true

      - name: Upload ESLint SARIF
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: eslint-results.sarif
          category: eslint-security
```

---

## 7. Managing Code Scanning Alerts with `gh api`

```bash
# List all open code scanning alerts
gh api /repos/OWNER/REPO/code-scanning/alerts \
  --jq '.[] | {number: .number, rule: .rule.id, severity: .rule.severity, description: .rule.description}'

# Filter by severity
gh api "/repos/OWNER/REPO/code-scanning/alerts?severity=critical" \
  --jq '.[].rule.description'

# Get a specific alert
gh api /repos/OWNER/REPO/code-scanning/alerts/ALERT_NUMBER | jq .

# Dismiss an alert (false positive)
gh api \
  --method PATCH \
  /repos/OWNER/REPO/code-scanning/alerts/ALERT_NUMBER \
  -f dismissed_reason="false positive" \
  -f dismissed_comment="This is a test file, not production code"

# List alerts for a specific tool
gh api "/repos/OWNER/REPO/code-scanning/alerts?tool_name=CodeQL" \
  --jq '.[].rule.id' | sort | uniq -c | sort -rn
```

---

## 8. Security Advisories Workflow

When a code scanning alert reveals a confirmed vulnerability, create a draft security advisory:

```yaml
- name: Create security advisory
  uses: actions/github-script@v7
  with:
    script: |
      await github.rest.securityAdvisories.createRepositoryAdvisory({
        owner: context.repo.owner,
        repo: context.repo.repo,
        summary: 'SQL injection vulnerability in user search endpoint',
        description: 'Unparameterized query in src/api/users.js:145 allows SQL injection via the `name` parameter.',
        severity: 'high',
        cve_id: null,    // fill in once CVE is assigned
        vulnerabilities: [{
          package: { ecosystem: 'npm', name: 'my-app' },
          vulnerable_version_range: '< 2.3.1',
          patched_versions: '>= 2.3.1'
        }]
      });
```

---

## 9. Blocking PRs on Code Scanning Alerts

Configure code scanning as a required status check so PRs with new alerts cannot be merged:

```bash
# Enable code scanning alerts as a required check
gh api \
  --method PUT \
  /repos/OWNER/REPO/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "CodeQL Analysis (javascript-typescript)",
      "CodeQL Analysis (python)"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null
}
EOF
```

---

## Hands-on

1. Create a CodeQL analysis workflow for JavaScript using the `security-extended` query suite:

   ??? success "Solution"
   `bash
    mkdir -p .github/workflows
    cat > .github/workflows/codeql.yml << 'EOF'
    name: CodeQL Analysis
    on:
      push:
        branches: [main]
      pull_request:
        branches: [main]
      schedule:
        - cron: "0 3 * * 1"
    permissions:
      contents: read
      security-events: write
      actions: read
    jobs:
      analyze:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: github/codeql-action/init@v3
            with:
              languages: javascript-typescript
              queries: security-extended
          - uses: github/codeql-action/autobuild@v3
          - uses: github/codeql-action/analyze@v3
    EOF
    git add .github/workflows/codeql.yml && git commit -m "ci: add CodeQL analysis workflow"
    `

2. Check the default query suite used by CodeQL for JavaScript:

   ??? success "Solution"
   `bash
    gh api repos/OWNER/REPO/code-scanning/alerts \
      --jq 'map(select(.tool.name == "CodeQL")) | .[0].tool'
    `

3. List code scanning alerts using `gh api` and filter by severity:

   ??? success "Solution"
   `bash
    gh api repos/OWNER/REPO/code-scanning/alerts \
      --jq '.[] | {number: .number, rule: .rule.id, severity: .rule.severity, description: .rule.description}'
    `

4. Dismiss a false-positive code scanning alert by its number:

   ??? success "Solution"
   `bash
    ALERT_NUMBER=1
    gh api repos/OWNER/REPO/code-scanning/alerts/${ALERT_NUMBER} \
      --method PATCH \
      -f dismissed_reason="false positive" \
      -f dismissed_comment="This is test code, not production"
    `

5. Upload a custom SARIF file to GitHub code scanning using `gh api`:

   ??? success "Solution"
   `bash
    SARIF_B64=$(base64 -w 0 results.sarif)
    COMMIT_SHA=$(git rev-parse HEAD)
    gh api repos/OWNER/REPO/code-scanning/sarifs \
      --method POST \
      -f commit_sha="${COMMIT_SHA}" \
      -f ref="refs/heads/main" \
      -f sarif="${SARIF_B64}" \
      -f tool_name="custom-scanner"
    `

## Exercises

### Exercise 1 - Basic CodeQL Setup

Create a `.github/workflows/codeql.yml` for a JavaScript repository. Run it on push to main and weekly on a schedule. Use the `security-extended` query suite.

### Exercise 2 - Multi-Language Matrix

Extend the workflow to analyze both `javascript-typescript` and `python` in parallel using a matrix strategy.

### Exercise 3 - Custom Configuration

Create a `.github/codeql/codeql-config.yml` that excludes `node_modules`, `dist`, and all test files from the analysis. Apply it to your CodeQL workflow.

### Exercise 4 - Third-Party Tool

Add a Semgrep job to your security workflow. Upload the SARIF output to GitHub and verify it appears in the Security > Code scanning alerts tab.

### Exercise 5 - Alert Management

Use `gh api` to list the code scanning alerts in a public repository (e.g., a popular open source project). Count alerts by severity and by rule ID.

---

## Summary

- CodeQL requires `permissions: security-events: write` to upload SARIF results to GitHub
- The `security-extended` query suite finds more vulnerabilities than `default` at the cost of slightly higher false-positive rates
- SARIF (Static Analysis Results Interchange Format) is the standard for uploading any tool's findings to GitHub code scanning
- Any static analysis tool (Semgrep, ESLint, Trivy, Checkov) can integrate with GitHub code scanning by outputting SARIF and using `upload-sarif`
- Custom CodeQL queries in `.ql` files let you encode organization-specific security policies
- Code scanning alerts can be managed via `gh api /repos/{owner}/{repo}/code-scanning/alerts` for bulk dismissal and triage
- Adding CodeQL check names to branch protection rules blocks PRs that introduce new code scanning alerts
