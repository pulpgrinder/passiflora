#!/bin/sh
# mkiosbundle.sh — Create an iOS application bundle (.app)
#
# Usage: mkiosbundle.sh <progname> <binary> <icon1024> <bundleid> [version] [outdir]
#
# Produces:  bin/iOS/<progname>.app/
#   <progname>           (the executable)
#   Info.plist
#   AppIcon60x60@2x.png (home screen icon, 120px)
#   AppIcon60x60@3x.png (home screen icon, 180px)
#   AppIcon76x76@2x.png (iPad icon, 152px)
#   LaunchScreen.storyboardc  (placeholder, optional — we use plist key)
#
set -e

PROGNAME="$1"
BINARY="$2"
ICON1024="$3"
BUNDLE_ID="${4:-com.example.$PROGNAME}"
VERSION="${5:-1.0.0}"
OUTDIR="$6"

if [ -z "$PROGNAME" ] || [ -z "$BINARY" ]; then
    echo "Usage: $0 <progname> <binary> <icon1024> [bundleid] [version] [outdir]" >&2
    exit 1
fi

# Read permissions file (default everything to 0)
_perm_location=0
_perm_camera=0
_perm_microphone=0
_perm_remotedebugging=0
_permfile="$(dirname "$0")/../src/permissions"
if [ -f "$_permfile" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
        _name="${_line%% *}"
        _val="${_line##* }"
        case "$_name" in
            location)         _perm_location="$_val" ;;
            camera)           _perm_camera="$_val" ;;
            microphone)       _perm_microphone="$_val" ;;
            remotedebugging)  _perm_remotedebugging="$_val" ;;
        esac
    done < "$_permfile"
fi

# Read config file (defaults)
_cfg_orientation="both"
_cfgfile="$(dirname "$0")/../src/config"
if [ -f "$_cfgfile" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
        _name="$(echo "${_line%% *}" | tr '[:upper:]' '[:lower:]')"
        _val="$(echo "${_line##* }" | tr '[:upper:]' '[:lower:]')"
        case "$_name" in
            orientation) _cfg_orientation="$_val" ;;
        esac
    done < "$_cfgfile"
fi

# Prefer magick (IM7) but fall back to convert (IM6)
if command -v magick >/dev/null 2>&1; then
    CONVERT="magick"
elif command -v convert >/dev/null 2>&1; then
    CONVERT="convert"
else
    echo "mkiosbundle: warning — ImageMagick not found, skipping icon embedding" >&2
    CONVERT=""
fi

BINDIR="$(dirname "$BINARY")"
# Use explicit outdir if given, otherwise default to bin/iOS/
if [ -n "$OUTDIR" ]; then
    IOS_DIR="$OUTDIR"
else
    IOS_DIR="$(dirname "$BINDIR")/iOS"
fi
APP="$IOS_DIR/${PROGNAME}.app"

# Clean previous bundle
rm -rf "$APP"
mkdir -p "$APP"

# Copy executable (flat bundle — no Contents/MacOS on iOS)
cp "$BINARY" "$APP/$PROGNAME"
chmod 755 "$APP/$PROGNAME"

# Embed icons from the pre-built icon set if available
IOS_ICONS="src/icons/builticons/ios"
if [ -d "$IOS_ICONS" ]; then
    # Copy the relevant iOS icon files
    for f in "$IOS_ICONS"/Icon-60@2x.png; do [ -f "$f" ] && cp "$f" "$APP/AppIcon60x60@2x.png"; done
    for f in "$IOS_ICONS"/Icon-60@3x.png; do [ -f "$f" ] && cp "$f" "$APP/AppIcon60x60@3x.png"; done
    for f in "$IOS_ICONS"/Icon-76@2x.png; do [ -f "$f" ] && cp "$f" "$APP/AppIcon76x76@2x.png"; done
    for f in "$IOS_ICONS"/Icon-83.5@2x.png; do [ -f "$f" ] && cp "$f" "$APP/AppIcon83.5x83.5@2x.png"; done
    for f in "$IOS_ICONS"/AppIcon-1024.png; do [ -f "$f" ] && cp "$f" "$APP/AppIcon1024x1024.png"; done
elif [ -n "$CONVERT" ] && [ -n "$ICON1024" ] && [ -f "$ICON1024" ]; then
    # Fall back to generating from the 1024 source
    $CONVERT "$ICON1024" -resize 120x120 "$APP/AppIcon60x60@2x.png"
    $CONVERT "$ICON1024" -resize 180x180 "$APP/AppIcon60x60@3x.png"
    $CONVERT "$ICON1024" -resize 152x152 "$APP/AppIcon76x76@2x.png"
    $CONVERT "$ICON1024" -resize 167x167 "$APP/AppIcon83.5x83.5@2x.png"
fi

# PkgInfo
printf 'APPL????' > "$APP/PkgInfo"

# Info.plist
cat > "$APP/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${PROGNAME}</string>

    <key>CFBundleDisplayName</key>
    <string>${PROGNAME}</string>

    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>

    <key>CFBundleVersion</key>
    <string>${VERSION}</string>

    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>

    <key>CFBundleExecutable</key>
    <string>${PROGNAME}</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>CFBundleSignature</key>
    <string>????</string>

    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <key>MinimumOSVersion</key>
    <string>15.0</string>

    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>iPhoneOS</string>
    </array>

    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>

    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>arm64</string>
    </array>

    <key>UISupportedInterfaceOrientations</key>
    <array>
PLIST

# Emit orientation entries based on config
case "$_cfg_orientation" in
    portrait)
        cat >> "$APP/Info.plist" << 'PLIST'
        <string>UIInterfaceOrientationPortrait</string>
PLIST
        ;;
    landscape)
        cat >> "$APP/Info.plist" << 'PLIST'
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
PLIST
        ;;
    *)
        cat >> "$APP/Info.plist" << 'PLIST'
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
PLIST
        ;;
esac

cat >> "$APP/Info.plist" << 'PLIST'
    </array>

    <key>UILaunchScreen</key>
    <dict/>

    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <false/>
        <key>UISceneConfigurations</key>
        <dict/>
    </dict>

    <key>CFBundleIcons</key>
    <dict>
        <key>CFBundlePrimaryIcon</key>
        <dict>
            <key>CFBundleIconFiles</key>
            <array>
                <string>AppIcon60x60</string>
                <string>AppIcon76x76</string>
                <string>AppIcon83.5x83.5</string>
            </array>
            <key>UIPrerenderedIcon</key>
            <false/>
        </dict>
    </dict>

    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>

    <key>UIFileSharingEnabled</key>
    <true/>

    <key>LSSupportsOpeningDocumentsInPlace</key>
    <true/>
PLIST

# Conditionally emit privacy plist keys based on src/permissions
if [ "$_perm_location" = "1" ]; then
    cat >> "$APP/Info.plist" << 'PLIST'

    <key>NSLocationWhenInUseUsageDescription</key>
    <string>This app needs your location for location-based features.</string>
PLIST
fi
if [ "$_perm_camera" = "1" ]; then
    cat >> "$APP/Info.plist" << 'PLIST'

    <key>NSCameraUsageDescription</key>
    <string>This app needs access to your camera for photo and video capture.</string>
PLIST
fi
if [ "$_perm_microphone" = "1" ]; then
    cat >> "$APP/Info.plist" << 'PLIST'

    <key>NSMicrophoneUsageDescription</key>
    <string>This app needs access to your microphone for audio and video recording.</string>
PLIST
fi
if [ "$_perm_remotedebugging" = "1" ]; then
    cat >> "$APP/Info.plist" << 'PLIST'

    <key>NSLocalNetworkUsageDescription</key>
    <string>This app uses the local network for remote debugging.</string>

    <key>NSBonjourServices</key>
    <array>
        <string>_http._tcp</string>
    </array>
PLIST
fi

cat >> "$APP/Info.plist" << 'PLIST'
</dict>
</plist>
PLIST

# Strip extended attributes (resource forks, provenance, etc.) so codesign
# and xcrun simctl install don't reject the bundle.
xattr -cr "$APP"

echo "mkiosbundle: ${APP} created"
