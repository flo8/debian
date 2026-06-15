#!/usr/bin/env bash
set -euo pipefail

# Installs the scanners used by the Gitea security cron tiers and copies the
# scan scripts + shared library to fixed, root-owned paths so cron can run them
# regardless of where this repo is checked out.
#
# Scanners:
#   - gitleaks    : secrets in git history           (fast tier)
#   - grype       : dependency CVEs                    (fast tier)
#   - govulncheck : Go reachability-aware vuln scan    (daily tier)
#   - gosec       : Go SAST (insecure code patterns)   (daily tier)
#   - osv-scanner : multi-ecosystem OSV vuln scan      (daily tier)
#   - syft        : SBOM generator (grype + weekly)    (weekly tier)
#
# Every scanner is a Go program installed with `go install` — no Python. Trivy
# is intentionally NOT installed: grype covers dependency CVEs, gitleaks covers
# secrets, and gosec covers Go code — so Trivy only overlapped them. Note: gosec
# is Go-only, so JS/TS code-pattern SAST is not covered (deps still are).

# Where to put binaries, the shared lib, and the scan scripts.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="/usr/local/bin"
LIB_DIR="/usr/local/lib/gitea-security"

# Go installs its tools here when GOBIN is set; ensure the Go toolchain is found.
export GOBIN="$BIN_DIR"
export PATH="$PATH:/usr/local/go/bin"

# ── Root check ─────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "Run as root:  sudo bash gitea/security-install.sh"
    exit 1
fi

# ── Base dependencies ──────────────────────────────────────────────────────────
# curl + jq are runtime deps of the scan scripts (Slack webhook + JSON parsing).
# Everything else is a Go program, so no Python toolchain is needed.
echo "[+] Installing base dependencies..."
apt-get update
apt-get install -y \
    git curl jq ca-certificates

# ── Go-native scanners ─────────────────────────────────────────────────────────
# Every scanner is a Go program installed with `go install`; GOBIN=$BIN_DIR drops
# the binaries straight onto PATH. grype/syft report version "unknown" when built
# this way, but their DB compatibility is compiled in, so scans and
# `grype db update` work fine. Pin the versions for reproducible installs.
echo "[+] Installing Go-native scanners..."
go install github.com/gitleaks/gitleaks/v8@latest
go install github.com/anchore/grype/cmd/grype@latest
go install github.com/anchore/syft/cmd/syft@latest
go install golang.org/x/vuln/cmd/govulncheck@latest
go install github.com/securego/gosec/v2/cmd/gosec@latest
go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest

# ── Install scan scripts + shared lib ──────────────────────────────────────────
echo "[+] Installing scan scripts + library..."
mkdir -p "$LIB_DIR"
install -m 0644 "$SCRIPT_DIR/security-lib.sh"         "$LIB_DIR/security-lib.sh"
install -m 0755 "$SCRIPT_DIR/security-scan-fast.sh"   "$BIN_DIR/gitea-security-fast"
install -m 0755 "$SCRIPT_DIR/security-scan-daily.sh"  "$BIN_DIR/gitea-security-daily"
install -m 0755 "$SCRIPT_DIR/security-scan-weekly.sh" "$BIN_DIR/gitea-security-weekly"

# ── Versions ───────────────────────────────────────────────────────────────────
echo "[+] Done! Installed versions:"
gitleaks version    || true
grype version       || true
syft version        || true
govulncheck -version 2>/dev/null || true
gosec -version      2>/dev/null || true
osv-scanner --version || true
