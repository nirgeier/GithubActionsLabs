#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 026 - Code Scanning Demo"

# ─────────────────────────────────────────────────────────────
# 1. Create a comprehensive CodeQL workflow
# ─────────────────────────────────────────────────────────────
section "1. Creating CodeQL Analysis Workflow"

mkdir -p .github/workflows

cat >.github/workflows/lab026-codeql.yml <<'YAML'
name: "Lab 026 - CodeQL Analysis"

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 3 * * 1'    # Weekly on Monday at 03:00 UTC

permissions:
  contents: read
  security-events: write
  actions: read

jobs:
  # ── CodeQL Analysis ──────────────────────────────────────────
  codeql:
    name: CodeQL (${{ matrix.language }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - language: javascript-typescript
            build-mode: none
          - language: python
            build-mode: none

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Initialize CodeQL
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
          build-mode: ${{ matrix.build-mode }}
          queries: security-extended
          config-file: .github/codeql/config.yml

      - name: Auto-build (for compiled languages)
        if: matrix.build-mode == 'autobuild'
        uses: github/codeql-action/autobuild@v3

      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@v3
        with:
          category: "/language:${{ matrix.language }}"
          output: results/

      - name: Upload SARIF as artifact
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: codeql-results-${{ matrix.language }}
          path: results/
          retention-days: 30

  # ── Semgrep SAST ─────────────────────────────────────────────
  semgrep:
    name: Semgrep SAST
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write

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
        continue-on-error: true

      - name: Upload Semgrep SARIF
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: semgrep.sarif
          category: semgrep
YAML

echo "Created: .github/workflows/lab026-codeql.yml"

# ─────────────────────────────────────────────────────────────
# 2. Create CodeQL configuration file
# ─────────────────────────────────────────────────────────────
section "2. Creating CodeQL Configuration"

mkdir -p .github/codeql

cat >.github/codeql/config.yml <<'YAML'
name: "Custom CodeQL Config"

# Query suites to run
queries:
  - name: Security extended
    uses: security-extended

# Paths to exclude from analysis
paths-ignore:
  - node_modules
  - dist
  - build
  - coverage
  - "**/*.test.js"
  - "**/*.test.ts"
  - "**/*.spec.js"
  - "**/*.spec.ts"
  - "**/test/**"
  - "**/tests/**"
  - "**/fixtures/**"
  - "**/__mocks__/**"

# Paths to include (restrict analysis scope)
paths:
  - src
  - lib
  - app
YAML

echo "Created: .github/codeql/config.yml"

# ─────────────────────────────────────────────────────────────
# 3. Create a minimal SARIF example
# ─────────────────────────────────────────────────────────────
section "3. SARIF Format Reference"

cat >/tmp/lab026-example.sarif <<'JSON'
{
  "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
  "version": "2.1.0",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "MyCustomTool",
          "version": "1.0.0",
          "rules": [
            {
              "id": "MY001",
              "name": "HardcodedPassword",
              "shortDescription": { "text": "Hardcoded password detected" },
              "defaultConfiguration": { "level": "error" }
            }
          ]
        }
      },
      "results": [
        {
          "ruleId": "MY001",
          "level": "error",
          "message": { "text": "Hardcoded password found in configuration" },
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": { "uri": "src/config.js" },
                "region": { "startLine": 42, "startColumn": 5 }
              }
            }
          ]
        }
      ]
    }
  ]
}
JSON

echo "Example SARIF structure written to /tmp/lab026-example.sarif"
echo ""
echo "Key SARIF fields:"
echo "  - runs[].tool.driver.name: tool name shown in GitHub Security tab"
echo "  - runs[].results[].ruleId: identifies the rule that triggered"
echo "  - runs[].results[].level: error | warning | note"
echo "  - runs[].results[].locations: file and line number of finding"

# ─────────────────────────────────────────────────────────────
# 4. Show gh api commands for alerts
# ─────────────────────────────────────────────────────────────
section "4. Managing Code Scanning Alerts via gh api"

echo ""
echo "# List all open alerts:"
echo "gh api /repos/OWNER/REPO/code-scanning/alerts \\"
echo "  --jq '.[] | {number, rule: .rule.id, severity: .rule.severity, state}'"

echo ""
echo "# Filter by severity:"
echo "gh api '/repos/OWNER/REPO/code-scanning/alerts?severity=critical' \\"
echo "  --jq '.[].rule.description'"

echo ""
echo "# Filter by tool:"
echo "gh api '/repos/OWNER/REPO/code-scanning/alerts?tool_name=CodeQL' \\"
echo "  --jq '.[].rule.id' | sort | uniq -c | sort -rn"

echo ""
echo "# Get details for a specific alert:"
echo "gh api /repos/OWNER/REPO/code-scanning/alerts/ALERT_NUMBER | jq ."

echo ""
echo "# Dismiss a false positive:"
echo "gh api \\"
echo "  --method PATCH \\"
echo "  /repos/OWNER/REPO/code-scanning/alerts/ALERT_NUMBER \\"
echo "  -f dismissed_reason='false positive' \\"
echo "  -f dismissed_comment='Test file, not production code'"

echo ""
echo "# Count alerts by severity:"
echo "gh api /repos/OWNER/REPO/code-scanning/alerts \\"
echo "  --jq 'group_by(.rule.severity) | map({severity: .[0].rule.severity, count: length})'"

# ─────────────────────────────────────────────────────────────
# 5. Live alert check if gh available
# ─────────────────────────────────────────────────────────────
section "5. Live Code Scanning Check (if gh configured)"

if command_exists gh && gh auth status >/dev/null 2>&1; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  if [ -n "$REPO" ]; then
    echo "Code scanning alerts for: $REPO"
    gh api "repos/${REPO}/code-scanning/alerts" \
      --jq '.[] | {number, rule: .rule.id, severity: .rule.severity, state}' \
      2>/dev/null || echo "(Code scanning not enabled or no alerts found)"
  fi
else
  echo "(gh not authenticated - showing reference only)"
fi

# ─────────────────────────────────────────────────────────────
# 6. Supported languages reference
# ─────────────────────────────────────────────────────────────
section "6. CodeQL Supported Languages"

echo ""
printf "%-25s %-20s\n" "LANGUAGE VALUE" "FILE EXTENSIONS"
printf "%-25s %-20s\n" "───────────────────────" "────────────────────"
printf "%-25s %-20s\n" "javascript-typescript" ".js, .ts, .jsx, .tsx"
printf "%-25s %-20s\n" "python" ".py"
printf "%-25s %-20s\n" "java-kotlin" ".java, .kt"
printf "%-25s %-20s\n" "c-cpp" ".c, .cpp, .h"
printf "%-25s %-20s\n" "csharp" ".cs"
printf "%-25s %-20s\n" "go" ".go"
printf "%-25s %-20s\n" "ruby" ".rb"
printf "%-25s %-20s\n" "swift" ".swift"

# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────
section "Cleanup"
rm -f .github/workflows/lab026-codeql.yml
rm -f .github/codeql/config.yml
rm -f /tmp/lab026-example.sarif
rmdir .github/codeql 2>/dev/null || true
echo "Demo files removed"

section "Lab 026 Complete"
echo "Key takeaways:"
echo "  - CodeQL requires permissions: security-events: write to upload SARIF"
echo "  - 'security-extended' query suite finds more than 'default' at slightly more false positives"
echo "  - Any tool outputting SARIF can integrate with GitHub code scanning"
echo "  - paths-ignore in codeql-config.yml excludes test files from analysis"
echo "  - gh api /repos/{owner}/{repo}/code-scanning/alerts enables bulk alert management"
