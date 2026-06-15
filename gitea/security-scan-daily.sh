#!/usr/bin/env bash
set -euo pipefail

# Daily security tier — the deeper analysis that needs the Go toolchain.
#
#   - govulncheck : Go-only, but does call-graph reachability analysis, so it
#                   reports only vulnerabilities your code can actually hit
#                   (far lower noise than a plain CVE match).
#   - gosec       : Go SAST — insecure code patterns (injection, weak crypto,
#                   hardcoded credentials, unsafe file ops). Go repos only.
#   - osv-scanner : multi-ecosystem lockfile scan against Google's OSV database
#                   (Go + npm/yarn/pnpm); complements grype's different feeds.
#
# Always sends a Slack message: a red alert when something is found, or a green
# "all clean" heartbeat otherwise, so you know the scan actually ran each day.

# Load shared config + helpers.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/security-lib.sh"
[ -f "$LIB" ] || LIB="/usr/local/lib/gitea-security/security-lib.sh"
# shellcheck disable=SC1090
source "$LIB"

require_config

# Per-run report directory.
DATE=$(date +"%Y-%m-%d")
DAY_DIR="$REPORT_DIR/daily-$DATE"
SUMMARY="$DAY_DIR/summary.txt"
mkdir -p "$DAY_DIR"

# Runs govulncheck + gosec (Go repos only) + osv-scanner against one tree.
# Each tool exits non-zero when it finds something, hence the || true.
scan_repo() {
    local wt="$1"
    local out="$2"

    # govulncheck + gosec need the Go toolchain and a module; skip non-Go repos.
    if repo_has "$wt" "go.mod"; then
        ( cd "$wt" && govulncheck ./... ) > "$out/govulncheck.txt" 2>&1 || true
        ( cd "$wt" && gosec -quiet -fmt=json -out="$out/gosec.json" ./... ) || true
    fi

    # osv-scanner walks all supported lockfiles in the tree.
    osv-scanner --format json --recursive "$wt" > "$out/osv.json" 2>/dev/null || true
}

# Counts findings across the three reports for one repo.
count_findings() {
    local out="$1"
    local govuln_n=0
    local gosec_n=0
    local osv_n=0

    # govulncheck text output lists each issue as "Vulnerability #N".
    [ -f "$out/govulncheck.txt" ] && govuln_n=$(grep -c '^Vulnerability #' "$out/govulncheck.txt" 2>/dev/null || echo 0)

    # gosec: top-level Issues array.
    [ -f "$out/gosec.json" ] && gosec_n=$(jq '(.Issues // []) | length' "$out/gosec.json" 2>/dev/null || echo 0)

    # osv-scanner: sum vulnerabilities across all matched packages.
    [ -f "$out/osv.json" ] && osv_n=$(jq '[.results[]?.packages[]?.vulnerabilities | length] | add // 0' "$out/osv.json" 2>/dev/null || echo 0)

    echo "$((govuln_n + gosec_n + osv_n))"
}

# ── Scan every repo ────────────────────────────────────────────────────────────
echo "[+] Daily scan starting..."
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
    scan_repo "$wt" "$out"

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

# Daily run always reports back so the channel doubles as a heartbeat.
if [ "$total" -gt 0 ]; then
    notify_slack "alert" "🚨 Daily scan: $total vulnerabilities" "Repos with findings:$details"$'\n'"Reports: $DAY_DIR"
    echo "[!] Findings — see $DAY_DIR"
else
    notify_slack "ok" "✅ Daily scan clean" "govulncheck + gosec + osv-scanner found nothing."
fi

prune_reports
echo "[+] Reports at $DAY_DIR"
