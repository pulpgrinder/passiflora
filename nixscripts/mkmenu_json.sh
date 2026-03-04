#!/bin/sh
# mkmenu_json.sh — Generate a JSON menu file from a menu template.
#
# Usage: ./mkmenu_json.sh <template> <progname> [output]
#
# Template format (same as mkmenu.sh):
#   - Indentation (tabs or groups of 4 spaces) sets the nesting level
#   - Level 0 entries become top-level menu objects
#   - Level 1+ entries become items within that menu
#   - "-" alone means a separator
#   - Blank lines are skipped
#   - {{progname}} is replaced with the progname argument
#
# Output: a JSON file like:
#   [
#     {
#       "title": "File",
#       "items": [
#         { "title": "Open" },
#         { "separator": true },
#         { "title": "Quit" }
#       ]
#     }
#   ]
#
set -e

TEMPLATE="$1"
PROGNAME="${2:-passiflora}"
OUTPUT="${3:-src/www/generated/PassifloraMenus.js}"

if [ -z "$TEMPLATE" ] || [ ! -f "$TEMPLATE" ]; then
    echo "Usage: $0 <template> [progname] [output]" >&2
    echo "Error: template file '${TEMPLATE}' not found" >&2
    exit 1
fi

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT")"

awk -v progname="$PROGNAME" '
BEGIN {
    menu_count = 0
    item_count = 0
}
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

    # Escape backslashes and double quotes for JSON
    gsub(/\\/, "\\\\", line)
    gsub(/"/, "\\\"", line)

    levels[NR] = level
    texts[NR]  = line
    count = NR
}
END {
    printf "// Auto-generated file \xe2\x80\x94 DO NOT EDIT. This file is overwritten on every build.\n"
    printf "PASSIFLORA_MENUS = [\n"
    first_menu = 1
    in_menu = 0

    for (i = 1; i <= count; i++) {
        if (!(i in levels)) continue
        level = levels[i]
        text  = texts[i]

        if (level == 0) {
            # Close previous menu if open
            if (in_menu) {
                printf "\n      ]\n    }"
            }
            if (!first_menu) printf ","
            printf "\n  {\n    \"title\": \"%s\",\n    \"items\": [", text
            first_menu = 0
            in_menu = 1
            first_item = 1
        } else {
            if (!first_item) printf ","
            if (text == "-") {
                printf "\n      { \"separator\": true }"
            } else {
                printf "\n      { \"title\": \"%s\" }", text
            }
            first_item = 0
        }
    }

    # Close last menu
    if (in_menu) {
        printf "\n      ]\n    }"
    }

    printf "\n]\n"
}
' "$TEMPLATE" > "$OUTPUT"

echo "mkmenu_json: $OUTPUT generated from $TEMPLATE (progname=$PROGNAME)"
