#!/bin/sh
# signapp.sh — Interactively sign a macOS or iOS application bundle.
#
# Usage: signapp.sh <platform> <bundle.app> [bundleid]
#
#   platform:  macos | ios | iossim
#   bundle:    Path to the .app bundle
#   bundleid:  Bundle identifier (used for entitlements, optional)
#
# Lists available codesigning identities and lets the user choose one.
# Ad-hoc signing (no identity) is always offered as an option.
#
set -e

PLATFORM="${1:?Usage: $0 <macos|ios|iossim> <bundle.app> [bundleid]}"
BUNDLE="${2:?Usage: $0 <platform> <bundle.app> [bundleid]}"
BUNDLE_ID="${3:-}"

if [ ! -d "$BUNDLE" ]; then
    echo "signapp: bundle not found: $BUNDLE" >&2
    echo "  Build the app first, then sign it." >&2
    exit 1
fi

# ── Gather signing identities ──────────────────────────────────────
# security find-identity returns lines like:
#   1) ABCDEF123456 "Apple Development: name@example.com (TEAMID)"
IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E '^\s+[0-9]+\)' | sed 's/^[[:space:]]*//')

echo ""
echo "=== Code Signing: $BUNDLE ==="
echo ""

case "$PLATFORM" in
    macos)
        echo "Platform: macOS"
        echo ""
        echo "Signing options:"
        echo "  • Developer ID Application — For distribution outside the App Store."
        echo "    Recipients can run the app without disabling Gatekeeper."
        echo "  • Apple Development / Mac Developer — For local development and testing."
        echo "    Requires the destination Mac to trust your certificate."
        echo "  • Apple Distribution / 3rd Party Mac Developer Application —"
        echo "    For Mac App Store submission (requires additional packaging)."
        echo "  • Ad-hoc (-) — No identity. The app runs on this Mac only."
        echo "    Gatekeeper will block it on other machines."
        ;;
    ios)
        echo "Platform: iOS (device)"
        echo ""
        echo "Signing options:"
        echo "  • Apple Development / iPhone Developer — For running on your own"
        echo "    devices registered in your developer account."
        echo "  • Apple Distribution / iPhone Distribution — For App Store"
        echo "    submission or enterprise distribution."
        echo "  • Ad-hoc (-) — Minimal signature. Will NOT install on devices"
        echo "    without a provisioning profile."
        ;;
    iossim)
        echo "Platform: iOS Simulator"
        echo ""
        echo "Signing options:"
        echo "  • Apple Development — Standard development signing for Simulator."
        echo "  • Ad-hoc (-) — Usually sufficient for Simulator use."
        ;;
    *)
        echo "signapp: unknown platform: $PLATFORM" >&2
        exit 1
        ;;
esac

echo ""

# ── Build menu ─────────────────────────────────────────────────────
N=0
if [ -n "$IDENTITIES" ]; then
    echo "Available signing identities:"
    echo ""
    echo "$IDENTITIES" | while IFS= read -r line; do
        # Extract the quoted description for display
        DESC=$(echo "$line" | sed 's/.*"\(.*\)".*/\1/')
        NUM=$(echo "$line" | sed 's/^\([0-9]*\)).*/\1/')
        echo "  $NUM) $DESC"
    done
    N=$(echo "$IDENTITIES" | wc -l | tr -d ' ')
fi

ADHOC_NUM=$((N + 1))
echo "  $ADHOC_NUM) Ad-hoc (no identity)"
echo ""

# ── Prompt ─────────────────────────────────────────────────────────
printf "Choose identity [1-%d]: " "$ADHOC_NUM"
read -r CHOICE

if [ -z "$CHOICE" ]; then
    echo "signapp: no selection made, aborting." >&2
    exit 1
fi

if [ "$CHOICE" -eq "$ADHOC_NUM" ] 2>/dev/null; then
    SIGN_ID="-"
    echo ""
    echo "Signing ad-hoc..."
else
    # Extract the SHA-1 hash from the chosen line
    LINE=$(echo "$IDENTITIES" | sed -n "${CHOICE}p")
    if [ -z "$LINE" ]; then
        echo "signapp: invalid selection." >&2
        exit 1
    fi
    SIGN_ID=$(echo "$LINE" | sed 's/^[0-9]*) *\([A-F0-9]*\).*/\1/')
    SIGN_DESC=$(echo "$LINE" | sed 's/.*"\(.*\)".*/\1/')
    echo ""
    echo "Signing with: $SIGN_DESC"
fi

# ── Sign ───────────────────────────────────────────────────────────

# Read permissions file for entitlements
_perm_camera=0
_perm_microphone=0
_permfile="$(dirname "$0")/../src/permissions"
if [ -f "$_permfile" ]; then
    while read -r _name _val; do
        case "$_name" in
            camera)     _perm_camera="$_val" ;;
            microphone) _perm_microphone="$_val" ;;
        esac
    done < "$_permfile"
fi

case "$PLATFORM" in
    macos)
        # Generate entitlements for camera/microphone access
        ENTITLEMENTS_FLAG=""
        if [ "$_perm_camera" = "1" ] || [ "$_perm_microphone" = "1" ]; then
            ENT_FILE=$(mktemp /tmp/signapp-ent.XXXXXX.plist)
            cat > "$ENT_FILE" <<ENTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
ENTEOF
            if [ "$_perm_camera" = "1" ]; then
                cat >> "$ENT_FILE" <<ENTEOF
    <key>com.apple.security.device.camera</key>
    <true/>
ENTEOF
            fi
            if [ "$_perm_microphone" = "1" ]; then
                cat >> "$ENT_FILE" <<ENTEOF
    <key>com.apple.security.device.audio-input</key>
    <true/>
ENTEOF
            fi
            cat >> "$ENT_FILE" <<ENTEOF
</dict>
</plist>
ENTEOF
            ENTITLEMENTS_FLAG="--entitlements $ENT_FILE"
        fi

        # shellcheck disable=SC2086
        xattr -cr "$BUNDLE"
        codesign --deep --force --options runtime \
            --sign "$SIGN_ID" \
            $ENTITLEMENTS_FLAG \
            "$BUNDLE"

        [ -n "$ENT_FILE" ] && rm -f "$ENT_FILE"
        ;;
    ios|iossim)
        # Generate minimal entitlements if a bundle ID was provided
        ENTITLEMENTS_FLAG=""
        if [ -n "$BUNDLE_ID" ]; then
            ENT_FILE=$(mktemp /tmp/signapp-ent.XXXXXX.plist)
            cat > "$ENT_FILE" <<ENTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>application-identifier</key>
    <string>$BUNDLE_ID</string>
    <key>get-task-allow</key>
    <true/>
</dict>
</plist>
ENTEOF
            ENTITLEMENTS_FLAG="--entitlements $ENT_FILE"
        fi

        # shellcheck disable=SC2086
        xattr -cr "$BUNDLE"
        codesign --force \
            --sign "$SIGN_ID" \
            --generate-entitlement-der \
            $ENTITLEMENTS_FLAG \
            "$BUNDLE"

        [ -n "$ENT_FILE" ] && rm -f "$ENT_FILE"
        ;;
esac

echo ""
echo "signapp: $BUNDLE signed successfully."

# Show signature info
echo ""
codesign -dvv "$BUNDLE" 2>&1 | grep -E '^(Authority|TeamIdentifier|Signature)'
