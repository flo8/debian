#!/usr/bin/env bash
# Shared helpers for the Gitea security scans (fast / daily / weekly).
#
# This file is SOURCED by each scan script — it is never executed directly.
# It centralises the plumbing every scan needs: configuration, finding the
# on-disk repositories, exporting a working tree, Slack notifications, and
# report pruning. The three scan scripts then stay short and focused on
# *what* they scan rather than the mechanics around it.
#
# No Gitea API / token is used: Gitea stores every repo as a bare git repo on
# disk, so the scans read straight from that directory. gitleaks reads the bare
# repo's history directly; the source-reading scanners get a working tree that
# we export from the bare repo.

# ── Configuration ─────────────────────────────────────────────────────────────
# Secrets (only SLACK_WEBHOOK_URL today) live in this env file so they are never
# committed. Keep it root-owned: chmod 600. See security-scan.env.example.
ENV_FILE="${ENV_FILE:-/etc/gitea-security.env}"

# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

# Where Gitea keeps its bare repositories on the host. When unset we resolve it
# from the Docker named volume created by install.sh. Override in $ENV_FILE if
# your layout differs.
GITEA_REPOS_DIR="${GITEA_REPOS_DIR:-}"
GITEA_VOLUME="${GITEA_VOLUME:-gitea_gitea_data}"

# Working area for exported trees + JSON reports.
BASE_DIR="${BASE_DIR:-/srv/gitea-security}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

# Send a Slack heartbeat from the fast tier even when it finds nothing. Off by
# default so the hourly run stays quiet unless there is something to report.
NOTIFY_ON_SUCCESS="${NOTIFY_ON_SUCCESS:-0}"

# Derived paths shared by every scan tier.
WORK_DIR="$BASE_DIR/worktrees"
REPORT_DIR="$BASE_DIR/reports"

# ── Repos directory resolution ────────────────────────────────────────────────
# Resolves the host path to Gitea's bare repositories. Prefers an explicit
# GITEA_REPOS_DIR, otherwise asks Docker for the volume mountpoint. Exits if it
# cannot be found, since every scan depends on it.
resolve_repos_dir() {
    local mount

    # Explicit override wins — no Docker lookup needed.
    if [ -n "$GITEA_REPOS_DIR" ]; then
        return 0
    fi

    # Ask Docker where the named volume lives on the host filesystem.
    mount=$(docker volume inspect "$GITEA_VOLUME" -f '{{.Mountpoint}}' 2>/dev/null || true)
    if [ -z "$mount" ]; then
        echo "[-] Could not resolve Gitea repos dir. Set GITEA_REPOS_DIR in $ENV_FILE."
        exit 1
    fi

    # Gitea's install wizard puts repos under <data>/gitea/repositories.
    GITEA_REPOS_DIR="$mount/gitea/repositories"
}

# ── Preconditions ─────────────────────────────────────────────────────────────
# Verifies the repos directory exists and prepares the working area. Run once at
# the top of every scan script.
require_config() {
    resolve_repos_dir

    if [ ! -d "$GITEA_REPOS_DIR" ]; then
        echo "[-] Repos dir not found: $GITEA_REPOS_DIR"
        exit 1
    fi

    mkdir -p "$WORK_DIR"
}

# ── Repo discovery ────────────────────────────────────────────────────────────
# Lists every bare repository on disk as "<owner>/<repo>.git" paths. Gitea lays
# them out two levels deep: <repos>/<owner>/<repo>.git.
list_bare_repos() {
    find "$GITEA_REPOS_DIR" -mindepth 2 -maxdepth 2 -type d -name '*.git' 2>/dev/null
}

# Derives a stable "owner__repo" label from a bare repo path, for use in report
# directory names and Slack messages.
repo_label() {
    local bare="$1"
    local rel

    # Strip the repos root prefix and the trailing .git, then flatten the slash.
    rel="${bare#"$GITEA_REPOS_DIR"/}"
    rel="${rel%.git}"
    echo "${rel//\//__}"
}

# ── Working-tree export ───────────────────────────────────────────────────────
# Exports the default branch of a bare repo into a clean working tree the
# source-reading scanners can read. We wipe and re-export each run so the tree
# always matches the current branch tip with no stale files.
export_worktree() {
    local bare="$1"
    local wt="$2"
    local branch

    # The bare repo's HEAD points at its default branch.
    branch=$(git --git-dir="$bare" symbolic-ref --short HEAD 2>/dev/null || echo "master")

    # Re-export from scratch: drop the old tree, then stream the branch into it.
    rm -rf "$wt"
    mkdir -p "$wt"
    git --git-dir="$bare" archive --format=tar "$branch" | tar -x -C "$wt"
}

# ── Language detection ────────────────────────────────────────────────────────
# Tells a scan tier whether a tool is worth running (e.g. govulncheck only makes
# sense for Go). Returns 0 if the marker file exists anywhere in the tree.
repo_has() {
    local src="$1"
    local marker="$2"

    # -print -quit stops at the first match so large trees stay cheap.
    [ -n "$(find "$src" -name "$marker" -not -path '*/.git/*' -print -quit 2>/dev/null)" ]
}

# ── Slack notification ────────────────────────────────────────────────────────
# Posts one message to the configured Slack webhook. Silently does nothing when
# no webhook is set, so the scans still work without Slack. `level` controls the
# attachment colour: "alert" (red) for findings, "ok" (green) for the heartbeat.
notify_slack() {
    local level="$1"
    local title="$2"
    local body="$3"
    local color
    local payload

    # No webhook configured — Slack is optional, so just skip.
    [ -z "$SLACK_WEBHOOK_URL" ] && return 0

    # Map the level to a Slack attachment colour.
    if [ "$level" = "alert" ]; then
        color="#d40000"
    else
        color="#2eb886"
    fi

    # Build the payload with jq so the title/body are safely JSON-escaped.
    payload=$(jq -n \
        --arg color "$color" \
        --arg title "$title" \
        --arg body "$body" \
        '{attachments: [{color: $color, title: $title, text: $body}]}')

    # Fire-and-forget: a Slack outage must never fail the scan.
    curl -s -X POST -H 'Content-Type: application/json' \
        --data "$payload" "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || true
}

# ── Retention ─────────────────────────────────────────────────────────────────
# Drops report directories older than the retention window so the disk does not
# grow without bound.
prune_reports() {
    find "$REPORT_DIR" -mindepth 1 -maxdepth 1 -type d \
        -mtime +"$RETENTION_DAYS" -exec rm -rf {} + 2>/dev/null || true
}
