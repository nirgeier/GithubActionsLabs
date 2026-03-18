# Lab 028 - Self-Hosted Runners

## Introduction

- GitHub provides managed runners (Ubuntu, Windows, macOS) that are sufficient for most CI/CD workloads.
- But some scenarios require **self-hosted runners**: accessing private network resources, using specialized hardware (GPUs, specific CPU architectures), meeting compliance requirements that prohibit code execution on shared infrastructure, or running jobs at a scale where GitHub-hosted runners become cost-prohibitive.
- This lab covers the architecture of self-hosted runners, registration via `gh api` and the runner agent, ephemeral vs persistent runners, Docker-based runners, scaling with Actions Runner Controller (ARC), and the security considerations that make self-hosted runners a meaningful risk if misconfigured.

---

## 1. Self-Hosted Runner Architecture

```
GitHub Server
    │
    │  HTTPS long-poll (runner → GitHub)
    ▼
Runner Agent (runs on your infrastructure)
    │
    ├── Listens for job assignments
    ├── Downloads workflow steps
    ├── Executes steps in isolated working directory
    └── Reports results and logs back to GitHub
```

Key points:

- Runners **initiate** the connection to GitHub (outbound HTTPS only)
- No inbound firewall rules are needed
- Runners download job steps from GitHub, then execute them locally
- Each job runs in a clean working directory (but the runner host itself persists between jobs unless using ephemeral mode)

---

## 2. System Requirements

Minimum requirements for a self-hosted runner:

| Component | Requirement                                                       |
| --------- | ----------------------------------------------------------------- |
| OS        | Linux (x64, ARM64, ARM32), Windows, macOS                         |
| CPU       | 2 cores (4+ recommended)                                          |
| RAM       | 4 GB (8+ recommended)                                             |
| Disk      | 20 GB available                                                   |
| Network   | Outbound HTTPS to `github.com`, `*.actions.githubusercontent.com` |

Required domains to allow through firewalls:

```
github.com
api.github.com
*.actions.githubusercontent.com
results-receiver.actions.githubusercontent.com
objects.githubusercontent.com
codeload.github.com
pkg.actions.githubusercontent.com
```

---

## 3. Registering a Runner Manually

Download and configure the runner agent:

```bash
# Create a directory for the runner
mkdir -p ~/actions-runner && cd ~/actions-runner

# Download the latest runner package (Linux x64)
curl -o actions-runner-linux-x64-2.317.0.tar.gz \
  -L https://github.com/actions/runner/releases/download/v2.317.0/actions-runner-linux-x64-2.317.0.tar.gz

# Extract
tar xzf actions-runner-linux-x64-2.317.0.tar.gz

# Get a registration token via gh api
REGISTRATION_TOKEN=$(gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  /repos/OWNER/REPO/actions/runners/registration-token \
  --jq '.token')

# Configure the runner
./config.sh \
  --url https://github.com/OWNER/REPO \
  --token "$REGISTRATION_TOKEN" \
  --name "my-self-hosted-runner" \
  --labels "self-hosted,linux,x64,gpu" \
  --work _work \
  --unattended

# Run as a service
sudo ./svc.sh install
sudo ./svc.sh start
```

---

## 4. Registering at Organization Level

Organization-level runners can be used by any repository in the org:

```bash
REGISTRATION_TOKEN=$(gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  /orgs/MY_ORG/actions/runners/registration-token \
  --jq '.token')

./config.sh \
  --url https://github.com/MY_ORG \
  --token "$REGISTRATION_TOKEN" \
  --name "org-runner-01" \
  --labels "self-hosted,linux,production" \
  --runnergroup "Production Runners"
```

---

## 5. Targeting Self-Hosted Runners in Workflows

Use the `runs-on:` key with the runner's labels:

```yaml
jobs:
  build:
    runs-on: [self-hosted, linux, x64]

  gpu-training:
    runs-on: [self-hosted, linux, gpu]

  windows-test:
    runs-on: [self-hosted, windows]

  arm-build:
    runs-on: [self-hosted, linux, ARM64]
```

All labels in the list must match a single runner. Use multiple labels to target specific runner capabilities.

---

## 6. Runner Labels and Groups

Labels are set at registration time or updated via the API:

```bash
# List runners for a repository
gh api /repos/OWNER/REPO/actions/runners \
  --jq '.runners[] | {id, name, status, labels: [.labels[].name]}'

# Add/update labels on a runner
gh api \
  --method PUT \
  /repos/OWNER/REPO/actions/runners/RUNNER_ID/labels \
  -f 'labels[]=self-hosted' \
  -f 'labels[]=linux' \
  -f 'labels[]=production' \
  -f 'labels[]=x64'

# Remove a specific label
gh api \
  --method DELETE \
  /repos/OWNER/REPO/actions/runners/RUNNER_ID/labels/staging
```

**Runner groups** (org-level feature) let you control which repositories can access specific runners:

```bash
# Create a runner group
gh api \
  --method POST \
  /orgs/MY_ORG/actions/runner-groups \
  -f name="production-runners" \
  -f visibility="selected" \
  --jq '.id'

# Add a runner to the group
gh api \
  --method PUT \
  /orgs/MY_ORG/actions/runner-groups/GROUP_ID/runners/RUNNER_ID
```

---

## 7. Docker-Based Runners

Running the runner inside Docker provides isolation and makes it easy to create fresh environments per job:

```dockerfile
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    git \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Create runner user
RUN useradd -m runner && echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

WORKDIR /home/runner/actions-runner
USER runner

# Download runner (version pinned for reproducibility)
ARG RUNNER_VERSION=2.317.0
RUN curl -o runner.tar.gz -L \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
    && tar xzf runner.tar.gz \
    && rm runner.tar.gz

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

`entrypoint.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Register runner at startup
./config.sh \
  --url "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}" \
  --token "${RUNNER_TOKEN}" \
  --name "${RUNNER_NAME:-docker-runner}" \
  --labels "${RUNNER_LABELS:-self-hosted,linux,docker}" \
  --ephemeral \
  --unattended

# Run once and exit (ephemeral)
./run.sh
```

Run it:

```bash
docker run -d \
  -e GITHUB_OWNER=my-org \
  -e GITHUB_REPO=my-repo \
  -e RUNNER_TOKEN=$(gh api --method POST /repos/my-org/my-repo/actions/runners/registration-token --jq '.token') \
  my-runner-image:latest
```

---

## 8. Ephemeral Runners Pattern

Ephemeral runners register, run exactly one job, and then deregister. This provides strong isolation guarantees - each job gets a clean environment:

```bash
# Register as ephemeral (auto-deregisters after one job)
./config.sh \
  --url https://github.com/OWNER/REPO \
  --token "$REGISTRATION_TOKEN" \
  --ephemeral \
  --unattended
```

A management script that keeps a pool of ephemeral runners ready:

```bash
#!/bin/bash
# Maintain a pool of 5 ephemeral runners
POOL_SIZE=5
while true; do
  CURRENT=$(gh api /repos/OWNER/REPO/actions/runners --jq '.total_count')
  NEEDED=$(( POOL_SIZE - CURRENT ))
  if [ "$NEEDED" -gt 0 ]; then
    echo "Spawning $NEEDED runner(s)..."
    for i in $(seq 1 $NEEDED); do
      TOKEN=$(gh api --method POST /repos/OWNER/REPO/actions/runners/registration-token --jq '.token')
      docker run -d -e RUNNER_TOKEN="$TOKEN" my-runner-image:latest
    done
  fi
  sleep 30
done
```

---

## 9. Actions Runner Controller (ARC)

ARC is a Kubernetes operator that scales self-hosted runners based on workflow queue depth:

```yaml
# Install ARC via Helm
helm install arc \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --namespace arc-systems \
  --create-namespace

# Deploy a runner scale set
helm install arc-runner-set \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --namespace arc-runners \
  --create-namespace \
  --set githubConfigUrl="https://github.com/MY_ORG/MY_REPO" \
  --set githubConfigSecret.github_token="$GITHUB_PAT" \
  --set minRunners=0 \
  --set maxRunners=10 \
  --set containerMode.type=dind   # Docker-in-Docker for container jobs
```

Target ARC runners in workflows:

```yaml
jobs:
  build:
    runs-on: arc-runner-set # matches the Helm release name
```

---

## 10. Security Considerations

Self-hosted runners carry significant security risks if misconfigured:

### Critical: Never use self-hosted runners with public repositories

A malicious PR from a fork can execute arbitrary code on your runner host. Use GitHub-hosted runners for public repositories.

### Isolation Best Practices

```yaml
# Use containers for isolation in self-hosted runner jobs
jobs:
  build:
    runs-on: [self-hosted, linux]
    container:
      image: node:20-alpine # Job runs inside this container
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm test
```

Other security hardening measures:

- Run the runner agent as a low-privilege user (not root)
- Use ephemeral runners so each job starts clean
- Apply network policies to restrict what the runner can reach
- Rotate registration tokens regularly
- Monitor runner activity for anomalous behavior
- Enable runner groups with `visibility: selected` to limit repo access

---

## Hands-on

1. List all registered self-hosted runners for a repository using `gh api`:

   ??? success "Solution"
   `bash
    gh api repos/OWNER/REPO/actions/runners \
      --jq '.runners[] | {id, name, status, os, labels: [.labels[].name]}'
    `

2. Create a workflow that targets a self-hosted runner with the `runs-on: self-hosted` label:

   ??? success "Solution"
   `bash
    cat > .github/workflows/self-hosted.yml << 'EOF'
    name: Self-Hosted Job
    on: [workflow_dispatch]
    jobs:
      run-on-self-hosted:
        runs-on: self-hosted
        steps:
          - run: echo "Running on $(hostname)"
          - run: uname -a
    EOF
    git add .github/workflows/self-hosted.yml && git commit -m "ci: add self-hosted runner workflow"
    `

3. Check runner labels for a specific runner ID using `gh api`:

   ??? success "Solution"
   `bash
    RUNNER_ID=$(gh api repos/OWNER/REPO/actions/runners --jq '.runners[0].id')
    gh api repos/OWNER/REPO/actions/runners/${RUNNER_ID} \
      --jq '{name, status, labels: [.labels[].name]}'
    `

4. Write a Docker-based ephemeral runner `Dockerfile` and build it locally:

   ??? success "Solution"
   `bash
    cat > Dockerfile.runner << 'EOF'
    FROM ubuntu:22.04
    RUN apt-get update && apt-get install -y curl jq git sudo && rm -rf /var/lib/apt/lists/*
    RUN useradd -m runner && echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    WORKDIR /home/runner/actions-runner
    USER runner
    ARG RUNNER_VERSION=2.317.0
    RUN curl -o runner.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
        && tar xzf runner.tar.gz && rm runner.tar.gz
    EOF
    docker build -f Dockerfile.runner -t my-runner:latest .
    `

5. Create a runner group restricted to selected repositories using `gh api`:

   ??? success "Solution"
   `bash
    gh api orgs/MY_ORG/actions/runner-groups \
      --method POST \
      -f name="private-runners" \
      -f visibility="selected" \
      --jq '{id, name, visibility}'
    `

## Exercises

### Exercise 1 - Register a Runner

Register a self-hosted runner on your local machine or a VM. Target it from a simple workflow that runs `hostname` and `uname -a`. Verify the output shows your machine.

### Exercise 2 - Labels

Add custom labels to your runner. Create a workflow that specifically targets those labels. Verify that a job without the labels doesn't execute on your runner.

### Exercise 3 - Docker Runner

Build the Dockerfile from this lab and run it as a self-hosted runner. Execute a workflow that uses Docker commands inside the runner.

### Exercise 4 - Ephemeral Runner

Modify your registration to use `--ephemeral`. Observe that the runner deregisters after running one job. Write a script that automatically re-registers a new ephemeral runner.

---

## Summary

- Self-hosted runners connect outbound to GitHub via HTTPS - no inbound firewall rules are needed
- Runners are registered with a short-lived token obtained via `gh api --method POST /repos/{owner}/{repo}/actions/runners/registration-token`
- Target runners in workflows using label lists in `runs-on:` - all listed labels must match a single runner
- Ephemeral runners (`--ephemeral` flag) register, run one job, and deregister - eliminating state contamination between jobs
- Docker-based runners provide consistent environments and easy provisioning; pair with `--ephemeral` for maximum isolation
- Actions Runner Controller (ARC) on Kubernetes provides autoscaling runners that scale from zero to N based on the job queue
- Self-hosted runners should never be used for public repositories - any fork PR can execute arbitrary code on the runner host
