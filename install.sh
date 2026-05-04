#!/usr/bin/env bash

# Run this script with:
# curl -fsSL https://raw.githubusercontent.com/flo8/debian/main/install.sh | sudo bash

set -euo pipefail

# ========= CONFIG =========
USERNAME="flo"
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEjGiJLi9DlEA8h0GKTz9WtvD6P2XE9C/KHn5nKtKC2Y flo@lothlorien"
HOSTNAME="debian"

# ========= HELPERS =========
log() { echo -e "\n[+] $*"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root (use sudo)"
    exit 1
  fi
}

append_if_missing() {
  local line="$1"
  local file="$2"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

set_sshd_option() {
  local key="$1"
  local value="$2"
  local file="/etc/ssh/sshd_config"

  if grep -qE "^#?\s*${key}\s+" "$file"; then
    sed -i "s|^#\?\s*${key}\s\+.*|${key} ${value}|g" "$file"
  else
    echo "${key} ${value}" >> "$file"
  fi
}

# ========= START =========
require_root

export DEBIAN_FRONTEND=noninteractive

log "Configuring apt"
mkdir -p /etc/apt/apt.conf.d
cat > /etc/apt/apt.conf.d/90forceconf <<EOF
Dpkg::Options {
 "--force-confdef";
 "--force-confold";
};
EOF

log "Updating & upgrading system"
apt-get update -y
apt-get dist-upgrade -y

log "Installing base packages"
apt-get install -y micro tmux rsync cron htop rsyslog git lsof curl wget ufw unzip

# ========= USER SETUP =========
log "Setting up user $USERNAME"

if ! id "$USERNAME" &>/dev/null; then
  useradd -m -s /bin/bash "$USERNAME"
fi

if ! id -nG "$USERNAME" | grep -qw sudo; then
  usermod -aG sudo "$USERNAME"
fi

HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6)
SSH_DIR="$HOME_DIR/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"
chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"

touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

grep -qxF "$PUBKEY" "$AUTH_KEYS" || echo "$PUBKEY" >> "$AUTH_KEYS"

# Air360 directory
log "Creating /usr/local/air360 directory"
install -d -m 755 -o "$USERNAME" -g "$USERNAME" /usr/local/air360

# ========= UFW =========
log "Configuring UFW"

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw limit 22/tcp
ufw logging on
ufw --force enable

# ========= SSH HARDENING =========
log "Hardening SSH"

set_sshd_option "LogLevel" "INFO"
set_sshd_option "LoginGraceTime" "1m"
set_sshd_option "PermitRootLogin" "no"
set_sshd_option "StrictModes" "yes"
set_sshd_option "MaxAuthTries" "3"
set_sshd_option "MaxSessions" "5"
set_sshd_option "PubkeyAuthentication" "yes"
set_sshd_option "PasswordAuthentication" "no"
set_sshd_option "PermitEmptyPasswords" "no"
set_sshd_option "ChallengeResponseAuthentication" "no"
set_sshd_option "UsePAM" "yes"
set_sshd_option "X11Forwarding" "no"

# Allow our user to SSH
if [ -n "$USERNAME" ]; then
  set_sshd_option "AllowUsers" "$USERNAME"
fi

sshd -t
systemctl reload ssh || systemctl reload sshd

# ========= MISC =========
log "Installing tmux config"

curl -fsSL https://raw.githubusercontent.com/flo8/debian/main/.tmux.conf -o "$HOME_DIR/.tmux.conf"
chown "$USERNAME:$USERNAME" "$HOME_DIR/.tmux.conf"

log "Enable cron"
systemctl enable cron
systemctl start cron

log "Enable NTP"
timedatectl set-ntp true

log "Add bash alias"
append_if_missing "alias ls='ls --color=auto'" "$HOME_DIR/.bashrc"
chown "$USERNAME:$USERNAME" "$HOME_DIR/.bashrc"

log "Final checks"
ufw status verbose || true

log "Setting hostname"
hostnamectl set-hostname "$HOSTNAME"
sed -i "s/127.0.1.1.*/127.0.1.1 $HOSTNAME/" /etc/hosts || true

log "✅ Machine secured and ready"
