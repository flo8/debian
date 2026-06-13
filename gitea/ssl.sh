#!/usr/bin/env bash
set -euo pipefail

DOMAIN="forge.air360hq.com"
EMAIL="flo@${DOMAIN}"
AWS_CREDS_FILE="/root/.aws/credentials"

# ── Root check ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "Run as root:  sudo bash gitea/ssl.sh"
    exit 1
fi

echo
echo "=== Certbot + Route53 Installer ==="
echo

# ── Collect AWS credentials ───────────────────────────────────────────────────
read -rp  "AWS Access Key ID:     " AWS_ACCESS_KEY_ID
read -rsp "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
echo

# ── Install certbot + Route53 plugin ─────────────────────────────────────────
apt-get update -qq
apt-get install -y -qq certbot python3-certbot-dns-route53

# ── Write AWS credentials ─────────────────────────────────────────────────────
mkdir -p /root/.aws
cat > "$AWS_CREDS_FILE" <<EOF
[default]
aws_access_key_id     = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF
chmod 600 "$AWS_CREDS_FILE"
echo "AWS credentials saved to $AWS_CREDS_FILE"

# ── Issue certificate ─────────────────────────────────────────────────────────
echo "Requesting certificate for ${DOMAIN} (DNS-01 via Route53)..."
certbot certonly \
    --dns-route53 \
    --dns-route53-propagation-seconds 30 \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$DOMAIN"

echo
echo "Certificate issued:"
ls -la /etc/letsencrypt/live/${DOMAIN}/

# ── Test renewal ──────────────────────────────────────────────────────────────
echo
echo "Testing renewal (dry run)..."
certbot renew --dry-run
echo "Renewal dry run passed."

# ── Done ──────────────────────────────────────────────────────────────────────
echo
echo "=================================="
echo " Certbot Installed"
echo "=================================="
echo
echo "Cert location:"
echo "  /etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
echo "  /etc/letsencrypt/live/${DOMAIN}/privkey.pem"
echo
echo "Auto-renewal: certbot runs via systemd timer (certbot.timer)"
echo "  systemctl status certbot.timer"
echo
echo "If Gitea is already installed, the renewal hook at"
echo "  /etc/letsencrypt/renewal-hooks/deploy/gitea-cert-reload.sh"
echo "will automatically copy new certs and restart Gitea on renewal."
echo
