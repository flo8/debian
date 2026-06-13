#!/usr/bin/env bash
set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
# Recolors the air360 Gitea theme primary color to Catppuccin "Mauve" (pastel
# purple). Shades are derived from the base mauve: "dark-*" go lighter (hover
# states in the dark theme), "light-*" go darker (used by the light theme).
CONTAINER="gitea"
THEME_FILE="/data/gitea/public/assets/css/theme-air360.css"

# Catppuccin Mauve palette (base + derived shades).
NEW_PRIMARY="#cba6f7"
NEW_DARK_1="#d4b5f9"
NEW_DARK_2="#ddc4fb"
NEW_DARK_3="#e6d3fd"
NEW_LIGHT_1="#b48ae8"
NEW_LIGHT_2="#9d6ed4"
NEW_BARE="cba6f7"

# Bare hex shades previously written into the theme, mapped to their Mauve
# equivalent. These catch occurrences that are NOT --color-primary* variables
# (the air360 theme also hardcodes the primary shades in a few other places).
# Format: "old_hex new_hex" — old_hex is a case-insensitive regex, no leading #.
declare -a BARE_MAP=(
    # Original blue palette.
    "4183c4 ${NEW_BARE}"
    "548[Ff][Cc][Aa] d4b5f9"
    "679[Cc][Dd]0 ddc4fb"
    "7[Aa][Aa]8[Dd]6 e6d3fd"
    "3876[Bb]3 b48ae8"
    "31699[Ff] 9d6ed4"
    # Earlier pink patch.
    "[Ff][Ff]70[Bb]3 ${NEW_BARE}"
    "[Ee]55[Ff]9[Ee] d4b5f9"
    "[Cc][Cc]5490 ddc4fb"
    "[Bb]24[Aa]7[Ee] e6d3fd"
    "[Ff][Ff]85[Bb][Ff] b48ae8"
    "[Ff][Ff]9[Bb][Cc][Bb] 9d6ed4"
)

# ── Root check ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo "Run as root:  sudo bash gitea/theme.sh"
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
# Match the variable NAME and overwrite whatever hex value follows. This is
# value-agnostic, so it works whether the theme is currently blue or pink.
# The ":" after the name keeps "--color-primary" from matching "-dark-*"/"-light-*".
HEX='#[0-9A-Fa-f]\{3,8\}'
docker exec "$CONTAINER" sed -i \
    -e "s/--color-primary: ${HEX}/--color-primary: ${NEW_PRIMARY}/" \
    -e "s/--color-primary-dark-1: ${HEX}/--color-primary-dark-1: ${NEW_DARK_1}/" \
    -e "s/--color-primary-dark-2: ${HEX}/--color-primary-dark-2: ${NEW_DARK_2}/" \
    -e "s/--color-primary-dark-3: ${HEX}/--color-primary-dark-3: ${NEW_DARK_3}/" \
    -e "s/--color-primary-light-1: ${HEX}/--color-primary-light-1: ${NEW_LIGHT_1}/" \
    -e "s/--color-primary-light-2: ${HEX}/--color-primary-light-2: ${NEW_LIGHT_2}/" \
    "$THEME_FILE"

# Catch any remaining bare occurrences (original blue + earlier pink patch).
# Build one sed expression per old->new pair from the map above.
SED_ARGS=()
for pair in "${BARE_MAP[@]}"; do

    # Split "old new" into its two hex values.
    old_hex="${pair%% *}"
    new_hex="${pair##* }"
    SED_ARGS+=(-e "s/${old_hex}/${new_hex}/g")
done

docker exec "$CONTAINER" sed -i "${SED_ARGS[@]}" "$THEME_FILE"

# ── Restart to load new CSS ──────────────────────────────────────────────────
docker restart "$CONTAINER"

echo
echo "Done. air360 theme primary color is now Catppuccin Mauve (${NEW_PRIMARY})."
echo "Hard-refresh your browser (Ctrl+Shift+R) to bust the CSS cache."
echo
