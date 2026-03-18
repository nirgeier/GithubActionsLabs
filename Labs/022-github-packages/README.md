# Lab 022 - GitHub Packages

## Introduction

- **GitHub Packages** is a package registry built into GitHub that supports Docker/OCI container images (via the **GitHub Container Registry**, GHCR), npm, Maven, Gradle, RubyGems, and NuGet packages.
- It is tightly integrated with GitHub's permission model, meaning access to packages inherits from repository and organization membership.
- This lab focuses on the most common use case: **building and publishing Docker images to GHCR** using GitHub Actions, along with publishing **npm packages** to GitHub's npm registry.
- You will learn how to authenticate, build multi-platform images, apply semantic version tags, and control package visibility.

---

## Why GitHub Packages / GHCR?

- **Co-location**: Packages live next to their source code and issues - no separate account on Docker Hub
- **Integrated auth**: GitHub tokens (`GITHUB_TOKEN`) work automatically in Actions - no external secrets needed for publishing
- **Granular permissions**: Packages can be linked to repositories and inherit their access control
- **Multi-arch support**: GHCR supports OCI manifests, enabling multi-platform image manifests
- **Free for public repos**: Public packages on GHCR are free to publish and pull

---

## 1. GitHub Container Registry (GHCR) Overview

GHCR images are hosted at `ghcr.io`:

```
ghcr.io/<owner>/<image-name>:<tag>

# Examples:
ghcr.io/my-org/my-app:latest
ghcr.io/my-org/my-app:1.2.3
ghcr.io/my-user/tool:sha-abc1234
```

GHCR supports:

- Docker image format (Docker Manifest V2)
- OCI Image Format Specification
- Multi-platform manifests (via `docker buildx`)
- Image attestations (SBOM, provenance)

---

## 2. Required Permissions

Workflows that push to GHCR need `packages: write` permission. The `GITHUB_TOKEN` is sufficient - no personal access token required:

```yaml
permissions:
  contents: read
  packages: write
```

---

## 3. Minimal Docker Build and Push Workflow

```yaml
name: Build and Push Docker Image

on:
  push:
    branches: [main]
  release:
    types: [published]

permissions:
  contents: read
  packages: write

jobs:
  build-push:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ghcr.io/${{ github.repository }}:latest
```

---

## 4. Semantic Versioning Tags with `docker/metadata-action`

The `docker/metadata-action` automatically generates appropriate tags and labels based on the Git ref, making it easy to apply semver tags from Git tags, branch names, and SHAs:

```yaml
name: Build and Push with Semver Tags

on:
  push:
    branches: [main, develop]
    tags: ["v*.*.*"]
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

      - name: Log in to GHCR
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            # Branch name as tag
            type=ref,event=branch
            # PR number as tag
            type=ref,event=pr
            # Semver from Git tag: v1.2.3 → 1.2.3, 1.2, 1
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=semver,pattern={{major}}
            # Short SHA always
            type=sha,prefix=sha-
            # latest on default branch
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

For a Git tag `v1.2.3`, this produces:

- `ghcr.io/org/repo:1.2.3`
- `ghcr.io/org/repo:1.2`
- `ghcr.io/org/repo:1`
- `ghcr.io/org/repo:sha-abc1234`
- `ghcr.io/org/repo:latest`

---

## 5. Multi-Platform Builds with Docker Buildx

GHCR supports multi-platform OCI manifests. Use `docker/setup-buildx-action` and specify multiple platforms:

```yaml
name: Multi-platform Build

on:
  push:
    tags: ["v*.*.*"]

permissions:
  contents: read
  packages: write

jobs:
  build-multiplatform:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3
        with:
          platforms: linux/amd64,linux/arm64,linux/arm/v7

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha,prefix=sha-

      - name: Build and push multi-platform
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

## 6. Build Arguments and Secrets

Pass build arguments securely during the Docker build:

```yaml
- name: Build and push with build args
  uses: docker/build-push-action@v6
  with:
    context: .
    push: true
    tags: ghcr.io/${{ github.repository }}:latest
    build-args: |
      APP_VERSION=${{ github.ref_name }}
      BUILD_DATE=${{ github.event.head_commit.timestamp }}
      COMMIT_SHA=${{ github.sha }}
    secrets: |
      NPM_TOKEN=${{ secrets.NPM_TOKEN }}
```

In your `Dockerfile`:

```dockerfile
ARG APP_VERSION=dev
ARG BUILD_DATE
ARG COMMIT_SHA

LABEL org.opencontainers.image.version="${APP_VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${COMMIT_SHA}"

# Secret is available only during the build step it's mounted in
RUN --mount=type=secret,id=NPM_TOKEN \
    NPM_TOKEN=$(cat /run/secrets/NPM_TOKEN) npm ci
```

---

## 7. Pulling GHCR Images in Workflows

Use a GHCR image as a service container or job container:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/my-org/test-runner:latest
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    services:
      database:
        image: ghcr.io/my-org/test-db:latest
        credentials:
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
        ports:
          - 5432:5432

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Run tests
        run: npm test
```

---

## 8. Publishing npm Packages to GitHub Packages

Configure your `package.json` to point to the GitHub Packages npm registry:

```json
{
  "name": "@my-org/my-package",
  "version": "1.0.0",
  "publishConfig": {
    "registry": "https://npm.pkg.github.com"
  }
}
```

Publish workflow:

```yaml
name: Publish npm Package

on:
  release:
    types: [published]

permissions:
  contents: read
  packages: write

jobs:
  publish:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          registry-url: "https://npm.pkg.github.com"
          scope: "@my-org"

      - name: Install dependencies
        run: npm ci

      - name: Build package
        run: npm run build

      - name: Publish to GitHub Packages
        run: npm publish
        env:
          NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## 9. Package Visibility and Permissions

By default, packages published from a private repository are private. You can change visibility in the package settings page (`github.com/users/<user>/packages` or `github.com/orgs/<org>/packages`).

**Linking a package to a repository** is important - it inherits the repository's access controls:

```bash
# Connect a package to its source repository via API
gh api \
  --method PATCH \
  -H "Accept: application/vnd.github+json" \
  /user/packages/container/my-image/versions \
  -f visibility=public
```

---

## 10. Scanning Images Before Push

Integrate vulnerability scanning before pushing to production tags:

```yaml
- name: Build image (no push yet)
  id: build
  uses: docker/build-push-action@v6
  with:
    context: .
    load: true
    tags: ghcr.io/${{ github.repository }}:scan-candidate
    cache-from: type=gha

- name: Scan image with Trivy
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ghcr.io/${{ github.repository }}:scan-candidate
    format: table
    exit-code: "1"
    severity: CRITICAL,HIGH

- name: Push after scan passes
  uses: docker/build-push-action@v6
  with:
    context: .
    push: true
    tags: ${{ steps.meta.outputs.tags }}
    cache-from: type=gha
```

---

## Hands-on

1. Log in to GitHub Container Registry using `docker login` with a personal access token:

   ??? success "Solution"
   `bash
    echo $GITHUB_TOKEN | docker login ghcr.io \
      --username YOUR_GITHUB_USERNAME \
      --password-stdin
    `

2. Write a minimal workflow that builds a Docker image and pushes it to GHCR using `docker/build-push-action`, tagging it with the commit SHA:

   ??? success "Solution"
   `bash
    mkdir -p .github/workflows
    cat > .github/workflows/docker-publish.yml << 'EOF'
    name: Publish Docker Image
    on:
      push:
        branches: [main]
    permissions:
      contents: read
      packages: write
    jobs:
      build:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: docker/login-action@v3
            with:
              registry: ghcr.io
              username: ${{ github.actor }}
              password: ${{ secrets.GITHUB_TOKEN }}
          - uses: docker/build-push-action@v6
            with:
              context: .
              push: true
              tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
    EOF
    git add .github/workflows/docker-publish.yml && git commit -m "ci: publish Docker image to GHCR"
    `

3. Tag the image locally with the current git SHA and push it to GHCR:

   ??? success "Solution"
   `bash
    SHA=$(git rev-parse --short HEAD)
    IMAGE="ghcr.io/OWNER/REPO:${SHA}"
    docker build -t "$IMAGE" .
    docker push "$IMAGE"
    echo "Pushed $IMAGE"
    `

4. Pull a GHCR image in a subsequent job and verify it runs by checking the OS release:

   ??? success "Solution"
   `bash
    docker pull ghcr.io/OWNER/REPO:$(git rev-parse --short HEAD)
    docker run --rm ghcr.io/OWNER/REPO:$(git rev-parse --short HEAD) cat /etc/os-release
    `

5. List packages published to GHCR for your user account using `gh api`:

   ??? success "Solution"
   `bash
    gh api /user/packages?package_type=container \
      --jq '.[] | {name: .name, visibility: .visibility, updated_at: .updated_at}'
    `

## Exercises

### Exercise 1 - Basic GHCR Push

Create a workflow that builds a simple `Dockerfile` (use `FROM alpine:latest`) and pushes it to GHCR on every push to main. Verify the image appears under your GitHub profile's Packages tab.

### Exercise 2 - Semver Tags

Extend the workflow to use `docker/metadata-action` with semver tags. Create a Git tag `v1.0.0` and verify that three tags (`1.0.0`, `1.0`, `1`) are created in GHCR.

### Exercise 3 - Multi-Platform

Add `linux/arm64` to the build platforms. Use `docker buildx imagetools inspect` to verify the manifest list contains both `amd64` and `arm64` entries.

### Exercise 4 - npm Publish

Create a scoped npm package (`@your-org/hello-lib`) with a minimal `index.js` and publish it to GitHub Packages on release. Install it from GitHub Packages in a separate test job.

---

## Summary

- GHCR images are hosted at `ghcr.io/<owner>/<image>:<tag>` and authenticate with `GITHUB_TOKEN` - no external secrets needed
- `docker/metadata-action` generates semver tags, branch tags, PR tags, and SHA tags automatically from Git context
- `docker/setup-qemu-action` + `docker/setup-buildx-action` enable multi-platform builds targeting `linux/amd64`, `linux/arm64`, and more
- The `cache-from: type=gha` / `cache-to: type=gha,mode=max` pattern dramatically speeds up repeated image builds
- npm packages published to GitHub Packages require a scoped name (`@org/package`) and `registry-url: https://npm.pkg.github.com` in `setup-node`
- Packages can be linked to repositories so they inherit the repository's visibility and access controls
- Scanning images with Trivy (or Snyk) before pushing prevents vulnerable images from reaching production registries
