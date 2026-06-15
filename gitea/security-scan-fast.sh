#!/usr/bin/env bash
set -euo pipefail

# Fast security tier — meant to run frequently (e.g. hourly) from cron.
#
# Runs the two cheap, no-build scanners against every Gitea repo on disk:
#   - gitleaks : secrets (passwords, API keys, tokens) in git history
#   - grype    : known CVEs in dependencies (go.mod, package-lock.json, ...)
#
# Source analysis that needs the Go toolchain (govulncheck, gosec) lives in the
# daily tier, so this hourly run stays fast. Findings always trigger a red Slack
# alert; a clean run stays silent unless NOTIFY_ON_SUCCESS=1.

# Load shared config + helpers (sits next to this script, or in /usr/local/lib).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/security-lib.sh"
[ -f "$LIB" ] || LIB="/usr/local/lib/gitea-security/security-lib.sh"
# shellcheck disable=SC1090
source "$LIB"

require_config

# Per-run report directory, stamped with the date + hour so hourly runs do not
# overwrite each other.
STAMP=$(date +"%Y-%m-%d_%H%M")
DAY_DIR="$REPORT_DIR/fast-$STAMP"
SUMMARY="$DAY_DIR/summary.txt"
mkdir -p "$DAY_DIR"

# Runs gitleaks + grype for one repo and writes JSON reports.
# Each scanner may fail without aborting the run (|| true).
scan_repo() {
    local bare="$1"
    local wt="$2"
    local out="$3"

    # gitleaks reads the bare repo's git history directly — no worktree needed.
    gitleaks detect \
        --source="$bare" \
        --report-format json \
        --report-path "$out/gitleaks.json" \
        --no-banner || true

    # grype — dependency CVEs from the lockfiles in the tree.
    grype "dir:$wt" -o json > "$out/grype.json" || true
}

# Counts findings across the two reports for one repo.
count_findings() {
    local out="$1"
    local gitleaks_n=0
    local grype_n=0

    # gitleaks: top-level array of leaks.
    [ -f "$out/gitleaks.json" ] && gitleaks_n=$(jq 'length' "$out/gitleaks.json" 2>/dev/null || echo 0)

    # grype: matched vulnerabilities.
    [ -f "$out/grype.json" ] && grype_n=$(jq '(.matches // []) | length' "$out/grype.json" 2>/dev/null || echo 0)

    echo "$((gitleaks_n + grype_n))"
}

# ── Scan every repo ────────────────────────────────────────────────────────────
echo "[+] Fast scan starting..."
total=0
details=""

while read -r bare; do

    # Skip the loop body on an empty list.
    [ -z "$bare" ] && continue

    # Derive a label and per-repo paths.
    label=$(repo_label "$bare")
    wt="$WORK_DIR/$label"
    out="$DAY_DIR/$label"
    mkdir -p "$out"

    echo "  [*] $label"

    # Export the working tree, then scan it.
    export_worktree "$bare" "$wt"
    scan_repo "$bare" "$wt" "$out"

    # Record this repo's finding count.
    found=$(count_findings "$out")
    total=$((total + found))
    echo "$label: $found findings" >> "$SUMMARY"

    # Collect a line for the Slack alert only when this repo has findings.
    if [ "$found" -gt 0 ]; then
        details="$details"$'\n'"• $label: $found"
    fi

done <<< "$(list_bare_repos)"

# ── Summarise + notify + prune ─────────────────────────────────────────────────
echo "[+] Total findings: $total" | tee -a "$SUMMARY"

# Loud alert on any finding; otherwise stay quiet unless asked to confirm.
if [ "$total" -gt 0 ]; then
    notify_slack "alert" "🚨 Fast scan: $total findings" "Repos with findings:$details"$'\n'"Reports: $DAY_DIR"
    echo "[!] Findings — see $DAY_DIR"
elif [ "$NOTIFY_ON_SUCCESS" = "1" ]; then
    notify_slack "ok" "✅ Fast scan clean" "No secrets, code issues, or CVEs found."
fi

prune_reports
echo "[+] Reports at $DAY_DIR"
