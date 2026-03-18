# Lab 016 - JavaScript Actions

## Introduction

- JavaScript (and TypeScript) actions are the most common type of custom GitHub Actions.
- They start faster than Docker actions, run on all platforms (Linux, macOS, Windows), and have first-class support through the `@actions/` toolkit packages.
- This lab covers building a JavaScript action from scratch using `@actions/core`, `@actions/github`, bundling with `@vercel/ncc`, and testing with Jest.

---

## Why JavaScript Actions?

| Feature           | JavaScript Action | Docker Action | Composite Action |
| ----------------- | ----------------- | ------------- | ---------------- |
| Startup speed     | Fastest           | Slowest       | Medium           |
| Cross-platform    | Yes               | Linux only    | Yes              |
| Language          | JS/TS             | Any           | Bash             |
| Dependencies      | Bundled (ncc)     | In image      | External actions |
| GitHub API access | `@actions/github` | Manual        | Manual           |

---

## `action.yml` for a JavaScript Action

```yaml
name: My JavaScript Action
description: An example JavaScript action

inputs:
  who-to-greet:
    description: "Who to greet"
    required: true
    default: "World"
  log-level:
    description: "Logging level: debug | info | warning | error"
    required: false
    default: "info"

outputs:
  greeting:
    description: "The greeting message"
  time:
    description: "The time the greeting was produced"

runs:
  using: node20 # Options: node16, node20
  main: dist/index.js # Path to the compiled/bundled entrypoint
  pre: dist/setup.js # Optional: runs before main
  post: dist/cleanup.js # Optional: runs after main
```

---

## The `@actions/core` Package

`@actions/core` is the primary toolkit for interacting with the Actions runtime.

### Inputs and Outputs

```javascript
const core = require("@actions/core");

// Read inputs (defined in action.yml)
const whoToGreet = core.getInput("who-to-greet"); // Required input
const logLevel = core.getInput("log-level", { required: false }); // Optional input
const flag = core.getBooleanInput("some-flag"); // Boolean input

// Set outputs
core.setOutput("greeting", `Hello, ${whoToGreet}!`);
core.setOutput("time", new Date().toISOString());
```

### Logging

```javascript
core.debug(
  "Detailed debug info - only visible when ACTIONS_STEP_DEBUG is true",
);
core.info("Normal informational message");
core.notice("A notable message that appears in the PR/commit");
core.warning("A warning - visible in the Actions UI");
core.error("An error message - marks the step as failed in annotations");
```

### Failing and Success

```javascript
// Fail the action with a message
core.setFailed("Something went wrong: " + error.message);

// Add structured annotations
core.error("File not found", {
  file: "src/index.js",
  startLine: 42,
  endLine: 42,
  title: "Missing file",
});
```

### Environment and Path

```javascript
// Export an environment variable to subsequent steps
core.exportVariable("MY_VAR", "my_value");

// Add a directory to PATH
core.addPath("/usr/local/my-tools/bin");
```

### Masking Secrets

```javascript
// Prevent a value from appearing in logs
const secret = core.getInput("api-key");
core.setSecret(secret);
```

### Summary

```javascript
// Write to the step summary
await core.summary
  .addHeading("Test Results")
  .addTable([
    [
      { data: "Test", header: true },
      { data: "Status", header: true },
    ],
    ["unit tests", "PASS"],
    ["integration tests", "FAIL"],
  ])
  .write();
```

---

## The `@actions/github` Package

`@actions/github` provides an authenticated Octokit instance and GitHub context:

```javascript
const github = require("@actions/github");
const core = require("@actions/core");

async function run() {
  // Get authenticated GitHub client
  const token = core.getInput("github-token", { required: true });
  const octokit = github.getOctokit(token);

  // Access event context
  const { owner, repo } = github.context.repo;
  const { sha, ref, eventName } = github.context;

  // Create a commit status
  await octokit.rest.repos.createCommitStatus({
    owner,
    repo,
    sha,
    state: "success",
    description: "All checks passed",
    context: "my-action/check",
  });

  // Add a PR comment
  if (github.context.payload.pull_request) {
    const prNumber = github.context.payload.pull_request.number;
    await octokit.rest.issues.createComment({
      owner,
      repo,
      issue_number: prNumber,
      body: "## Build Results\n\nAll checks passed!",
    });
  }
}

run().catch(core.setFailed);
```

---

## Complete `index.js` Example

```javascript
const core = require("@actions/core");
const github = require("@actions/github");

async function run() {
  try {
    // ---- Read Inputs ----
    const whoToGreet = core.getInput("who-to-greet");
    const token = core.getInput("github-token");
    const postComment = core.getBooleanInput("post-comment");

    core.debug(`whoToGreet: ${whoToGreet}`);

    // ---- Core Logic ----
    const greeting = `Hello, ${whoToGreet}!`;
    const timestamp = new Date().toISOString();

    core.info(greeting);

    // ---- Set Outputs ----
    core.setOutput("greeting", greeting);
    core.setOutput("time", timestamp);

    // ---- Optional GitHub API Call ----
    if (postComment && token && github.context.payload.pull_request) {
      const octokit = github.getOctokit(token);
      const { owner, repo } = github.context.repo;
      const prNumber = github.context.payload.pull_request.number;

      await octokit.rest.issues.createComment({
        owner,
        repo,
        issue_number: prNumber,
        body: `👋 ${greeting}\n\nTimestamp: ${timestamp}`,
      });

      core.info("Comment posted on PR");
    }

    // ---- Write Step Summary ----
    await core.summary
      .addHeading("Greeting Action")
      .addRaw(`**${greeting}**`)
      .addBreak()
      .addRaw(`Timestamp: ${timestamp}`)
      .write();
  } catch (error) {
    core.setFailed(error.message);
  }
}

run();
```

---

## `package.json`

```json
{
  "name": "my-github-action",
  "version": "1.0.0",
  "description": "A sample JavaScript GitHub Action",
  "main": "index.js",
  "scripts": {
    "build": "ncc build index.js --license licenses.txt --out dist",
    "test": "jest",
    "lint": "eslint index.js"
  },
  "dependencies": {
    "@actions/core": "^1.10.0",
    "@actions/github": "^6.0.0"
  },
  "devDependencies": {
    "@vercel/ncc": "^0.38.0",
    "jest": "^29.0.0",
    "@jest/globals": "^29.0.0"
  }
}
```

---

## Bundling with `@vercel/ncc`

`@vercel/ncc` compiles a Node.js project into a single JavaScript file, including all `node_modules`. This is required because the runner does not install your action's dependencies.

```bash
# Install ncc as a dev dependency
npm install --save-dev @vercel/ncc

# Build the bundle
npx ncc build index.js --out dist --license licenses.txt

# The result is dist/index.js - a single self-contained file
```

The workflow uses `main: dist/index.js` in `action.yml`, pointing to the bundle.

**Important:** Commit the `dist/` directory to your repository. Do not add it to `.gitignore`.

---

## Testing with Jest

```javascript
// __tests__/index.test.js
const { describe, test, expect, beforeEach } = require("@jest/globals");

// Mock the @actions packages before requiring the action
jest.mock("@actions/core");
jest.mock("@actions/github");

const core = require("@actions/core");
const github = require("@actions/github");

describe("greet action", () => {
  beforeEach(() => {
    jest.resetAllMocks();
  });

  test("sets greeting output", async () => {
    core.getInput.mockImplementation((name) => {
      const inputs = {
        "who-to-greet": "Alice",
        "github-token": "",
        "post-comment": "false",
      };
      return inputs[name] ?? "";
    });
    core.getBooleanInput.mockReturnValue(false);

    // Require the action AFTER mocking
    jest.isolateModules(() => {
      require("../index");
    });

    // Allow async operations to complete
    await new Promise((resolve) => setTimeout(resolve, 50));

    expect(core.setOutput).toHaveBeenCalledWith("greeting", "Hello, Alice!");
    expect(core.setFailed).not.toHaveBeenCalled();
  });

  test("calls setFailed on error", async () => {
    core.getInput.mockImplementation(() => {
      throw new Error("Input not found");
    });

    jest.isolateModules(() => {
      require("../index");
    });

    await new Promise((resolve) => setTimeout(resolve, 50));

    expect(core.setFailed).toHaveBeenCalled();
  });
});
```

---

## Workflow Using the JavaScript Action

```yaml
name: Use JavaScript Action

on: [push, pull_request]

jobs:
  greet:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Use action from same repository
      - name: Run greet action
        id: greet
        uses: ./.github/actions/greet-action
        with:
          who-to-greet: ${{ github.actor }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
          post-comment: ${{ github.event_name == 'pull_request' }}

      - name: Use action outputs
        run: |
          echo "Greeting: ${{ steps.greet.outputs.greeting }}"
          echo "Time: ${{ steps.greet.outputs.time }}"
```

---

## Hands-on

1. Create `index.js` that uses `@actions/core` to read a `who-to-greet` input and set a `greeting` output:

   ??? success "Solution"
   `bash
    mkdir -p .github/actions/greet-js
    cat > .github/actions/greet-js/index.js << 'EOF'
    const core = require('@actions/core');
    async function run() {
      try {
        const name = core.getInput('who-to-greet');
        const greeting = 'Hello, ' + name + '!';
        core.info(greeting);
        core.setOutput('greeting', greeting);
      } catch (err) {
        core.setFailed(err.message);
      }
    }
    run();
    EOF
    `

2. Write `action.yml` for the JavaScript action with `runs.using: node20` and `main: index.js`:

   ??? success "Solution"
   `bash
    cat > .github/actions/greet-js/action.yml << 'EOF'
    name: Greet JS Action
    description: Greets someone using Node.js
    inputs:
      who-to-greet:
        description: Who to greet
        required: true
        default: World
    outputs:
      greeting:
        description: The greeting message
    runs:
      using: node20
      main: index.js
    EOF
    `

3. Read the `greeting` output in a subsequent workflow step and print it:

   ??? success "Solution"
   `bash
    cat > .github/workflows/js-action-demo.yml << 'EOF'
    name: JS Action Demo
    on: push
    jobs:
      greet:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - id: g
            uses: ./.github/actions/greet-js
            with:
              who-to-greet: ${{ github.actor }}
          - run: echo "Greeting was ${{ steps.g.outputs.greeting }}"
    EOF
    `

4. Use `core.setFailed` to fail the action when the input is empty, then verify it in `gh run view --log`:

   ??? success "Solution"
   `bash
    cat > .github/actions/greet-js/index.js << 'EOF'
    const core = require('@actions/core');
    async function run() {
      try {
        const name = core.getInput('who-to-greet');
        if (!name) {
          core.setFailed('who-to-greet input must not be empty');
          return;
        }
        core.setOutput('greeting', 'Hello, ' + name + '!');
      } catch (err) {
        core.setFailed(err.message);
      }
    }
    run();
    EOF
    `

5. Check the action output in a completed run with `gh run view --log`:

   ??? success "Solution"
   `bash
    git add .github/actions/greet-js/ .github/workflows/js-action-demo.yml
    git commit -m "add js action"
    git push
    RUN_ID=$(gh run list --workflow js-action-demo.yml --limit 1 --json databaseId -q '.[0].databaseId')
    gh run watch "$RUN_ID"
    gh run view "$RUN_ID" --log | grep -i greeting
    `

## Exercises

### Exercise 1 - Hello World Action

Create a JavaScript action that:

1. Takes a `name` input
2. Prints `Hello, {name}!`
3. Sets a `greeting` output
4. Writes the result to the step summary

### Exercise 2 - GitHub API Action

Create an action that:

1. Reads `github-token` and `label` inputs
2. Lists all open PRs
3. Adds the label to PRs missing it
4. Outputs the count of PRs labeled

### Exercise 3 - Logging Levels

Modify an action to log at different levels based on a `log-level` input. Test that `debug` messages only appear with `ACTIONS_STEP_DEBUG=true`.

### Exercise 4 - Build and Bundle

Write a complete action with `index.js`, `package.json`, and `action.yml`. Run `ncc build` and verify `dist/index.js` is generated. Commit both source and bundle.

### Exercise 5 - Test with Jest

Write a Jest test suite for your action. Mock `@actions/core` and `@actions/github`. Achieve at least 80% coverage.

---

## Summary

- JavaScript actions use `runs.using: node20` and point `main:` at a bundled `dist/index.js` that includes all dependencies
- `@actions/core` provides `getInput()`, `setOutput()`, `setFailed()`, and structured logging with `info()`, `warning()`, `error()`, `debug()`
- `@actions/github` provides an authenticated `octokit` client and the `context` object with event payload, `repo`, and `sha`
- `@vercel/ncc` compiles the action and its `node_modules` into a single file - the compiled `dist/` directory must be committed to the repository
- Jest with mocked `@actions/core` and `@actions/github` packages enables unit testing without running in an actual Actions environment
- The `pre:` and `post:` hooks in `action.yml` allow setup and cleanup code to run before and after the main action
- JavaScript actions run on all GitHub-hosted runner platforms (Linux, macOS, Windows), making them ideal for cross-platform scenarios
