#!/bin/sh
# mkgenerated.sh — Build generated.js and generated.css from framework files.
#
# Usage: ./mkgenerated.sh <menu_template> <progname> <os_name> <theme> <configfile>
#
# Reads boolean flags from <configfile> (usefilesystem, usepassifloraui)
# and concatenates the appropriate JS/CSS framework
# files into src/www/generated/generated.js and generated.css.
#
# The config.js content (PassifloraConfig) is always included first.
#
set -e

TEMPLATE="$1"
PROGNAME="${2:-passiflora}"
OS_NAME="${3:-unknown}"
THEME="${4:-Default}"
CONFIGFILE="${5:-src/config}"

GENERATED_DIR="src/www/generated"
GENERATED_JS="$GENERATED_DIR/generated.js"
GENERATED_CSS="$GENERATED_DIR/generated.css"

PASSIFLORA_DIR="src/passiflora"
PANELS_DIR="src/www/panels"
VFS_DIR="src/vfs"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Read feature flags from config ──
USE_FILESYSTEM=false
USE_PASSIFLORAUI=false

if [ -f "$CONFIGFILE" ]; then
    _val=$(awk '/^usefilesystem /   {print $2}' "$CONFIGFILE"); [ "$_val" = "true" ] && USE_FILESYSTEM=true
    _val=$(awk '/^usepassifloraui / {print $2}' "$CONFIGFILE"); [ "$_val" = "true" ] && USE_PASSIFLORAUI=true
fi

mkdir -p "$GENERATED_DIR"

# ── Step 1: Generate config.js (PassifloraConfig) into a temp file ──
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

CONFIG_TMP="$TMPDIR/config.js"
sh "$SCRIPT_DIR/mkmenu_json.sh" "$TEMPLATE" "$PROGNAME" "$OS_NAME" "$CONFIG_TMP" "$THEME" "$CONFIGFILE"

# ── Step 2: Build generated.js by concatenation ──
cat "$CONFIG_TMP" > "$GENERATED_JS"

if [ "$USE_FILESYSTEM" = "true" ]; then
    # Generate vfspreload.js into temp, then append
    VFS_TMP="$TMPDIR/vfspreload.js"
    sh "$SCRIPT_DIR/mkvfspreload.sh" "$VFS_DIR" "$VFS_TMP"
    printf '\n' >> "$GENERATED_JS"
    cat "$VFS_TMP" >> "$GENERATED_JS"

    # Append PassifloraIO.js
    printf '\n' >> "$GENERATED_JS"
    cat "$PASSIFLORA_DIR/PassifloraIO.js" >> "$GENERATED_JS"
fi

if [ "$USE_PASSIFLORAUI" = "true" ]; then
    printf '\n' >> "$GENERATED_JS"
    cat "$PASSIFLORA_DIR/UI/fileui.js" >> "$GENERATED_JS"

    printf '\n' >> "$GENERATED_JS"
    cat "$PASSIFLORA_DIR/UI/buildmenu.js" >> "$GENERATED_JS"

    printf '\n' >> "$GENERATED_JS"
    cat "$PASSIFLORA_DIR/UI/themes.js" >> "$GENERATED_JS"

    PANELS_TMP="$TMPDIR/panels.js"
    sh "$SCRIPT_DIR/mkpanels.sh" "$PANELS_DIR" "$PANELS_TMP"
    printf '\n' >> "$GENERATED_JS"
    cat "$PANELS_TMP" >> "$GENERATED_JS"
fi

echo "mkgenerated: $GENERATED_JS built"

# ── Step 3: Build generated.css by concatenation ──
: > "$GENERATED_CSS"

if [ "$USE_PASSIFLORAUI" = "true" ]; then
    cat "$PASSIFLORA_DIR/UI/theme.css" >> "$GENERATED_CSS"
fi

echo "mkgenerated: $GENERATED_CSS built"
