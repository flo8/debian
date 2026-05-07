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
# REQUIREMENTS:
# - Debian 12+ / 13
# - Root or sudo access
# - SSH key ready for user login
#
# ============================================================================

# ========= CONFIG =========
USERNAME="flo"
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEjGiJLi9DlEA8h0GKTz9WtvD6P2XE9C/KHn5nKtKC2Y flo@lothlorien"
REPO_RAW="https://raw.githubusercontent.com/flo8/debian/main"
HOSTNAME="debian"

# ========= HELPERS =========
log() {
  echo -e "\n\033[0;35m[+] $*\033[0m"
}

die() { echo -e "\n[!] ERROR: $*" >&2; exit 1; }

fetch() {
  local url="$1" dest="$2"
  curl -fsSL "$url" -o "$dest" || die "Failed to download: $url"
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Run as root"
}

require_root
export DEBIAN_FRONTEND=noninteractive

# ========= BOOT =========
echo -e "\n\033[1;35m╔══════════════════════════════════════╗\033[0m"
echo -e "\033[1;35m║   INITIALIZING... version 1.1.1      ║\033[0m"
echo -e "\033[1;35m╚══════════════════════════════════════╝\033[0m"

# ========= SYSTEM =========
log "Updating system"
apt-get update -y
apt-get dist-upgrade -y

log "Installing base packages"
apt-get install -y \
  sudo micro tmux rsync cron htop rsyslog git lsof curl wget \
  tree mc fzf bat strace ufw unzip s3cmd jq openssh-server zsh sysstat \
  bash-completion hx ncdu linux-cpupower linux-perf dnsutils duf iftop dstat

# ========= USER =========
log "Creating user $USERNAME"

if ! id "$USERNAME" &>/dev/null; then
  useradd -m -s /bin/bash "$USERNAME"
fi

HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6)
SSH_DIR="$HOME_DIR/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"

# Write key first, then lock down permissions
grep -qxF "$PUBKEY" "$AUTH_KEYS" 2>/dev/null || echo "$PUBKEY" >> "$AUTH_KEYS"

chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_KEYS"

# ========= BASHRC =========
log "Installing bashrc"

BASH_CONFIG_DIR="$HOME_DIR/.config/bash"
mkdir -p "$BASH_CONFIG_DIR"

# Get our remote bashrc
fetch "$REPO_RAW/bashrc" "$BASH_CONFIG_DIR/bashrc"

BASHRC_SOURCE_LINE="[ -f \"\$HOME/.config/bash/bashrc\" ] && . \"\$HOME/.config/bash/bashrc\""
grep -qxF "$BASHRC_SOURCE_LINE" "$HOME_DIR/.bashrc" 2>/dev/null || echo "$BASHRC_SOURCE_LINE" >> "$HOME_DIR/.bashrc"

chown -R "$USERNAME:$USERNAME" "$BASH_CONFIG_DIR" "$HOME_DIR/.bashrc"
echo "✔ bashrc installed"

# ========= SUDO (PASSWORDLESS) =========
log "Configuring passwordless sudo"

echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$USERNAME"
chmod 440 "/etc/sudoers.d/90-$USERNAME"
visudo -cf "/etc/sudoers.d/90-$USERNAME"

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

set_sshd "PermitRootLogin"               "no"
set_sshd "PubkeyAuthentication"          "yes"
set_sshd "PasswordAuthentication"        "no"
set_sshd "PermitEmptyPasswords"          "no"
set_sshd "KbdInteractiveAuthentication"  "no"   # replaces deprecated ChallengeResponseAuthentication
set_sshd "UsePAM"                        "yes"
set_sshd "StrictModes"                   "yes"
set_sshd "MaxAuthTries"                  "3"
set_sshd "MaxSessions"                   "5"
set_sshd "LoginGraceTime"               "1m"
set_sshd "LogLevel"                      "INFO"
set_sshd "X11Forwarding"                 "no"
set_sshd "AllowUsers"                    "$USERNAME"
set_sshd "ClientAliveInterval"           "300"
set_sshd "ClientAliveCountMax"           "2"

sshd -t || die "sshd config validation failed — check $SSHD"
systemctl restart ssh || systemctl restart sshd

# ========= SERVICES =========
log "Enabling services"
systemctl enable --now cron
timedatectl set-ntp true

# ========= TMUX =========
log "Installing tmux config"

fetch "$REPO_RAW/.tmux.conf" "$HOME_DIR/.tmux.conf"
chown "$USERNAME:$USERNAME" "$HOME_DIR/.tmux.conf"

# ========= MICRO =========
log "Configuring micro"

MICRO_DIR="$HOME_DIR/.config/micro"
MICRO_SETTINGS="$MICRO_DIR/settings.json"

mkdir -p "$MICRO_DIR"
# Fetch version-controlled config (recommended)
fetch "$REPO_RAW/micro-settings.json" "$MICRO_SETTINGS"
chown -R "$USERNAME:$USERNAME" "$MICRO_DIR"

# ========= HOSTNAME =========
log "Setting hostname"

hostnamectl set-hostname "$HOSTNAME"
if grep -q "^127.0.1.1" /etc/hosts; then
  sed -i "s/^127.0.1.1.*/127.0.1.1 $HOSTNAME/" /etc/hosts
else
  echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
fi

# ========= BETTER (USEFUL) MOTD =========
log "Installing MOTD..."
sudo truncate -s 0 /etc/motd
sudo mkdir -p /etc/update-motd.d
fetch "$REPO_RAW/server-motd" "/etc/update-motd.d/01-status"
sudo chmod +x /etc/update-motd.d/01-status

# ========= BULLETPROOF OWNERSHIP =========
chown -R "$USERNAME:$USERNAME" "$HOME_DIR"

# ========= DONE =========
log "Firewall status"
ufw status verbose

log "✅ DONE — system ready. SSH as $USERNAME using your key."
