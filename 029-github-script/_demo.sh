#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 029 - GitHub Script Demo"

# ─────────────────────────────────────────────────────────────
# 1. Create workflow with PR comment examples
# ─────────────────────────────────────────────────────────────
section "1. Creating PR Comment Workflow"

mkdir -p .github/workflows

cat >.github/workflows/lab029-pr-comment.yml <<'YAML'
name: "Lab 029 - PR Comment with github-script"

on:
  pull_request:
    types: [opened, synchronize]

permissions:
  pull-requests: write
  contents: read

jobs:
  pr-analysis:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Post PR analysis comment (upsert)
        uses: actions/github-script@v7
        with:
          script: |
            const marker = '<!-- lab029-pr-analysis -->';

            const pr = context.payload.pull_request;
            const filesChanged = pr.changed_files;
            const additions   = pr.additions;
            const deletions   = pr.deletions;
            const netChange   = additions - deletions;
            const sizeLabel   = pr.additions > 500 ? '⚠️ Large PR' : '✅ Reasonable size';

            const body = [
              marker,
              '## PR Analysis Summary',
              '',
              `| Metric | Value |`,
              `|--------|-------|`,
              `| Files changed | ${filesChanged} |`,
              `| Lines added | +${additions} |`,
              `| Lines removed | -${deletions} |`,
              `| Net change | ${netChange > 0 ? '+' : ''}${netChange} |`,
              `| Size | ${sizeLabel} |`,
              '',
              `*Updated at ${new Date().toISOString()}*`
            ].join('\n');

            // Upsert: find existing comment, update or create
            const { data: comments } = await github.rest.issues.listComments({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: pr.number
            });

            const existing = comments.find(c => c.body.includes(marker));

            if (existing) {
              await github.rest.issues.updateComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                comment_id: existing.id,
                body
              });
              core.info(`Updated comment ${existing.id}`);
            } else {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: pr.number,
                body
              });
              core.info('Created new analysis comment');
            }
YAML

echo "Created: .github/workflows/lab029-pr-comment.yml"

# ─────────────────────────────────────────────────────────────
# 2. Create auto-labeler workflow
# ─────────────────────────────────────────────────────────────
section "2. Creating Issue/PR Labeler Workflow"

cat >.github/workflows/lab029-labeler.yml <<'YAML'
name: "Lab 029 - Auto-Labeler with github-script"

on:
  pull_request:
    types: [opened, synchronize]
  issues:
    types: [opened]

permissions:
  pull-requests: write
  issues: write
  contents: read

jobs:
  # ── Label PRs based on changed files ─────────────────────
  label-pr:
    name: Label PR
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'

    steps:
      - name: Apply labels based on changed files
        uses: actions/github-script@v7
        with:
          script: |
            const { data: files } = await github.rest.pulls.listFiles({
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: context.payload.pull_request.number,
              per_page: 100
            });

            const filenames = files.map(f => f.filename);
            const labels = new Set();

            const rules = [
              { pattern: /^\.github\//,           label: 'ci/cd' },
              { pattern: /^src\/frontend\//,       label: 'frontend' },
              { pattern: /\.(css|scss|less)$/,     label: 'frontend' },
              { pattern: /^src\/api\//,            label: 'backend' },
              { pattern: /^infra\//,               label: 'infrastructure' },
              { pattern: /\.tf$/,                  label: 'infrastructure' },
              { pattern: /\.(test|spec)\.(js|ts)/, label: 'tests' },
              { pattern: /^docs\//,                label: 'documentation' },
              { pattern: /\.md$/,                  label: 'documentation' },
              { pattern: /package(-lock)?\.json$/, label: 'dependencies' },
              { pattern: /requirements.*\.txt$/,   label: 'dependencies' },
            ];

            for (const filename of filenames) {
              for (const rule of rules) {
                if (rule.pattern.test(filename)) {
                  labels.add(rule.label);
                }
              }
            }

            if (context.payload.pull_request.additions > 500) {
              labels.add('large-pr');
            }

            if (labels.size > 0) {
              // Ensure labels exist before applying
              for (const label of labels) {
                try {
                  await github.rest.issues.getLabel({
                    owner: context.repo.owner,
                    repo: context.repo.repo,
                    name: label
                  });
                } catch {
                  // Label doesn't exist, create it
                  await github.rest.issues.createLabel({
                    owner: context.repo.owner,
                    repo: context.repo.repo,
                    name: label,
                    color: 'ededed'
                  });
                }
              }

              await github.rest.issues.addLabels({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: context.payload.pull_request.number,
                labels: [...labels]
              });
              core.info(`Applied labels: ${[...labels].join(', ')}`);
            }

  # ── Label issues based on content ─────────────────────────
  label-issue:
    name: Label Issue
    runs-on: ubuntu-latest
    if: github.event_name == 'issues'

    steps:
      - name: Triage new issue
        uses: actions/github-script@v7
        with:
          script: |
            const issue = context.payload.issue;
            const body  = (issue.body || '').toLowerCase();
            const title = issue.title.toLowerCase();
            const labels = [];

            if (/error|exception|crash|broken|fail/.test(body + title)) labels.push('bug');
            if (/how to|how do|question/.test(body + title)) labels.push('question');
            if (/feat:|feature:|request|would be nice/.test(body + title)) labels.push('enhancement');
            if (/docs|documentation|readme/.test(body + title)) labels.push('documentation');
            if (labels.length === 0) labels.push('needs-triage');

            await github.rest.issues.addLabels({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: issue.number,
              labels
            });
YAML

echo "Created: .github/workflows/lab029-labeler.yml"

# ─────────────────────────────────────────────────────────────
# 3. Create check run workflow
# ─────────────────────────────────────────────────────────────
section "3. Creating Custom Check Run Workflow"

cat >.github/workflows/lab029-check-run.yml <<'YAML'
name: "Lab 029 - Custom Check Run"

on:
  pull_request:
    types: [opened, synchronize]

permissions:
  checks: write
  contents: read

jobs:
  file-size-check:
    name: File Size Check
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Run file size check with annotations
        uses: actions/github-script@v7
        with:
          script: |
            const MAX_FILE_SIZE_KB = 500;

            // Create check run in 'in_progress' state
            const { data: checkRun } = await github.rest.checks.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              name: 'File Size Check',
              head_sha: context.payload.pull_request.head.sha,
              status: 'in_progress',
              started_at: new Date().toISOString()
            });

            // Get changed files
            const { data: files } = await github.rest.pulls.listFiles({
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: context.payload.pull_request.number
            });

            const oversized = files.filter(f => f.status !== 'removed' && f.changes > MAX_FILE_SIZE_KB);

            const annotations = oversized.map(f => ({
              path: f.filename,
              start_line: 1,
              end_line: 1,
              annotation_level: 'warning',
              title: 'Large file detected',
              message: `This file has ${f.changes} changed lines (limit: ${MAX_FILE_SIZE_KB}). Consider splitting it.`
            }));

            const conclusion = oversized.length === 0 ? 'success' : 'warning';

            await github.rest.checks.update({
              owner: context.repo.owner,
              repo: context.repo.repo,
              check_run_id: checkRun.id,
              status: 'completed',
              conclusion,
              completed_at: new Date().toISOString(),
              output: {
                title: oversized.length === 0
                  ? 'All files within size limits'
                  : `${oversized.length} large file(s) detected`,
                summary: oversized.length === 0
                  ? `All ${files.length} changed files are within the ${MAX_FILE_SIZE_KB} line limit.`
                  : `${oversized.length} file(s) exceed the recommended ${MAX_FILE_SIZE_KB} line change limit.`,
                annotations
              }
            });

            if (oversized.length > 0) {
              core.warning(`${oversized.length} oversized file(s): ${oversized.map(f => f.filename).join(', ')}`);
            }
YAML

echo "Created: .github/workflows/lab029-check-run.yml"

# ─────────────────────────────────────────────────────────────
# 4. Show GraphQL examples
# ─────────────────────────────────────────────────────────────
section "4. GraphQL Examples with github.graphql"

echo ""
echo "# Query PR review threads (not available via REST):"
cat <<'SNIPPET'
uses: actions/github-script@v7
with:
  script: |
    const result = await github.graphql(`
      query($owner: String!, $repo: String!, $number: Int!) {
        repository(owner: $owner, name: $repo) {
          pullRequest(number: $number) {
            reviewThreads(first: 20) {
              nodes {
                isResolved
                comments(first: 1) {
                  nodes { body author { login } }
                }
              }
            }
          }
        }
      }
    `, {
      owner: context.repo.owner,
      repo: context.repo.repo,
      number: context.payload.pull_request.number
    });

    const threads = result.repository.pullRequest.reviewThreads.nodes;
    const unresolved = threads.filter(t => !t.isResolved);
    console.log(`Unresolved threads: ${unresolved.length}`);
SNIPPET

# ─────────────────────────────────────────────────────────────
# 5. Show pagination example
# ─────────────────────────────────────────────────────────────
section "5. Pagination with github.paginate()"

echo ""
echo "# Process ALL issues (not just the first page):"
cat <<'SNIPPET'
uses: actions/github-script@v7
with:
  script: |
    // github.paginate() automatically fetches all pages
    const issues = await github.paginate(github.rest.issues.listForRepo, {
      owner: context.repo.owner,
      repo: context.repo.repo,
      state: 'open',
      labels: 'bug',
      per_page: 100
    });

    console.log(`Total open bugs: ${issues.length}`);

    const stale = issues.filter(issue => {
      const days = (Date.now() - new Date(issue.updated_at)) / 86400000;
      return days > 30;
    });
    console.log(`Stale bugs (>30 days): ${stale.length}`);
SNIPPET

# ─────────────────────────────────────────────────────────────
# 6. Live demo - repo info
# ─────────────────────────────────────────────────────────────
section "6. Live context.repo Example (if gh configured)"

if command_exists gh && gh auth status >/dev/null 2>&1; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  if [ -n "$REPO" ]; then
    echo "Demonstrating github-script context with: $REPO"
    echo ""
    echo "Equivalent to context.repo in a workflow:"
    OWNER=$(echo "$REPO" | cut -d/ -f1)
    REPONAME=$(echo "$REPO" | cut -d/ -f2)
    echo "  context.repo.owner = $OWNER"
    echo "  context.repo.repo  = $REPONAME"
    echo ""
    echo "Open issues count:"
    gh api "repos/${REPO}/issues?state=open&per_page=1" \
      -i 2>/dev/null | grep "x-total-count" | awk '{print "  " $2}' ||
      gh api "repos/${REPO}" --jq '.open_issues_count' 2>/dev/null ||
      echo "  (Could not determine)"
  fi
else
  echo "(gh not authenticated - skipping live demo)"
fi

# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────
section "Cleanup"
rm -f .github/workflows/lab029-pr-comment.yml
rm -f .github/workflows/lab029-labeler.yml
rm -f .github/workflows/lab029-check-run.yml
echo "Demo files removed"

section "Lab 029 Complete"
echo "Key takeaways:"
echo "  - github-script provides pre-authenticated Octokit without any setup"
echo "  - github.rest.* maps to REST API; github.graphql for GraphQL queries"
echo "  - github.paginate() fetches all pages automatically"
echo "  - core.setOutput() passes values to subsequent workflow steps"
echo "  - The upsert comment pattern (find marker, update or create) avoids PR spam"
echo "  - Check run annotations appear inline in PR file diffs"
