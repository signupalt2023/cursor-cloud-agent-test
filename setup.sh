#!/bin/bash
# This script is designed to be SOURCED in Cursor Cloud Agent environments
# Usage: source <(curl -fsSL "$CURSOR_SETUP_REPO_URL/setup.sh")

set -euo pipefail

# Validate that the repository URL is set
if [[ -z "${CURSOR_SETUP_REPO_URL:-}" ]]; then
    echo "ERROR: CURSOR_SETUP_REPO_URL environment variable not set" >&2
    echo "Please add it as a secret in Cursor Dashboard" >&2
    echo "Example: https://raw.githubusercontent.com/YOUR_USERNAME/your-repo/main" >&2
    return 1
fi

echo "[Setup] Using repository: $CURSOR_SETUP_REPO_URL"
echo "[Setup] Running GPG initialization..."

# Download and execute init-gpg.sh directly without saving to disk
if ! curl -fsSL "$CURSOR_SETUP_REPO_URL/init-gpg.sh" | bash; then
    echo "ERROR: GPG initialization failed" >&2
    return 1
fi

# Security: Clear sensitive environment variables to prevent exposure to subsequent
# commands in the Cloud agent "install" step (e.g., npm install). This protects
# against malicious dependencies.
echo "[Setup] Clearing sensitive environment variables..."
unset GPG_PRIVATE_KEY_BASE64
unset GPG_PRIVATE_KEY_PASSPHRASE
unset MY_GIT_EMAIL
unset MY_FULL_NAME

echo "[Setup] GPG configuration complete"