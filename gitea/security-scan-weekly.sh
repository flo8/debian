#!/usr/bin/env bash
set -euo pipefail

# Weekly security tier — rebuild each repo's SBOM and review dependency changes.
#
#   - syft : generates a CycloneDX SBOM (the component inventory grype/osv use).
#   - diff : compares this week's component list against last week's, so newly
#            introduced dependencies are easy to review.
#
# SBOMs are kept under $BASE_DIR/sbom/<repo>/ across runs (current + previous)
# so the week-over-week diff has something to compare against.

# Load shared config + helpers.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/security-lib.sh"
[ -f "$LIB" ] || LIB="/usr/local/lib/gitea-security/security-lib.sh"
# shellcheck disable=SC1090
source "$LIB"

require_config

# Per-run report dir for the human-readable dependency-change summary.
DATE=$(date +"%Y-%m-%d")
DAY_DIR="$REPORT_DIR/weekly-$DATE"
SUMMARY="$DAY_DIR/summary.txt"
mkdir -p "$DAY_DIR"

# Persistent SBOM store (survives across weeks; not pruned with the reports).
SBOM_DIR="$BASE_DIR/sbom"

# Rebuilds the SBOM for one working tree, rotating last week's into previous.
build_sbom() {
    local wt="$1"
    local store="$2"

    mkdir -p "$store"

    # Rotate: this run's "current" becomes the baseline we diff against.
    [ -f "$store/current.cdx.json" ] && mv "$store/current.cdx.json" "$store/previous.cdx.json"

    # Generate the fresh SBOM in CycloneDX JSON.
    syft "dir:$wt" -o cyclonedx-json > "$store/current.cdx.json" 2>/dev/null || true
}

# Extracts a sorted "name@version" component list from a CycloneDX SBOM file.
component_list() {
    local sbom="$1"

    [ -f "$sbom" ] || return 0
    jq -r '.components[]? | "\(.name)@\(.version)"' "$sbom" 2>/dev/null | sort -u
}

# Writes the added/removed dependencies for one repo and echoes the added count.
diff_sbom() {
    local store="$1"
    local out="$2"
    local added

    # comm -13 lists lines only in the new list (i.e. added dependencies).
    added=$(comm -13 \
        <(component_list "$store/previous.cdx.json") \
        <(component_list "$store/current.cdx.json"))

    # Record the added dependencies for this repo's report.
    if [ -n "$added" ]; then
        echo "$added" > "$out/new-deps.txt"
    fi

    # Echo how many were added so the caller can total + alert.
    echo "$added" | grep -c . || echo 0
}

# ── Rebuild + diff every repo ──────────────────────────────────────────────────
echo "[+] Weekly SBOM rebuild starting..."
total_new=0
details=""

while read -r bare; do

    # Skip the loop body on an empty list.
    [ -z "$bare" ] && continue

    # Derive a label and per-repo paths.
    label=$(repo_label "$bare")
    wt="$WORK_DIR/$label"
    out="$DAY_DIR/$label"
    store="$SBOM_DIR/$label"
    mkdir -p "$out"

    echo "  [*] $label"

    # Export the tree, rebuild its SBOM, then diff against last week.
    export_worktree "$bare" "$wt"
    build_sbom "$wt" "$store"
    new=$(diff_sbom "$store" "$out")

    total_new=$((total_new + new))
    echo "$label: $new new dependencies" >> "$SUMMARY"

    # Collect a line for Slack only when this repo gained dependencies.
    if [ "$new" -gt 0 ]; then
        details="$details"$'\n'"• $label: $new new"
    fi

done <<< "$(list_bare_repos)"

# ── Summarise + notify + prune ─────────────────────────────────────────────────
echo "[+] Total new dependencies this week: $total_new" | tee -a "$SUMMARY"

# Weekly run always reports: a dependency-change digest, or an all-quiet note.
if [ "$total_new" -gt 0 ]; then
    notify_slack "ok" "📦 Weekly SBOM: $total_new new dependencies" "Review these:$details"$'\n'"Details: $DAY_DIR"
else
    notify_slack "ok" "📦 Weekly SBOM rebuilt" "No new dependencies since last week."
fi

prune_reports
echo "[+] SBOMs at $SBOM_DIR, report at $DAY_DIR"
