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
VERSION="1.1.21"
USERNAME="flo"
AIR360_USER="air360"
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEjGiJLi9DlEA8h0GKTz9WtvD6P2XE9C/KHn5nKtKC2Y flo@lothlorien"
REPO_RAW="https://raw.githubusercontent.com/flo8/debian/main"

# Optional hostname override. Set via env: NEW_HOSTNAME=foo curl ... | sudo -E bash
# When empty, the script leaves the system hostname unchanged.
NEW_HOSTNAME="${NEW_HOSTNAME:-}"

# Time (UTC, HH:MM) to reboot after a security update that needs one, such as
# a new kernel. Boxes behind the same DNS name need different times so they
# never reboot together. Set via env like NEW_HOSTNAME.
REBOOT_TIME="${REBOOT_TIME:-02:00}"

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
# %-11s keeps the right border aligned for any version up to 11 chars long.
echo -e "\n\033[1;35m╔══════════════════════════════════════╗\033[0m"
printf '\033[1;35m║   INITIALIZING... version %-11s║\033[0m\n' "$VERSION"
echo -e "\033[1;35m╚══════════════════════════════════════╝\033[0m"

# ========= SYSTEM =========
log "Updating system"
apt-get update -y
apt-get dist-upgrade -y

log "Installing base packages"
apt-get install -y \
  `# Core shell / system` \
  sudo vim micro hx tmux bash-completion cron systemd-timesyncd \
  `# File / archive utilities` \
  rsync tree mc fzf bat unzip s3cmd jq sqlite3 \
  `# Version control & transfer` \
  git lazygit curl wget \
  `# System observability` \
  htop btop lsof strace sysstat ncdu duf linux-cpupower linux-perf valgrind \
  `# Compilers / dev tools` \
  build-essential clang clang-format clangd gdb pkg-config cmake \
  `# Network troubleshooting` \
  dnsutils traceroute mtr-tiny tcpdump netcat-openbsd nmap whois \
  iperf3 ipcalc arping iftop \
  `# Security / remote access` \
  ufw openssh-server

# No dstat above: on Debian 13 "dstat" is provided by pcp, which runs pmcd,
# pmlogger and a check every 30 minutes that spikes the CPU.
#
# No rsyslog either: the journal is persistent on Debian 13, rsyslog would only
# copy it to text files. Use journalctl instead of /var/log/syslog.
#
# cron recommends a mail agent, so apt pulls in the exim4 daemon. Nothing here
# reads local mail, so remove it; cron itself stays.
log "Removing the exim4 mail daemon"
apt-get purge -y exim4-base exim4-config exim4-daemon-light bsd-mailx

# man-db rebuilds its index daily (the timer) and after every apt run (the
# auto-update file). Both spike the CPU; man works without it, only apropos
# gets stale.
log "Disabling man-db index rebuilds"
systemctl mask --now man-db.timer
echo "man-db man-db/auto-update boolean false" | debconf-set-selections
rm -f /var/lib/man-db/auto-update

# ========= SECURITY UPDATES =========
# unattended-upgrades runs once a day, between 06:00 and 07:00 UTC
# (apt-daily-upgrade.timer). Security fixes only: Debian's default also
# installs point releases, which are not urgent and are upgraded by hand.
#
# A new kernel does nothing until the box reboots, so reboot at REBOOT_TIME
# when an update asks for it (/var/run/reboot-required). Without this, a
# fixed kernel can sit on disk for weeks while the old one runs.
#
# Our own file, read after 50unattended-upgrades, so the package's file stays
# untouched. ${distro_codename} is for apt to expand, not the shell.
log "Enabling daily security updates, reboot at $REBOOT_TIME UTC when needed"
[[ "$REBOOT_TIME" =~ ^[0-2][0-9]:[0-5][0-9]$ ]] || die "REBOOT_TIME must be HH:MM, got: $REBOOT_TIME"
apt-get install -y unattended-upgrades

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT

cat > /etc/apt/apt.conf.d/51unattended-upgrades-air360 <<APT
#clear Unattended-Upgrade::Origins-Pattern;
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=\${distro_codename}-security,label=Debian-Security";
};
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "$REBOOT_TIME";
APT

# Older collector boxes had the security-only part in a file of their own
rm -f /etc/apt/apt.conf.d/51unattended-upgrades-security

# ========= MPTCP =========
# Multipath TCP has had several kernel CVEs in 2026. Go 1.24+ listens with
# MPTCP by default, so our Go services accept it unless the kernel says no.
# With it off, Go falls back to plain TCP on its own.
#
# MPTCP is built into Debian's kernel, not a module, so blacklisting does
# nothing: the sysctl is the only switch.
log "Disabling MPTCP"
echo "net.mptcp.enabled = 0" > /etc/sysctl.d/90-no-mptcp.conf
sysctl -p /etc/sysctl.d/90-no-mptcp.conf

# ========= LLMNR =========
# systemd-resolved answers LLMNR name lookups on port 5355, on every
# interface. That is for finding machines on a home LAN by name; a server
# never needs it. ufw already blocks the port, this stops the listener too.
log "Disabling LLMNR in systemd-resolved"
mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nLLMNR=no\n' > /etc/systemd/resolved.conf.d/90-no-llmnr.conf
systemctl restart systemd-resolved

# ========= BAT SYMLINK =========
log "Creating bat symlink for fzf"
ln -sf /usr/bin/batcat /usr/local/bin/bat

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

# Strip leftovers from older install.sh versions that wrote a botched heredoc into
# ~/.bashrc — pattern:
#   # Display MOTD
#   [ -x /etc/update-motd.d/01-status ] && /etc/update-motd.d/01-status
#   EOF
# All MOTD printing is now handled inside ~/.config/bash/bashrc, so these lines are
# redundant at best and cause "EOF: command not found" at worst.
if [ -f "$HOME_DIR/.bashrc" ]; then
  sed -i \
    -e '/^[[:space:]]*# Display MOTD[[:space:]]*$/d' \
    -e '/^[[:space:]]*\[ -x \/etc\/update-motd\.d\/01-status \] && \/etc\/update-motd\.d\/01-status[[:space:]]*$/d' \
    -e '/^[[:space:]]*EOF[[:space:]]*$/d' \
    "$HOME_DIR/.bashrc"
fi

BASHRC_SOURCE_LINE="[ -f \"\$HOME/.config/bash/bashrc\" ] && . \"\$HOME/.config/bash/bashrc\""
grep -qxF "$BASHRC_SOURCE_LINE" "$HOME_DIR/.bashrc" 2>/dev/null || echo "$BASHRC_SOURCE_LINE" >> "$HOME_DIR/.bashrc"

chown -R "$USERNAME:$USERNAME" "$BASH_CONFIG_DIR" "$HOME_DIR/.bashrc"
echo "✔ bashrc installed"

# ========= BASH_PROFILE =========
log "Installing bash_profile"

# ~/.bash_profile is for login shells — just sources ~/.bashrc.
# All config goes in bashrc (the rule of thumb to avoid "works in one terminal but not another" issues).
fetch "$REPO_RAW/bash_profile" "$HOME_DIR/.bash_profile"
chown "$USERNAME:$USERNAME" "$HOME_DIR/.bash_profile"
echo "✔ bash_profile installed"

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

# ========= AIR360 SERVICE USER =========
log "Creating service user $AIR360_USER"

# System account: no login shell, no home directory of its own. It exists
# only to own /usr/local/air360, not to log in (it's also blocked from SSH
# by the sshd AllowGroups sshusers restriction below).
if ! id "$AIR360_USER" &>/dev/null; then
  useradd --system --no-create-home --home-dir /usr/local/air360 --shell /usr/sbin/nologin "$AIR360_USER"
fi

# The deploy Makefile (air360-live) rsyncs the binary in as $USERNAME
# directly, then sudo-chowns it to $AIR360_USER afterward — that chown only
# fixes ownership of the file rsync just wrote, it doesn't grant $USERNAME
# write access to the directory itself. Group membership does that part.
usermod -aG "$AIR360_USER" "$USERNAME"

# ========= DIRECTORY =========
log "Creating /usr/local/air360"

# 2775: setgid so anything written here (by $USERNAME over rsync, or by
# $AIR360_USER itself) lands in the air360 group automatically, group-write
# so $USERNAME's rsync can create/replace files without needing to be
# $AIR360_USER. Ownership (the user, not group) still gets fixed up by the
# deploy Makefile's sudo chown after each push.
install -d -m 2775 -o "$AIR360_USER" -g "$AIR360_USER" /usr/local/air360

# Reassert ownership on everything already inside, in case this is a re-run
# on a box where files were dropped in under a different owner.
chown -R "$AIR360_USER:$AIR360_USER" /usr/local/air360

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
PrintMotd yes
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
timedatectl set-ntp true 2>/dev/null || log "NTP not available, skipping"

# ========= TMUX =========
log "Installing tmux config"

fetch "$REPO_RAW/.tmux.conf" "$HOME_DIR/.tmux.conf"
chown "$USERNAME:$USERNAME" "$HOME_DIR/.tmux.conf"

# Pomodoro break popup, launched by the break loop in .tmux.conf.
log "Download neon-break script"

fetch "$REPO_RAW/neon-break.sh" "/usr/local/bin/neon-break"
chmod 0755 "/usr/local/bin/neon-break"
chown root:root "/usr/local/bin/neon-break"

# ========= MICRO =========
# micro is installed via apt with the base packages above; here we just deploy
# the version-controlled config.
log "Configuring micro"

MICRO_DIR="$HOME_DIR/.config/micro"
MICRO_COLORS_DIR="$MICRO_DIR/colorschemes"

# colorschemes subdir holds the custom "flo" theme referenced by settings.json.
mkdir -p "$MICRO_COLORS_DIR"

# Fetch version-controlled config: editor settings, key bindings and theme.
fetch "$REPO_RAW/micro-settings.json" "$MICRO_DIR/settings.json"
fetch "$REPO_RAW/micro-bindings.json" "$MICRO_DIR/bindings.json"
fetch "$REPO_RAW/micro-flo.micro" "$MICRO_COLORS_DIR/flo.micro"

chown -R "$USERNAME:$USERNAME" "$MICRO_DIR"

# ========= MC (MIDNIGHT COMMANDER) =========
# Set the modarin256root skin for the main user and for /etc/skel so that
# any future user created by add-sshuser inherits the same theme.
log "Configuring mc theme"

MC_DIR="$HOME_DIR/.config/mc"
SKEL_MC_DIR="/etc/skel/.config/mc"

mkdir -p "$MC_DIR" "$SKEL_MC_DIR"

fetch "$REPO_RAW/mc-ini" "$MC_DIR/ini"
fetch "$REPO_RAW/mc-ini" "$SKEL_MC_DIR/ini"

chown -R "$USERNAME:$USERNAME" "$MC_DIR"

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
fetch "$REPO_RAW/motd" "/etc/update-motd.d/01-status"

# Bake the install-time version into the motd banner so we don't have to
# keep the literal in two places in the repo.
sed -i "s|AIR360 config [^ ]*|AIR360 config $VERSION|" /etc/update-motd.d/01-status

chmod +x /etc/update-motd.d/01-status

# ========= BULLETPROOF OWNERSHIP =========
chown -R "$USERNAME:$USERNAME" "$HOME_DIR"

# ========= DONE =========
log "Firewall status"
ufw status verbose

log "✅ DONE — system ready. SSH as $USERNAME using your key."
log "Once logged in as $USERNAME, add new users with: sudo add-sshuser <username> \"<ssh-pubkey>\""
