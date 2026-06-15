# security.mk — reusable security targets for a Go repo's inner dev loop.
#
# This is the dev-side mirror of the server-side cron scans (see this folder's
# security-scan-*.sh). Drop this file into a repo and add to its Makefile:
#
#     include security.mk
#
# Design: `make test` stays fast + offline. Every scanner lives in its own
# target, so you opt in. `make sec-tools` installs/updates the scanners and
# `make sec-update` refreshes their vulnerability databases / definitions.
#
# Requires $(GOBIN) on your PATH so the installed scanners are found.

# Where `go install` and the anchore installers drop binaries (usually on PATH).
GOBIN ?= $(shell go env GOPATH)/bin

# Tool versions — bump deliberately. @latest keeps them current.
GOVULNCHECK_VERSION ?= latest
OSVSCANNER_VERSION  ?= latest
GITLEAKS_VERSION    ?= latest
GRYPE_VERSION       ?= latest
SYFT_VERSION        ?= latest
GOSEC_VERSION       ?= latest

# SBOM definition file written by `make sbom`.
SBOM_FILE ?= sbom.cdx.json

.PHONY: sec-tools sec-update vuln secrets sast deps osv sbom sec sec-full check

# ── Bootstrap / updates ────────────────────────────────────────────────────────

# Installs (or updates) every scanner. All are Go programs, so it is a pure
# `go install` into $(GOBIN) — no Python.
sec-tools:

	# All Go-native scanners land in $(GOBIN). grype/syft report version
	# "unknown" when built this way, but their DB compatibility is compiled in,
	# so scans and `grype db update` work fine.
	GOBIN=$(GOBIN) go install golang.org/x/vuln/cmd/govulncheck@$(GOVULNCHECK_VERSION)
	GOBIN=$(GOBIN) go install github.com/securego/gosec/v2/cmd/gosec@$(GOSEC_VERSION)
	GOBIN=$(GOBIN) go install github.com/google/osv-scanner/v2/cmd/osv-scanner@$(OSVSCANNER_VERSION)
	GOBIN=$(GOBIN) go install github.com/gitleaks/gitleaks/v8@$(GITLEAKS_VERSION)
	GOBIN=$(GOBIN) go install github.com/anchore/grype/cmd/grype@$(GRYPE_VERSION)
	GOBIN=$(GOBIN) go install github.com/anchore/syft/cmd/syft@$(SYFT_VERSION)

# Refreshes local vulnerability definitions. Only grype keeps a local DB; the
# others fetch their data live at run time.
sec-update:

	# Pull the latest grype vulnerability database.
	grype db update

	# Make the live-fetch behaviour explicit so nobody hunts for a missing step.
	@echo "govulncheck and osv-scanner fetch definitions at run time — nothing to pre-update."

# ── Individual scanners ────────────────────────────────────────────────────────

# Go reachability-aware vuln scan. Fast, low-noise — the one to gate CI on.
vuln:
	govulncheck ./...

# Secrets in the working tree (passwords, API keys, tokens).
secrets:
	gitleaks detect --source=. --no-banner

# Go SAST for insecure code patterns (injection, weak crypto, hardcoded creds).
sast:
	gosec ./...

# Known CVEs in dependencies (go.mod, package-lock.json, ...).
deps:
	grype dir:.

# Multi-ecosystem lockfile scan against the OSV database.
osv:
	osv-scanner --recursive .

# Regenerate the SBOM definition file (CycloneDX) for this repo.
sbom:
	syft dir:. -o cyclonedx-json=$(SBOM_FILE)

# ── Grouped targets ────────────────────────────────────────────────────────────

# Quick local pass: reachable Go vulns + secrets.
sec: vuln secrets

# Full local mirror of the cron scan: adds SAST + dep CVEs + OSV.
sec-full: vuln secrets sast deps osv

# Pre-push gate: tests + the cheap, high-value vuln check. `test` comes from
# the including Makefile.
check: test vuln
