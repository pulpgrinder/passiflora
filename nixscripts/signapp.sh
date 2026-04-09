#!/bin/sh
# signapp.sh — Interactively sign a macOS or iOS application bundle.
#
# Usage: signapp.sh <platform> <bundle.app> [bundleid]
#
#   platform:  macos | ios | iossim
#   bundle:    Path to the .app bundle
#   bundleid:  Bundle identifier (used for entitlements, optional)
#
# macOS:
#   Produces two distribution-ready artifacts:
#     1. Notarized .app for distribution outside the App Store (Developer ID)
#     2. Signed .pkg for Mac App Store submission
#   Each step can be skipped interactively.
#
# iOS:
#   Signs the .app bundle. The Makefile's sign-ios target handles IPA packaging.
#   When signed with an Apple Distribution certificate and an App Store
#   provisioning profile, the resulting .ipa is ready for App Store submission.
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

# Read config file for entitlements
_perm_camera=false
_perm_microphone=false
_cfgfile="$(dirname "$0")/../src/config"
if [ -f "$_cfgfile" ]; then
    while read -r _name _val; do
        _name="$(echo "$_name" | tr '[:upper:]' '[:lower:]')"
        _val="$(echo "$_val" | tr '[:upper:]' '[:lower:]')"
        case "$_name" in
            usecamera)     _perm_camera="$_val" ;;
            usemicrophone) _perm_microphone="$_val" ;;
        esac
    done < "$_cfgfile"
fi

# ── Helper: list identities and prompt for a choice ────────────────
# Usage: choose_identity "prompt_label" [filter_grep_pattern]
# Sets: CHOSEN_SIGN_ID, CHOSEN_SIGN_DESC
choose_identity() {
    _label="$1"
    _filter="${2:-}"
    _idents=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -E '^\s+[0-9]+\)' | sed 's/^[[:space:]]*//')
    if [ -n "$_filter" ]; then
        _idents=$(echo "$_idents" | grep -i "$_filter" || true)
    fi

    _n=0
    if [ -n "$_idents" ]; then
        echo "Available signing identities${_label:+ ($_label)}:"
        echo ""
        # Re-number for display
        _i=0
        echo "$_idents" | while IFS= read -r _line; do
            _i=$((_i + 1))
            _desc=$(echo "$_line" | sed 's/.*"\(.*\)".*/\1/')
            echo "  $_i) $_desc"
        done
        _n=$(echo "$_idents" | wc -l | tr -d ' ')
    fi

    _adhoc=$((_n + 1))
    echo "  $_adhoc) Ad-hoc (no identity)"
    echo ""
    printf "Choose identity [1-%d]: " "$_adhoc"
    read -r _choice

    if [ -z "$_choice" ]; then
        CHOSEN_SIGN_ID=""
        CHOSEN_SIGN_DESC=""
        return 1
    fi

    if [ "$_choice" -eq "$_adhoc" ] 2>/dev/null; then
        CHOSEN_SIGN_ID="-"
        CHOSEN_SIGN_DESC="ad-hoc"
        return 0
    fi

    _line=$(echo "$_idents" | sed -n "${_choice}p")
    if [ -z "$_line" ]; then
        echo "signapp: invalid selection." >&2
        CHOSEN_SIGN_ID=""
        CHOSEN_SIGN_DESC=""
        return 1
    fi
    CHOSEN_SIGN_ID=$(echo "$_line" | sed 's/^[0-9]*) *\([A-F0-9]*\).*/\1/')
    CHOSEN_SIGN_DESC=$(echo "$_line" | sed 's/.*"\(.*\)".*/\1/')
    return 0
}

# ── Helper: generate macOS entitlements plist ──────────────────────
# Usage: make_macos_entitlements
# Sets: ENTITLEMENTS_FLAG, ENT_FILE (caller must clean up)
make_macos_entitlements() {
    ENTITLEMENTS_FLAG=""
    ENT_FILE=""
    if [ "$_perm_camera" = "true" ] || [ "$_perm_microphone" = "true" ]; then
        ENT_FILE=$(mktemp /tmp/signapp-ent.XXXXXX.plist)
        cat > "$ENT_FILE" <<ENTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
ENTEOF
        if [ "$_perm_camera" = "true" ]; then
            cat >> "$ENT_FILE" <<ENTEOF
    <key>com.apple.security.device.camera</key>
    <true/>
ENTEOF
        fi
        if [ "$_perm_microphone" = "true" ]; then
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
}

# ════════════════════════════════════════════════════════════════════
#  macOS — full distribution workflow
# ════════════════════════════════════════════════════════════════════
if [ "$PLATFORM" = "macos" ]; then
    echo ""
    echo "=== Code Signing: $BUNDLE ==="
    echo ""
    echo "This target can produce two distribution-ready artifacts:"
    echo "  1. Notarized .app — for distribution outside the App Store (Developer ID)"
    echo "  2. Signed .pkg   — for Mac App Store submission"
    echo ""
    echo "You will be prompted for each step and can skip either one."
    echo ""

    BUNDLE_DIR=$(dirname "$BUNDLE")

    # Ensure all temporary files are removed on exit (even on error)
    ENT_FILE=""
    _zip_file=""
    _mas_bundle=""
    trap '[ -n "$ENT_FILE" ] && rm -f "$ENT_FILE"; [ -n "$_zip_file" ] && rm -f "$_zip_file"; [ -n "$_mas_bundle" ] && rm -rf "$_mas_bundle"' EXIT

    # ── Step 1: Developer ID signing + notarization ────────────────
    echo "━━━ Step 1: Developer ID distribution (outside App Store) ━━━"
    echo ""
    printf "Sign and notarize for distribution outside the App Store? [y/N]: "
    read -r _do_devid
    echo ""

    if [ "$_do_devid" = "y" ] || [ "$_do_devid" = "Y" ]; then
        echo "Choose a Developer ID Application identity:"
        echo ""
        if choose_identity "Developer ID"; then
            DEVID_SIGN_ID="$CHOSEN_SIGN_ID"
            DEVID_SIGN_DESC="$CHOSEN_SIGN_DESC"

            echo ""
            echo "Signing with: $DEVID_SIGN_DESC"

            make_macos_entitlements
            # shellcheck disable=SC2086
            xattr -cr "$BUNDLE"
            codesign --deep --force --options runtime \
                --sign "$DEVID_SIGN_ID" \
                $ENTITLEMENTS_FLAG \
                "$BUNDLE"
            [ -n "$ENT_FILE" ] && rm -f "$ENT_FILE"

            echo ""
            echo "signapp: $BUNDLE signed (Developer ID)."
            codesign -dvv "$BUNDLE" 2>&1 | grep -E '^(Authority|TeamIdentifier|Signature)'

            # Notarization (only meaningful with a real identity)
            if [ "$DEVID_SIGN_ID" != "-" ]; then
                echo ""
                echo "── Notarization ──"
                echo ""
                echo "Notarization requires an Apple ID and an app-specific password."
                echo "Generate an app-specific password at https://appleid.apple.com/account/manage"
                echo "or store credentials with:"
                echo "  xcrun notarytool store-credentials \"notary-profile\" \\"
                echo "      --apple-id your@apple.id --team-id TEAMID --password <app-specific-pw>"
                echo ""
                printf "Do you have a stored keychain profile for notarytool? [y/N]: "
                read -r _has_profile

                if [ "$_has_profile" = "y" ] || [ "$_has_profile" = "Y" ]; then
                    printf "Keychain profile name: "
                    read -r _profile_name
                    if [ -n "$_profile_name" ]; then
                        echo ""
                        echo "signapp: zipping app bundle for notarization..."
                        _zip_file="$BUNDLE_DIR/$(basename "$BUNDLE" .app)-notarize.zip"
                        ditto -c -k --keepParent "$BUNDLE" "$_zip_file"

                        echo "signapp: submitting to Apple notary service (this may take several minutes)..."
                        xcrun notarytool submit "$_zip_file" \
                            --keychain-profile "$_profile_name" \
                            --wait

                        rm -f "$_zip_file"

                        echo ""
                        echo "signapp: stapling notarization ticket..."
                        xcrun stapler staple "$BUNDLE"

                        echo "signapp: notarization complete. The app is ready for distribution outside the App Store."
                    fi
                else
                    printf "Apple ID: "
                    read -r _apple_id
                    if [ -n "$_apple_id" ]; then
                        printf "App-specific password: "
                        stty -echo 2>/dev/null; read -r _apple_pw; stty echo 2>/dev/null; echo
                        printf "Team ID: "
                        read -r _team_id

                        if [ -n "$_apple_pw" ] && [ -n "$_team_id" ]; then
                            echo ""
                            echo "signapp: zipping app bundle for notarization..."
                            _zip_file="$BUNDLE_DIR/$(basename "$BUNDLE" .app)-notarize.zip"
                            ditto -c -k --keepParent "$BUNDLE" "$_zip_file"

                            echo "signapp: submitting to Apple notary service (this may take several minutes)..."
                            xcrun notarytool submit "$_zip_file" \
                                --apple-id "$_apple_id" \
                                --password "$_apple_pw" \
                                --team-id "$_team_id" \
                                --wait

                            rm -f "$_zip_file"

                            echo ""
                            echo "signapp: stapling notarization ticket..."
                            xcrun stapler staple "$BUNDLE"

                            echo "signapp: notarization complete. The app is ready for distribution outside the App Store."
                        else
                            echo "signapp: skipping notarization (missing credentials)."
                        fi
                    else
                        echo "signapp: skipping notarization."
                    fi
                fi
            else
                echo ""
                echo "signapp: ad-hoc signed — notarization not applicable."
            fi
        else
            echo "signapp: skipping Developer ID signing."
        fi
    else
        echo "Skipping Developer ID distribution."
    fi

    # ── Step 2: Mac App Store .pkg ─────────────────────────────────
    echo ""
    echo "━━━ Step 2: Mac App Store .pkg ━━━"
    echo ""
    printf "Create a signed .pkg for Mac App Store submission? [y/N]: "
    read -r _do_mas
    echo ""

    if [ "$_do_mas" = "y" ] || [ "$_do_mas" = "Y" ]; then
        # We need an App Store application identity and an installer identity.
        # Make a working copy so we don't clobber the Developer ID–signed .app.
        _mas_bundle="$BUNDLE_DIR/$(basename "$BUNDLE" .app)-MAS.app"
        echo "signapp: creating App Store copy → $(basename "$_mas_bundle")"
        rm -rf "$_mas_bundle"
        cp -R "$BUNDLE" "$_mas_bundle"

        echo ""
        echo "Choose an application signing identity for the App Store."
        echo "(Use \"Apple Distribution\" or \"3rd Party Mac Developer Application\".)"
        echo ""
        if choose_identity "App Store application"; then
            MAS_APP_ID="$CHOSEN_SIGN_ID"
            echo ""
            echo "Signing App Store copy with: $CHOSEN_SIGN_DESC"

            make_macos_entitlements

            # App Store builds need the sandbox entitlement
            if [ -z "$ENT_FILE" ]; then
                ENT_FILE=$(mktemp /tmp/signapp-ent.XXXXXX.plist)
                cat > "$ENT_FILE" <<ENTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
ENTEOF
                ENTITLEMENTS_FLAG="--entitlements $ENT_FILE"
            else
                # Inject sandbox entitlement into existing file (before closing </dict>)
                sed -i '' 's|</dict>|    <key>com.apple.security.app-sandbox</key>\
    <true/>\
</dict>|' "$ENT_FILE"
            fi

            # shellcheck disable=SC2086
            xattr -cr "$_mas_bundle"
            codesign --deep --force --options runtime \
                --sign "$MAS_APP_ID" \
                $ENTITLEMENTS_FLAG \
                "$_mas_bundle"
            [ -n "$ENT_FILE" ] && rm -f "$ENT_FILE"

            echo ""
            echo "signapp: App Store copy signed."

            # Now create the .pkg with an installer identity
            echo ""
            echo "Choose an installer signing identity for the .pkg."
            echo "(Use \"3rd Party Mac Developer Installer\" or \"Developer ID Installer\".)"
            echo ""

            # List installer identities (not codesigning — these are in the "Mac Installer Distribution" category)
            _inst_idents=$(security find-identity -v 2>/dev/null \
                | grep -iE 'installer|3rd Party Mac Developer Installer' \
                | grep -E '^\s+[0-9]+\)' | sed 's/^[[:space:]]*//' || true)

            _in=0
            if [ -n "$_inst_idents" ]; then
                echo "Available installer identities:"
                echo ""
                _i=0
                echo "$_inst_idents" | while IFS= read -r _line; do
                    _i=$((_i + 1))
                    _desc=$(echo "$_line" | sed 's/.*"\(.*\)".*/\1/')
                    echo "  $_i) $_desc"
                done
                _in=$(echo "$_inst_idents" | wc -l | tr -d ' ')
            fi

            _unsigned_num=$((_in + 1))
            echo "  $_unsigned_num) Unsigned .pkg (no installer identity)"
            echo ""
            printf "Choose installer identity [1-%d]: " "$_unsigned_num"
            read -r _ichoice

            _pkg_name="$(basename "$BUNDLE" .app).pkg"
            _pkg_path="$BUNDLE_DIR/$_pkg_name"

            if [ -n "$_ichoice" ] && [ "$_ichoice" -ne "$_unsigned_num" ] 2>/dev/null; then
                _iline=$(echo "$_inst_idents" | sed -n "${_ichoice}p")
                if [ -n "$_iline" ]; then
                    _inst_id=$(echo "$_iline" | sed 's/^[0-9]*) *\([A-F0-9]*\).*/\1/')
                    _inst_desc=$(echo "$_iline" | sed 's/.*"\(.*\)".*/\1/')
                    echo ""
                    echo "Building .pkg with installer identity: $_inst_desc"
                    productbuild --component "$_mas_bundle" /Applications \
                        --sign "$_inst_id" \
                        "$_pkg_path"
                else
                    echo "signapp: invalid selection, building unsigned .pkg." >&2
                    productbuild --component "$_mas_bundle" /Applications \
                        "$_pkg_path"
                fi
            else
                echo ""
                echo "Building unsigned .pkg..."
                productbuild --component "$_mas_bundle" /Applications \
                    "$_pkg_path"
            fi

            rm -rf "$_mas_bundle"
            echo ""
            echo "signapp: $_pkg_name created at $_pkg_path"
            echo "signapp: the .pkg is ready for upload to App Store Connect."
        else
            rm -rf "$_mas_bundle"
            echo "signapp: skipping App Store .pkg."
        fi
    else
        echo "Skipping Mac App Store .pkg."
    fi

    echo ""
    echo "=== macOS signing complete ==="
    exit 0
fi

# ════════════════════════════════════════════════════════════════════
#  iOS / iOS Simulator
# ════════════════════════════════════════════════════════════════════

# ── Gather signing identities ──────────────────────────────────────
IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E '^\s+[0-9]+\)' | sed 's/^[[:space:]]*//')

echo ""
echo "=== Code Signing: $BUNDLE ==="
echo ""

case "$PLATFORM" in
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

# ── Sign iOS/Simulator ────────────────────────────────────────────
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

echo ""
echo "signapp: $BUNDLE signed successfully."
echo ""
codesign -dvv "$BUNDLE" 2>&1 | grep -E '^(Authority|TeamIdentifier|Signature)'
