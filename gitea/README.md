# Gitea

Scripts to install and run a self-hosted [Gitea](https://about.gitea.com/) forge
behind HTTPS, plus a daily security scan of the hosted repositories.

All scripts are meant to run on the **server**, as root.

## Scripts

| Script | What it does |
|--------|--------------|
| `install.sh` | Installs Gitea (Docker Compose) at `/srv/gitea`, waits for it to come up, runs the initial setup, and creates the admin user. |
| `ssl.sh` | Installs Certbot with the Route53 DNS plugin and obtains a Let's Encrypt certificate for the Gitea domain. |
| `theme.sh` | Recolors the bundled `air360` theme's primary color to Catppuccin Mauve. |
| `security-install.sh` | Installs the scanners (Trivy, Grype, Syft, Semgrep) used by the daily scan. |
| `security-scan.sh` | Clones/refreshes every repo and scans it with Trivy + Grype + Semgrep. Intended for cron. |
| `security-scan.env.example` | Template for `/etc/gitea-security.env` (token + org). |

## Setup

### 1. Install and serve Gitea

```bash
sudo bash gitea/ssl.sh        # get the TLS certificate first
sudo bash gitea/install.sh    # install + initialise Gitea
sudo bash gitea/theme.sh      # optional: apply the Mauve theme
```

The domain, admin user, and paths are configured at the top of `install.sh`
and `ssl.sh` — edit them before running.

### 2. Daily security scan

```bash
# Install the scanners + the scan script (-> /usr/local/bin/gitea-security-scan).
sudo bash gitea/security-install.sh

# Configure the scan (token + org live here, never in git).
sudo cp gitea/security-scan.env.example /etc/gitea-security.env
sudo chmod 600 /etc/gitea-security.env
sudo nano /etc/gitea-security.env

# Schedule it daily at 03:00.
echo '0 3 * * * root /usr/local/bin/gitea-security-scan >> /var/log/gitea-security.log 2>&1' \
  | sudo tee /etc/cron.d/gitea-security
```

The installer copies `security-scan.sh` to `/usr/local/bin/gitea-security-scan`,
so cron runs from a fixed, root-owned path regardless of where this repo is
checked out. Re-run `security-install.sh` after editing the scan script to
refresh the installed copy.

Reports are written to `/srv/gitea-security/reports/<date>/`, one folder per
repo (`trivy.json`, `grype.json`, `semgrep.json`) plus a `summary.txt` with the
finding counts. Report folders older than `RETENTION_DAYS` (default 30) are
pruned automatically.

## Notes

- Secrets are kept out of the repo: the scan reads `GITEA_TOKEN` and `ORG` from
  `/etc/gitea-security.env` at runtime.
- The scan targets a Gitea **org** (`/api/v1/orgs/<ORG>/repos`). To scan a
  personal user's repos, change that endpoint in `security-scan.sh` to
  `/api/v1/users/<USER>/repos`.
- `security-scan.sh` exits `0` even when findings exist; the outcome is printed
  (`[!] Vulnerabilities found` / `[+] Clean`) and written to `summary.txt`. Wire
  alerting via cron `MAILTO` or by reading `summary.txt`.
