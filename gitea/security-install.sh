#!/usr/bin/env bash
set -euo pipefail

# Installs the security scanners used by the daily codebase scan:
#   - Trivy  : CVE / secret / misconfig scanner (primary)
#   - Grype  : vulnerability scanner (secondary validation)
#   - Syft   : SBOM generator that Grype relies on
#   - Semgrep: static analysis (SAST)
# It also installs security-scan.sh to /usr/local/bin so cron can run it from a
# fixed, root-owned path (no dependency on where this repo is checked out).

# Directory this script lives in, so we can find its sibling scan script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN_DEST="/usr/local/bin/gitea-security-scan"

# ── Root check ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "Run as root:  sudo bash gitea/security-install.sh"
    exit 1
fi

# Base packages needed by the installers and the scan script.
echo "[+] Installing base dependencies..."
apt-get update
apt-get install -y \
    git curl jq ca-certificates gnupg lsb-release python3 pipx

# Trivy — installed to /usr/local/bin so cron finds it on PATH.
echo "[+] Installing Trivy..."
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
    | sh -s -- -b /usr/local/bin

# Grype — secondary vulnerability scanner.
echo "[+] Installing Grype..."
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh \
    | sh -s -- -b /usr/local/bin

# Syft — Grype's SBOM helper, kept on the same path.
echo "[+] Installing Syft..."
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
    | sh -s -- -b /usr/local/bin

# Semgrep — Debian's Python is PEP 668 "externally managed", so a plain
# `pip install` is refused. pipx installs it in an isolated venv; PIPX_BIN_DIR
# puts the launcher on /usr/local/bin so the root cron job can run it.
echo "[+] Installing Semgrep..."
export PIPX_HOME=/opt/pipx
export PIPX_BIN_DIR=/usr/local/bin
pipx install semgrep

# Install the scan script to a fixed, root-owned PATH location for cron.
echo "[+] Installing scan script to $SCAN_DEST..."
install -m 0755 "$SCRIPT_DIR/security-scan.sh" "$SCAN_DEST"

# Report the installed versions (never fail the script on these).
echo "[+] Done! Installed versions:"
trivy -v || true
grype version || true
syft version || true
semgrep --version || true
