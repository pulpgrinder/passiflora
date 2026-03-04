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
</dict>
</plist>
PLIST

echo "mkbundle: ${APP} created"
