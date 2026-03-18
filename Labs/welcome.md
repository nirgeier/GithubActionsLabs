# Welcome to GitHub Actions Labs

Welcome to the **GitHub Actions Labs** - an interactive, hands-on learning environment for mastering GitHub Actions CI/CD automation.

## What You Will Learn

This lab series covers **GitHub Actions from basics to advanced patterns**, including:

- Writing your first workflow and understanding YAML syntax
- Configuring triggers, events, and workflow filters
- Using runners, jobs, steps, and dependencies
- Managing environment variables, secrets, and contexts
- Building matrix strategies for cross-platform testing
- Caching dependencies and managing build artifacts
- Creating reusable workflows and custom actions
- Implementing complete CI/CD pipelines
- Security best practices: OIDC, permissions, and secret scanning
- Advanced patterns: concurrency, environments, and deployment strategies

## Lab Structure

Each lab is organized as follows:

```
Labs/
├── 000-setup/
│   ├── README.md       ← Lab instructions and explanation
│   └── _demo.sh        ← Runnable demo script
├── 001-first-workflow/
│   ├── README.md
│   └── _demo.sh
└── ...
```

## Getting Started

1. Open the terminal on the right
2. Navigate to the labs directory:
   ```bash
   cd $LABS/000-setup
   cat README.md
   ```
3. Follow the instructions in each lab's `README.md`
4. Run `bash _demo.sh` to see the concepts in action

## Prerequisites

- Basic understanding of YAML syntax
- A GitHub account (for creating repositories and running workflows)
- Familiarity with command-line basics

## Tips

- Use `gh auth login` in the terminal to authenticate with GitHub CLI
- Use `act` to run workflows locally without pushing to GitHub
- Each `_demo.sh` script is self-contained and demonstrates the lab concept

---

> **Ready to start?** Click on **Labs** in the navigation bar or proceed to [Lab 000 - Setup](000-setup/README.md).
