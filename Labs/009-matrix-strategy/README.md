# Lab 009 - Matrix Strategy

## Introduction

- The **matrix strategy** lets you run a job multiple times with different configurations simultaneously.
- Instead of duplicating jobs for every OS, language version, or configuration combination, you define the variables once and GitHub Actions spawns a separate job for each combination.
- This is the standard approach for cross-platform testing, multi-version validation, and parallel environment builds.
- This lab covers matrix syntax, multi-dimensional matrices, `include`/`exclude`, and advanced matrix control.

---

## 1. Basic Matrix

A matrix is defined under `strategy.matrix`. Each key becomes a variable, and each value becomes one combination:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        node-version: [16, 18, 20] # runs 3 jobs: one per version

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}

      - run: |
          node --version
          npm test
```

This creates three jobs:

- `test (16)`
- `test (18)`
- `test (20)`

---

## 2. Multi-Dimensional Matrix

Multiple keys create a Cartesian product - every combination of values:

```yaml
jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
        node-version: [18, 20]

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
      - run: node --version
```

This creates **3 × 2 = 6** jobs:
| OS | Node |
|---|---|
| ubuntu-latest | 18 |
| ubuntu-latest | 20 |
| windows-latest | 18 |
| windows-latest | 20 |
| macos-latest | 18 |
| macos-latest | 20 |

---

## 3. Accessing Matrix Values

Use `${{ matrix.KEY }}` in any YAML field:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
    python-version: ["3.10", "3.11", "3.12"]
    experimental: [false]

jobs:
  build:
    name: ${{ matrix.os }} / Python ${{ matrix.python-version }}
    runs-on: ${{ matrix.os }}
    steps:
      - name: Setup Python ${{ matrix.python-version }}
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}

      - run: python --version

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: results-${{ matrix.os }}-py${{ matrix.python-version }}
          path: ./output/
```

---

## 4. `include` - Adding Combinations

Use `include` to add extra combinations that don't fit the standard Cartesian product, or to add extra variables to existing combinations:

### Adding an entirely new combination

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest]
    node-version: [18, 20]
    include:
      # This combination doesn't exist in the base matrix - adds it
      - os: macos-latest
        node-version: 20
        experimental: true
```

### Augmenting existing combinations

When an `include` entry matches an existing combination, it adds the extra keys to those jobs:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
    node-version: [18, 20]
    include:
      # Add 'npm-flags: --legacy-peer-deps' to all jobs with node-version 18
      - node-version: 18
        npm-flags: "--legacy-peer-deps"

      # Add a custom label to the macOS job
      - os: macos-latest
        runner-label: "macOS Runner"
```

### Complete include example

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest]
    python: ["3.11", "3.12"]
    include:
      # New combination: ubuntu + Python 3.10 (not in base grid)
      - os: ubuntu-latest
        python: "3.10"
        legacy: true

      # Augment: add extra variable to ubuntu jobs only
      - os: ubuntu-latest
        extra-packages: "build-essential"
```

---

## 5. `exclude` - Removing Combinations

Use `exclude` to remove specific combinations from the matrix:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
    node-version: [16, 18, 20]
    exclude:
      # Don't test Node 16 on Windows (unsupported)
      - os: windows-latest
        node-version: 16

      # Don't test Node 16 on macOS
      - os: macos-latest
        node-version: 16
```

### Combining include and exclude

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
    node-version: [16, 18, 20]
    include:
      # Add an edge case: ubuntu + node 21 (not in base)
      - os: ubuntu-latest
        node-version: 21
        experimental: true
    exclude:
      # Remove old combination
      - os: windows-latest
        node-version: 16
```

Final matrix: the full 3×3 grid minus the excluded entry, plus the included edge case.

---

## 6. `fail-fast`

By default, `fail-fast: true` means that if one matrix job fails, GitHub cancels all remaining in-progress jobs:

```yaml
strategy:
  fail-fast: true # default - cancel others on first failure
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
```

Set `fail-fast: false` to run all combinations regardless of failures:

```yaml
strategy:
  fail-fast: false # let all matrix jobs complete even if one fails
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
```

When to use `fail-fast: false`:

- You want to see all failures at once (e.g., compatibility testing)
- Running expensive tests where you want the full picture
- When matrix jobs are independent and partial results are valuable

---

## 7. `max-parallel`

Limits how many matrix jobs run at the same time:

```yaml
strategy:
  max-parallel: 2 # only 2 jobs run concurrently (default: all)
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
    node-version: [18, 20]
# 6 total jobs, but only 2 at a time
```

Use cases:

- Rate-limited external services (test databases, APIs)
- Self-hosted runners with limited capacity
- Cost control on paid minutes

---

## 8. Experimental Combinations with `continue-on-error`

Mark specific matrix combinations as experimental so their failure doesn't fail the entire workflow:

```yaml
strategy:
  fail-fast: false
  matrix:
    node-version: [18, 20, 22]
    include:
      - node-version: 22
        experimental: true

jobs:
  test:
    runs-on: ubuntu-latest
    continue-on-error: ${{ matrix.experimental == true }}
    strategy:
      fail-fast: false
      matrix:
        node-version: [18, 20, 22]
        experimental: [false]
        include:
          - node-version: 22
            experimental: true

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
      - run: npm test
```

Node 22 failures won't fail the overall job - they're expected experiments.

---

## 9. Dynamic Matrix with `fromJSON`

Generate a matrix at runtime based on computed values:

```yaml
jobs:
  compute-matrix:
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.set-matrix.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4

      - name: Determine test matrix
        id: set-matrix
        run: |
          # Could analyze changed files, current branch, etc.
          if [ "${{ github.ref }}" = "refs/heads/main" ]; then
            # Full matrix for main branch
            MATRIX='{"os":["ubuntu-latest","windows-latest","macos-latest"],"node":["18","20","22"]}'
          else
            # Reduced matrix for feature branches (faster feedback)
            MATRIX='{"os":["ubuntu-latest"],"node":["20"]}'
          fi
          echo "matrix=${MATRIX}" >> $GITHUB_OUTPUT
          echo "Using matrix: ${MATRIX}"

  test:
    needs: compute-matrix
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix: ${{ fromJSON(needs.compute-matrix.outputs.matrix) }}

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node }}
      - run: |
          echo "Testing on ${{ matrix.os }} with Node ${{ matrix.node }}"
          node --version
```

---

## 10. Complete Example: Node.js × OS Matrix

```yaml
name: Node.js Cross-Platform CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    name: Node ${{ matrix.node-version }} on ${{ matrix.os }}
    runs-on: ${{ matrix.os }}

    strategy:
      fail-fast: false
      max-parallel: 6
      matrix:
        os:
          - ubuntu-latest
          - windows-latest
          - macos-latest
        node-version:
          - "18"
          - "20"
          - "22"
        include:
          # Add LTS flag to LTS versions
          - node-version: "18"
            lts: true
          - node-version: "20"
            lts: true
          # Node 22 is experimental on all platforms
          - node-version: "22"
            experimental: true
        exclude:
          # Windows + Node 18 combination is not supported in our project
          - os: windows-latest
            node-version: "18"

    continue-on-error: ${{ matrix.experimental == true }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js ${{ matrix.node-version }}
        uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Run linter
        run: npm run lint || echo "No lint script"

      - name: Run tests
        run: npm test || echo "No test script"

      - name: Build
        run: npm run build || echo "No build script"

      - name: LTS-only step
        if: matrix.lts == true
        run: echo "Running LTS-specific checks for Node ${{ matrix.node-version }}"

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results-${{ matrix.os }}-node${{ matrix.node-version }}
          path: coverage/
          if-no-files-found: ignore

  # Aggregate job that requires ALL matrix jobs to pass
  test-complete:
    runs-on: ubuntu-latest
    needs: test
    if: always()
    steps:
      - name: Check matrix results
        run: |
          if [ "${{ needs.test.result }}" = "success" ]; then
            echo "All matrix jobs passed!"
          elif [ "${{ needs.test.result }}" = "failure" ]; then
            echo "Some matrix jobs failed!"
            exit 1
          else
            echo "Matrix result: ${{ needs.test.result }}"
          fi
```

---

## Hands-on

1. Create a 2D matrix workflow that tests across Node.js 18 and 20 on both `ubuntu-latest` and `macos-latest`:

    ??? success "Solution"
        ```bash
        cat > .github/workflows/matrix-2d.yml << 'EOF'
        name: 2D Matrix
        on: [push]
        jobs:
          test:
            runs-on: ${{ matrix.os }}
            strategy:
              matrix:
                os: [ubuntu-latest, macos-latest]
                node: ["18", "20"]
            steps:
              - uses: actions/setup-node@v4
                with:
                  node-version: ${{ matrix.node }}
              - run: node --version
        EOF
        ```

2. Add an `include` entry to the matrix that adds an extra combination — `ubuntu-latest` with Node 22 marked as experimental:

    ??? success "Solution"
        ```bash
        cat > .github/workflows/matrix-include.yml << 'EOF'
        name: Matrix with Include
        on: [push]
        jobs:
          test:
            runs-on: ${{ matrix.os }}
            continue-on-error: ${{ matrix.experimental == true }}
            strategy:
              matrix:
                os: [ubuntu-latest, macos-latest]
                node: ["18", "20"]
                include:
                  - os: ubuntu-latest
                    node: "22"
                    experimental: true
            steps:
              - run: echo "OS=${{ matrix.os }} Node=${{ matrix.node }}"
        EOF
        ```

3. Add an `exclude` entry to remove the `macos-latest` + Node 18 combination from the matrix:

    ??? success "Solution"
        ```bash
        cat > .github/workflows/matrix-exclude.yml << 'EOF'
        name: Matrix with Exclude
        on: [push]
        jobs:
          test:
            runs-on: ${{ matrix.os }}
            strategy:
              matrix:
                os: [ubuntu-latest, macos-latest]
                node: ["18", "20"]
                exclude:
                  - os: macos-latest
                    node: "18"
            steps:
              - run: echo "Running ${{ matrix.os }} / Node ${{ matrix.node }}"
        EOF
        ```

4. Set `fail-fast: false` so all matrix jobs complete even when one combination fails:

    ??? success "Solution"
        ```bash
        cat > .github/workflows/matrix-failfast.yml << 'EOF'
        name: Matrix Fail-Fast False
        on: [push]
        jobs:
          test:
            runs-on: ${{ matrix.os }}
            strategy:
              fail-fast: false
              matrix:
                os: [ubuntu-latest, macos-latest]
                node: ["18", "20"]
            steps:
              - run: echo "Testing on ${{ matrix.os }} with Node ${{ matrix.node }}"
        EOF
        ```

5. Build a dynamic matrix: a first job outputs JSON, and a second job consumes it via `fromJSON`:

    ??? success "Solution"
        ```bash
        cat > .github/workflows/dynamic-matrix.yml << 'EOF'
        name: Dynamic Matrix
        on: [push]
        jobs:
          compute:
            runs-on: ubuntu-latest
            outputs:
              matrix: ${{ steps.set.outputs.matrix }}
            steps:
              - id: set
                run: |
                  echo 'matrix={"node":["18","20"],"os":["ubuntu-latest"]}' >> $GITHUB_OUTPUT
          test:
            needs: compute
            runs-on: ${{ matrix.os }}
            strategy:
              matrix: ${{ fromJSON(needs.compute.outputs.matrix) }}
            steps:
              - run: echo "Node ${{ matrix.node }} on ${{ matrix.os }}"
        EOF
        ```

---

## Exercises

### Exercise 1: Simple Node.js Matrix

Create a workflow that tests on Node.js versions 18, 20, and 22:

```yaml
matrix:
  node-version: ["18", "20", "22"]
```

### Exercise 2: Multi-Dimensional Matrix

Create a matrix of 2 operating systems × 3 Python versions = 6 jobs.

### Exercise 3: Use include to Add Metadata

Add extra variables to specific combinations using `include`:

```yaml
include:
  - os: ubuntu-latest
    coverage: true # run coverage only on ubuntu
```

Then use it: `if: matrix.coverage == true`

### Exercise 4: Exclude a Problem Combination

Add an `exclude` entry that removes a known-broken combination from your matrix.

### Exercise 5: Dynamic Matrix

Create a two-job workflow where the first job builds the matrix JSON and the second uses `fromJSON` to consume it.

---

## Summary

- The matrix strategy eliminates job duplication by defining a set of variable values; GitHub Actions runs one job per combination, all in parallel by default
- Multiple matrix keys create a Cartesian product - `m` values × `n` values = `m × n` jobs; use `max-parallel` to limit concurrent executions
- The `include` directive adds entirely new combinations or augments existing ones with extra variables accessible via `${{ matrix.extra-key }}`
- The `exclude` directive removes specific combinations from the matrix, useful for skipping known-broken or unsupported OS/version pairs
- `fail-fast: false` instructs GitHub Actions to run all matrix jobs to completion even if one fails, providing the full compatibility picture
- Mark experimental combinations with a custom boolean variable and use `continue-on-error: ${{ matrix.experimental == true }}` so failures on those combinations don't block the workflow
- Dynamic matrices are generated at runtime by outputting a JSON string from one job and consuming it with `fromJSON(needs.job.outputs.matrix)` in the next job's `strategy.matrix` field
