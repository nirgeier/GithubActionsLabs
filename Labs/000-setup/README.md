# Lab 000 - Setup

## Introduction

- Before diving into GitHub Actions, you need the right tools installed and configured.
- This lab walks you through installing the **GitHub CLI (`gh`)**, the **`act` local runner**, creating a test repository, and verifying that your environment is ready for all subsequent labs.
- Having a properly configured environment saves time and frustration.
- The `gh` CLI lets you interact with GitHub from the terminal - managing repos, secrets, workflow runs, and more.
- The `act` tool lets you run GitHub Actions workflows locally, dramatically speeding up the feedback loop during development.

---

## Prerequisites

- macOS, Linux, or Windows (WSL2 recommended for Windows)
- Git installed and configured (`git config --global user.name` and `user.email`)
- A GitHub account
- Internet access

---

## 1. Installing the GitHub CLI (`gh`)

The GitHub CLI is the primary tool for interacting with GitHub from the command line. It supports authentication, repository management, pull requests, issues, workflow runs, secrets, and much more.

### macOS

```bash
brew install gh
```

### Linux (Debian/Ubuntu)

```bash
type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
  https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh -y
```

### Verify installation

```bash
gh --version
# Expected output: gh version 2.x.x (...)
```

---

## 2. Authenticating the GitHub CLI

```bash
gh auth login
```

Follow the interactive prompts:

1. Select `GitHub.com`
2. Select `HTTPS` as the protocol
3. Choose `Login with a web browser` or paste a token
4. Authorize in the browser

### Verify authentication

```bash
gh auth status
# Expected output:
# github.com
#   ✓ Logged in to github.com as <your-username> (...)
#   ✓ Git operations for github.com configured to use https protocol.
```

### Using a Personal Access Token (PAT)

For CI environments or headless setups:

```bash
export GH_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
gh auth status
```

Or store it permanently:

```bash
echo "ghp_xxxxxxxxxxxxxxxxxxxx" | gh auth login --with-token
```

---

## 3. Installing `act` (Local Runner)

`act` is a tool that runs GitHub Actions locally using Docker. It reads your workflow files and executes them in Docker containers that mimic the GitHub-hosted runners.

### macOS

```bash
brew install act
```

### Linux

```bash
curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

### Verify installation

```bash
act --version
# Expected output: act version 0.2.x
```

### Docker requirement

`act` requires Docker to be running:

```bash
docker info > /dev/null 2>&1 && echo "Docker is running" || echo "Docker is NOT running"
```

### First-time `act` configuration

When you run `act` for the first time, it asks which Docker image size to use:

```
? Please choose the default image you want to use with act:
  - Micro: +200MB, no Node.js
  - Medium: +500MB, includes most tools
  - Large: +17GB, matches GitHub hosted runners exactly
```

For most labs, **Medium** is sufficient.

---

## 4. Creating a Test Repository

All labs assume you have a GitHub repository to work with. Create one now:

```bash
# Create a new local repo
mkdir github-actions-test
cd github-actions-test
git init
git branch -M main

# Create the workflows directory
mkdir -p .github/workflows

# Create an initial commit
echo "# GitHub Actions Test Repo" > README.md
git add README.md
git commit -m "Initial commit"

# Create the remote repo and push
gh repo create github-actions-test \
  --public \
  --source=. \
  --remote=origin \
  --push

echo "Repository created successfully!"
```

### Verify the repository exists

```bash
gh repo view github-actions-test
```

---

## 5. Checking GitHub API Access

Verify that your token has the necessary permissions:

```bash
# Check rate limits
gh api rate_limit

# Check your user info
gh api user --jq '.login, .name, .plan.name'

# List your repos
gh repo list --limit 5
```

### Required token scopes for these labs

| Scope             | Purpose                                         |
| ----------------- | ----------------------------------------------- |
| `repo`            | Full repository access                          |
| `workflow`        | Manage GitHub Actions workflows                 |
| `read:org`        | Read organization info (for org-level features) |
| `admin:repo_hook` | Manage webhooks                                 |

Check current scopes:

```bash
gh auth status
```

---

## 6. Validating YAML Syntax

GitHub Actions workflows are YAML files. Install a YAML linter to catch syntax errors before pushing:

```bash
# Python-based YAML validator (usually pre-installed)
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml'))"

# Or install yamllint
pip install yamllint
yamllint .github/workflows/

# Or use the actionlint tool (GitHub Actions specific linter)
brew install actionlint   # macOS
# or
bash <(curl https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)
```

---

## 7. Setting Up Your Editor

### VS Code Extensions

Install these VS Code extensions for the best GitHub Actions experience:

```bash
# GitHub Actions extension (syntax highlighting, autocomplete, run history)
code --install-extension github.vscode-github-actions

# YAML extension (general YAML support)
code --install-extension redhat.vscode-yaml
```

### VS Code settings for YAML schema validation

Add to `.vscode/settings.json`:

```json
{
  "yaml.schemas": {
    "https://json.schemastore.org/github-workflow.json": ".github/workflows/*.yml"
  }
}
```

---

## 8. Directory Structure for Labs

All labs follow this structure:

```
GithubActionsLabs/
├── _utils/
│   └── common.sh          # Shared utility functions
├── Labs/
│   ├── 000-setup/
│   │   ├── README.md
│   │   └── _demo.sh
│   ├── 001-first-workflow/
│   │   ├── README.md
│   │   └── _demo.sh
│   └── ...
└── .github/
    └── workflows/
        └── ...
```

---

## Hands-on

1. Verify that `gh` is authenticated and print the currently logged-in username:

   ??? success "Solution"
   `bash
    gh auth status
    gh api user --jq '.login'
    `

2. Check the installed version of `act` and confirm Docker is running:

   ??? success "Solution"
   `bash
    act --version
    docker info > /dev/null 2>&1 && echo "Docker is running" || echo "Docker is NOT running"
    `

3. Create a `.actrc` file in your home directory that maps `ubuntu-latest` to the `catthehacker` medium image:

   ??? success "Solution"
   `bash
    cat > ~/.actrc << 'EOF'
    -P ubuntu-latest=catthehacker/ubuntu:act-latest
    -P ubuntu-22.04=catthehacker/ubuntu:act-22.04
    -P ubuntu-20.04=catthehacker/ubuntu:act-20.04
    EOF
    cat ~/.actrc
    `

4. List all installed `gh` extensions:

   ??? success "Solution"
   `bash
    gh extension list
    `

5. Validate that a YAML file is syntactically correct using `python3`:

   ??? success "Solution"
   `bash
    python3 -c "
    import yaml, sys
    path = '.github/workflows/hello.yml'
    try:
        yaml.safe_load(open(path))
        print(f'{path}: valid YAML')
    except yaml.YAMLError as e:
        print(f'Invalid YAML: {e}')
        sys.exit(1)
    "
    `

## Exercises

### Exercise 1: Verify Your Environment

Run the following and confirm each succeeds:

```bash
gh --version
act --version
docker info > /dev/null 2>&1 && echo "Docker OK"
git --version
python3 --version
```

### Exercise 2: Create a Personal Repository

```bash
gh repo create my-actions-playground \
  --public \
  --add-readme \
  --description "Learning GitHub Actions"
```

### Exercise 3: Explore the gh CLI

```bash
# List available gh commands
gh help

# Explore workflow-related commands
gh workflow --help
gh run --help
```

### Exercise 4: Check GitHub Status

```bash
# Check GitHub's API status
curl -s https://www.githubstatus.com/api/v2/status.json | python3 -m json.tool
```

### Exercise 5: Configure act

Create a `.actrc` file in your home directory:

```bash
cat > ~/.actrc << 'EOF'
-P ubuntu-latest=catthehacker/ubuntu:act-latest
-P ubuntu-22.04=catthehacker/ubuntu:act-22.04
-P ubuntu-20.04=catthehacker/ubuntu:act-20.04
EOF
```

---

## Summary

- The `gh` CLI is the primary tool for interacting with GitHub from the terminal - install it with `brew install gh` or the official package repository
- Authenticate with `gh auth login` and verify with `gh auth status` before proceeding with any lab
- The `act` tool runs GitHub Actions workflows locally using Docker, enabling fast local iteration without pushing to GitHub
- Workflows must be placed in the `.github/workflows/` directory of your repository as YAML files
- Use `python3 -c "import yaml; yaml.safe_load(...)"` or `yamllint` to validate YAML syntax before committing
- VS Code with the GitHub Actions extension provides schema validation, autocomplete, and run history directly in the editor
- Verify API access and token scopes with `gh auth status` and `gh api rate_limit` to ensure all labs will work correctly
