# Lab 004 - Runners

## Introduction

- A **runner** is the server (virtual machine or container) that executes your workflow jobs.
- GitHub provides hosted runners with pre-installed software, or you can bring your own **self-hosted runner** for custom requirements.
- Choosing the right runner type affects cost, performance, available software, and security posture.
- This lab explores GitHub-hosted runner types, the `runs-on` syntax, pre-installed software, and an overview of self-hosted runners.

---

## 1. GitHub-Hosted Runners

GitHub maintains a fleet of runners that are provisioned fresh for each job and torn down after completion. You pay per minute (free for public repos, limited free minutes for private repos).

### Available runner types

| Label            | OS                  | Architecture | vCPUs | RAM   | Storage   |
| ---------------- | ------------------- | ------------ | ----- | ----- | --------- |
| `ubuntu-latest`  | Ubuntu 22.04        | x64          | 4     | 16 GB | 14 GB SSD |
| `ubuntu-24.04`   | Ubuntu 24.04        | x64          | 4     | 16 GB | 14 GB SSD |
| `ubuntu-22.04`   | Ubuntu 22.04        | x64          | 4     | 16 GB | 14 GB SSD |
| `ubuntu-20.04`   | Ubuntu 20.04        | x64          | 4     | 16 GB | 14 GB SSD |
| `windows-latest` | Windows Server 2022 | x64          | 4     | 16 GB | 14 GB SSD |
| `windows-2022`   | Windows Server 2022 | x64          | 4     | 16 GB | 14 GB SSD |
| `windows-2019`   | Windows Server 2019 | x64          | 4     | 16 GB | 14 GB SSD |
| `macos-latest`   | macOS 14 (Sonoma)   | arm64        | 3     | 7 GB  | 14 GB SSD |
| `macos-14`       | macOS 14 (Sonoma)   | arm64        | 3     | 7 GB  | 14 GB SSD |
| `macos-13`       | macOS 13 (Ventura)  | x64          | 4     | 14 GB | 14 GB SSD |

### Larger hosted runners (paid)

GitHub also offers larger runners for organizations:

| Label                    | vCPUs | RAM    |
| ------------------------ | ----- | ------ |
| `ubuntu-latest-4-cores`  | 4     | 16 GB  |
| `ubuntu-latest-8-cores`  | 8     | 32 GB  |
| `ubuntu-latest-16-cores` | 16    | 64 GB  |
| `ubuntu-latest-32-cores` | 32    | 128 GB |

---

## 2. The `runs-on` Key

### Single label

```yaml
jobs:
  linux-job:
    runs-on: ubuntu-latest
    steps:
      - run: echo "Running on Ubuntu"

  windows-job:
    runs-on: windows-latest
    steps:
      - run: Write-Host "Running on Windows"
        shell: pwsh

  macos-job:
    runs-on: macos-latest
    steps:
      - run: echo "Running on macOS"
```

### Label array (runner must match ALL labels)

```yaml
jobs:
  labeled-job:
    runs-on: [self-hosted, linux, x64, production]
    steps:
      - run: echo "Running on a self-hosted Linux x64 production runner"
```

### Using a variable for the runner

```yaml
jobs:
  dynamic:
    runs-on: ${{ vars.RUNNER_LABEL || 'ubuntu-latest' }}
    steps:
      - run: echo "Runner: ${{ runner.os }}"
```

---

## 3. Pre-installed Software on Ubuntu Runners

GitHub-hosted Ubuntu runners come with hundreds of tools pre-installed. Here are the key ones:

### Languages and runtimes

```yaml
steps:
  - name: Check pre-installed languages
    run: |
      echo "=== Languages ==="
      node --version        # Node.js (multiple versions via nvm)
      python3 --version     # Python 3
      ruby --version        # Ruby
      java -version 2>&1    # Java (multiple via SDKMAN)
      go version            # Go
      dotnet --version      # .NET SDK
      php --version         # PHP

      echo "=== Build Tools ==="
      make --version
      cmake --version
      gradle --version || true
      mvn --version || true

      echo "=== Containers ==="
      docker --version
      docker-compose --version || true

      echo "=== Cloud CLIs ==="
      aws --version || true
      az --version || true
      gcloud --version || true
```

### Setting up specific versions

```yaml
steps:
  - uses: actions/setup-node@v4
    with:
      node-version: "20"

  - uses: actions/setup-python@v5
    with:
      python-version: "3.12"

  - uses: actions/setup-go@v5
    with:
      go-version: "1.22"

  - uses: actions/setup-java@v4
    with:
      java-version: "21"
      distribution: "temurin"
```

---

## 4. Runner Context

The `runner` context provides information about the runner executing the job:

```yaml
steps:
  - name: Runner information
    run: |
      echo "OS:          ${{ runner.os }}"
      echo "Arch:        ${{ runner.arch }}"
      echo "Name:        ${{ runner.name }}"
      echo "Temp dir:    ${{ runner.temp }}"
      echo "Tool cache:  ${{ runner.tool_cache }}"
```

### Environment variables set by the runner

```bash
# Available in every step on every runner type
RUNNER_OS=Linux           # Linux, Windows, macOS
RUNNER_ARCH=X64           # X64, ARM, ARM64
RUNNER_TEMP=/tmp          # temporary directory
RUNNER_TOOL_CACHE=/opt/hostedtoolcache  # cached tool installations
RUNNER_WORKSPACE=/home/runner/work
GITHUB_WORKSPACE=/home/runner/work/repo/repo
```

---

## 5. Cross-Platform Workflows

Use matrix strategy to test across multiple operating systems:

```yaml
name: Cross-Platform CI

on: [push, pull_request]

jobs:
  test:
    name: Test on ${{ matrix.os }}
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]

    steps:
      - uses: actions/checkout@v4

      - name: Platform-specific info
        run: |
          echo "OS: ${{ runner.os }}"
          echo "Arch: ${{ runner.arch }}"

      - name: List directory (cross-platform)
        shell: bash
        run: ls -la

      - name: Platform-specific step (Linux only)
        if: runner.os == 'Linux'
        run: |
          echo "Linux-specific commands"
          cat /etc/os-release | head -5

      - name: Platform-specific step (Windows only)
        if: runner.os == 'Windows'
        shell: pwsh
        run: |
          Write-Host "Windows-specific commands"
          Get-ComputerInfo | Select-Object WindowsProductName

      - name: Platform-specific step (macOS only)
        if: runner.os == 'macOS'
        run: |
          echo "macOS-specific commands"
          sw_vers
```

---

## 6. Shell Selection

Different runners support different shells:

```yaml
steps:
  # Default shell: bash on Linux/macOS, pwsh on Windows
  - run: echo "Default shell"

  # Explicit bash (Linux/macOS/Windows with Git Bash)
  - shell: bash
    run: echo "Explicitly bash"

  # PowerShell (all platforms with pwsh installed)
  - shell: pwsh
    run: Write-Host "PowerShell"

  # Windows Command Prompt (Windows only)
  - shell: cmd
    run: echo Windows CMD

  # Python inline
  - shell: python
    run: print("Hello from Python inline")

  # Custom shell
  - shell: /usr/bin/fish {0}
    run: echo "Hello from fish shell"
```

---

## 7. Self-Hosted Runners

Self-hosted runners are machines you manage and register with GitHub. They run within your own infrastructure.

### When to use self-hosted runners

- Need access to internal resources (databases, private registries, VPNs)
- Require custom hardware (GPU, specific CPU architecture, specialized peripherals)
- Need Windows-specific software not available on hosted runners
- Want faster performance (larger machines, faster disks, local caches)
- Cost optimization for high-volume workloads
- Compliance requirements (data must not leave your infrastructure)

### Registering a self-hosted runner

```bash
# 1. Go to: Settings > Actions > Runners > New self-hosted runner
# 2. Download the runner package
mkdir actions-runner && cd actions-runner
curl -o actions-runner-linux-x64.tar.gz \
  -L https://github.com/actions/runner/releases/download/v2.314.1/actions-runner-linux-x64-2.314.1.tar.gz
tar xzf ./actions-runner-linux-x64.tar.gz

# 3. Configure
./config.sh --url https://github.com/OWNER/REPO --token REGISTRATION_TOKEN

# 4. Run as a service
sudo ./svc.sh install
sudo ./svc.sh start
```

### Using a self-hosted runner in a workflow

```yaml
jobs:
  build:
    runs-on: self-hosted # use any available self-hosted runner

  build-gpu:
    runs-on: [self-hosted, gpu, linux] # require specific labels

  build-internal:
    runs-on: [self-hosted, production, x64]
```

---

## 8. Runner Groups (Organizations)

Organizations can group runners and control which repositories can use them:

```yaml
jobs:
  prod-deploy:
    runs-on:
      group: production-runners # runner group name
      labels: [linux, x64] # additional label filters
```

---

## 9. Caching Dependencies

Improve runner performance by caching dependencies:

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: actions/setup-node@v4
    with:
      node-version: "20"
      cache: "npm" # built-in caching in setup actions

  - name: Manual cache example
    uses: actions/cache@v4
    with:
      path: ~/.cache/pip
      key: ${{ runner.os }}-pip-${{ hashFiles('requirements.txt') }}
      restore-keys: |
        ${{ runner.os }}-pip-

  - run: pip install -r requirements.txt
```

---

## Hands-on

1. List the runner labels available for your repository using the `gh` CLI:

   ??? success "Solution"
   `bash
    gh api repos/{owner}/{repo}/actions/runners --jq '.runners[].labels[].name' 2>/dev/null \
      || echo "No self-hosted runners registered; GitHub-hosted labels: ubuntu-latest, windows-latest, macos-latest"
    `

2. Create a matrix workflow that runs the same step on both `ubuntu-latest` and `macos-latest`:

   ??? success "Solution"
   `bash
    cat > .github/workflows/multi-os.yml << 'EOF'
    name: Multi-OS Matrix
    on: [push]
    jobs:
      test:
        runs-on: ${{ matrix.os }}
        strategy:
          matrix:
            os: [ubuntu-latest, macos-latest]
        steps:
          - run: echo "Running on ${{ runner.os }}"
    EOF
    `

3. Check which versions of `node` and `python3` are pre-installed on the runner:

   ??? success "Solution"
   `bash
    cat > .github/workflows/check-tools.yml << 'EOF'
    name: Check Pre-installed Tools
    on: [workflow_dispatch]
    jobs:
      check:
        runs-on: ubuntu-latest
        steps:
          - run: |
              which node && node --version
              which python3 && python3 --version
    EOF
    # Run it locally with act:
    act workflow_dispatch --workflows .github/workflows/check-tools.yml
    `

4. Add a step that only executes when the runner label is `ubuntu-latest` using a conditional:

   ??? success "Solution"
   `bash
    cat > .github/workflows/label-check.yml << 'EOF'
    name: Runner Label Check
    on: [push]
    jobs:
      check:
        runs-on: ubuntu-latest
        steps:
          - name: Linux-only step
            if: runner.os == 'Linux'
            run: echo "This runner is Linux: ${{ runner.name }}"
    EOF
    `

5. Compare runner capabilities by printing `runner.os`, `runner.arch`, and `RUNNER_TOOL_CACHE` across two OS runners:

   ??? success "Solution"
   `bash
    cat > .github/workflows/runner-compare.yml << 'EOF'
    name: Runner Capabilities
    on: [workflow_dispatch]
    jobs:
      info:
        runs-on: ${{ matrix.os }}
        strategy:
          matrix:
            os: [ubuntu-latest, macos-latest]
        steps:
          - run: |
              echo "OS:         ${{ runner.os }}"
              echo "Arch:       ${{ runner.arch }}"
              echo "Tool cache: $RUNNER_TOOL_CACHE"
    EOF
    `

## Exercises

### Exercise 1: Multi-OS Workflow

Create a workflow that runs the same steps on Ubuntu, Windows, and macOS:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
runs-on: ${{ matrix.os }}
```

### Exercise 2: Check Runner Environment

Create a workflow that prints `runner.os`, `runner.arch`, `runner.name`, and all `RUNNER_*` environment variables.

### Exercise 3: Platform-Specific Commands

Create a workflow with steps that use `if: runner.os == 'Linux'` etc. to run OS-specific commands.

### Exercise 4: Add Dependency Caching

Add `actions/cache@v4` to a workflow to cache `node_modules` or `~/.cache/pip`.

---

## Summary

- GitHub-hosted runners (`ubuntu-latest`, `windows-latest`, `macos-latest`) are provisioned fresh for each job and come with hundreds of pre-installed tools
- The `runs-on:` key accepts a single label string or an array of labels; when an array is used, the runner must match all labels simultaneously
- The `runner` context provides `runner.os`, `runner.arch`, `runner.name`, `runner.temp`, and `runner.tool_cache` which are useful for cross-platform workflows
- Use `if: runner.os == 'Linux'` conditions to run OS-specific steps within a matrix job instead of duplicating the entire workflow
- Self-hosted runners are required when jobs need access to internal resources, custom hardware, or must not send data outside your infrastructure
- Use `actions/setup-node`, `actions/setup-python`, etc. to install specific language versions regardless of what is pre-installed on the runner
- Caching with `actions/cache@v4` or the built-in `cache:` option in setup actions dramatically reduces job runtime by avoiding redundant dependency downloads
