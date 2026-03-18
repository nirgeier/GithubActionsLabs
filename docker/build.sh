#!/usr/bin/env bash
: <<'DOC'
build.sh
---------
Small helper for building and pushing a multi-architecture Docker image
for the GitHub Actions Labs project using Docker Buildx and a docker-compose
build definition.

What this script does (high level):
	1. Locates the git repository root and cd's there so paths are predictable.
	2. Builds the MkDocs site so it can be copied into the Docker image.
	3. Ensures the host supports emulating other CPU architectures by
		 registering binfmt handlers (via tonistiigi/binfmt).
	4. Creates and switches to a docker buildx builder instance named
		 `multiarch-builder` and bootstraps it.
	5. Runs `docker buildx bake` with the project's docker-compose.yml to
		 build and push the github-actions-labs image defined in that file.

Usage:
	./build.sh

Requirements / Preconditions:
	- Docker (Engine) installed and running on the host
	- docker buildx available (Docker >= 19.03 with buildx plugin)
	- You must be logged in to the GitHub Container Registry:
		echo $CR_PAT | docker login ghcr.io -u USERNAME --password-stdin
	- You must be logged in to Docker Hub:
		docker login -u USERNAME
	- This script must be executed from a git working tree.

Customization:
	- You can change the image name and tag by exporting IMAGE and IMAGE_TAG
		before running the script, e.g.:
			IMAGE=ghcr.io/nirgeier/github-actions-labs IMAGE_TAG=v1.2.3 ./build.sh
DOC

set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
cd "$ROOT_DIR"

IMAGE=${IMAGE:-ghcr.io/nirgeier/github-actions-labs}
IMAGE_TAG=${IMAGE_TAG:-latest}
DOCKERHUB_IMAGE=${DOCKERHUB_IMAGE:-nirgeier/github-actions-labs}

BUILD_TIME=$(date +"%Y-%m-%dT%H:%M:%SZ")
SourceRepository=$(git config --local --get remote.origin.url 2>/dev/null || echo "")

echo "Building image: ${IMAGE}:${IMAGE_TAG} (root: ${ROOT_DIR})"

# Step 1: Build the mkdocs site so it can be copied into the Docker image.
echo "Building mkdocs site..."
if [ -f "$ROOT_DIR/.venv/bin/activate" ]; then
  source "$ROOT_DIR/.venv/bin/activate"
fi
bash "$ROOT_DIR/mkdocs/scripts/init_site.sh" --no-serve

# Step 2: Register binfmt handlers for multi-architecture emulation.
echo "Registering binfmt emulation handlers (required for cross-arch builds)..."
docker run --privileged --rm tonistiigi/binfmt --install all

# Step 3: Create / select a docker buildx builder and switch to it.
echo "Creating and switching to buildx builder 'multiarch-builder'..."
if ! docker buildx inspect multiarch-builder >/dev/null 2>&1; then
	docker buildx create --name multiarch-builder --use
else
	docker buildx use multiarch-builder
fi

echo "Bootstrapping buildx builder..."
docker buildx inspect --bootstrap

# Step 4: Build and push using docker buildx bake.
# Run from docker/ so that context: .. in the compose file resolves to the repo root.
echo "Running buildx bake for production (build + push)..."
cd "$ROOT_DIR/docker"
BUILD_TIME="$BUILD_TIME" \
IMAGE="$IMAGE" \
IMAGE_TAG="$IMAGE_TAG" \
SourceRepository="$SourceRepository" \
docker buildx bake \
	--allow=fs.read=.. \
	-f docker-compose.yml \
	--push \
	github-actions-labs

echo "Done."
