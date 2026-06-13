#!/usr/bin/env bash
set -euo pipefail

DOMAIN="forge.air360hq.com"
GITEA_DIR="/srv/gitea"
PEM_FILE="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
KEY_FILE="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
ADMIN_USER="flo"
ADMIN_EMAIL="flo@${DOMAIN}"
ADMIN_PASS="changeit"

# ── Root check ──────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "Run as root:  sudo bash install-gitea.sh"
    exit 1
fi

echo
echo "=== Gitea Auto Installer ==="
echo

# ── Cert check ───────────────────────────────────────────────────────────────
[ -f "$PEM_FILE" ] || { echo "ERROR: PEM not found at $PEM_FILE"; exit 1; }
[ -f "$KEY_FILE" ] || { echo "ERROR: Key not found at $KEY_FILE"; exit 1; }

# ── Copy certs ───────────────────────────────────────────────────────────────
mkdir -p "$GITEA_DIR/certs"
cp "$PEM_FILE" "$GITEA_DIR/certs/fullchain.pem"
cp "$KEY_FILE"  "$GITEA_DIR/certs/privkey.pem"
chmod 644 "$GITEA_DIR/certs/fullchain.pem"
chmod 644 "$GITEA_DIR/certs/privkey.pem"

# ── Detect distro for Docker repo ────────────────────────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO="${ID}"
    CODENAME="${VERSION_CODENAME}"
else
    echo "ERROR: Cannot detect OS"
    exit 1
fi

if [[ "$DISTRO" != "ubuntu" && "$DISTRO" != "debian" ]]; then
    echo "ERROR: Only Ubuntu/Debian supported by this script"
    exit 1
fi

# ── Install Docker ────────────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg

mkdir -p /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL "https://download.docker.com/linux/${DISTRO}/gpg" \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${DISTRO} ${CODENAME} stable
EOF

apt-get update -qq
apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

systemctl enable docker
systemctl start docker

# ── Open firewall (ufw if present) ───────────────────────────────────────────
if command -v ufw &>/dev/null; then
    ufw allow 443/tcp  comment "Gitea HTTPS"
    ufw allow 2222/tcp comment "Gitea SSH"
    echo "ufw rules added for 443 and 2222"
fi

# ── Write docker-compose.yml ─────────────────────────────────────────────────
mkdir -p "$GITEA_DIR"
cat > "$GITEA_DIR/docker-compose.yml" <<EOF
services:
  gitea:
    image: docker.gitea.com/gitea:1
    container_name: gitea
    restart: unless-stopped
    ports:
      - "443:3000"
      - "2222:2222"
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=sqlite3
      - GITEA__database__PATH=/data/gitea/gitea.db
      - GITEA__server__PROTOCOL=https
      - GITEA__server__HTTP_PORT=3000
      - GITEA__server__DOMAIN=${DOMAIN}
      - GITEA__server__ROOT_URL=https://${DOMAIN}/
      - GITEA__server__CERT_FILE=/certs/fullchain.pem
      - GITEA__server__KEY_FILE=/certs/privkey.pem
      - GITEA__server__START_SSH_SERVER=true
      - GITEA__server__SSH_DOMAIN=${DOMAIN}
      - GITEA__server__SSH_PORT=2222
      - GITEA__server__SSH_LISTEN_PORT=2222
      - GITEA__service__DISABLE_REGISTRATION=true
    volumes:
      - gitea_data:/data
      - ./certs:/certs:ro

volumes:
  gitea_data:
EOF

# ── Start Gitea ───────────────────────────────────────────────────────────────
cd "$GITEA_DIR"
docker compose pull
docker compose up -d

# ── Wait for Gitea to respond on HTTPS (up to 60 s) ──────────────────────────
echo -n "Waiting for Gitea to be ready"
READY=0
for i in $(seq 1 12); do
    if docker exec gitea curl -sk https://localhost:3000 &>/dev/null; then
        echo " ready!"
        READY=1
        break
    fi
    echo -n "."
    sleep 5
done
[ "$READY" -eq 1 ] || { echo; echo "ERROR: Gitea did not start in time. Check: docker logs gitea"; exit 1; }

# ── Run install wizard ────────────────────────────────────────────────────────
echo "Running install wizard..."
docker exec gitea curl -sk -o /dev/null -X POST https://localhost:3000 \
    --data "db_type=sqlite3&db_path=/data/gitea/gitea.db&app_name=Gitea&repo_root_path=/data/gitea/repositories&run_user=git&domain=${DOMAIN}&ssh_port=2222&http_port=3000&app_url=https://${DOMAIN}/&log_root_path=/data/gitea/log"

# ── Restart so Gitea switches from install mode to running mode ───────────────
echo "Restarting Gitea..."
docker restart gitea

# ── Wait for Gitea to come back up ───────────────────────────────────────────
echo -n "Waiting for Gitea to reload"
READY=0
for i in $(seq 1 12); do
    sleep 5
    if docker exec gitea curl -sk https://localhost:3000 &>/dev/null; then
        echo " ready!"
        READY=1
        break
    fi
    echo -n "."
done
[ "$READY" -eq 1 ] || { echo; echo "ERROR: Gitea did not come back after restart. Check: docker logs gitea"; exit 1; }

# ── Create first admin user ───────────────────────────────────────────────────
echo "Creating admin user '${ADMIN_USER}'..."
docker exec -u git gitea \
    gitea admin user create \
    --username "$ADMIN_USER" \
    --password "$ADMIN_PASS" \
    --email    "$ADMIN_EMAIL" \
    --admin \
    --must-change-password=true

echo "Admin user '${ADMIN_USER}' created (password: ${ADMIN_PASS} — change on first login)."

# ── Cert renewal hook ─────────────────────────────────────────────────────────
HOOK="/etc/letsencrypt/renewal-hooks/deploy/gitea-cert-reload.sh"
cat > "$HOOK" <<'HOOK_EOF'
#!/usr/bin/env bash
set -euo pipefail
DOMAIN="forge.air360hq.com"
GITEA_DIR="/srv/gitea"
cp "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" "$GITEA_DIR/certs/fullchain.pem"
cp "/etc/letsencrypt/live/${DOMAIN}/privkey.pem"   "$GITEA_DIR/certs/privkey.pem"
chmod 644 "$GITEA_DIR/certs/fullchain.pem"
chmod 644 "$GITEA_DIR/certs/privkey.pem"
docker exec gitea kill -HUP 1 2>/dev/null || docker restart gitea
HOOK_EOF
chmod +x "$HOOK"
echo "Cert auto-renewal hook installed at $HOOK"

# ── Done ──────────────────────────────────────────────────────────────────────
echo
echo "=================================="
echo " Gitea Installed"
echo "=================================="
echo
echo "Web:    https://${DOMAIN}"
echo "SSH:    ssh -p 2222 git@${DOMAIN}"
echo "Clone:  git clone ssh://git@${DOMAIN}:2222/USER/REPO.git"
echo
echo "Login:  ${ADMIN_USER} / ${ADMIN_PASS}  (you will be forced to change this)"
echo
echo "Logs:   docker logs -f gitea"
echo
