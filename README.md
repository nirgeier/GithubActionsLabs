# GitHub Actions Labs

[![Open in Docker](https://img.shields.io/badge/Open%20in-Docker-2496ED?logo=docker)](https://hub.docker.com/r/nirgeier/github-actions-labs)

A hands-on collection of **31 labs** covering all major aspects of GitHub Actions CI/CD automation - from your first workflow to advanced deployment patterns.

## Labs

| Lab                                                | Topic                  | Description                                      |
| -------------------------------------------------- | ---------------------- | ------------------------------------------------ |
| [000](Labs/000-setup/README.md)                    | Setup                  | Install tools, authenticate with GitHub CLI      |
| [001](Labs/001-first-workflow/README.md)           | First Workflow         | Hello World workflow, YAML syntax                |
| [002](Labs/002-triggers-events/README.md)          | Triggers & Events      | push, pull_request, schedule, workflow_dispatch  |
| [003](Labs/003-jobs-steps/README.md)               | Jobs & Steps           | Multi-job workflows, step dependencies           |
| [004](Labs/004-runners/README.md)                  | Runners                | GitHub-hosted vs self-hosted, runner labels      |
| [005](Labs/005-env-variables/README.md)            | Environment Variables  | env, job env, step env, GITHUB_ENV               |
| [006](Labs/006-secrets-contexts/README.md)         | Secrets & Contexts     | github, env, secrets, runner, job contexts       |
| [007](Labs/007-expressions/README.md)              | Expressions            | ${{ }}, functions, operators                     |
| [008](Labs/008-conditions/README.md)               | Conditions             | if expressions, status checks, skipping          |
| [009](Labs/009-matrix-strategy/README.md)          | Matrix Strategy        | Build matrices, include/exclude, fail-fast       |
| [010](Labs/010-artifacts/README.md)                | Artifacts              | Upload/download, retention, sharing between jobs |
| [011](Labs/011-caching/README.md)                  | Caching                | actions/cache, cache keys, restore keys          |
| [012](Labs/012-services-containers/README.md)      | Services & Containers  | Docker services, PostgreSQL, Redis               |
| [013](Labs/013-reusable-workflows/README.md)       | Reusable Workflows     | workflow_call, inputs, outputs, secrets          |
| [014](Labs/014-composite-actions/README.md)        | Composite Actions      | Custom composite actions with steps              |
| [015](Labs/015-docker-actions/README.md)           | Docker Actions         | Dockerfile-based custom actions                  |
| [016](Labs/016-javascript-actions/README.md)       | JavaScript Actions     | @actions/core, @actions/github toolkit           |
| [017](Labs/017-permissions-security/README.md)     | Permissions & Security | GITHUB_TOKEN, minimal permissions                |
| [018](Labs/018-environments-deployments/README.md) | Environments           | Protection rules, deployment gates               |
| [019](Labs/019-concurrency/README.md)              | Concurrency            | Concurrency groups, cancel-in-progress           |
| [020](Labs/020-workflow-dispatch/README.md)        | Workflow Dispatch      | Manual triggers, parameterized inputs            |
| [021](Labs/021-dependabot/README.md)               | Dependabot             | Auto dependency updates, security alerts         |
| [022](Labs/022-github-packages/README.md)          | GitHub Packages        | Publish to GHCR, npm, Maven                      |
| [023](Labs/023-ci-pipeline/README.md)              | CI Pipeline            | Complete CI: lint, test, build, scan             |
| [024](Labs/024-cd-pipeline/README.md)              | CD Pipeline            | Complete CD: staging, production, rollback       |
| [025](Labs/025-branch-protection/README.md)        | Branch Protection      | Required checks, review rules, status badges     |
| [026](Labs/026-code-scanning/README.md)            | Code Scanning          | CodeQL analysis, SARIF, security advisories      |
| [027](Labs/027-oidc-secrets/README.md)             | OIDC & Secrets         | Keyless auth, cloud provider federation          |
| [028](Labs/028-self-hosted-runners/README.md)      | Self-Hosted Runners    | Setup, labels, runner groups, scaling            |
| [029](Labs/029-github-script/README.md)            | GitHub Script          | octokit/graphql, PR comments, issue automation   |
| [030](Labs/030-advanced-patterns/README.md)        | Advanced Patterns      | Dynamic matrices, slash commands, monorepo       |

## Quick Start

### Run with Docker

```bash
docker run -it --rm -p 3000:3000 ghcr.io/nirgeier/github-actions-labs:latest
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

### Run locally

```bash
git clone https://github.com/nirgeier/GithubActionsLabs
cd GithubActionsLabs

# Install gh CLI and act
gh auth login
act --version

# Start any lab
cd Labs/001-first-workflow
cat README.md
bash _demo.sh
```

## Prerequisites

- A GitHub account
- [gh CLI](https://cli.github.com/) installed and authenticated
- Docker (for running the containerized environment)
- Basic YAML and Git knowledge

## Structure

```
GithubActionsLabs/
├── Labs/               ← All 31 lab directories
│   ├── 000-setup/
│   │   ├── README.md   ← Lab instructions
│   │   └── _demo.sh    ← Runnable demo
│   └── ...
├── docker/             ← Docker image for the interactive environment
│   ├── Dockerfile
│   ├── server.js       ← WebSocket terminal server
│   └── public/         ← xterm.js UI
├── mkdocs/             ← MkDocs configuration components
└── tests/              ← GitHub Actions test workflows
```

---

<p align="center">
  Made with ❤️ for the DevOps community
</p>
