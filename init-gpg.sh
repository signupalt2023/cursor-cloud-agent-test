#!/bin/bash
set -euo pipefail

# Safety check: Only run in Cursor Cloud Agent environments
# Set IS_RUNNING_CURSOR_CLOUD_AGENT=1 as a secret in Cursor Dashboard
if [[ -z "${IS_RUNNING_CURSOR_CLOUD_AGENT:-}" ]]; then
    echo "WARNING: This script is designed for Cursor Cloud Agents only." >&2
    echo "Skipping GPG setup to avoid breaking your local configuration." >&2
    echo "To enable: Add IS_RUNNING_CURSOR_CLOUD_AGENT=1 as a secret in Cursor Dashboard" >&2
    exit 0
fi

# Required environment variables (from Cursor Secrets)
: "${GPG_PRIVATE_KEY_BASE64:?Error: GPG_PRIVATE_KEY_BASE64 not set in Cursor Secrets}"
: "${GPG_PRIVATE_KEY_PASSPHRASE:?Error: GPG_PRIVATE_KEY_PASSPHRASE not set in Cursor Secrets}"
: "${MY_GIT_EMAIL:?Error: MY_GIT_EMAIL not set in Cursor Secrets}"
: "${MY_FULL_NAME:?Error: MY_FULL_NAME not set in Cursor Secrets}"

echo "Setting up GPG signing for $MY_FULL_NAME..."

# Initialize GPG home with proper permissions
export GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg}"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"

# Configure gpg-agent for non-interactive operation
cat > "$GNUPGHOME/gpg-agent.conf" <<EOF
allow-preset-passphrase
allow-loopback-pinentry
default-cache-ttl 28800
max-cache-ttl 86400
EOF

# Start/reload agent to apply config
gpgconf --kill gpg-agent 2>/dev/null || true
gpgconf --launch gpg-agent

# Decode and import private key (base64 -> ASCII-armored GPG key)
echo "$GPG_PRIVATE_KEY_BASE64" | base64 -d | gpg --batch --import 2>/dev/null

# Get keygrip and fingerprint for the imported key
KEY_INFO=$(gpg --with-colons --with-keygrip --list-secret-keys "$MY_GIT_EMAIL" 2>/dev/null)
KEYGRIP=$(echo "$KEY_INFO" | awk -F: '/^grp:/ {print $10; exit}')
FINGERPRINT=$(echo "$KEY_INFO" | awk -F: '/^fpr:/ {print $10; exit}')

if [[ -z "$KEYGRIP" ]] || [[ -z "$FINGERPRINT" ]]; then
    echo "Error: Failed to extract keygrip or fingerprint for $MY_GIT_EMAIL" >&2
    echo "Available keys:" >&2
    gpg --list-secret-keys >&2
    exit 1
fi

# Find and use gpg-preset-passphrase (Ubuntu typically has it in /usr/lib/gnupg)
GPG_PRESET=""
for preset_path in \
    "/usr/lib/gnupg/gpg-preset-passphrase" \
    "/usr/lib/gnupg2/gpg-preset-passphrase" \
    "/usr/libexec/gpg-preset-passphrase" \
    "$(command -v gpg-preset-passphrase 2>/dev/null || echo '')"; do
    if [[ -x "$preset_path" ]]; then
        GPG_PRESET="$preset_path"
        break
    fi
done

if [[ -z "$GPG_PRESET" ]]; then
    echo "Error: gpg-preset-passphrase not found. Installing gnupg2..." >&2
    sudo apt-get update && sudo apt-get install -y gnupg2
    GPG_PRESET="/usr/lib/gnupg/gpg-preset-passphrase"
fi

# Preset the passphrase into gpg-agent cache
printf '%s' "$GPG_PRIVATE_KEY_PASSPHRASE" | "$GPG_PRESET" --preset "$KEYGRIP"

# Configure Git globally for automatic signing
git config --global user.name "$MY_FULL_NAME"
git config --global user.email "$MY_GIT_EMAIL"
git config --global user.signingkey "$FINGERPRINT"
git config --global commit.gpgsign true
git config --global gpg.program "gpg"

# Verification - fail fast if signing doesn't work
if echo "test" | gpg --batch --yes --pinentry-mode loopback \
    --local-user "$FINGERPRINT" --clearsign >/dev/null 2>&1; then
    echo "[OK] GPG signing configured successfully"
    echo "  Name: $MY_FULL_NAME"
    echo "  Email: $MY_GIT_EMAIL"
    echo "  Fingerprint: $FINGERPRINT"
else
    echo "ERROR: GPG signing verification failed!" >&2
    echo "Debugging information:" >&2
    gpg --list-secret-keys "$MY_GIT_EMAIL" >&2
    echo "" >&2
    echo "Attempting test signature with verbose output:" >&2
    echo "test" | gpg --batch --yes --pinentry-mode loopback \
        --local-user "$FINGERPRINT" --clearsign 2>&2 || true
    exit 1
fi