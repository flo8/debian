#!/usr/bin/env bash
set -euo pipefail

# Daily security scan of every repository hosted in Gitea.
# Clones/refreshes each repo's working tree, runs Trivy + Grype + Semgrep, and
# writes JSON reports plus a summary under $REPORT_DIR/<date>/.
# Intended to run from cron. See security-scan.env.example for configuration.

# ── Config ───────────────────────────────────────────────────────────────────
# Secrets (GITEA_TOKEN, ORG) are read from this env file when present so they
# are never committed to the repo. Keep it root-owned: chmod 600.
ENV_FILE="/etc/gitea-security.env"

# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

# Defaults — override any of these in $ENV_FILE.
GITEA_URL="${GITEA_URL:-http://127.0.0.1:3000}"
GITEA_TOKEN="${GITEA_TOKEN:-}"
ORG="${ORG:-}"
BASE_DIR="${BASE_DIR:-/srv/gitea-security}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

REPO_DIR="$BASE_DIR/repos"
REPORT_DIR="$BASE_DIR/reports"
DATE=$(date +"%Y-%m-%d")
DAY_DIR="$REPORT_DIR/$DATE"
SUMMARY="$DAY_DIR/summary.txt"

# Authenticate git over HTTP without persisting the token into .git/config.
GIT_AUTH=(-c "http.extraHeader=Authorization: token ${GITEA_TOKEN}")

# ── Preconditions ────────────────────────────────────────────────────────────
if [ -z "$GITEA_TOKEN" ] || [ -z "$ORG" ]; then
    echo "[-] GITEA_TOKEN and ORG must be set (in $ENV_FILE or the environment)"
    exit 1
fi

mkdir -p "$REPO_DIR" "$DAY_DIR"

# Returns every clone_url for the org, following pagination. Gitea caps the
# page size, so a single large `limit` would silently drop repositories.
fetch_repo_urls() {
    local page=1
    local per_page=50
    local body
    local urls

    while :; do

        # Pull one page of repositories.
        body=$(curl -s -H "Authorization: token $GITEA_TOKEN" \
            "$GITEA_URL/api/v1/orgs/$ORG/repos?limit=$per_page&page=$page" || true)
        urls=$(echo "$body" | jq -r '.[].clone_url' 2>/dev/null || true)

        # Stop once a page comes back empty.
        [ -z "$urls" ] && break

        echo "$urls"
        page=$((page + 1))
    done
}

# Clones a repo's working tree, or hard-resets an existing checkout to the
# remote default branch. A working tree is required: the scanners read source
# files, so a bare/mirror clone would have nothing to scan.
sync_repo() {
    local repo="$1"
    local target="$2"
    local branch

    # Fresh checkout when we have not cloned it before.
    if [ ! -d "$target/.git" ]; then
        git "${GIT_AUTH[@]}" clone "$repo" "$target"
        return
    fi

    # Otherwise fetch and reset to the remote's default branch.
    git "${GIT_AUTH[@]}" -C "$target" fetch --prune origin
    branch=$(git "${GIT_AUTH[@]}" -C "$target" remote show origin \
        | sed -n 's/.*HEAD branch: //p')
    git -C "$target" reset --hard "origin/$branch"
}

# Runs all three scanners against a repo working tree and writes JSON reports.
# Each scanner is allowed to fail without aborting the run.
scan_repo() {
    local src="$1"
    local out="$2"

    # Trivy — primary CVE / secret / misconfig scan.
    trivy fs \
        --scanners vuln,secret,misconfig \
        --format json \
        -o "$out/trivy.json" \
        "$src" || true

    # Grype — secondary vulnerability validation.
    grype "dir:$src" -o json > "$out/grype.json" || true

    # Semgrep — static analysis with the auto rule set.
    semgrep \
        --config=auto \
        --json \
        -o "$out/semgrep.json" \
        "$src" || true
}

# Counts findings across the three reports for one repo.
count_findings() {
    local out="$1"
    local trivy_n=0
    local grype_n=0
    local semgrep_n=0

    # Trivy: vulnerabilities + secrets + misconfigurations.
    [ -f "$out/trivy.json" ] && trivy_n=$(jq '[.Results[]? | (.Vulnerabilities // [] | length) + (.Secrets // [] | length) + (.Misconfigurations // [] | length)] | add // 0' "$out/trivy.json" 2>/dev/null || echo 0)

    # Grype: matched vulnerabilities.
    [ -f "$out/grype.json" ] && grype_n=$(jq '(.matches // []) | length' "$out/grype.json" 2>/dev/null || echo 0)

    # Semgrep: rule matches.
    [ -f "$out/semgrep.json" ] && semgrep_n=$(jq '(.results // []) | length' "$out/semgrep.json" 2>/dev/null || echo 0)

    echo "$((trivy_n + grype_n + semgrep_n))"
}

# ── Fetch repo list ──────────────────────────────────────────────────────────
echo "[+] Fetching repo list from Gitea..."
repos=$(fetch_repo_urls)

if [ -z "$repos" ]; then
    echo "[-] No repos found or API call failed"
    exit 1
fi

# ── Sync + scan each repo ────────────────────────────────────────────────────
echo "[+] Syncing and scanning repositories..."
total=0

while read -r repo; do

    # Derive a stable name and per-repo output dir.
    name=$(basename "$repo" .git)
    target="$REPO_DIR/$name"
    out="$DAY_DIR/$name"
    mkdir -p "$out"

    echo "  [*] $name"

    # Refresh the working tree, then scan it. A sync failure must not abort
    # the whole run — log it and move on.
    sync_repo "$repo" "$target" || echo "  [-] sync failed for $name"
    scan_repo "$target" "$out"

    # Record this repo's finding count.
    found=$(count_findings "$out")
    total=$((total + found))
    echo "$name: $found findings" >> "$SUMMARY"

done <<< "$repos"

# ── Summarise + prune ────────────────────────────────────────────────────────
echo "[+] Total findings: $total" | tee -a "$SUMMARY"

# Drop report directories older than the retention window.
find "$REPORT_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$RETENTION_DAYS" \
    -exec rm -rf {} +

# Make the outcome obvious in cron logs / mail.
if [ "$total" -gt 0 ]; then
    echo "[!] Vulnerabilities found — see $DAY_DIR"
else
    echo "[+] Clean — no findings"
fi

echo "[+] Reports at $DAY_DIR"
