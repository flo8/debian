#!/usr/bin/env bash
set -euo pipefail

USERNAME="flo"
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEjGiJLi9DlEA8h0GKTz9WtvD6P2XE9C/KHn5nKtKC2Y flo@lothlorien"

# 1. Create user if it doesn't exist
if ! id "$USERNAME" &>/dev/null; then
    echo "Creating user $USERNAME"
    useradd -m -s /bin/bash "$USERNAME"
fi

HOME_DIR=$(eval echo "~$USERNAME")
SSH_DIR="$HOME_DIR/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

# 2. Create .ssh directory if needed
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# 3. Create authorized_keys if needed
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

# 4. Add key if not already present
if ! grep -qxF "$PUBKEY" "$AUTH_KEYS"; then
    echo "Adding public key"
    echo "$PUBKEY" >> "$AUTH_KEYS"
else
    echo "Key already present"
fi

# 5. Fix ownership
chown -R "$USERNAME:$USERNAME" "$SSH_DIR"

echo "Done."
