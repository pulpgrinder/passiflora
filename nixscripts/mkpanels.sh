#!/bin/sh
# mkpanels.sh — Generate panels.js from HTML/JS files in passiflora/UI/panels.
#
# Usage: ./mkpanels.sh [panels_dir] [output]
#
# Scans panels_dir for .html files.  For each one, emits JavaScript that
# creates a hidden <div class="passiflora_menu_screen" id="Basename">
# containing the file's markup, plus a back-button header.
# After all HTML panels, appends the contents of every .js file found
# in the same directory so that panel scripts run after the DOM nodes
# they reference have been injected.
#
# Default panels_dir: src/www/passiflora/UI/panels
# Default output:     src/www/generated/panels.js
#
set -e

PANELS_DIR="${1:-src/www/passiflora/UI/panels}"
OUTPUT="${2:-src/www/generated/panels.js}"

mkdir -p "$(dirname "$OUTPUT")"

# If no panel HTML files exist, write a no-op stub and exit.
set -- "$PANELS_DIR"/*.html
if [ "$1" = "$PANELS_DIR/*.html" ] && [ ! -e "$1" ]; then
    printf '// Auto-generated \xe2\x80\x94 no panel files found.\n' > "$OUTPUT"
    echo "mkpanels: $OUTPUT generated (no panels found in $PANELS_DIR)"
    exit 0
fi

{
    printf '// Auto-generated file \xe2\x80\x94 DO NOT EDIT. This file is overwritten on every build.\n'
    printf '(function() {\n'
    printf '  "use strict";\n'

    for html in "$PANELS_DIR"/*.html; do
        [ -f "$html" ] || continue
        BASENAME=$(basename "$html" .html)

        printf '  var d = document.createElement("div");\n'
        printf '  d.className = "passiflora_menu_screen";\n'
        printf '  d.id = "%s";\n' "$BASENAME"
        printf '  d.style.display = "none";\n'
        printf '  d.innerHTML = "'

        # Escape the HTML for safe embedding inside a JS double-quoted string:
        #   \ → \\    " → \"    newlines → \n    </script> → <\/script>
        awk '{
            gsub(/\\/, "\\\\")
            gsub(/"/, "\\\"")
            gsub(/<\/script>/, "<\\/script>")
            if (NR > 1) printf "\\n"
            printf "%s", $0
        }' "$html"

        printf '";\n'
        printf '  document.body.appendChild(d);\n'
    done

    printf '})();\n'
    printf '\n'

    # Append panel JS files verbatim
    for js in "$PANELS_DIR"/*.js; do
        [ -f "$js" ] || continue
        JSBASE=$(basename "$js")
        printf '// --- %s ---\n' "$JSBASE"
        cat "$js"
        printf '\n'
    done
} > "$OUTPUT"

echo "mkpanels: $OUTPUT generated from $PANELS_DIR"
