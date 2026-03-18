# Lab 029 - GitHub Script

## Introduction

- `actions/github-script` is a GitHub Actions action that lets you write JavaScript directly in your workflow YAML - with the full **Octokit REST API** and **GraphQL API** pre-authenticated and pre-configured.
- Instead of shelling out to `curl` and juggling JSON with `jq`, you get a proper SDK with typed methods, automatic pagination, and first-class promise support.
- This lab covers the `github-script` action API, common patterns (PR comments, issue labeling, check runs, project automation), GraphQL usage, pagination, and how to write maintainable multi-line scripts.

---

## Why `github-script`?

- **No authentication boilerplate**: `github` is pre-authenticated with `GITHUB_TOKEN`
- **No dependency installation**: The Octokit library is bundled in the action
- **Typed API methods**: `github.rest.issues.addLabels(...)` is easier to read than `curl -X POST ...`
- **Works with both REST and GraphQL**: `github.rest.*` for REST, `github.graphql` for GraphQL
- **Access to workflow context**: The `context` object contains `repo`, `sha`, `actor`, `payload`, and everything else from the GitHub event

---

## 1. Basic Structure

```yaml
- name: My GitHub Script step
  uses: actions/github-script@v7
  with:
    script: |
      // 'github' is the authenticated Octokit client
      // 'context' is the workflow run context
      // 'core' is @actions/core for logging and outputs
      // 'exec' is @actions/exec for running commands
      // 'io' is @actions/io for filesystem operations
      // 'fetch' is node-fetch for HTTP requests

      const result = await github.rest.repos.get({
        owner: context.repo.owner,
        repo: context.repo.repo
      });
      console.log(`Stars: ${result.data.stargazers_count}`);
```

You can also specify a `result-encoding` and read the output:

```yaml
- name: Get PR number
  id: pr-info
  uses: actions/github-script@v7
  with:
    result-encoding: string
    script: return context.payload.pull_request.number.toString()

- name: Use result
  run: echo "PR number is ${{ steps.pr-info.outputs.result }}"
```

---

## 2. Accessing the `context` Object

The `context` object mirrors the workflow's `${{ github }}` context:

```javascript
// Repository info
context.repo; // { owner: 'my-org', repo: 'my-repo' }
context.repo.owner; // 'my-org'
context.repo.repo; // 'my-repo'

// Run info
context.sha; // commit SHA
context.ref; // 'refs/heads/main'
context.workflow; // workflow name
context.job; // current job name
context.runId; // workflow run ID
context.runNumber; // run number
context.actor; // triggering user

// Event payload (varies by event type)
context.payload; // full event payload
context.payload.pull_request; // for pull_request events
context.payload.issue; // for issues events
context.payload.comment; // for issue_comment events
context.eventName; // 'push', 'pull_request', etc.
```

---

## 3. Creating PR Comments

Post a comment on the pull request that triggered the workflow:

```yaml
name: PR Analyzer

on:
  pull_request:
    types: [opened, synchronize]

permissions:
  pull-requests: write

jobs:
  analyze:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Post analysis comment
        uses: actions/github-script@v7
        with:
          script: |
            const prNumber = context.payload.pull_request.number;
            const filesChanged = context.payload.pull_request.changed_files;
            const additions = context.payload.pull_request.additions;
            const deletions = context.payload.pull_request.deletions;

            const body = [
              '## PR Analysis',
              '',
              `| Metric | Value |`,
              `|--------|-------|`,
              `| Files changed | ${filesChanged} |`,
              `| Lines added | +${additions} |`,
              `| Lines removed | -${deletions} |`,
              `| Net change | ${additions - deletions} |`,
              '',
              `> Analyzed at ${new Date().toISOString()}`
            ].join('\n');

            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: prNumber,
              body
            });
```

### Updating an Existing Comment (Upsert Pattern)

Avoid spamming new comments on every push - find and update an existing one:

```yaml
- name: Upsert PR comment
  uses: actions/github-script@v7
  with:
    script: |
      const marker = '<!-- ci-status-comment -->';
      const body = `${marker}\n## CI Status\n\nAll checks passed! ✅`;
      const prNumber = context.payload.pull_request.number;

      // Search for existing comment with the marker
      const { data: comments } = await github.rest.issues.listComments({
        owner: context.repo.owner,
        repo: context.repo.repo,
        issue_number: prNumber
      });

      const existing = comments.find(c => c.body.includes(marker));

      if (existing) {
        await github.rest.issues.updateComment({
          owner: context.repo.owner,
          repo: context.repo.repo,
          comment_id: existing.id,
          body
        });
        console.log(`Updated comment ${existing.id}`);
      } else {
        await github.rest.issues.createComment({
          owner: context.repo.owner,
          repo: context.repo.repo,
          issue_number: prNumber,
          body
        });
        console.log('Created new comment');
      }
```

---

## 4. Adding Labels to Pull Requests

```yaml
name: Auto-label PRs

on:
  pull_request:
    types: [opened, synchronize]

permissions:
  pull-requests: write
  contents: read

jobs:
  label:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Apply labels based on changed files
        uses: actions/github-script@v7
        with:
          script: |
            const { data: files } = await github.rest.pulls.listFiles({
              owner: context.repo.owner,
              repo: context.repo.repo,
              pull_number: context.payload.pull_request.number
            });

            const labels = new Set();
            const fileNames = files.map(f => f.filename);

            // Label rules
            const rules = [
              { pattern: /^\.github\//, label: 'ci/cd' },
              { pattern: /^src\/frontend\//, label: 'frontend' },
              { pattern: /^src\/api\//, label: 'backend' },
              { pattern: /^infra\//, label: 'infrastructure' },
              { pattern: /\.test\.(js|ts)$/, label: 'tests' },
              { pattern: /^docs\//, label: 'documentation' },
              { pattern: /package(-lock)?\.json$/, label: 'dependencies' },
            ];

            for (const file of fileNames) {
              for (const rule of rules) {
                if (rule.pattern.test(file)) {
                  labels.add(rule.label);
                }
              }
            }

            if (context.payload.pull_request.additions > 500) {
              labels.add('large-pr');
            }

            if (labels.size > 0) {
              await github.rest.issues.addLabels({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: context.payload.pull_request.number,
                labels: [...labels]
              });
              console.log(`Applied labels: ${[...labels].join(', ')}`);
            }
```

---

## 5. Creating Check Runs

Create custom check runs with detailed output:

```yaml
- name: Create custom check run
  uses: actions/github-script@v7
  with:
    script: |
      const { data: checkRun } = await github.rest.checks.create({
        owner: context.repo.owner,
        repo: context.repo.repo,
        name: 'Custom Analysis',
        head_sha: context.sha,
        status: 'in_progress',
        started_at: new Date().toISOString()
      });

      // ... run your analysis ...
      const findings = ['Issue 1 in src/app.js:42', 'Issue 2 in src/utils.js:15'];

      await github.rest.checks.update({
        owner: context.repo.owner,
        repo: context.repo.repo,
        check_run_id: checkRun.id,
        status: 'completed',
        conclusion: findings.length === 0 ? 'success' : 'failure',
        completed_at: new Date().toISOString(),
        output: {
          title: `Found ${findings.length} issue(s)`,
          summary: findings.length === 0
            ? 'No issues found.'
            : `Found ${findings.length} issue(s) that need attention.`,
          text: findings.map(f => `- ${f}`).join('\n'),
          annotations: [
            {
              path: 'src/app.js',
              start_line: 42,
              end_line: 42,
              annotation_level: 'warning',
              message: 'Potential null dereference',
              title: 'Null dereference'
            }
          ]
        }
      });
```

---

## 6. GraphQL with `github.graphql`

Use GraphQL for queries that require nested data or aren't available in the REST API:

```yaml
- name: Get PR review threads
  uses: actions/github-script@v7
  with:
    script: |
      const query = `
        query getPRThreads($owner: String!, $repo: String!, $number: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $number) {
              reviewThreads(first: 10) {
                nodes {
                  isResolved
                  comments(first: 1) {
                    nodes {
                      body
                      author { login }
                    }
                  }
                }
              }
            }
          }
        }
      `;

      const result = await github.graphql(query, {
        owner: context.repo.owner,
        repo: context.repo.repo,
        number: context.payload.pull_request.number
      });

      const threads = result.repository.pullRequest.reviewThreads.nodes;
      const unresolved = threads.filter(t => !t.isResolved);
      console.log(`Unresolved review threads: ${unresolved.length}`);

      if (unresolved.length > 0) {
        core.setFailed(`There are ${unresolved.length} unresolved review threads`);
      }
```

---

## 7. Pagination with `paginate()`

Most GitHub API endpoints return paginated results. Use `github.paginate()` to automatically fetch all pages:

```yaml
- name: List all open issues with a specific label
  uses: actions/github-script@v7
  with:
    script: |
      const issues = await github.paginate(github.rest.issues.listForRepo, {
        owner: context.repo.owner,
        repo: context.repo.repo,
        state: 'open',
        labels: 'bug',
        per_page: 100
      });

      console.log(`Total open bugs: ${issues.length}`);

      // Process all issues (no need to handle pagination manually)
      const staleIssues = issues.filter(issue => {
        const lastUpdate = new Date(issue.updated_at);
        const daysSinceUpdate = (Date.now() - lastUpdate) / (1000 * 60 * 60 * 24);
        return daysSinceUpdate > 30;
      });

      console.log(`Stale bugs (>30 days): ${staleIssues.length}`);
      for (const issue of staleIssues) {
        console.log(`  #${issue.number}: ${issue.title}`);
      }
```

---

## 8. Setting Outputs

Use `core.setOutput()` to pass values from a `github-script` step to subsequent steps:

```yaml
- name: Get latest release version
  id: latest-release
  uses: actions/github-script@v7
  with:
    script: |
      const { data: release } = await github.rest.repos.getLatestRelease({
        owner: context.repo.owner,
        repo: context.repo.repo
      });
      core.setOutput('version', release.tag_name);
      core.setOutput('url', release.html_url);
      return release.tag_name;

- name: Use the version
  run: |
    echo "Latest release: ${{ steps.latest-release.outputs.version }}"
    echo "URL: ${{ steps.latest-release.outputs.url }}"
```

---

## 9. Complete Example: Issue Triage Automation

```yaml
name: Issue Triage

on:
  issues:
    types: [opened]

permissions:
  issues: write

jobs:
  triage:
    runs-on: ubuntu-latest

    steps:
      - name: Triage new issue
        uses: actions/github-script@v7
        with:
          script: |
            const issue = context.payload.issue;
            const labels = [];
            const body = issue.body?.toLowerCase() || '';
            const title = issue.title.toLowerCase();

            // Auto-classify by content
            if (body.includes('error') || body.includes('exception') || body.includes('crash')) {
              labels.push('bug');
            }
            if (body.includes('how to') || body.includes('how do i') || title.startsWith('question:')) {
              labels.push('question');
            }
            if (title.startsWith('feat:') || title.startsWith('feature:') || body.includes('would be nice')) {
              labels.push('enhancement');
            }
            if (body.includes('docs') || body.includes('documentation') || body.includes('readme')) {
              labels.push('documentation');
            }

            // Add triage label if unclassified
            if (labels.length === 0) {
              labels.push('needs-triage');
            }

            await github.rest.issues.addLabels({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: issue.number,
              labels
            });

            // Post a welcome comment
            const isFirstIssue = issue.author_association === 'NONE';
            if (isFirstIssue) {
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: issue.number,
                body: `👋 Thanks for opening your first issue, @${issue.user.login}! A maintainer will review it shortly. Applied labels: ${labels.join(', ')}.`
              });
            }

            console.log(`Triaged issue #${issue.number} with labels: ${labels.join(', ')}`);
```

---

## Hands-on

1. Write a `github-script` step that posts a comment on the current PR with the run ID:

   ??? success "Solution"
   `bash
    cat > .github/workflows/pr-comment.yml << 'EOF'
    name: PR Comment
    on:
      pull_request:
        types: [opened, synchronize]
    permissions:
      pull-requests: write
    jobs:
      comment:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/github-script@v7
            with:
              script: |
                await github.rest.issues.createComment({
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  issue_number: context.payload.pull_request.number,
                  body: "CI run ID: " + context.runId
                });
    EOF
    git add .github/workflows/pr-comment.yml && git commit -m "ci: post PR comment with run ID"
    `

2. Add a label to the current PR using `octokit.rest.issues.addLabels`:

   ??? success "Solution"
   `bash
    cat > .github/workflows/pr-label.yml << 'EOF'
    name: PR Labeler
    on:
      pull_request:
        types: [opened]
    permissions:
      pull-requests: write
    jobs:
      label:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/github-script@v7
            with:
              script: |
                await github.rest.issues.addLabels({
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  issue_number: context.payload.pull_request.number,
                  labels: ["needs-review"]
                });
    EOF
    git add .github/workflows/pr-label.yml && git commit -m "ci: auto-label PRs on open"
    `

3. Create a check run using `rest.checks.create` and mark it completed:

   ??? success "Solution"
   `bash
    cat > .github/workflows/check-run.yml << 'EOF'
    name: Custom Check
    on: [push]
    permissions:
      checks: write
    jobs:
      check:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/github-script@v7
            with:
              script: |
                await github.rest.checks.create({
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  name: "Custom Check",
                  head_sha: context.sha,
                  status: "completed",
                  conclusion: "success",
                  completed_at: new Date().toISOString()
                });
    EOF
    git add .github/workflows/check-run.yml && git commit -m "ci: add custom check run"
    `

4. Use `github.graphql` to list the titles of the 5 most recently opened PRs:

   ??? success "Solution"
   `bash
    cat > .github/workflows/graphql-prs.yml << 'EOF'
    name: List Recent PRs
    on: [workflow_dispatch]
    jobs:
      list:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/github-script@v7
            with:
              script: |
                const result = await github.graphql(`
                  query($owner: String!, $repo: String!) {
                    repository(owner: $owner, name: $repo) {
                      pullRequests(first: 5, orderBy: {field: CREATED_AT, direction: DESC}) {
                        nodes { title number }
                      }
                    }
                  }`, { owner: context.repo.owner, repo: context.repo.repo });
                result.repository.pullRequests.nodes.forEach(pr => console.log(pr.number, pr.title));
    EOF
    git add .github/workflows/graphql-prs.yml && git commit -m "ci: list recent PRs via GraphQL"
    `

5. Paginate all open issues using `octokit.paginate` and print a count:

   ??? success "Solution"
   `bash
    cat > .github/workflows/paginate-issues.yml << 'EOF'
    name: Count Issues
    on: [workflow_dispatch]
    jobs:
      count:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/github-script@v7
            with:
              script: |
                const issues = await github.paginate(github.rest.issues.listForRepo, {
                  owner: context.repo.owner,
                  repo: context.repo.repo,
                  state: "open",
                  per_page: 100
                });
                console.log("Total open issues:", issues.length);
    EOF
    git add .github/workflows/paginate-issues.yml && git commit -m "ci: paginate and count open issues"
    `

## Exercises

### Exercise 1 - PR Comment

Create a workflow that posts a comment on every PR with the list of changed files.

### Exercise 2 - Auto-Labeler

Create a workflow that adds a `documentation` label when a PR only changes `.md` files, and a `dependencies` label when it only changes `package.json` or `package-lock.json`.

### Exercise 3 - Stale Issues

Create a scheduled workflow that lists all issues not updated in 60 days and adds a `stale` label to them using `github.paginate()`.

### Exercise 4 - Check Run

Create a workflow that creates a custom check run named "File Size Check" that fails if any changed file in a PR is larger than 1 MB.

### Exercise 5 - GraphQL

Use `github.graphql` to query the discussion threads on a PR and print the number of unresolved threads.

---

## Summary

- `actions/github-script` provides a pre-authenticated Octokit client (`github`) and workflow context (`context`) without any setup
- `github.rest.*` methods map directly to the GitHub REST API with full TypeScript types and error handling
- `github.graphql(query, variables)` executes GraphQL queries for nested data not available via REST
- `github.paginate(method, params)` automatically fetches all pages of paginated API responses
- `core.setOutput('name', value)` passes values from a `github-script` step to subsequent workflow steps
- The upsert comment pattern (find existing marker, update or create) prevents PR comment spam on repeated pushes
- Check run annotations (`annotation_level: 'warning' | 'failure'`) appear inline in PR file diffs for precise feedback
