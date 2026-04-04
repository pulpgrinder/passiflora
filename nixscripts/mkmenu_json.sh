#!/bin/sh
# mkmenu_json.sh — Generate config.js with PassifloraConfig from a menu template.
#
# Usage: ./mkmenu_json.sh <template> <progname> <os_name> [output]
#
# Template format (same as mkmenu.sh):
#   - Indentation (tabs or groups of 4 spaces) sets the nesting level
#   - Level 0 entries become top-level menu objects
#   - Level 1+ entries become items within that menu
#   - "-" alone means a separator
#   - Blank lines are skipped
#   - Items starting with * are native-only and are excluded from the JS menu
#   - {{progname}} is replaced with the progname argument
#
# Output: a JS file defining PassifloraConfig with os_name, menus, and handleMenu.
#
set -e

TEMPLATE="$1"
PROGNAME="${2:-passiflora}"
OS_NAME="${3:-unknown}"
OUTPUT="${4:-src/www/generated/config.js}"
THEME="${5:-Default}"
CONFIGFILE="${6:-src/config}"

# Read font stacks from config file (everything after the key)
BODY_FONT_STACK="System UI"
HEADING_FONT_STACK="System UI"
CODE_FONT_STACK="Monospace Code"
if [ -f "$CONFIGFILE" ]; then
    _val=$(awk '/^body-font-stack / {sub(/^body-font-stack /, ""); print}' "$CONFIGFILE")
    [ -n "$_val" ] && BODY_FONT_STACK="$_val"
    _val=$(awk '/^heading-font-stack / {sub(/^heading-font-stack /, ""); print}' "$CONFIGFILE")
    [ -n "$_val" ] && HEADING_FONT_STACK="$_val"
    _val=$(awk '/^code-font-stack / {sub(/^code-font-stack /, ""); print}' "$CONFIGFILE")
    [ -n "$_val" ] && CODE_FONT_STACK="$_val"
fi

if [ -z "$TEMPLATE" ] || [ ! -f "$TEMPLATE" ]; then
    echo "Usage: $0 <template> <progname> <os_name> [output]" >&2
    echo "Error: template file '${TEMPLATE}' not found" >&2
    exit 1
fi

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT")"

awk -v progname="$PROGNAME" -v os_name="$OS_NAME" -v theme="$THEME" \
    -v body_font="$BODY_FONT_STACK" -v heading_font="$HEADING_FONT_STACK" -v code_font="$CODE_FONT_STACK" '
function pad(n,    s, k) { s = ""; for (k = 0; k < n; k++) s = s "  "; return s }
{
    line = $0
    level = 0

    # Count leading tabs
    while (length(line) > 0 && substr(line, 1, 1) == "\t") {
        level++
        line = substr(line, 2)
    }

    # If no tabs found, count groups of 4 leading spaces
    if (level == 0) {
        while (length(line) >= 4 && substr(line, 1, 4) == "    ") {
            level++
            line = substr(line, 5)
        }
    }

    # Strip remaining leading/trailing whitespace
    gsub(/^[ \t]+/, "", line)
    gsub(/[ \t]+$/, "", line)

    # Skip blank lines
    if (line == "") next

    # Replace {{progname}} with the actual program name
    while ((idx = index(line, "{{progname}}")) > 0) {
        line = substr(line, 1, idx - 1) progname substr(line, idx + 12)
    }

    # Items starting with * are native-only; skip them from JS output
    if (substr(line, 1, 1) == "*") next

    # Escape backslashes and double quotes for JSON
    gsub(/\\/, "\\\\", line)
    gsub(/"/, "\\\"", line)

    levels[NR] = level
    texts[NR]  = line
    count = NR
}
END {
    printf "// Auto-generated file \xe2\x80\x94 DO NOT EDIT. This file is overwritten on every build.\n"
    printf "var PassifloraConfig = {\n"
    printf "  progname: \"%s\",\n", progname
    printf "  os_name: \"%s\",\n", os_name
    printf "  theme: \"%s\",\n", theme
    printf "  \"body-font-stack\": \"%s\",\n", body_font
    printf "  \"heading-font-stack\": \"%s\",\n", heading_font
    printf "  \"code-font-stack\": \"%s\",\n", code_font
    printf "  menus: ["

    # open_depth tracks how many "items": [ arrays are open.
    # The top-level menus: [ counts as depth 0.
    open_depth = 0
    # first_at[d] = 1 means we have not yet printed an item at depth d
    first_at[0] = 1

    for (i = 1; i <= count; i++) {
        if (!(i in levels)) continue
        level = levels[i]
        text  = texts[i]

        # Peek ahead to see if this item has children
        has_children = 0
        for (j = i + 1; j <= count; j++) {
            if (!(j in levels)) continue
            if (levels[j] > level) has_children = 1
            break
        }

        # Close deeper levels until open_depth == level
        while (open_depth > level) {
            open_depth--
            printf "\n%s]", pad(open_depth + 2)
            printf "\n%s}", pad(open_depth + 1)
        }

        # Comma before sibling
        if (!first_at[level]) printf ","

        if (text == "-") {
            printf "\n%s{ \"separator\": true }", pad(level + 1)
        } else if (has_children) {
            printf "\n%s{", pad(level + 1)
            printf "\n%s\"title\": \"%s\",", pad(level + 2), text
            printf "\n%s\"items\": [", pad(level + 2)
            open_depth = level + 1
            first_at[level + 1] = 1
        } else {
            printf "\n%s{ \"title\": \"%s\" }", pad(level + 1), text
        }

        first_at[level] = 0
    }

    # Close any remaining open levels
    while (open_depth > 0) {
        open_depth--
        printf "\n%s]", pad(open_depth + 2)
        printf "\n%s}", pad(open_depth + 1)
    }

    printf "\n  ],\n"
    printf "  handleMenu: function(title) { alert(\"Menu item clicked: \" + title); }\n"
    printf "};\n"
}
' "$TEMPLATE" > "$OUTPUT"

echo "mkmenu_json: $OUTPUT generated from $TEMPLATE (progname=$PROGNAME, os=$OS_NAME, theme=$THEME)"
