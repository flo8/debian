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
# - Debian 13 (trixie)
# - Root or sudo access
# - SSH key ready for user login
#
# ============================================================================

# ========= CONFIG =========
USERNAME="flo"
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEjGiJLi9DlEA8h0GKTz9WtvD6P2XE9C/KHn5nKtKC2Y flo@lothlorien"
REPO_RAW="https://raw.githubusercontent.com/flo8/debian/main"

# Optional hostname override. Set via env: NEW_HOSTNAME=foo curl ... | sudo -E bash
# When empty, the script leaves the system hostname unchanged.
NEW_HOSTNAME="${NEW_HOSTNAME:-}"

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
echo -e "\033[1;35m║   INITIALIZING... version 1.1.2      ║\033[0m"
echo -e "\033[1;35m╚══════════════════════════════════════╝\033[0m"

# ========= SYSTEM =========
log "Updating system"
apt-get update -y
apt-get dist-upgrade -y

log "Installing base packages"
apt-get install -y \
  sudo vim micro tmux rsync cron htop rsyslog git lsof curl wget \
  tree mc fzf bat strace ufw unzip s3cmd jq openssh-server sysstat \
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

# ========= SSH USERS GROUP =========
log "Setting up sshusers group"

# Create group if it doesn't exist
getent group sshusers >/dev/null || groupadd sshusers

# Add main user
usermod -aG sshusers "$USERNAME"

# Check
id -nG "$USERNAME" | grep -qw sshusers || die "User not in sshusers group"

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

# ========= INPUTRC =========
log "Installing inputrc"

# Get our remote inputrc
fetch "$REPO_RAW/inputrc" "$HOME_DIR/.inputrc"
chown "$USERNAME:$USERNAME" "$HOME_DIR/.inputrc"
echo "✔ inputrc installed"

# ========= SCRIPT TO ADD NEW USERS =========
# Installed as /usr/local/bin/add-sshuser:
# - Avoids the name clash with Debian's system /usr/sbin/adduser.
# - /usr/local/bin is in sudo's default secure_path, so `sudo add-sshuser ...` works.
log "Download add-sshuser script"

fetch "$REPO_RAW/add-sshuser.sh" "/usr/local/bin/add-sshuser"
chmod 0755 "/usr/local/bin/add-sshuser"
chown root:root "/usr/local/bin/add-sshuser"

# ========= SUDO (PASSWORDLESS) =========
log "Configuring passwordless sudo"

echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$USERNAME"
chmod 440 "/etc/sudoers.d/90-$USERNAME"
visudo -cf "/etc/sudoers.d/90-$USERNAME"

# ========= DIRECTORY =========
log "Creating /usr/local/air360"
install -d -m 755 -o "$USERNAME" -g "$USERNAME" /usr/local/air360

# ========= UFW =========
# Configure firewall BEFORE touching sshd so that, if the sshd restart goes
# sideways, the box is at least in a known firewall state with port 22 open.
log "Configuring firewall"

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw limit 22/tcp
ufw logging on
ufw --force enable

# ========= SSH HARDENING =========
# On Debian 13, /etc/ssh/sshd_config ends with `Include /etc/ssh/sshd_config.d/*.conf`,
# and OpenSSH applies first-match-wins for most directives. Cloud images often
# ship /etc/ssh/sshd_config.d/50-cloud-init.conf with PasswordAuthentication yes,
# which would silently override edits to the main file.
#
# We drop a 01-* file so it loads BEFORE any 50-cloud-init.conf and wins.
log "Hardening SSH (drop-in: /etc/ssh/sshd_config.d/01-hardening.conf)"

SSHD_DROPIN="/etc/ssh/sshd_config.d/01-hardening.conf"
SSHD_TMP="$(mktemp)"

cat > "$SSHD_TMP" <<'EOF'
# Managed by install.sh — do not edit by hand.
# Loaded ahead of cloud-init drop-ins so first-match-wins favors these values.

PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication no
UsePAM yes
StrictModes yes
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 1m
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
AllowGroups sshusers
EOF

# sshd -t validates the full config (main file + includes), so we must place
# the drop-in first. If validation fails, remove the bad drop-in immediately
# so the live SSH config stays clean.
mkdir -p /etc/ssh/sshd_config.d
install -m 0644 -o root -g root "$SSHD_TMP" "$SSHD_DROPIN"
rm -f "$SSHD_TMP"

if ! sshd -t; then
  rm -f "$SSHD_DROPIN"
  die "sshd config validation failed — drop-in removed, live config untouched"
fi

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
# Only touch the hostname when explicitly asked. Avoids every server
# in a fleet ending up named "debian".
if [ -n "$NEW_HOSTNAME" ]; then
  log "Setting hostname to $NEW_HOSTNAME"

  hostnamectl set-hostname "$NEW_HOSTNAME"
  if grep -q "^127.0.1.1" /etc/hosts; then
    sed -i "s/^127.0.1.1.*/127.0.1.1 $NEW_HOSTNAME/" /etc/hosts
  else
    echo "127.0.1.1 $NEW_HOSTNAME" >> /etc/hosts
  fi
else
  log "Skipping hostname change (NEW_HOSTNAME not set)"
fi

# ========= BETTER (USEFUL) MOTD =========
log "Installing MOTD..."
truncate -s 0 /etc/motd
mkdir -p /etc/update-motd.d
fetch "$REPO_RAW/server-motd" "/etc/update-motd.d/01-status"
chmod +x /etc/update-motd.d/01-status

# ========= BULLETPROOF OWNERSHIP =========
chown -R "$USERNAME:$USERNAME" "$HOME_DIR"

# ========= DONE =========
log "Firewall status"
ufw status verbose

log "✅ DONE — system ready. SSH as $USERNAME using your key."
log "Once logged in as $USERNAME, add new users with: sudo add-sshuser <username> \"<ssh-pubkey>\""
