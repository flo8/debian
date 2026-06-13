#!/usr/bin/env bash
set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
# Recolors the air360 Gitea theme primary color to Catppuccin "Mauve" (pastel
# purple). Shades are derived from the base mauve: "dark-*" go lighter (hover
# states in the dark theme), "light-*" go darker (used by the light theme).
CONTAINER="gitea"
THEME_FILE="/data/gitea/public/assets/css/theme-air360.css"

# Original blue values shipped by the air360 theme (what we replace).
OLD_PRIMARY="#4183c4"
OLD_DARK_1="#548fca"
OLD_DARK_2="#679cd0"
OLD_DARK_3="#7aa8d6"
OLD_LIGHT_1="#3876b3"
OLD_LIGHT_2="#31699f"
OLD_BARE="4183c4"

# Catppuccin Mauve palette (base + derived shades).
NEW_PRIMARY="#cba6f7"
NEW_DARK_1="#d4b5f9"
NEW_DARK_2="#ddc4fb"
NEW_DARK_3="#e6d3fd"
NEW_LIGHT_1="#b48ae8"
NEW_LIGHT_2="#9d6ed4"
NEW_BARE="cba6f7"

# ── Root check ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "Run as root:  sudo bash gitea_theme.sh"
    exit 1
fi

# ── Container check ──────────────────────────────────────────────────────────
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "ERROR: container '$CONTAINER' is not running"
    exit 1
fi

echo
echo "=== Recoloring air360 theme -> Catppuccin Mauve ==="
echo

# ── Apply CSS variable swaps ─────────────────────────────────────────────────
docker exec "$CONTAINER" sed -i \
    -e "s/--color-primary: ${OLD_PRIMARY}/--color-primary: ${NEW_PRIMARY}/" \
    -e "s/--color-primary-dark-1: ${OLD_DARK_1}/--color-primary-dark-1: ${NEW_DARK_1}/" \
    -e "s/--color-primary-dark-2: ${OLD_DARK_2}/--color-primary-dark-2: ${NEW_DARK_2}/" \
    -e "s/--color-primary-dark-3: ${OLD_DARK_3}/--color-primary-dark-3: ${NEW_DARK_3}/" \
    -e "s/--color-primary-light-1: ${OLD_LIGHT_1}/--color-primary-light-1: ${NEW_LIGHT_1}/" \
    -e "s/--color-primary-light-2: ${OLD_LIGHT_2}/--color-primary-light-2: ${NEW_LIGHT_2}/" \
    "$THEME_FILE"

# Catch any remaining bare occurrences of the original blue.
docker exec "$CONTAINER" sed -i "s/${OLD_BARE}/${NEW_BARE}/g" "$THEME_FILE"

# ── Restart to load new CSS ──────────────────────────────────────────────────
docker restart "$CONTAINER"

echo
echo "Done. air360 theme primary color is now Catppuccin Mauve (${NEW_PRIMARY})."
echo "Hard-refresh your browser (Ctrl+Shift+R) to bust the CSS cache."
echo
