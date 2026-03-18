#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 028 - Self-Hosted Runners Demo"

# ─────────────────────────────────────────────────────────────
# 1. Show runner registration commands
# ─────────────────────────────────────────────────────────────
section "1. Runner Registration via gh api"

echo ""
echo "# Get a registration token for a repository:"
echo "REGISTRATION_TOKEN=\$(gh api \\"
echo "  --method POST \\"
echo "  -H \"Accept: application/vnd.github+json\" \\"
echo "  /repos/OWNER/REPO/actions/runners/registration-token \\"
echo "  --jq '.token')"

echo ""
echo "# Get a registration token for an organization:"
echo "REGISTRATION_TOKEN=\$(gh api \\"
echo "  --method POST \\"
echo "  /orgs/MY_ORG/actions/runners/registration-token \\"
echo "  --jq '.token')"

echo ""
echo "# Full registration sequence:"
cat <<'SCRIPT'
mkdir -p ~/actions-runner && cd ~/actions-runner

# Download runner (check https://github.com/actions/runner/releases for latest)
RUNNER_VERSION=2.317.0
curl -o runner.tar.gz -L \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
tar xzf runner.tar.gz

# Register
./config.sh \
  --url https://github.com/OWNER/REPO \
  --token "$REGISTRATION_TOKEN" \
  --name "my-runner-01" \
  --labels "self-hosted,linux,x64,production" \
  --work _work \
  --unattended

# Install and start as a service
sudo ./svc.sh install
sudo ./svc.sh start
SCRIPT

# ─────────────────────────────────────────────────────────────
# 2. Create workflow targeting self-hosted runner
# ─────────────────────────────────────────────────────────────
section "2. Creating Workflow Targeting Self-Hosted Runner"

mkdir -p .github/workflows

cat >.github/workflows/lab028-self-hosted.yml <<'YAML'
name: "Lab 028 - Self-Hosted Runner Demo"

on:
  workflow_dispatch:
    inputs:
      runner_label:
        description: "Runner label to target"
        type: choice
        default: self-hosted
        options:
          - self-hosted
          - self-hosted,linux
          - self-hosted,linux,gpu
          - self-hosted,windows

jobs:
  # ── Basic self-hosted job ─────────────────────────────────
  basic-self-hosted:
    name: Basic Self-Hosted Job
    runs-on: ${{ fromJson(format('["{0}"]', inputs.runner_label)) }}

    steps:
      - name: System information
        run: |
          echo "=== Runner Info ==="
          echo "Hostname:  $(hostname)"
          echo "OS:        $(uname -a)"
          echo "User:      $(whoami)"
          echo "Disk:      $(df -h / | awk 'NR==2 {print $4}') available"
          echo "RAM:       $(free -h | awk '/Mem:/ {print $7}') available"
          echo "CPUs:      $(nproc)"

      - name: Checkout
        uses: actions/checkout@v4

      - name: Access private network resource
        run: |
          echo "This runner has access to internal resources:"
          # In a real scenario:
          # curl http://internal-api.company.local/health
          # kubectl get pods --namespace production
          echo "(Simulated private network access)"

  # ── GPU job (specialized hardware) ───────────────────────
  gpu-job:
    name: GPU Accelerated Job
    runs-on: [self-hosted, linux, gpu]
    if: false   # disabled in demo - would need actual GPU runner

    steps:
      - name: Verify GPU availability
        run: nvidia-smi

      - name: Run ML training
        run: python train.py --epochs 100 --device cuda

  # ── Ephemeral runner job ──────────────────────────────────
  ephemeral-demo:
    name: Ephemeral Runner Pattern
    runs-on: [self-hosted, linux, ephemeral]
    if: false   # disabled in demo - would need ephemeral runner

    steps:
      - name: Verify clean state
        run: |
          echo "This runner was freshly provisioned for this job"
          ls ~/    # should be empty (fresh ephemeral runner)
YAML

echo "Created: .github/workflows/lab028-self-hosted.yml"

# ─────────────────────────────────────────────────────────────
# 3. Create Dockerfile for Docker-based runner
# ─────────────────────────────────────────────────────────────
section "3. Docker-Based Runner Files"

cat >/tmp/lab028-runner.Dockerfile <<'DOCKER'
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install runner dependencies
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    git \
    sudo \
    libicu70 \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root runner user
RUN useradd -m -s /bin/bash runner \
    && echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

WORKDIR /home/runner/actions-runner
USER runner

# Download and extract runner agent
ARG RUNNER_VERSION=2.317.0
RUN curl -o runner.tar.gz -L \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    && tar xzf runner.tar.gz \
    && rm runner.tar.gz

# Copy entrypoint script
COPY --chown=runner:runner entrypoint.sh /home/runner/entrypoint.sh
RUN chmod +x /home/runner/entrypoint.sh

ENTRYPOINT ["/home/runner/entrypoint.sh"]
DOCKER

cat >/tmp/lab028-entrypoint.sh <<'BASH'
#!/bin/bash
set -euo pipefail

# Required environment variables:
# GITHUB_OWNER - org or user name
# GITHUB_REPO  - repository name
# RUNNER_TOKEN - registration token from gh api

./config.sh \
  --url "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}" \
  --token "${RUNNER_TOKEN}" \
  --name "${RUNNER_NAME:-docker-runner-$(hostname)}" \
  --labels "${RUNNER_LABELS:-self-hosted,linux,docker}" \
  --ephemeral \
  --unattended \
  --disableupdate

# Run the runner (exits after one job when --ephemeral)
./run.sh

# Self-deregister (ephemeral mode handles this automatically)
echo "Job complete. Runner deregistered."
BASH

echo "Docker runner files created:"
echo "  /tmp/lab028-runner.Dockerfile"
echo "  /tmp/lab028-entrypoint.sh"
echo ""
echo "Build the runner image:"
echo "  docker build \\"
echo "    --file /tmp/lab028-runner.Dockerfile \\"
echo "    --build-arg RUNNER_VERSION=2.317.0 \\"
echo "    --tag my-runner:latest ."
echo ""
echo "Run an ephemeral instance:"
echo "  TOKEN=\$(gh api --method POST /repos/OWNER/REPO/actions/runners/registration-token --jq '.token')"
echo "  docker run -d \\"
echo "    -e GITHUB_OWNER=my-org \\"
echo "    -e GITHUB_REPO=my-repo \\"
echo "    -e RUNNER_TOKEN=\"\$TOKEN\" \\"
echo "    my-runner:latest"

# ─────────────────────────────────────────────────────────────
# 4. Show runner management commands
# ─────────────────────────────────────────────────────────────
section "4. Runner Management via gh api"

echo ""
echo "# List all runners for a repository:"
echo "gh api /repos/OWNER/REPO/actions/runners \\"
echo "  --jq '.runners[] | {id, name, status, os, labels: [.labels[].name]}'"

echo ""
echo "# List runners for an organization:"
echo "gh api /orgs/MY_ORG/actions/runners \\"
echo "  --jq '.runners[] | {id, name, status, busy}'"

echo ""
echo "# Get a specific runner:"
echo "gh api /repos/OWNER/REPO/actions/runners/RUNNER_ID | jq ."

echo ""
echo "# Update runner labels:"
echo "gh api \\"
echo "  --method PUT \\"
echo "  /repos/OWNER/REPO/actions/runners/RUNNER_ID/labels \\"
echo "  -f 'labels[]=self-hosted' \\"
echo "  -f 'labels[]=linux' \\"
echo "  -f 'labels[]=production'"

echo ""
echo "# Remove/deregister a runner:"
echo "gh api \\"
echo "  --method DELETE \\"
echo "  /repos/OWNER/REPO/actions/runners/RUNNER_ID"

echo ""
echo "# Get a removal token:"
echo "gh api \\"
echo "  --method POST \\"
echo "  /repos/OWNER/REPO/actions/runners/remove-token \\"
echo "  --jq '.token'"

# ─────────────────────────────────────────────────────────────
# 5. Show live runners if gh is available
# ─────────────────────────────────────────────────────────────
section "5. Live Runner Status (if gh configured)"

if command_exists gh && gh auth status >/dev/null 2>&1; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  if [ -n "$REPO" ]; then
    echo "Self-hosted runners for: $REPO"
    gh api "repos/${REPO}/actions/runners" \
      --jq '.runners[] | {id, name, status, busy, labels: [.labels[].name]}' \
      2>/dev/null || echo "(No self-hosted runners registered)"
    echo ""
    echo "Total runner count:"
    gh api "repos/${REPO}/actions/runners" --jq '.total_count' 2>/dev/null || echo "0"
  fi
else
  echo "(gh not authenticated - showing reference only)"
fi

# ─────────────────────────────────────────────────────────────
# 6. Security checklist
# ─────────────────────────────────────────────────────────────
section "6. Self-Hosted Runner Security Checklist"

echo ""
echo "CRITICAL SECURITY RULES:"
echo "  [!] NEVER use self-hosted runners for public repositories"
echo "      Any fork PR can execute arbitrary code on your runner host"
echo ""
echo "BEST PRACTICES:"
echo "  [x] Run runner agent as a low-privilege user (not root)"
echo "  [x] Use --ephemeral flag: one runner = one job = clean state"
echo "  [x] Put runner in a container for additional isolation"
echo "  [x] Apply network policies to restrict runner's outbound access"
echo "  [x] Use runner groups with visibility: selected at org level"
echo "  [x] Rotate registration tokens; remove stale runners"
echo "  [x] Monitor runner activity logs for anomalous behavior"
echo "  [x] Keep runner agent version up to date"

# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────
section "Cleanup"
rm -f .github/workflows/lab028-self-hosted.yml
rm -f /tmp/lab028-runner.Dockerfile /tmp/lab028-entrypoint.sh
echo "Demo files removed"

section "Lab 028 Complete"
echo "Key takeaways:"
echo "  - Runners connect outbound to GitHub via HTTPS - no inbound rules needed"
echo "  - Registration tokens are obtained via POST .../runners/registration-token"
echo "  - --ephemeral flag makes runners deregister after one job (strong isolation)"
echo "  - Docker-based runners provide consistent environments and easy scaling"
echo "  - Actions Runner Controller (ARC) on Kubernetes provides autoscaling"
echo "  - Never use self-hosted runners for public repos - fork PRs can run arbitrary code"
