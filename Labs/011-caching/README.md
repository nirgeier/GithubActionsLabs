# Lab 011 - Caching

## Introduction

- Dependency installation is often the most time-consuming part of a CI workflow.
- GitHub Actions provides a built-in caching mechanism that saves and restores directories between runs, dramatically reducing workflow durations when dependencies haven't changed.
- This lab covers the `actions/cache` action in depth, cache key design strategies, restore keys as fallbacks, and language-specific caching patterns for Node.js, Python, Maven, and Gradle.

---

## How Caching Works

When a workflow runs:

1. GitHub checks whether a cache exists for the provided **key**
2. If found (**cache hit**), the cached directory is restored before the steps run
3. If not found (**cache miss**), the workflow runs normally, and the directory is saved as a new cache entry at the end of the job

Cache entries are stored per repository, branch, and key. Caches are scoped to the branch that created them but can fall back to the default branch.

---

## `actions/cache` - Core Usage

```yaml
- name: Cache dependencies
  uses: actions/cache@v4
  with:
    path: ~/.npm
    key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-node-
```

### Parameters

| Parameter              | Description                                    |
| ---------------------- | ---------------------------------------------- |
| `path`                 | Directory (or list of directories) to cache    |
| `key`                  | The cache key - must match exactly for a hit   |
| `restore-keys`         | Prefix list to use as fallback if `key` misses |
| `save-always`          | Save cache even if the job fails (v4+)         |
| `enableCrossOsArchive` | Allow caching across OS (use carefully)        |

---

## Cache Key Design

The cache key is the most important decision. A good key:

- Changes when dependencies change
- Stays stable when dependencies haven't changed
- Uses `hashFiles()` to incorporate lock file content

### `hashFiles()` Function

`hashFiles()` produces a SHA-256 hash of one or more files. If the files change, the hash changes, triggering a cache miss and fresh install.

```yaml
# Hash a single lock file
key: ${{ runner.os }}-npm-${{ hashFiles('package-lock.json') }}

# Hash multiple lock files (monorepo)
key: ${{ runner.os }}-npm-${{ hashFiles('**/package-lock.json') }}

# Hash multiple files (e.g., requirements + setup.cfg)
key: ${{ runner.os }}-pip-${{ hashFiles('requirements.txt', 'setup.cfg') }}
```

### Including OS in the Key

Always include `runner.os` in cache keys so caches are not shared across incompatible operating systems:

```yaml
key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
```

### Including Node/Python Version

If you test multiple versions, include the version in the key:

```yaml
key: ${{ runner.os }}-node-${{ matrix.node-version }}-${{ hashFiles('**/package-lock.json') }}
```

---

## Restore Keys - Fallback Strategy

`restore-keys` is a list of prefix-based fallbacks used when the primary key misses. GitHub uses the most recent matching entry.

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.npm
    key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-node-
      ${{ runner.os }}-
```

**Matching order:**

1. Try exact key match → use if found
2. Try `${{ runner.os }}-node-` prefix → use most recent match
3. Try `${{ runner.os }}-` prefix → use most recent match
4. Miss - start fresh

This means even if the lock file changed, you still restore a warm cache and only install the delta, which is much faster than a cold install.

---

## Cache Hit vs Cache Miss

You can inspect cache hit status using the action's output:

```yaml
- name: Cache node_modules
  id: node-cache
  uses: actions/cache@v4
  with:
    path: node_modules
    key: ${{ runner.os }}-node-${{ hashFiles('package-lock.json') }}

- name: Install dependencies (only on cache miss)
  if: steps.node-cache.outputs.cache-hit != 'true'
  run: npm ci

- name: Report cache status
  run: |
    if [ "${{ steps.node-cache.outputs.cache-hit }}" == "true" ]; then
      echo "Cache HIT - dependencies restored from cache"
    else
      echo "Cache MISS - dependencies installed fresh"
    fi
```

---

## Node.js Caching

### Method 1: `actions/cache` directly

```yaml
name: Node.js with Cache

on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Cache npm dependencies
        uses: actions/cache@v4
        with:
          path: ~/.npm
          key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-node-

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "20"

      - name: Install dependencies
        run: npm ci

      - name: Build
        run: npm run build
```

### Method 2: Built-in caching via `setup-node`

```yaml
name: Node.js with setup-node Cache

on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js with cache
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm" # Automatically caches ~/.npm
          # cache: 'yarn'        # Or yarn cache
          # cache: 'pnpm'        # Or pnpm store

      - name: Install dependencies
        run: npm ci

      - name: Test
        run: npm test
```

### Caching node_modules vs npm cache

```yaml
# Option A: Cache the npm global cache (~/.npm)
# Pros: works across projects, clean install each time
# Cons: npm ci still recreates node_modules from cache

- uses: actions/cache@v4
  with:
    path: ~/.npm
    key: ${{ runner.os }}-npm-cache-${{ hashFiles('package-lock.json') }}

# Option B: Cache node_modules directly
# Pros: fastest possible (skip install entirely on hit)
# Cons: platform-specific binaries may break

- uses: actions/cache@v4
  with:
    path: node_modules
    key: ${{ runner.os }}-node-modules-${{ hashFiles('package-lock.json') }}
```

---

## Python Caching

### Method 1: `actions/cache` directly

```yaml
name: Python with Cache

on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Cache pip packages
        uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: ${{ runner.os }}-pip-${{ hashFiles('requirements.txt', 'requirements-dev.txt') }}
          restore-keys: |
            ${{ runner.os }}-pip-
            ${{ runner.os }}-

      - name: Install dependencies
        run: pip install -r requirements.txt -r requirements-dev.txt

      - name: Run tests
        run: pytest
```

### Method 2: Built-in caching via `setup-python`

```yaml
name: Python with setup-python Cache

on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python with cache
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: "pip" # Automatically handles pip cache
          cache-dependency-path: | # Override which files to hash
            requirements.txt
            requirements-dev.txt

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Test
        run: pytest
```

### Virtual Environment Caching

```yaml
- name: Cache virtualenv
  uses: actions/cache@v4
  with:
    path: .venv
    key: ${{ runner.os }}-venv-${{ hashFiles('requirements*.txt') }}

- name: Create and populate virtualenv
  run: |
    python -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt
```

---

## Maven Caching

```yaml
name: Java Maven with Cache

on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          java-version: "21"
          distribution: "temurin"
          cache: "maven" # Built-in Maven caching in setup-java

      - name: Build with Maven
        run: mvn --batch-mode clean verify

      # Alternative: manual cache
      - name: Cache Maven repository
        uses: actions/cache@v4
        with:
          path: ~/.m2/repository
          key: ${{ runner.os }}-maven-${{ hashFiles('**/pom.xml') }}
          restore-keys: |
            ${{ runner.os }}-maven-
```

---

## Gradle Caching

```yaml
name: Java Gradle with Cache

on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Java with Gradle cache
        uses: actions/setup-java@v4
        with:
          java-version: "21"
          distribution: "temurin"
          cache: "gradle" # Built-in Gradle caching

      - name: Build with Gradle
        run: ./gradlew build

      # Alternative: manual cache
      - name: Cache Gradle packages
        uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: ${{ runner.os }}-gradle-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
          restore-keys: |
            ${{ runner.os }}-gradle-
```

---

## Cache Size Limits and Eviction

- Maximum cache size per entry: **10 GB**
- Total cache storage per repository: **10 GB**
- When the total exceeds 10 GB, the **least recently used** caches are evicted
- Caches that have not been accessed for **7 days** are deleted automatically
- Branch-scoped caches fall back to the **default branch** cache on miss

### Cache Scope Rules

```
Branch A push  → Can use: Branch A caches, then default branch caches
PR from Fork   → Can read: base branch caches (cannot write)
Default branch → Can use: any branch's caches (is the global fallback)
```

---

## Advanced: Saving Cache on Failure

By default, cache is only saved if the job succeeds. Use `save-always` to save even on failure:

```yaml
- uses: actions/cache@v4
  with:
    path: node_modules
    key: ${{ runner.os }}-node-${{ hashFiles('package-lock.json') }}
    save-always: true
```

---

## Complete Example: Monorepo Multi-Language Cache

```yaml
name: Monorepo Build

on: [push]

jobs:
  frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm"
          cache-dependency-path: frontend/package-lock.json
      - run: cd frontend && npm ci && npm run build

  backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: "pip"
          cache-dependency-path: backend/requirements.txt
      - run: cd backend && pip install -r requirements.txt && pytest

  java-service:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: "21"
          distribution: "temurin"
          cache: "maven"
      - run: cd java-service && mvn --batch-mode verify
```

---

## Hands-on

1. Write a workflow step that caches `~/.npm` using `hashFiles('**/package-lock.json')` as the key and `${{ runner.os }}-node-` as a restore-key fallback:

   ??? success "Solution"
   `bash
    cat > .github/workflows/cache-demo.yml << 'EOF'
    name: Cache Demo
    on: push
    jobs:
      build:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - name: Cache npm
            id: npm-cache
            uses: actions/cache@v4
            with:
              path: ~/.npm
              key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
              restore-keys: |
                ${{ runner.os }}-node-
          - run: npm ci
    EOF
    `

2. Use `actions/setup-node` with the built-in `cache: npm` option instead of a manual `actions/cache` step:

   ??? success "Solution"
   `bash
    cat > .github/workflows/setup-node-cache.yml << 'EOF'
    name: Setup Node Cache
    on: push
    jobs:
      build:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: actions/setup-node@v4
            with:
              node-version: '20'
              cache: 'npm'
          - run: npm ci && npm test
    EOF
    `

3. Add a step that checks `steps.npm-cache.outputs.cache-hit` and skips `npm ci` on an exact hit:

   ??? success "Solution"
   `bash
    cat > .github/workflows/conditional-install.yml << 'EOF'
    name: Conditional Install
    on: push
    jobs:
      build:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - name: Cache npm
            id: npm-cache
            uses: actions/cache@v4
            with:
              path: ~/.npm
              key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
          - name: Install deps (cache miss only)
            if: steps.npm-cache.outputs.cache-hit != 'true'
            run: npm ci
    EOF
    `

4. Force a cache miss by changing the cache key, then verify a fresh install happens using `gh run view --log`:

   ??? success "Solution"
   `bash
    # Temporarily override the key with a timestamp to bust the cache
    # In your workflow, change the key to:
    # key: ${{ runner.os }}-node-bust-${{ github.run_id }}
    # Then trigger a run and inspect the log:
    gh workflow run cache-demo.yml
    RUN_ID=$(gh run list --limit 1 --json databaseId -q '.[0].databaseId')
    gh run watch "$RUN_ID"
    gh run view "$RUN_ID" --log | grep -i 'cache'
    `

5. List all caches for the repository and their sizes using `gh api`:

   ??? success "Solution"
   `bash
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    gh api repos/$REPO/actions/caches \
      | jq '.actions_caches[] | {key, size_in_bytes, last_accessed_at}'
    `

## Exercises

### Exercise 1 - Measure Cache Impact

Create a workflow with and without cache for a Node.js project. Compare run times.

### Exercise 2 - Cache Key Invalidation

1. Cache `node_modules` with a key based on `package-lock.json`
2. Add a new dependency
3. Observe the cache miss and verify the new dependency is installed

### Exercise 3 - Restore Key Fallback

Design a cache key with three restore-key levels. Manually delete the primary cache entry and verify the fallback is used.

### Exercise 4 - Multi-Language Monorepo

Create a workflow caching Node.js, Python, and Java dependencies in the same run.

### Exercise 5 - Conditional Install

Use `cache-hit` output to skip `npm ci` on an exact cache hit, saving even more time.

---

## Summary

- `actions/cache@v4` saves and restores directories between workflow runs, avoiding redundant dependency installation
- Cache keys should always include `runner.os` and `hashFiles()` of the relevant lock file to ensure correctness
- `restore-keys` provide a fallback hierarchy so workflows can warm-start from a partial cache even after lock file changes
- `setup-node`, `setup-python`, and `setup-java` all offer a built-in `cache:` parameter that wraps `actions/cache` automatically
- A cache hit means the cached directory is fully restored; use the `cache-hit` output to skip installation steps entirely
- GitHub evicts least-recently-used caches when the 10 GB per-repository limit is exceeded; design keys to maximize reuse
- Branch caches automatically fall back to the default branch cache, ensuring PRs benefit from the main branch's warm cache
