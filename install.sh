#!/usr/bin/env bash

# Run this script with:
# sudo curl -fsSL https://raw.githubusercontent.com/flo8/debian/main/install.sh | sudo bash

set -euo pipefail

# ========= CONFIG =========
USERNAME="flo"
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEjGiJLi9DlEA8h0GKTz9WtvD6P2XE9C/KHn5nKtKC2Y flo@lothlorien"
FAIL2BAN_JAIL_URL="https://raw.githubusercontent.com/flo8/debian/main/jail.local"

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
apt-get install -y \
  micro tmux rsync cron htop rsyslog fail2ban \
  git lsof curl wget ufw

# ========= USER SETUP =========
log "Setting up user $USERNAME"

if ! id "$USERNAME" &>/dev/null; then
  useradd -m -s /bin/bash "$USERNAME"
  usermod -aG sudo "$USERNAME"
fi

HOME_DIR=$(eval echo "~$USERNAME")
SSH_DIR="$HOME_DIR/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
touch "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"
grep -qxF "$PUBKEY" "$AUTH_KEYS" || echo "$PUBKEY" >> "$AUTH_KEYS"
chown -R "$USERNAME:$USERNAME" "$SSH_DIR"

# ========= UFW =========
log "Configuring UFW"

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw limit 22/tcp
ufw logging on
ufw --force enable

# ========= FAIL2BAN =========
log "Configuring fail2ban"

curl -fsSL "$FAIL2BAN_JAIL_URL" -o /etc/fail2ban/jail.local
systemctl enable fail2ban
systemctl restart fail2ban

# ========= SSH HARDENING =========
log "Hardening SSH"

set_sshd_option "LogLevel" "INFO"
set_sshd_option "LoginGraceTime" "1m"
set_sshd_option "PermitRootLogin" "prohibit-password"
set_sshd_option "StrictModes" "yes"
set_sshd_option "MaxAuthTries" "3"
set_sshd_option "MaxSessions" "5"
set_sshd_option "PubkeyAuthentication" "yes"
set_sshd_option "PermitEmptyPasswords" "no"

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
fail2ban-client status || true

log "Installing DuckDB"

curl -fsSL https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-amd64.zip -o /tmp/duckdb.zip 
unzip -o /tmp/duckdb.zip -d /usr/local/bin/ 
chmod +x /usr/local/bin/duckdb
rm -f /tmp/duckdb.zip

log "Setting hostname"
HOSTNAME="debian"
hostnamectl set-hostname "$HOSTNAME"

log "✅ Machine secured and ready"
