#!/bin/bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

section "Lab 022 - GitHub Packages Demo"

# ─────────────────────────────────────────────────────────────
# 1. Create a sample Dockerfile
# ─────────────────────────────────────────────────────────────
section "1. Creating sample Dockerfile"

cat >/tmp/lab022-Dockerfile <<'DOCKER'
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY src/ ./src/

FROM node:20-alpine AS runtime

ARG APP_VERSION=dev
ARG BUILD_DATE
ARG COMMIT_SHA

LABEL org.opencontainers.image.title="lab022-demo"
LABEL org.opencontainers.image.description="GitHub Packages lab demo image"
LABEL org.opencontainers.image.version="${APP_VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${COMMIT_SHA}"
LABEL org.opencontainers.image.source="https://github.com/OWNER/REPO"

WORKDIR /app
COPY --from=builder /app .

EXPOSE 3000
CMD ["node", "src/index.js"]
DOCKER

echo "Created Dockerfile at /tmp/lab022-Dockerfile"
cat /tmp/lab022-Dockerfile

# ─────────────────────────────────────────────────────────────
# 2. Create the GHCR build-push workflow
# ─────────────────────────────────────────────────────────────
section "2. Creating GHCR Build-Push Workflow YAML"

mkdir -p .github/workflows

cat >.github/workflows/lab022-ghcr.yml <<'YAML'
name: "Lab 022 - Build and Push to GHCR"

on:
  push:
    branches: [main]
    tags: ['v*.*.*']
  pull_request:
    branches: [main]

permissions:
  contents: read
  packages: write

jobs:
  build-push:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU (for multi-platform builds)
        uses: docker/setup-qemu-action@v3
        with:
          platforms: linux/amd64,linux/arm64

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata (tags, labels)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=semver,pattern={{major}}
            type=sha,prefix=sha-
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push image
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: |
            APP_VERSION=${{ github.ref_name }}
            BUILD_DATE=${{ github.event.head_commit.timestamp }}
            COMMIT_SHA=${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Print generated tags
        run: |
          echo "Generated tags:"
          echo "${{ steps.meta.outputs.tags }}" | tr ',' '\n' | sed 's/^/  /'
YAML

echo "Created: .github/workflows/lab022-ghcr.yml"

# ─────────────────────────────────────────────────────────────
# 3. Docker login example
# ─────────────────────────────────────────────────────────────
section "3. Docker Login to GHCR"

echo ""
echo "# Login to GHCR from the terminal:"
echo "echo \$GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin"
echo ""
echo "# Or using gh to get a token:"
echo "gh auth token | docker login ghcr.io -u \$(gh api user --jq .login) --password-stdin"

echo ""
echo "# Pull a GHCR image:"
echo "docker pull ghcr.io/OWNER/REPO:latest"

echo ""
echo "# List your GHCR packages:"
echo "gh api user/packages?package_type=container --jq '.[].name'"

# ─────────────────────────────────────────────────────────────
# 4. Show Trivy security scan example
# ─────────────────────────────────────────────────────────────
section "4. Image Vulnerability Scan (Trivy)"

echo ""
echo "# Scan a local or remote image with Trivy:"
echo "docker run --rm aquasec/trivy:latest image ghcr.io/OWNER/REPO:latest"

echo ""
echo "# Scan with severity filter:"
echo "docker run --rm aquasec/trivy:latest image \\"
echo "  --severity CRITICAL,HIGH \\"
echo "  --exit-code 1 \\"
echo "  ghcr.io/OWNER/REPO:latest"

# ─────────────────────────────────────────────────────────────
# 5. Local Docker build demonstration
# ─────────────────────────────────────────────────────────────
section "5. Local Docker Build (if Docker available)"

if command_exists docker; then
  echo "Docker is available - building a test image..."
  # Build a minimal test image from the demo Dockerfile
  cat >/tmp/lab022-test-Dockerfile <<'MINI'
FROM alpine:latest
ARG APP_VERSION=dev
ARG BUILD_DATE=unknown
ARG COMMIT_SHA=unknown
LABEL version="${APP_VERSION}"
RUN echo "GitHub Packages lab022 demo" > /README
CMD ["cat", "/README"]
MINI

  docker build \
    --file /tmp/lab022-test-Dockerfile \
    --build-arg APP_VERSION=1.0.0-demo \
    --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --build-arg COMMIT_SHA=abc123 \
    --tag ghcr.io/demo/lab022-test:local \
    /tmp || true

  echo ""
  echo "Image built: ghcr.io/demo/lab022-test:local"
  docker image inspect ghcr.io/demo/lab022-test:local --format '{{json .Config.Labels}}' 2>/dev/null | jq . || true

  # Cleanup
  docker image rm ghcr.io/demo/lab022-test:local 2>/dev/null || true
else
  echo "(Docker not available - skipping local build)"
fi

# ─────────────────────────────────────────────────────────────
# 6. npm package configuration example
# ─────────────────────────────────────────────────────────────
section "6. npm Package Configuration for GitHub Packages"

echo ""
echo "# package.json for GitHub Packages registry:"
cat <<'JSON'
{
  "name": "@my-org/my-library",
  "version": "1.0.0",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com"
  }
}
JSON

echo ""
echo "# .npmrc for installing from GitHub Packages:"
echo "@my-org:registry=https://npm.pkg.github.com"
echo "//npm.pkg.github.com/:_authToken=\${NODE_AUTH_TOKEN}"

# ─────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────
section "Cleanup"
rm -f .github/workflows/lab022-ghcr.yml
rm -f /tmp/lab022-Dockerfile /tmp/lab022-test-Dockerfile
echo "Demo files removed"

section "Lab 022 Complete"
echo "Key takeaways:"
echo "  - GHCR images live at ghcr.io/<owner>/<repo>:<tag>"
echo "  - GITHUB_TOKEN with packages:write is sufficient - no external secrets"
echo "  - docker/metadata-action generates semver + SHA tags automatically"
echo "  - docker/setup-qemu-action + buildx enable multi-platform builds"
echo "  - cache-from/cache-to: type=gha speeds up repeated builds significantly"
