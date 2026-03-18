#!/usr/bin/env bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

# =============================================================================
# Lab 016 - JavaScript Actions Demo
# Demonstrates: a sample JavaScript action with index.js, package.json, action.yml
# =============================================================================

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$LAB_DIR/demo-output"
ACTION_DIR="$OUTPUT_DIR/greet-action"
TEST_DIR="$ACTION_DIR/__tests__"
WORKFLOW_DIR="$OUTPUT_DIR/workflow-examples"

print_header "Lab 016 - JavaScript Actions"
print_info "This demo creates a complete JavaScript action with index.js, package.json, and action.yml"

mkdir -p "$ACTION_DIR" "$TEST_DIR" "$WORKFLOW_DIR"

# -----------------------------------------------------------------------------
# 1. Create action.yml
# -----------------------------------------------------------------------------
print_step "Creating action.yml..."

cat >"$ACTION_DIR/action.yml" <<'EOF'
# =============================================================
# JavaScript Action: greet-action
# Greets a user, posts a PR comment, and produces summary output
# =============================================================
name: Greet Action
description: >
  Greets a specified user, optionally posts a PR comment,
  and outputs the greeting message and timestamp.
author: 'GitHub Actions Lab'

branding:
  icon: 'smile'
  color: 'yellow'

# ---- INPUTS ----
inputs:
  who-to-greet:
    description: 'The name or username to greet'
    required: true
    default: 'World'

  github-token:
    description: 'GitHub token for API access (required for post-comment)'
    required: false
    default: ''

  post-comment:
    description: 'Post a comment on the pull request (true/false)'
    required: false
    default: 'false'

  log-level:
    description: 'Logging level: debug | info | warning | error'
    required: false
    default: 'info'

# ---- OUTPUTS ----
outputs:
  greeting:
    description: 'The full greeting message'

  time:
    description: 'ISO 8601 timestamp when the greeting was produced'

# ---- RUNS ----
runs:
  using: node20
  main: dist/index.js
  # pre: dist/setup.js    # runs before main (optional)
  # post: dist/cleanup.js # runs after main (optional)
EOF

print_success "Created: $ACTION_DIR/action.yml"

# -----------------------------------------------------------------------------
# 2. Create index.js
# -----------------------------------------------------------------------------
print_step "Creating index.js..."

cat >"$ACTION_DIR/index.js" <<'EOF'
/**
 * greet-action - index.js
 *
 * A sample GitHub Actions JavaScript action that:
 * 1. Reads inputs: who-to-greet, github-token, post-comment, log-level
 * 2. Produces a greeting message
 * 3. Optionally posts a PR comment via GitHub API
 * 4. Writes to the step summary
 * 5. Sets outputs: greeting, time
 */

const core   = require('@actions/core');
const github = require('@actions/github');

/**
 * Main action entry point
 */
async function run() {
  try {
    // ---- Read inputs ----
    const whoToGreet  = core.getInput('who-to-greet', { required: true });
    const token       = core.getInput('github-token');
    const postComment = core.getBooleanInput('post-comment');
    const logLevel    = core.getInput('log-level') || 'info';

    // ---- Logging (respects log-level input) ----
    core.debug(`Inputs: whoToGreet=${whoToGreet}, postComment=${postComment}, logLevel=${logLevel}`);
    core.info(`Processing greeting for: ${whoToGreet}`);

    if (logLevel === 'debug') {
      core.debug('Debug mode active - verbose logging enabled');
    }

    // ---- Core logic ----
    const greeting  = `Hello, ${whoToGreet}!`;
    const timestamp = new Date().toISOString();

    core.info(greeting);

    // ---- GitHub API: post PR comment ----
    if (postComment && token) {
      const octokit = github.getOctokit(token);
      const { owner, repo } = github.context.repo;
      const pr = github.context.payload.pull_request;

      if (pr) {
        core.info(`Posting comment on PR #${pr.number}...`);

        await octokit.rest.issues.createComment({
          owner,
          repo,
          issue_number: pr.number,
          body: [
            '## Greeting from greet-action',
            '',
            `**${greeting}**`,
            '',
            `_Timestamp: ${timestamp}_`,
          ].join('\n'),
        });

        core.info('Comment posted successfully.');
      } else {
        core.warning('post-comment is true but this is not a pull_request event - skipping comment.');
      }
    } else if (postComment && !token) {
      core.warning('post-comment is true but no github-token provided - skipping comment.');
    }

    // ---- Set outputs ----
    core.setOutput('greeting', greeting);
    core.setOutput('time', timestamp);

    // ---- Write step summary ----
    await core.summary
      .addHeading('Greet Action Results')
      .addTable([
        [{ data: 'Field',     header: true }, { data: 'Value',     header: true }],
        ['Greeted user',  whoToGreet],
        ['Greeting',      greeting],
        ['Timestamp',     timestamp],
        ['PR Comment',    postComment ? 'Posted' : 'Skipped'],
      ])
      .write();

    core.info('Action completed successfully.');

  } catch (error) {
    // setFailed marks the step as failed and exits
    core.setFailed(`Action failed: ${error.message}`);
  }
}

// Execute
run();
EOF

print_success "Created: $ACTION_DIR/index.js"

# -----------------------------------------------------------------------------
# 3. Create package.json
# -----------------------------------------------------------------------------
print_step "Creating package.json..."

cat >"$ACTION_DIR/package.json" <<'EOF'
{
  "name": "greet-action",
  "version": "1.0.0",
  "description": "Sample GitHub Actions JavaScript action",
  "main": "index.js",
  "scripts": {
    "build": "ncc build index.js --license licenses.txt --out dist",
    "test": "jest",
    "test:coverage": "jest --coverage",
    "lint": "eslint index.js __tests__/**/*.js"
  },
  "dependencies": {
    "@actions/core": "^1.10.1",
    "@actions/github": "^6.0.0"
  },
  "devDependencies": {
    "@vercel/ncc": "^0.38.1",
    "jest": "^29.7.0",
    "@jest/globals": "^29.7.0"
  },
  "jest": {
    "testEnvironment": "node",
    "clearMocks": true,
    "resetMocks": true
  }
}
EOF

print_success "Created: $ACTION_DIR/package.json"

# -----------------------------------------------------------------------------
# 4. Create Jest test file
# -----------------------------------------------------------------------------
print_step "Creating Jest tests..."

cat >"$TEST_DIR/index.test.js" <<'EOF'
/**
 * Jest tests for greet-action
 *
 * Mocks @actions/core and @actions/github to test the action logic
 * without running in an actual GitHub Actions environment.
 */

// Mock the @actions packages BEFORE any require of the action
jest.mock('@actions/core');
jest.mock('@actions/github');

const core   = require('@actions/core');
const github = require('@actions/github');

// Helper to get the mock summary builder
function mockSummary() {
  const builder = {
    addHeading:  jest.fn().mockReturnThis(),
    addTable:    jest.fn().mockReturnThis(),
    addRaw:      jest.fn().mockReturnThis(),
    addBreak:    jest.fn().mockReturnThis(),
    write:       jest.fn().mockResolvedValue(undefined),
  };
  core.summary = builder;
  return builder;
}

// Helper to require action fresh each test
function requireAction() {
  jest.resetModules();
  return require('../index');
}

describe('greet-action', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockSummary();

    // Default GitHub context (not a PR event)
    github.context = {
      repo: { owner: 'test-owner', repo: 'test-repo' },
      sha: 'abc123',
      ref: 'refs/heads/main',
      eventName: 'push',
      payload: {},
    };
  });

  describe('basic greeting', () => {
    test('sets greeting output for a named user', async () => {
      core.getInput.mockImplementation((name) => {
        const inputs = {
          'who-to-greet': 'Alice',
          'github-token': '',
          'log-level': 'info',
        };
        return inputs[name] ?? '';
      });
      core.getBooleanInput.mockReturnValue(false);

      requireAction();
      await new Promise(resolve => setTimeout(resolve, 100));

      expect(core.setOutput).toHaveBeenCalledWith('greeting', 'Hello, Alice!');
      expect(core.setOutput).toHaveBeenCalledWith('time', expect.any(String));
      expect(core.setFailed).not.toHaveBeenCalled();
    });

    test('uses default World when no name given', async () => {
      core.getInput.mockReturnValue('World');
      core.getBooleanInput.mockReturnValue(false);

      requireAction();
      await new Promise(resolve => setTimeout(resolve, 100));

      expect(core.setOutput).toHaveBeenCalledWith('greeting', 'Hello, World!');
    });
  });

  describe('error handling', () => {
    test('calls setFailed when getInput throws', async () => {
      core.getInput.mockImplementation(() => {
        throw new Error('Input not found');
      });

      requireAction();
      await new Promise(resolve => setTimeout(resolve, 100));

      expect(core.setFailed).toHaveBeenCalledWith(
        expect.stringContaining('Input not found')
      );
    });
  });

  describe('post-comment behavior', () => {
    test('warns if post-comment is true but no token provided', async () => {
      core.getInput.mockImplementation((name) => {
        const inputs = { 'who-to-greet': 'Bob', 'github-token': '', 'log-level': 'info' };
        return inputs[name] ?? '';
      });
      core.getBooleanInput.mockReturnValue(true); // post-comment = true

      requireAction();
      await new Promise(resolve => setTimeout(resolve, 100));

      expect(core.warning).toHaveBeenCalledWith(
        expect.stringContaining('no github-token')
      );
    });

    test('warns if post-comment is true but event is not PR', async () => {
      core.getInput.mockImplementation((name) => {
        const inputs = { 'who-to-greet': 'Charlie', 'github-token': 'fake-token', 'log-level': 'info' };
        return inputs[name] ?? '';
      });
      core.getBooleanInput.mockReturnValue(true);

      const mockOctokit = { rest: { issues: { createComment: jest.fn() } } };
      github.getOctokit = jest.fn().mockReturnValue(mockOctokit);
      // No PR in payload → should warn

      requireAction();
      await new Promise(resolve => setTimeout(resolve, 100));

      expect(core.warning).toHaveBeenCalledWith(
        expect.stringContaining('not a pull_request event')
      );
      expect(mockOctokit.rest.issues.createComment).not.toHaveBeenCalled();
    });
  });
});
EOF

print_success "Created: $TEST_DIR/index.test.js"

# -----------------------------------------------------------------------------
# 5. Create workflow that uses the action
# -----------------------------------------------------------------------------
print_step "Creating workflow..."

cat >"$WORKFLOW_DIR/use-greet-action.yml" <<'EOF'
name: Use Greet JavaScript Action

on:
  push:
    branches: [main]
  pull_request:

jobs:
  greet:
    name: Run Greet Action
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Run greet action
        id: greet
        uses: ./.github/actions/greet-action
        with:
          who-to-greet: ${{ github.actor }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
          post-comment: ${{ github.event_name == 'pull_request' }}
          log-level: info

      - name: Use outputs from the action
        run: |
          echo "Greeting : ${{ steps.greet.outputs.greeting }}"
          echo "Timestamp: ${{ steps.greet.outputs.time }}"

  # Run tests as part of CI (important: test the action before shipping it)
  test-action-code:
    name: Test Action Code
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: .github/actions/greet-action/package-lock.json

      - name: Install action dependencies
        working-directory: .github/actions/greet-action
        run: npm ci

      - name: Run tests
        working-directory: .github/actions/greet-action
        run: npm test -- --coverage

      - name: Build bundle
        working-directory: .github/actions/greet-action
        run: npm run build

      - name: Verify bundle was created
        run: test -f .github/actions/greet-action/dist/index.js
EOF

print_success "Created: $WORKFLOW_DIR/use-greet-action.yml"

# -----------------------------------------------------------------------------
# 6. Demonstrate ncc bundling (if Node.js is available)
# -----------------------------------------------------------------------------
print_step "Demonstrating ncc bundling..."

if command -v node &>/dev/null && command -v npm &>/dev/null; then
  print_info "Node.js is available ($(node --version)). Demonstrating ncc bundling..."

  cd "$ACTION_DIR"

  print_info "Installing action dependencies..."
  npm install --silent 2>&1 | tail -3 || print_info "npm install failed - may need network access"

  if [ -d "$ACTION_DIR/node_modules/@actions/core" ]; then
    print_info "Running ncc build..."
    npx ncc build index.js --out dist --no-source-map 2>&1 | tail -5 || print_info "ncc build failed"

    if [ -f "$ACTION_DIR/dist/index.js" ]; then
      BUNDLE_SIZE=$(du -sh "$ACTION_DIR/dist/index.js" | cut -f1)
      SOURCE_SIZE=$(du -sh "$ACTION_DIR/index.js" | cut -f1)
      NODE_MODULES_SIZE=$(du -sh "$ACTION_DIR/node_modules" | cut -f1)

      print_success "Bundle created: dist/index.js"
      echo ""
      echo "  Source file    : $SOURCE_SIZE (index.js)"
      echo "  node_modules   : $NODE_MODULES_SIZE"
      echo "  Bundled file   : $BUNDLE_SIZE (dist/index.js - single file with all deps!)"
      echo ""
      print_info "The dist/ directory should be committed to the repository."
      print_info "The node_modules/ directory should NOT be committed (.gitignore)."
    fi

    print_info "Running Jest tests..."
    npm test -- --passWithNoTests 2>&1 | tail -15 || print_info "Tests ran (some may fail without full setup)"
  else
    print_info "Dependencies not fully installed - skipping build/test demo."
  fi

  cd "$LAB_DIR"
else
  print_info "Node.js not available - skipping live build demo."
  print_info "Build commands for reference:"
  echo "  npm install"
  echo "  npx ncc build index.js --out dist --license licenses.txt"
  echo "  npm test -- --coverage"
fi

# -----------------------------------------------------------------------------
# 7. Summary
# -----------------------------------------------------------------------------
print_header "Demo Complete"
echo ""
print_info "Generated JavaScript action files:"
find "$ACTION_DIR" -type f -not -path "*/node_modules/*" -not -path "*/.git/*" | sort | while read -r f; do
  echo "  ${f#$ACTION_DIR/}"
done
echo ""
print_info "Key concepts:"
echo "  index.js       - action logic using @actions/core and @actions/github"
echo "  package.json   - dependencies and build/test scripts"
echo "  action.yml     - metadata, inputs, outputs, runs.using: node20"
echo "  __tests__/     - Jest tests mocking @actions packages"
echo "  dist/index.js  - ncc bundle (MUST be committed)"
