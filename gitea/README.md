# Gitea

Scripts to install and run a self-hosted [Gitea](https://about.gitea.com/) forge
behind HTTPS, plus a tiered security scan of the hosted repositories.

All scripts are meant to run on the **server**, as root.

## Scripts

| Script | What it does |
|--------|--------------|
| `install.sh` | Installs Gitea (Docker Compose) at `/srv/gitea`, waits for it to come up, runs the initial setup, and creates the admin user. |
| `ssl.sh` | Installs Certbot with the Route53 DNS plugin and obtains a Let's Encrypt certificate for the Gitea domain. |
| `theme.sh` | Recolors the bundled `air360` theme's primary color to Catppuccin Mauve. |
| `security-install.sh` | Installs the scanners (gitleaks, grype, govulncheck, gosec, osv-scanner, syft) and the scan scripts. All Go, no Python. |
| `security-lib.sh` | Shared helpers (config, repo discovery, worktree export, Slack) sourced by the three scan tiers. |
| `security-scan-fast.sh` | gitleaks + grype. Hourly. |
| `security-scan-daily.sh` | govulncheck + gosec + osv-scanner. Daily. |
| `security-scan-weekly.sh` | syft SBOM rebuild + new-dependency diff. Weekly. |
| `security-scan.env.example` | Template for `/etc/gitea-security.env` (Slack + overrides). |
| `security.mk` | Reusable Make include — the dev-side mirror of the scans, for copying into Go repos. |

## Setup

### 1. Install and serve Gitea

```bash
sudo bash gitea/ssl.sh        # get the TLS certificate first
sudo bash gitea/install.sh    # install + initialise Gitea
sudo bash gitea/theme.sh      # optional: apply the Mauve theme
```

The domain, admin user, and paths are configured at the top of `install.sh`
and `ssl.sh` — edit them before running.

### 2. Security scans

```bash
# Install the scanners + the three scan scripts.
sudo bash gitea/security-install.sh

# Optional config (Slack webhook, overrides). Defaults work without it.
sudo cp gitea/security-scan.env.example /etc/gitea-security.env
sudo chmod 600 /etc/gitea-security.env
sudo nano /etc/gitea-security.env

# Schedule the three tiers.
sudo tee /etc/cron.d/gitea-security >/dev/null <<'CRON'
# m h dom mon dow user command
0   *   * * *   root /usr/local/bin/gitea-security-fast   >> /var/log/gitea-security.log 2>&1
30  3   * * *   root /usr/local/bin/gitea-security-daily  >> /var/log/gitea-security.log 2>&1
0   4   * * 1   root /usr/local/bin/gitea-security-weekly >> /var/log/gitea-security.log 2>&1
CRON
```

## How it works

- **No API / token.** Gitea stores every repo as a bare git repo on disk; the
  scans read straight from that directory (resolved from the Docker volume).
  gitleaks scans the bare repo's history directly; the source-reading scanners
  get a working tree exported from the bare repo into `$BASE_DIR/worktrees`.
- **Three cron tiers** balance speed against depth:

| Tier | Cadence | Tools | Catches |
|------|---------|-------|---------|
| fast | hourly | gitleaks, grype | secrets, dependency CVEs (no build, so cheap) |
| daily | daily | govulncheck, gosec, osv-scanner | reachable Go vulns, insecure Go code, OSV-DB vulns |
| weekly | weekly | syft | new dependencies to review (SBOM diff) |

- **All Go, no Python.** Every scanner is a Go binary installed with
  `go install`. The trade-off: gosec (Go SAST) replaces semgrep, so insecure
  *code-pattern* analysis covers Go only — JS/TS repos still get dependency-CVE
  coverage (grype + osv-scanner) but not code-pattern SAST.
- **Why these tools (and not Trivy).** grype covers dependency CVEs, gitleaks
  covers secrets, gosec covers Go code — together they cover what Trivy did, so
  Trivy is dropped. grype and osv-scanner use *different* vuln databases, so
  running both widens coverage; govulncheck adds Go call-graph reachability
  (much lower noise than a plain CVE match).

## Output

- **Reports** land in `$BASE_DIR/reports/<tier>-<date>/`, one folder per repo,
  plus a `summary.txt` with finding counts. Folders older than `RETENTION_DAYS`
  (default 30) are pruned automatically. SBOMs persist in `$BASE_DIR/sbom/`.
- **Slack** (set `SLACK_WEBHOOK_URL`): any finding posts a red alert. The daily
  run also posts a green "all clean" heartbeat so you know it ran; the weekly
  run posts a dependency-change digest. The hourly fast run stays quiet unless
  it finds something, or set `NOTIFY_ON_SUCCESS=1` for an hourly heartbeat.

## Dev-side scans (`security.mk`)

The cron tiers above are defense-in-depth on the server. To shift-left, copy
`security.mk` into a Go repo and add `include security.mk` to its `Makefile`.

```bash
make sec-tools     # install/update the scanners (pure go install, no Python)
make sec-update    # refresh the grype vuln DB (others fetch live at run time)

make vuln          # govulncheck ./...        — fast, the one to gate CI on
make sec           # vuln + secrets (gitleaks) — quick local pass
make sec-full      # + sast(gosec) + deps + osv — full local mirror of the cron
make sbom          # regenerate sbom.cdx.json  — SBOM definition file
make check         # test + vuln               — pre-push gate
```

`make test` is deliberately left untouched — it stays fast and offline. The
scanners that need the network (govulncheck, grype, osv-scanner) live in their
own targets so a flaky network never breaks your tests. Requires the Go bin dir
(`go env GOPATH`/bin) on your `PATH`.

The Makefile and the cron are **complementary, not redundant**: the Makefile/CI
only runs when someone builds the code, while the cron catches newly-disclosed
CVEs against code that has not changed and covers repos nobody is actively
working on.

## Notes

- Scanning is read-only and never blocks pushes — it is a detection layer, not
  CI. Rotate any secret gitleaks reports: it is already in history.
- All settings have defaults; `/etc/gitea-security.env` is optional and only
  needed for Slack or to override the repo path / retention.
