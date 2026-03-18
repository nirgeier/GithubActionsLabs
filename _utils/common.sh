#!/bin/bash

##########################################
### Colors
##########################################

source <(curl -s https://raw.githubusercontent.com/nirgeier/labs-assets/refs/heads/main/assets/scripts/colors.sh) 2>/dev/null || true

##########################################
### Global functions
##########################################

ROOT_FOLDER=$(git rev-parse --show-toplevel)

command_exists() { command -v "$1" >/dev/null 2>&1; }

section() {
    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  $1"
    echo "────────────────────────────────────────────────────────"
}

# Wait for a GitHub Actions workflow run to complete
wait_for_run() {
    local repo="$1"
    local run_id="$2"
    echo ">>> Waiting for workflow run ${run_id}..."
    gh run watch "${run_id}" --repo "${repo}" 2>/dev/null || true
}
