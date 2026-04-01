#!/bin/sh
# mkbundle.sh — Create a macOS application bundle (.app)
#
# Usage: mkbundle.sh <progname> <binary> <icns> <bundleid> [version]
#
# Produces:  bin/macOS/<progname>.app/
#   Contents/
#     Info.plist
#     PkgInfo
#     MacOS/<progname>      (the executable)
#     Resources/AppIcon.icns
#
set -e

PROGNAME="$1"
BINARY="$2"
ICNS="$3"
BUNDLE_ID="${4:-com.example.$PROGNAME}"
VERSION="${5:-1.0.0}"

if [ -z "$PROGNAME" ] || [ -z "$BINARY" ]; then
    echo "Usage: $0 <progname> <binary> <icns> [bundleid] [version]" >&2
    exit 1
fi

# Read config file (permissions + settings)
_perm_location=false
_perm_camera=false
_perm_microphone=false
_cfgfile="$(dirname "$0")/../src/config"
if [ -f "$_cfgfile" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
        _name="$(echo "${_line%% *}" | tr '[:upper:]' '[:lower:]')"
        _val="$(echo "${_line##* }" | tr '[:upper:]' '[:lower:]')"
        case "$_name" in
            uselocation)   _perm_location="$_val" ;;
            usecamera)     _perm_camera="$_val" ;;
            usemicrophone) _perm_microphone="$_val" ;;
        esac
    done < "$_cfgfile"
fi

BINDIR="$(dirname "$BINARY")"
APP="$BINDIR/${PROGNAME}.app"

# Clean previous bundle
rm -rf "$APP"

# Create bundle structure
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Copy executable
cp "$BINARY" "$APP/Contents/MacOS/$PROGNAME"
chmod 755 "$APP/Contents/MacOS/$PROGNAME"

# Copy icon if available
if [ -n "$ICNS" ] && [ -f "$ICNS" ]; then
    cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
fi

# PkgInfo
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Info.plist
cat > "$APP/Contents/Info.plist" << PLIST
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

    <key>CFBundleIconFile</key>
    <string>AppIcon</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>CFBundleSignature</key>
    <string>????</string>

    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>

    <key>LSMinimumSystemVersion</key>
    <string>10.13</string>

    <key>NSHighResolutionCapable</key>
    <true/>

    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>

    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
PLIST

# Conditionally emit privacy plist keys based on src/config
if [ "$_perm_location" = "true" ]; then
    cat >> "$APP/Contents/Info.plist" << 'PLIST'

    <key>NSLocationWhenInUseUsageDescription</key>
    <string>This app needs your location for location-based features.</string>
    <key>NSLocationUsageDescription</key>
    <string>This app needs your location for location-based features.</string>
    <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
    <string>This app needs your location for location-based features.</string>
    <key>NSLocationAlwaysUsageDescription</key>
    <string>This app needs your location for location-based features.</string>
PLIST
fi
if [ "$_perm_camera" = "true" ]; then
    cat >> "$APP/Contents/Info.plist" << 'PLIST'

    <key>NSCameraUsageDescription</key>
    <string>This app needs access to your camera for photo and video capture.</string>
PLIST
fi
if [ "$_perm_microphone" = "true" ]; then
    cat >> "$APP/Contents/Info.plist" << 'PLIST'

    <key>NSMicrophoneUsageDescription</key>
    <string>This app needs access to your microphone for audio and video recording.</string>
PLIST
fi

cat >> "$APP/Contents/Info.plist" << 'PLIST'
</dict>
</plist>
PLIST

echo "mkbundle: ${APP} created"
