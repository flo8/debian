#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# AIR360 DEBIAN INSTALL SCRIPT
# ============================================================================
#
# ▶ HOW TO RUN (recommended):
#
#   curl -fsSL https://raw.githubusercontent.com/flo8/debian/main/install.sh | sudo bash
#
# OR safer (better for debugging):
#
#   curl -fsSL -o install.sh https://raw.githubusercontent.com/flo8/debian/main/install.sh
#   sudo bash install.sh
#
# ⚠️ REQUIREMENTS:
# - Debian 12+ / 13
# - Root or sudo access
# - SSH key ready for user login
#
# ===========================================================================

# ========= CONFIG =========
USERNAME="flo"
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEjGiJLi9DlEA8h0GKTz9WtvD6P2XE9C/KHn5nKtKC2Y flo@lothlorien"
HOSTNAME="debian"

# ========= HELPERS =========
log() { echo -e "\n[+] $*"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root"
    exit 1
  fi
}

require_root
export DEBIAN_FRONTEND=noninteractive

# ========= BOOT =========
echo -e "\n\033[1;35m╔══════════════════════════════════════╗\033[0m"
echo -e "\033[1;35m║   INITIALIZING... version 1.0.2      ║\033[0m"
echo -e "\033[1;35m╚══════════════════════════════════════╝\033[0m"

# ========= SYSTEM =========
log "Updating system"
apt-get update -y
apt-get dist-upgrade -y

log "Installing base packages"
apt-get install -y sudo micro tmux rsync cron htop rsyslog git lsof curl wget ufw unzip jq openssh-server

# ========= USER =========
log "Creating user $USERNAME"

if ! id "$USERNAME" &>/dev/null; then
  useradd -m -s /bin/bash "$USERNAME"
fi

HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6)
SSH_DIR="$HOME_DIR/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"
touch "$AUTH_KEYS"

chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_KEYS"

grep -qxF "$PUBKEY" "$AUTH_KEYS" || echo "$PUBKEY" >> "$AUTH_KEYS"

# ========= SUDO (NO PASSWORD - YOUR REQUIREMENT) =========
log "Configuring passwordless sudo"

echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-$USERNAME
chmod 440 /etc/sudoers.d/90-$USERNAME
visudo -cf /etc/sudoers.d/90-$USERNAME

# ========= DIRECTORY =========
log "Creating /usr/local/air360"
install -d -m 755 -o "$USERNAME" -g "$USERNAME" /usr/local/air360

# ========= UFW =========
log "Configuring firewall"

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw limit 22/tcp
ufw logging on
ufw --force enable

# ========= SSH HARDENING =========
log "Hardening SSH"

SSHD="/etc/ssh/sshd_config"

set_sshd() {
  local key="$1"
  local value="$2"

  if grep -qE "^#?\s*${key}\s+" "$SSHD"; then
    sed -i "s|^#\?\s*${key}\s\+.*|${key} ${value}|g" "$SSHD"
  else
    echo "${key} ${value}" >> "$SSHD"
  fi
}

set_sshd "PermitRootLogin" "no"
set_sshd "PubkeyAuthentication" "yes"
set_sshd "PasswordAuthentication" "no"
set_sshd "PermitEmptyPasswords" "no"
set_sshd "ChallengeResponseAuthentication" "no"
set_sshd "UsePAM" "yes"
set_sshd "StrictModes" "yes"
set_sshd "MaxAuthTries" "3"
set_sshd "MaxSessions" "5"
set_sshd "LoginGraceTime" "1m"
set_sshd "LogLevel" "INFO"
set_sshd "X11Forwarding" "no"
set_sshd "AllowUsers" "$USERNAME"

sshd -t
systemctl reload ssh || systemctl reload sshd

# ========= SERVICES =========
log "Enabling services"
systemctl enable cron
systemctl start cron
timedatectl set-ntp true

# ========= TMUX =========
log "Installing tmux config"

curl -fsSL https://raw.githubusercontent.com/flo8/debian/main/.tmux.conf \
  -o "$HOME_DIR/.tmux.conf"

chown "$USERNAME:$USERNAME" "$HOME_DIR/.tmux.conf"

# ========= SHELL =========
echo "alias ls='ls --color=auto'" >> "$HOME_DIR/.bashrc"
chown "$USERNAME:$USERNAME" "$HOME_DIR/.bashrc"

# ========= HOSTNAME =========
log "Setting hostname"

hostnamectl set-hostname "$HOSTNAME"
sed -i "s/127.0.1.1.*/127.0.1.1 $HOSTNAME/" /etc/hosts || true

# ========= DONE =========
log "Final check"
ufw status verbose || true

log "✅ DONE - system ready"
