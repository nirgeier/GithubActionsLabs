# Lab 015 - Docker Actions

## Introduction

- Docker-based custom actions run your action logic inside a Docker container, giving you complete control over the runtime environment.
- Any language, any tool, any dependency - if it fits in a Docker image, it can be a GitHub Action.
- This lab covers how to build Docker actions from scratch: the `action.yml` configuration, the `Dockerfile`, the `entrypoint.sh` pattern, how inputs are passed as environment variables, and how to set outputs.

---

## When to Use Docker Actions

Docker actions are ideal when you need:

- A specific runtime environment (a particular OS, library version, or tool)
- Actions written in languages other than JavaScript (Go, Python, Rust, Ruby, etc.)
- Complex dependency trees that are hard to bundle as JavaScript
- Guaranteed reproducibility regardless of the runner environment

**Tradeoffs compared to JavaScript actions:**

| Aspect              | Docker Action                 | JavaScript Action     |
| ------------------- | ----------------------------- | --------------------- |
| Startup time        | Slower (image pull/build)     | Faster                |
| Language            | Any                           | JavaScript/TypeScript |
| Environment control | Complete                      | Limited to runner     |
| Runner OS support   | Linux only (on GitHub-hosted) | All OS                |

---

## `action.yml` for a Docker Action

```yaml
name: My Docker Action
description: Processes files using a custom Docker image

inputs:
  message:
    description: "Message to process"
    required: true
  output-format:
    description: "Output format: plain or json"
    required: false
    default: "plain"

outputs:
  result:
    description: "The processed result"

runs:
  using: docker
  image: Dockerfile # Build from local Dockerfile
  # image: 'docker://alpine:3.19'  # Use a pre-built image
  entrypoint: /entrypoint.sh # Optional override
  args:
    - ${{ inputs.message }}
    - ${{ inputs.output-format }}
```

### `runs` Options for Docker Actions

| Option                      | Description                                        |
| --------------------------- | -------------------------------------------------- |
| `using: docker`             | Required to identify this as a Docker action       |
| `image: Dockerfile`         | Build the image from a local Dockerfile            |
| `image: docker://image:tag` | Use a pre-built image from Docker Hub or registry  |
| `entrypoint:`               | Override the Dockerfile's ENTRYPOINT               |
| `args:`                     | Arguments appended to the entrypoint command       |
| `env:`                      | Additional environment variables for the container |
| `pre-entrypoint:`           | Script to run before the main entrypoint           |
| `post-entrypoint:`          | Script to run after the main entrypoint            |

---

## Dockerfile for a Docker Action

```dockerfile
# Use a minimal base image
FROM alpine:3.19

# Install any required tools
RUN apk add --no-cache \
    bash \
    curl \
    jq

# Copy the entrypoint script
COPY entrypoint.sh /entrypoint.sh

# Make it executable
RUN chmod +x /entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/entrypoint.sh"]
```

### Best Practices for Action Dockerfiles

```dockerfile
# Pin base image to a specific digest for reproducibility
FROM alpine:3.19@sha256:abc123...

# Combine RUN commands to minimize layers
RUN apk add --no-cache bash curl jq \
    && adduser -D -h /app appuser

# Use COPY not ADD (more predictable)
COPY entrypoint.sh /entrypoint.sh

# Run as non-root for security
USER appuser

ENTRYPOINT ["/entrypoint.sh"]
```

---

## `entrypoint.sh` Pattern

The entrypoint script receives inputs as environment variables prefixed with `INPUT_` (uppercase, hyphens become underscores):

```bash
#!/bin/bash
set -euo pipefail

# Inputs are available as INPUT_<NAME> environment variables
# Input 'my-input' → INPUT_MY_INPUT
# Input 'message' → INPUT_MESSAGE
MESSAGE="${INPUT_MESSAGE:-default value}"
OUTPUT_FORMAT="${INPUT_OUTPUT_FORMAT:-plain}"

echo "Processing message: $MESSAGE"
echo "Output format: $OUTPUT_FORMAT"

# Process the input
RESULT="Processed: $MESSAGE"

if [ "$OUTPUT_FORMAT" = "json" ]; then
    RESULT=$(jq -n --arg r "$RESULT" '{"result": $r}')
fi

# Set output using GITHUB_OUTPUT
echo "result=$RESULT" >> "$GITHUB_OUTPUT"

echo "Done! Result: $RESULT"
```

---

## How Inputs Are Passed as Environment Variables

GitHub Actions automatically converts action inputs to environment variables for Docker containers:

| Input name      | Environment variable  |
| --------------- | --------------------- |
| `message`       | `INPUT_MESSAGE`       |
| `output-format` | `INPUT_OUTPUT_FORMAT` |
| `my-flag`       | `INPUT_MY_FLAG`       |
| `api_key`       | `INPUT_API_KEY`       |

Transformation rules:

- Prefix `INPUT_` is added
- Letters are uppercased
- Hyphens `-` become underscores `_`

---

## Setting Outputs in Docker Actions

Use the `GITHUB_OUTPUT` environment variable (the path to the output file):

```bash
# Set a single output
echo "result=my value" >> "$GITHUB_OUTPUT"

# Set a multiline output
{
  echo "summary<<EOF"
  echo "Line 1"
  echo "Line 2"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
```

---

## Complete Example: Markdown Linter Docker Action

### Directory Structure

```
.github/
  actions/
    markdown-lint/
      action.yml
      Dockerfile
      entrypoint.sh
```

### `action.yml`

```yaml
name: Markdown Linter
description: Lints Markdown files using markdownlint-cli inside Docker

inputs:
  path:
    description: "Path to lint (file or directory)"
    required: false
    default: "."
  config:
    description: "Path to .markdownlint.json config file"
    required: false
    default: ""
  fail-on-error:
    description: "Fail the action if lint errors are found"
    required: false
    default: "true"

outputs:
  error-count:
    description: "Number of lint errors found"
  report-path:
    description: "Path to the generated lint report"

runs:
  using: docker
  image: Dockerfile
```

### `Dockerfile`

```dockerfile
FROM node:20-alpine

RUN npm install -g markdownlint-cli

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
```

### `entrypoint.sh`

```bash
#!/bin/bash
set -eo pipefail

LINT_PATH="${INPUT_PATH:-.}"
CONFIG_FILE="${INPUT_CONFIG:-}"
FAIL_ON_ERROR="${INPUT_FAIL_ON_ERROR:-true}"
REPORT_PATH="/tmp/markdownlint-report.txt"

echo "=== Markdown Linter ==="
echo "Path: $LINT_PATH"
echo "Fail on error: $FAIL_ON_ERROR"

# Build markdownlint command
CMD="markdownlint"
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    CMD="$CMD --config $CONFIG_FILE"
fi
CMD="$CMD $LINT_PATH"

echo "Running: $CMD"

# Run linter and capture output
set +e
$CMD 2>&1 | tee "$REPORT_PATH"
EXIT_CODE=$?
set -e

# Count errors
ERROR_COUNT=$(grep -c "^" "$REPORT_PATH" || echo "0")

# Set outputs
echo "error-count=$ERROR_COUNT" >> "$GITHUB_OUTPUT"
echo "report-path=$REPORT_PATH" >> "$GITHUB_OUTPUT"

echo "Lint errors found: $ERROR_COUNT"

if [ "$FAIL_ON_ERROR" = "true" ] && [ "$EXIT_CODE" -ne 0 ]; then
    echo "Failing due to lint errors."
    exit 1
fi

echo "Markdown lint complete."
```

### Workflow using the Docker action

```yaml
name: Lint Documentation

on:
  push:
  pull_request:

jobs:
  lint-docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Lint Markdown files
        id: md-lint
        uses: ./.github/actions/markdown-lint
        with:
          path: docs/
          fail-on-error: "false"

      - name: Report results
        run: |
          echo "Lint errors: ${{ steps.md-lint.outputs.error-count }}"
          echo "Report at: ${{ steps.md-lint.outputs.report-path }}"
```

---

## Using a Pre-Built Docker Image

Instead of building from a Dockerfile, point to a pre-built image:

```yaml
runs:
  using: docker
  image: "docker://ghcr.io/my-org/my-action:v1.2.3"
```

This avoids a build step at runtime but requires the image to be published.

---

## Advantages of Docker Actions

1. **Any language** - Python, Go, Rust, Ruby, Bash, or any combination
2. **Complete environment control** - Pin exact OS, library, and tool versions
3. **No bundling required** - All dependencies in the image
4. **Portable** - Works the same locally and in CI
5. **Security** - Isolated container, non-root operation possible

---

## Publishing to GitHub Marketplace

To publish a Docker action:

1. Ensure `action.yml` is at the repository root
2. Add metadata: `branding.icon` and `branding.color`
3. Create a release with a semver tag
4. In the release UI, check "Publish this Action to the GitHub Marketplace"

```yaml
name: My Docker Action
description: Does something great
author: Your Name

branding:
  icon: "tool"
  color: "blue"

inputs:
  # ...

runs:
  using: docker
  image: Dockerfile
```

---

## Hands-on

1. Create a `Dockerfile` for a Docker action that installs `bash` on Alpine and runs an entrypoint that prints an input:

   ??? success "Solution"
   `bash
    mkdir -p .github/actions/hello-docker
    cat > .github/actions/hello-docker/Dockerfile << 'EOF'
    FROM alpine:3.19
    RUN apk add --no-cache bash
    COPY entrypoint.sh /entrypoint.sh
    RUN chmod +x /entrypoint.sh
    ENTRYPOINT ["/entrypoint.sh"]
    EOF
    cat > .github/actions/hello-docker/entrypoint.sh << 'EOF'
    #!/bin/bash
    set -euo pipefail
    echo "Hello, ${INPUT_NAME}!"
    echo "result=Hello, ${INPUT_NAME}!" >> "$GITHUB_OUTPUT"
    EOF
    chmod +x .github/actions/hello-docker/entrypoint.sh
    `

2. Write the `action.yml` for the Docker action with `runs.using: docker` and one `name` input:

   ??? success "Solution"
   `bash
    cat > .github/actions/hello-docker/action.yml << 'EOF'
    name: Hello Docker Action
    description: Greets someone from inside Docker
    inputs:
      name:
        description: Name to greet
        required: true
    outputs:
      result:
        description: The greeting
    runs:
      using: docker
      image: Dockerfile
    EOF
    `

3. Write `entrypoint.sh` so it reads `INPUT_NAME` and writes an output to `$GITHUB_OUTPUT`:

   ??? success "Solution"
   `bash
    cat .github/actions/hello-docker/entrypoint.sh
    echo "INPUT_NAME is set by GitHub Actions from the 'name' input automatically"
    echo "Outputs are written with: echo 'key=value' >> \"\$GITHUB_OUTPUT\""
    `

4. Build and test the Docker action locally with `docker build` and `docker run`:

   ??? success "Solution"
   `bash
    cd .github/actions/hello-docker
    docker build -t hello-docker-action .
    docker run --rm \
      -e INPUT_NAME="Local Test" \
      -e GITHUB_OUTPUT=/dev/stdout \
      hello-docker-action
    `

5. Reference the Docker action from a workflow using `uses: ./.github/actions/hello-docker`:

   ??? success "Solution"
   `bash
    cat > .github/workflows/docker-action-demo.yml << 'EOF'
    name: Docker Action Demo
    on: push
    jobs:
      greet:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - id: hello
            uses: ./.github/actions/hello-docker
            with:
              name: ${{ github.actor }}
          - run: echo "Result was ${{ steps.hello.outputs.result }}"
    EOF
    git add .github/actions/hello-docker/ .github/workflows/docker-action-demo.yml
    git commit -m "add docker action"
    git push
    `

## Exercises

### Exercise 1 - Hello World Docker Action

Create a Docker action that:

1. Accepts a `name` input
2. Prints `Hello, {name}!`
3. Outputs the greeting message

### Exercise 2 - Python Docker Action

Write a Docker action using a Python base image that:

1. Takes a JSON string as input
2. Parses and pretty-prints it
3. Outputs the key count

### Exercise 3 - Tool-Specific Action

Create a Docker action wrapping a CLI tool not available on GitHub runners (e.g., a custom binary). Package it in the Dockerfile.

### Exercise 4 - Pre and Post Entrypoints

Use `pre-entrypoint:` to set up resources and `post-entrypoint:` to clean them up. Verify the lifecycle.

### Exercise 5 - Published Docker Action

Publish your Docker action to a public GitHub repository, create a v1.0.0 release, and reference it from another repository as `owner/action-repo@v1`.

---

## Summary

- Docker actions use `runs.using: docker` in `action.yml` and build from a local `Dockerfile` or pull a pre-built image
- Inputs are automatically exposed to the container as `INPUT_<NAME>` environment variables (uppercased, hyphens replaced by underscores)
- Outputs are set by writing `name=value` lines to the file path stored in `$GITHUB_OUTPUT`
- The `entrypoint.sh` pattern provides a clean separation between the container environment and the action logic
- Docker actions support any programming language since all dependencies are baked into the image
- The `pre-entrypoint:` and `post-entrypoint:` hooks allow setup and teardown logic around the main action body
- Docker actions are Linux-only on GitHub-hosted runners; use JavaScript actions for cross-platform support
