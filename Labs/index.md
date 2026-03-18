# GitHub Actions Labs

A hands-on collection of labs covering all major aspects of GitHub Actions CI/CD automation.

| Lab | Topic | Description |
|-----|-------|-------------|
| [000](000-setup/README.md) | Setup | Install tools, authenticate with GitHub CLI |
| [001](001-first-workflow/README.md) | First Workflow | Hello World workflow, YAML syntax basics |
| [002](002-triggers-events/README.md) | Triggers & Events | push, pull_request, schedule, workflow_dispatch |
| [003](003-jobs-steps/README.md) | Jobs & Steps | Multi-job workflows, step dependencies |
| [004](004-runners/README.md) | Runners | GitHub-hosted vs self-hosted, runner labels |
| [005](005-env-variables/README.md) | Environment Variables | env, job env, step env, defaults |
| [006](006-secrets-contexts/README.md) | Secrets & Contexts | github, env, secrets, runner, job contexts |
| [007](007-expressions/README.md) | Expressions | ${{ }}, functions, operators |
| [008](008-conditions/README.md) | Conditions | if expressions, status checks, skipping steps |
| [009](009-matrix-strategy/README.md) | Matrix Strategy | Build matrices, include/exclude, fail-fast |
| [010](010-artifacts/README.md) | Artifacts | Upload/download artifacts, retention |
| [011](011-caching/README.md) | Caching | actions/cache, cache keys, restore keys |
| [012](012-services-containers/README.md) | Services & Containers | Docker services, container jobs |
| [013](013-reusable-workflows/README.md) | Reusable Workflows | workflow_call, inputs, outputs, secrets |
| [014](014-composite-actions/README.md) | Composite Actions | Custom composite actions with steps |
| [015](015-docker-actions/README.md) | Docker Actions | Dockerfile-based custom actions |
| [016](016-javascript-actions/README.md) | JavaScript Actions | @actions/core, @actions/github toolkit |
| [017](017-permissions-security/README.md) | Permissions & Security | GITHUB_TOKEN, minimal permissions, secret scanning |
| [018](018-environments-deployments/README.md) | Environments | Environment protection rules, deployment gates |
| [019](019-concurrency/README.md) | Concurrency | Concurrency groups, cancel-in-progress |
| [020](020-workflow-dispatch/README.md) | Workflow Dispatch | Manual triggers, inputs, workflow_dispatch |
| [021](021-dependabot/README.md) | Dependabot | Auto dependency updates, security alerts |
| [022](022-github-packages/README.md) | GitHub Packages | Publish to GHCR, npm, Maven |
| [023](023-ci-pipeline/README.md) | CI Pipeline | Complete CI: lint, test, build, scan |
| [024](024-cd-pipeline/README.md) | CD Pipeline | Complete CD: staging, production, rollback |
| [025](025-branch-protection/README.md) | Branch Protection | Required checks, review rules, status badges |
| [026](026-code-scanning/README.md) | Code Scanning | CodeQL analysis, SARIF, security advisories |
| [027](027-oidc-secrets/README.md) | OIDC & Secrets | Keyless auth, cloud provider federation |
| [028](028-self-hosted-runners/README.md) | Self-Hosted Runners | Setup, labels, runner groups, scaling |
| [029](029-github-script/README.md) | GitHub Script | octokit/graphql, PR comments, issue automation |
| [030](030-advanced-patterns/README.md) | Advanced Patterns | Composite orchestration, dynamic matrices, slash commands |
