# Lab 023 - CI Pipeline

## Introduction

- A **Continuous Integration (CI) pipeline** is the automated backbone of modern software delivery.
- Every time code is pushed, the pipeline runs a fixed sequence of quality gates - linting, testing, building, and security scanning - to ensure that every change meets your team's standards before it can be merged.
- This lab walks through building a production-grade CI pipeline for a Node.js project.
- You'll learn how to structure jobs for parallel execution, integrate code coverage reporting, add static analysis and security scanning, display build status badges, and configure smart failure behavior.

---

## What Makes a Good CI Pipeline?

A well-designed CI pipeline has these characteristics:

- **Fast**: Parallel jobs and caching keep total runtime under 5 minutes for most changes
- **Reliable**: Flaky tests are flagged and isolated, not hidden
- **Informative**: Failures link directly to the failing test or lint rule
- **Secure**: Dependencies and container images are scanned on every run
- **Visible**: Badges and check statuses surface health at a glance

---

## 1. Pipeline Architecture

Our CI pipeline for a Node.js project consists of these jobs:

```
push / pull_request
         │
    ┌────┴────┐
    │         │
  lint       test (matrix: node 18, 20, 22)
    │         │
    └────┬────┘
         │
       build
         │
       security-scan
         │
       notify (on failure only)
```

Jobs `lint` and `test` run in parallel. `build` waits for both to pass. `security-scan` runs after build. `notify` runs only when something fails.

---

## 2. Complete CI Workflow

```yaml
name: CI Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

# Cancel in-progress runs on the same branch when new commits arrive
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read
  checks: write # for test reporting
  pull-requests: write # for PR comments

jobs:
  # ─────────────────────────────────────────────
  # JOB 1: Lint
  # ─────────────────────────────────────────────
  lint:
    name: Lint & Format Check
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Run ESLint
        run: npm run lint -- --format=@microsoft/eslint-formatter-sarif --output-file eslint.sarif
        continue-on-error: true

      - name: Upload ESLint SARIF
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: eslint.sarif

      - name: Check formatting with Prettier
        run: npm run format:check

      - name: TypeScript type check
        run: npm run typecheck

  # ─────────────────────────────────────────────
  # JOB 2: Test (matrix across Node versions)
  # ─────────────────────────────────────────────
  test:
    name: Test (Node ${{ matrix.node-version }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        node-version: ["18", "20", "22"]

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Node.js ${{ matrix.node-version }}
        uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Run tests with coverage
        run: npm test -- --coverage --reporters=default --reporters=jest-junit
        env:
          JEST_JUNIT_OUTPUT_DIR: ./reports
          JEST_JUNIT_OUTPUT_NAME: junit-${{ matrix.node-version }}.xml

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results-node${{ matrix.node-version }}
          path: reports/junit-*.xml

      - name: Upload coverage
        if: matrix.node-version == '20'
        uses: codecov/codecov-action@v4
        with:
          token: ${{ secrets.CODECOV_TOKEN }}
          files: ./coverage/lcov.info
          flags: unit
          fail_ci_if_error: true

      - name: Publish test results
        uses: dorny/test-reporter@v1
        if: always()
        with:
          name: Jest Tests (Node ${{ matrix.node-version }})
          path: reports/junit-*.xml
          reporter: jest-junit

  # ─────────────────────────────────────────────
  # JOB 3: Build
  # ─────────────────────────────────────────────
  build:
    name: Build
    runs-on: ubuntu-latest
    needs: [lint, test]

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: npm

      - name: Install dependencies
        run: npm ci

      - name: Build
        run: npm run build

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: build-${{ github.sha }}
          path: dist/
          retention-days: 7

  # ─────────────────────────────────────────────
  # JOB 4: Security Scan
  # ─────────────────────────────────────────────
  security-scan:
    name: Security Scan
    runs-on: ubuntu-latest
    needs: build
    permissions:
      contents: read
      security-events: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Run npm audit
        run: npm audit --audit-level=high
        continue-on-error: true

      - name: Run Snyk vulnerability scan
        uses: snyk/actions/node@master
        continue-on-error: true
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
        with:
          args: --severity-threshold=high --sarif-file-output=snyk.sarif

      - name: Upload Snyk SARIF results
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: snyk.sarif

  # ─────────────────────────────────────────────
  # JOB 5: Notify on failure
  # ─────────────────────────────────────────────
  notify-failure:
    name: Notify on Failure
    runs-on: ubuntu-latest
    needs: [lint, test, build, security-scan]
    if: failure() && github.ref == 'refs/heads/main'

    steps:
      - name: Post Slack notification
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": ":red_circle: CI failed on `main`",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": ":red_circle: *CI Pipeline Failed*\n*Repo:* ${{ github.repository }}\n*Branch:* ${{ github.ref_name }}\n*Triggered by:* ${{ github.actor }}\n*Run:* <${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View Run>"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK
```

---

## 3. Caching Strategies

Effective caching is the single biggest lever for reducing CI runtime:

```yaml
# npm cache (built into setup-node)
- uses: actions/setup-node@v4
  with:
    node-version: "20"
    cache: npm

# Custom cache for build outputs
- name: Cache Next.js build
  uses: actions/cache@v4
  with:
    path: |
      .next/cache
      ~/.npm
    key: ${{ runner.os }}-nextjs-${{ hashFiles('**/package-lock.json') }}-${{ hashFiles('**/*.js', '**/*.ts', '**/*.tsx') }}
    restore-keys: |
      ${{ runner.os }}-nextjs-${{ hashFiles('**/package-lock.json') }}-
      ${{ runner.os }}-nextjs-
```

---

## 4. Fail Fast vs Continue on Error

Control whether a job matrix aborts all jobs when one fails:

```yaml
strategy:
  fail-fast: true    # Default: cancel remaining matrix jobs on first failure
  fail-fast: false   # Let all matrix jobs complete even if one fails
```

For individual steps, use `continue-on-error`:

```yaml
- name: Run optional analysis
  continue-on-error: true # Step failure won't fail the job
  run: ./optional-tool.sh
```

For jobs with required predecessors that should still run:

```yaml
notify-failure:
  needs: [lint, test, build]
  if: failure() # Run even if needs jobs failed
```

---

## 5. Build Status Badges

Add a status badge to your repository README to display CI health:

```markdown
![CI](https://github.com/OWNER/REPO/actions/workflows/ci.yml/badge.svg)
![CI (main)](https://github.com/OWNER/REPO/actions/workflows/ci.yml/badge.svg?branch=main)
```

For branch-specific badges, append `?branch=<branch-name>`. For event-specific badges, append `?event=push`.

---

## 6. Test Reporting with JUnit

`dorny/test-reporter` parses JUnit XML results and creates a check run with inline test results visible in the PR:

```yaml
- name: Publish test report
  uses: dorny/test-reporter@v1
  if: success() || failure()
  with:
    name: Test Results
    path: reports/*.xml
    reporter: jest-junit # or: java-junit, dotnet-trx, mocha-json
    fail-on-error: true
```

For Go projects using `gotestsum`:

```yaml
- name: Run tests
  run: gotestsum --junitfile reports/junit.xml ./...

- name: Publish test report
  uses: dorny/test-reporter@v1
  if: always()
  with:
    name: Go Tests
    path: reports/junit.xml
    reporter: java-junit
```

---

## 7. Code Coverage with Codecov

```yaml
- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    token: ${{ secrets.CODECOV_TOKEN }}
    files: ./coverage/lcov.info,./coverage/coverage.xml
    flags: unit,integration
    name: node-20-coverage
    fail_ci_if_error: true
    verbose: true
```

Then add the Codecov badge to your README:

```markdown
[![codecov](https://codecov.io/gh/OWNER/REPO/branch/main/graph/badge.svg)](https://codecov.io/gh/OWNER/REPO)
```

---

## 8. Path Filters for Monorepos

Use path filters to run only affected jobs:

```yaml
on:
  push:
    paths:
      - "packages/api/**"
      - "packages/shared/**"
      - ".github/workflows/ci-api.yml"
  pull_request:
    paths:
      - "packages/api/**"
```

Or use `dorny/paths-filter` for more granular control:

```yaml
- name: Detect changed packages
  id: changes
  uses: dorny/paths-filter@v3
  with:
    filters: |
      api:
        - 'packages/api/**'
      frontend:
        - 'packages/frontend/**'
      shared:
        - 'packages/shared/**'

- name: Run API tests
  if: steps.changes.outputs.api == 'true' || steps.changes.outputs.shared == 'true'
  run: cd packages/api && npm test
```

---

## Hands-on

1. Create a full CI workflow with `lint`, `test`, and `build` jobs where lint and test run in parallel and build waits for both:

   ??? success "Solution"
   `bash
    mkdir -p .github/workflows
    cat > .github/workflows/ci.yml << 'EOF'
    name: CI Pipeline
    on:
      push:
        branches: [main]
      pull_request:
    jobs:
      lint:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: actions/setup-node@v4
            with:
              node-version: "20"
              cache: npm
          - run: npm ci && npm run lint
      test:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: actions/setup-node@v4
            with:
              node-version: "20"
              cache: npm
          - run: npm ci && npm test
      build:
        needs: [lint, test]
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: actions/setup-node@v4
            with:
              node-version: "20"
              cache: npm
          - run: npm ci && npm run build
    EOF
    git add .github/workflows/ci.yml && git commit -m "ci: add parallel lint+test+build pipeline"
    `

2. Add path filters so the CI workflow only runs when files under `src/` change:

   ??? success "Solution"
   `bash
    git diff --name-only HEAD~1 HEAD | grep '^src/'
    `

3. Upload the build output directory as an artifact named with the commit SHA:

   ??? success "Solution"
   `bash
    RUN_ID=$(gh run list --workflow ci.yml --limit 1 --json databaseId -q '.[0].databaseId')
    gh api /repos/OWNER/REPO/actions/runs/${RUN_ID}/artifacts --jq '.artifacts[].name'
    `

4. Add a CI status badge to `README.md` pointing to the `main` branch:

   ??? success "Solution"
   `bash
    OWNER=$(gh repo view --json owner -q '.owner.login')
    REPO=$(gh repo view --json name -q '.name')
    echo "![CI](https://github.com/${OWNER}/${REPO}/actions/workflows/ci.yml/badge.svg?branch=main)" | cat - README.md > /tmp/readme_new && mv /tmp/readme_new README.md
    git add README.md && git commit -m "docs: add CI status badge"
    `

5. View the full log of the most recent CI run using `gh run view`:

   ??? success "Solution"
   `bash
    RUN_ID=$(gh run list --workflow ci.yml --limit 1 --json databaseId -q '.[0].databaseId')
    gh run view "$RUN_ID" --log
    `

## Exercises

### Exercise 1 - Basic Pipeline

Create a `.github/workflows/ci.yml` with three jobs: `lint` (runs `eslint`), `test` (runs `jest`), and `build` (runs `npm run build`). Configure `test` and `build` to depend on `lint`.

### Exercise 2 - Matrix Testing

Extend the test job to run across Node.js versions 18, 20, and 22 using a matrix strategy. Set `fail-fast: false` so all versions complete even if one fails.

### Exercise 3 - Artifacts and Reports

Add JUnit output to your test job and use `dorny/test-reporter` to publish the results as a check run. Upload the coverage report as an artifact.

### Exercise 4 - Caching

Add npm caching to all jobs using `actions/setup-node`'s built-in cache. Measure the time difference between a warm and cold cache run.

### Exercise 5 - Failure Notification

Add a notification job that runs only when the pipeline fails on the `main` branch. Use a Slack webhook or create a GitHub issue via `actions/github-script`.

---

## Summary

- Parallel jobs (`lint`, `test`) reduce total pipeline time; use `needs:` to enforce ordering only where required
- Matrix strategy across Node.js versions ensures compatibility without duplicating job definitions
- `fail-fast: false` lets all matrix legs complete, giving a full picture of failures across versions
- `dorny/test-reporter` converts JUnit XML into GitHub check annotations visible inline in pull requests
- `codecov/codecov-action` uploads LCOV/XML coverage reports and enforces minimum coverage thresholds
- `concurrency:` with `cancel-in-progress: true` avoids wasting runner time on superseded commits
- Build status badges in README provide instant visibility into pipeline health for the entire team
