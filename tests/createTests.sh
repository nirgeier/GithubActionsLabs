#!/bin/bash

###
### This script will create the tests for this repository
###

set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
LABS_FOLDER="$ROOT_FOLDER/Labs/"

if command -v gsed >/dev/null 2>&1; then SED=gsed; else SED=sed; fi

mkdir -p "$ROOT_FOLDER/.github/workflows"

mapfile -t LABS < <(find "$ROOT_FOLDER/Labs" -mindepth 1 -maxdepth 1 -type d | sort)

labsStatus="$ROOT_FOLDER/tests/README.md"

cat >"$labsStatus" <<'HEADER'
# GitHub Actions Labs - Build Status

| Lab | Build Status |
| --- | ------------ |
HEADER

# ── Workflow generation ───────────────────────────────────────────────────────
DEMO_FILES=$(find "$LABS_FOLDER" -name '_demo.sh' | sort)

for file in $DEMO_FILES; do
    labPath=$(basename "$(dirname "$file")")
    labId="$labPath"
    workflowName="Lab-${labId:0:3}.yaml"

    $SED -e "s|<LAB_ID>|${workflowName}|g" \
        -e "s|<LAB_PATH>|Labs/${labPath}|g" \
        "${ROOT_FOLDER}/tests/test-template.yaml" \
        >"${ROOT_FOLDER}/.github/workflows/${labId}.yaml"

    echo "  Generated: .github/workflows/${labId}.yaml"

    echo "| [${labId}](https://nirgeier.github.io/GithubActionsLabs/${labPath}/) | [![${labId}](https://github.com/nirgeier/GithubActionsLabs/actions/workflows/${labId}.yaml/badge.svg)](https://github.com/nirgeier/GithubActionsLabs/actions/workflows/${labId}.yaml) |" \
        >>"$labsStatus"
done

echo ""
echo "Done. Workflows written to .github/workflows/"
echo "Build status table written to tests/README.md"
