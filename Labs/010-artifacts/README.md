# Lab 010 - Artifacts

## Introduction

- GitHub Actions artifacts allow you to persist data produced during a workflow run and share that data between jobs.
- Artifacts are files or collections of files produced during a workflow run, such as compiled binaries, test results, coverage reports, or deployment packages.
- This lab covers the full lifecycle of artifacts: uploading them from a job, downloading them in a later job or locally, configuring retention, and understanding size and naming constraints.

---

## What Are Artifacts?

Artifacts are files uploaded during a workflow run and stored by GitHub. They persist beyond the workflow run itself (for a configurable period) and can be:

- Downloaded from the GitHub UI
- Downloaded with the `gh` CLI
- Used by subsequent jobs in the same workflow
- Shared across workflows via the API (in the same repository)

Artifacts are **not** the same as caches. Artifacts are for outputs you want to keep; caches are for speeding up future runs by reusing dependencies.

---

## Uploading Artifacts - `actions/upload-artifact`

The `actions/upload-artifact` action uploads files from the runner to GitHub's artifact storage.

### Basic Upload

```yaml
- name: Upload build output
  uses: actions/upload-artifact@v4
  with:
    name: my-build-artifact
    path: dist/
```

### Upload Multiple Paths

```yaml
- name: Upload test results and coverage
  uses: actions/upload-artifact@v4
  with:
    name: test-artifacts
    path: |
      test-results/
      coverage/
      *.log
```

### Upload with Retention Period

```yaml
- name: Upload artifact with custom retention
  uses: actions/upload-artifact@v4
  with:
    name: release-package
    path: release/
    retention-days: 90
```

### Upload with Overwrite Option

```yaml
- name: Upload artifact (allow overwrite)
  uses: actions/upload-artifact@v4
  with:
    name: build-output
    path: build/
    overwrite: true
```

### Exclude Files from Upload

```yaml
- name: Upload source excluding node_modules
  uses: actions/upload-artifact@v4
  with:
    name: source-package
    path: |
      src/
      !src/node_modules/
      !src/**/*.test.js
```

---

## Downloading Artifacts - `actions/download-artifact`

### Download a Specific Artifact

```yaml
- name: Download build artifact
  uses: actions/download-artifact@v4
  with:
    name: my-build-artifact
    path: downloaded-artifacts/
```

### Download All Artifacts

```yaml
- name: Download all artifacts
  uses: actions/download-artifact@v4
```

When downloading all artifacts, each artifact is placed in a subdirectory matching its name.

### Download from a Specific Run

```yaml
- name: Download artifact from another run
  uses: actions/download-artifact@v4
  with:
    name: my-build-artifact
    run-id: ${{ github.event.workflow_run.id }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

---

## Sharing Artifacts Between Jobs

The most common use case is passing build outputs from one job to a downstream job.

```yaml
name: Build and Test

on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build application
        run: |
          mkdir -p dist
          echo "compiled binary content" > dist/app
          echo "build metadata" > dist/build-info.json

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: build-output
          path: dist/
          retention-days: 1

  test:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Download build artifact
        uses: actions/download-artifact@v4
        with:
          name: build-output
          path: dist/

      - name: Run tests against build
        run: |
          ls -la dist/
          echo "Running tests with build output..."

  deploy:
    runs-on: ubuntu-latest
    needs: [build, test]
    steps:
      - name: Download build artifact
        uses: actions/download-artifact@v4
        with:
          name: build-output
          path: dist/

      - name: Deploy
        run: echo "Deploying from dist/..."
```

---

## Multi-Platform Build Artifacts

A common pattern is building on multiple platforms and collecting all outputs:

```yaml
name: Cross-Platform Build

on: [push]

jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Build for ${{ matrix.os }}
        run: |
          mkdir -p dist
          echo "binary for ${{ runner.os }}" > dist/app-${{ runner.os }}

      - name: Upload platform artifact
        uses: actions/upload-artifact@v4
        with:
          name: build-${{ runner.os }}
          path: dist/

  package:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Download all platform artifacts
        uses: actions/download-artifact@v4
        # No 'name' specified - downloads all artifacts

      - name: List downloaded artifacts
        run: find . -type f | sort

      - name: Create release package
        run: |
          mkdir -p release
          cp build-Linux/app-Linux release/
          cp build-macOS/app-macOS release/
          cp build-Windows/app-Windows release/

      - name: Upload combined release
        uses: actions/upload-artifact@v4
        with:
          name: release-all-platforms
          path: release/
```

---

## Artifact Naming Best Practices

Artifact names must be unique within a workflow run. Use descriptive, structured names:

```yaml
# Good naming patterns
name: build-${{ runner.os }}-${{ github.sha }}
name: test-results-unit
name: test-results-integration
name: coverage-report
name: dist-linux-amd64
name: dist-windows-amd64
```

Artifact names cannot contain:

- `..`
- `/` (forward slash)
- `\` (backslash)
- Certain special characters

---

## Retention Periods

By default, artifacts are retained for **90 days** for public repositories and **90 days** for private repositories (configurable per repository in Settings).

```yaml
# Short-lived artifact (CI intermediate)
- uses: actions/upload-artifact@v4
  with:
    name: build-cache
    path: build/
    retention-days: 1

# Long-lived release artifact
- uses: actions/upload-artifact@v4
  with:
    name: release-v1.2.3
    path: release/
    retention-days: 400
```

Retention can be set to a maximum of **400 days**.

---

## Downloading Artifacts with `gh` CLI

After a workflow run, you can download artifacts locally using the GitHub CLI:

```bash
# List artifacts for a run
gh run view <run-id> --repo owner/repo

# Download all artifacts from the latest run
gh run download --repo owner/repo

# Download a specific artifact by name
gh run download <run-id> --name my-build-artifact --repo owner/repo

# Download to a specific directory
gh run download <run-id> --name my-build-artifact --dir ./downloaded/
```

---

## Artifact Size Limits

- Individual artifact size: **500 MB** per file (compressed)
- Total artifact storage: varies by plan
  - Free: **500 MB** included
  - Pro: **2 GB** included
  - Enterprise: configurable

To reduce artifact size:

```yaml
- name: Compress before upload
  run: tar -czf build.tar.gz dist/

- name: Upload compressed artifact
  uses: actions/upload-artifact@v4
  with:
    name: build-compressed
    path: build.tar.gz
```

---

## Complete Real-World Example: Node.js Build Pipeline

```yaml
name: Node.js Build Pipeline

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
      - run: npm ci
      - run: npm run lint -- --format json --output-file lint-results.json || true
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: lint-results
          path: lint-results.json
          retention-days: 7

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - run: npm ci
      - run: npm test -- --coverage --reporter=json --outputFile=test-results.json
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: |
            test-results.json
            coverage/
          retention-days: 14

  build:
    runs-on: ubuntu-latest
    needs: [lint, test]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - run: npm ci
      - run: npm run build
      - uses: actions/upload-artifact@v4
        with:
          name: dist-${{ github.sha }}
          path: dist/
          retention-days: 30

  deploy-staging:
    runs-on: ubuntu-latest
    needs: build
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: dist-${{ github.sha }}
          path: dist/
      - name: Deploy to staging
        run: echo "Deploying to staging..."
```

---

## Hands-on

1. Write a workflow with two jobs: `produce` uploads a text file as an artifact named `my-output`, and `consume` downloads it and prints its contents:

   ??? success "Solution"
   `bash
    cat > .github/workflows/artifact-demo.yml << 'EOF'
    name: Artifact Demo
    on: push
    jobs:
      produce:
        runs-on: ubuntu-latest
        steps:
          - run: echo "hello from produce" > output.txt
          - uses: actions/upload-artifact@v4
            with:
              name: my-output
              path: output.txt
      consume:
        runs-on: ubuntu-latest
        needs: produce
        steps:
          - uses: actions/download-artifact@v4
            with:
              name: my-output
          - run: cat output.txt
    EOF
    `

2. List all artifacts for the most recent workflow run in your repository using `gh api`:

   ??? success "Solution"
   `bash
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    RUN_ID=$(gh run list --limit 1 --json databaseId -q '.[0].databaseId')
    gh api repos/$REPO/actions/runs/$RUN_ID/artifacts | jq '.artifacts[] | {name, size_in_bytes, expires_at}'
    `

3. Download a specific artifact locally by name from the latest completed run using `gh run download`:

   ??? success "Solution"
   `bash
    # List recent runs to find an ID
    gh run list --limit 5
    # Download artifact named 'my-output' from a specific run
    gh run download <run-id> --name my-output --dir ./downloaded-artifacts/
    # Or download from the latest run
    gh run download $(gh run list --limit 1 --json databaseId -q '.[0].databaseId') \
      --name my-output --dir ./downloaded-artifacts/
    ls ./downloaded-artifacts/
    `

4. Upload an artifact with a custom retention period of 5 days and verify the setting via `gh api`:

   ??? success "Solution"
   `bash
    # In your workflow YAML, set retention-days:
    # - uses: actions/upload-artifact@v4
    #   with:
    #     name: short-lived
    #     path: output.txt
    #     retention-days: 5
    # After the run, check the artifact's expiry via API
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    RUN_ID=$(gh run list --limit 1 --json databaseId -q '.[0].databaseId')
    gh api repos/$REPO/actions/runs/$RUN_ID/artifacts \
      | jq '.artifacts[] | select(.name=="short-lived") | {name, expires_at}'
    `

5. Use `if: always()` to upload test results even when a step fails, then verify the artifact appears despite the failed run:

   ??? success "Solution"
   `bash
    cat > .github/workflows/always-upload.yml << 'EOF'
    name: Always Upload
    on: push
    jobs:
      test:
        runs-on: ubuntu-latest
        steps:
          - run: echo "test result" > results.txt && exit 1
          - uses: actions/upload-artifact@v4
            if: always()
            with:
              name: test-results
              path: results.txt
    EOF
    # After run completes (even if failed), download the artifact
    gh run download --name test-results --dir ./results/
    cat ./results/results.txt
    `

## Exercises

### Exercise 1 - Basic Upload/Download

Create a workflow with two jobs:

1. `produce` - Creates a text file and uploads it as an artifact
2. `consume` - Downloads the artifact and prints its contents

### Exercise 2 - Matrix Artifacts

Create a workflow that:

1. Runs on `ubuntu-latest`, `windows-latest`, `macos-latest`
2. Produces a platform-specific file in each matrix job
3. Has a final `merge` job that downloads all three artifacts

### Exercise 3 - Conditional Artifacts

Modify a test job to:

1. Run tests that may fail
2. Always upload test results using `if: always()`
3. Only upload coverage reports if tests passed

### Exercise 4 - Retention Tuning

Create three upload steps with different retention periods:

- Debug logs: 1 day
- Test results: 14 days
- Release packages: 90 days

### Exercise 5 - CLI Download

Using the `gh` CLI:

1. Trigger a workflow that produces an artifact
2. Wait for it to complete
3. Download the artifact locally
4. Inspect its contents

---

## Summary

- `actions/upload-artifact@v4` persists files from a job run so they can be used by other jobs or downloaded after the workflow completes
- `actions/download-artifact@v4` retrieves artifacts within the same workflow run, either by name or all at once
- Artifacts are the primary mechanism for passing build outputs between jobs that run on separate runners
- Retention periods range from 1 to 400 days; the default is 90 days and can be overridden per upload
- Use `if: always()` on upload steps for test results so they are saved even when the job fails
- The `gh run download` command provides CLI access to artifacts from any completed run
- Artifact storage counts against your plan's included storage; compress large outputs before uploading to stay within limits
