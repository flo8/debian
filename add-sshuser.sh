#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# ADD-SSHUSER — create a user, add key, join sshusers group
# =========================================================
#
# Creates a Linux user (if not existing), adds it to the
# "sshusers" group, and installs the provided SSH public key.
#
# Named "add-sshuser" (not "adduser") to avoid shadowing
# Debian's system /usr/sbin/adduser tool.
#
# ---------------------------------------------------------
# USAGE:
#
#   sudo add-sshuser <username> "<ssh_public_key>"
#
# EXAMPLE:
#
#   sudo add-sshuser flo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
#
# NOTES:
# - Installed by install.sh as /usr/local/bin/add-sshuser
#   (which is in sudo's default secure_path).
# - Must be run as root (or via sudo).
# - Ensures sshusers group exists.
# - Safe to re-run (idempotent behavior for keys).
#
# =========================================================

die() {
  echo "[!] $*" >&2
  exit 1
}

log() {
  echo "[+] $*"
}

# -------- args --------
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <username> <ssh_public_key>"
  exit 1
fi

USERNAME="$1"
PUBKEY="$2"

# -------- must be root --------
[[ "$(id -u)" -eq 0 ]] || die "Run as root"

# -------- ensure group exists --------
if ! getent group sshusers >/dev/null; then
  log "Creating group sshusers"
  groupadd sshusers
fi

# -------- create user if needed --------
if ! id "$USERNAME" &>/dev/null; then
  log "Creating user $USERNAME"
  useradd -m -s /bin/bash "$USERNAME"
else
  log "User $USERNAME already exists"
fi

# -------- add to sshusers group --------
log "Adding $USERNAME to sshusers"
usermod -aG sshusers "$USERNAME"

# -------- setup SSH directory --------
HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6)
SSH_DIR="$HOME_DIR/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"

# add key (avoid duplicates)
grep -qxF "$PUBKEY" "$AUTH_KEYS" 2>/dev/null || echo "$PUBKEY" >> "$AUTH_KEYS"

# permissions
chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_KEYS"

# -------- verify --------
if ! id -nG "$USERNAME" | tr ' ' '\n' | grep -qx sshusers; then
  die "User not in sshusers group (something failed)"
fi

log "Done ✔ user $USERNAME created and SSH configured"
