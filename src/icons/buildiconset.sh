#!/bin/bash
#
# buildiconset.sh — Generate all app icons for macOS, iOS, Android, and Windows
# from two source images in the same directory as this script.
#
# Original script Copyright (C) 2014 Wenva <lvyexuwenfa100@126.com>
# Modifications by Anthony W. Hursh <support@gorillapresenter.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is furnished
# to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

set -e

# Always use squareicon.png and roundicon.png from the script's directory,
# and output into a builticons subdirectory.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SQUARE_FILE="$SCRIPT_DIR/squareicon.png"
CIRCULAR_FILE="$SCRIPT_DIR/roundicon.png"
DST_PATH="$SCRIPT_DIR/builticons"

VERSION=3.0.0

info() {
     local green="\033[1;32m"
     local normal="\033[0m"
     echo -e "[${green}INFO${normal}] $1"
}

error() {
     local red="\033[1;31m"
     local normal="\033[0m"
     echo -e "[${red}ERROR${normal}] $1"
}

usage() {
cat << EOF
VERSION: $VERSION
USAGE:
    $0

DESCRIPTION:
    Generates app icons for macOS, iOS, Android, and Windows from two
    source images in the same directory as this script:

    squareicon.png  - A square png image with your app icon/logo.
                      Should be at least 1024x1024 (4096x4096 recommended).

    roundicon.png   - A square png with an inscribed circular region
                      containing the important parts. Used for Android
                      circular/adaptive icons.

    Generated icons are placed in a builticons/ subdirectory, organized
    by platform: builticons/macos/, builticons/ios/, builticons/android/,
    and builticons/windows/.

    Requires ImageMagick. On macOS with Homebrew:
    'brew install ImageMagick'

LICENSE:
    MIT license.

EXAMPLE:
    $0
EOF
}

# ── Prefer magick (IM7) but fall back to convert (IM6) ──────────
if command -v magick >/dev/null 2>&1; then
    CONVERT="magick"
elif command -v convert >/dev/null 2>&1; then
    CONVERT="convert"
else
    error "ImageMagick is not installed. Please install it first."
    exit 1
fi

# Check that source images exist
if [ ! -f "$SQUARE_FILE" ]; then
    error "squareicon.png not found in $SCRIPT_DIR"
    usage
    exit 1
fi
if [ ! -f "$CIRCULAR_FILE" ]; then
    error "roundicon.png not found in $SCRIPT_DIR"
    usage
    exit 1
fi

# Create output directories
mkdir -p "$DST_PATH/macos/AppIcon.iconset"
mkdir -p "$DST_PATH/ios"
mkdir -p "$DST_PATH/windows"
mkdir -p "$DST_PATH/android/app/src/main/assets/public/assets/images"
mkdir -p "$DST_PATH/android/app/src/main/res/drawable"
for density in hdpi mdpi xhdpi xxhdpi xxxhdpi; do
    mkdir -p "$DST_PATH/android/app/src/main/res/drawable-land-$density"
    mkdir -p "$DST_PATH/android/app/src/main/res/drawable-port-$density"
    mkdir -p "$DST_PATH/android/app/src/main/res/mipmap-$density"
done

# ================================================================
#  macOS — AppIcon.iconset (used by iconutil to produce .icns)
#  Ref: https://developer.apple.com/design/human-interface-guidelines/app-icons
# ================================================================
info 'Generating macOS icons (AppIcon.iconset)...'
ICONSET="$DST_PATH/macos/AppIcon.iconset"

$CONVERT "$SQUARE_FILE" -resize 16x16     "$ICONSET/icon_16x16.png"
$CONVERT "$SQUARE_FILE" -resize 32x32     "$ICONSET/icon_16x16@2x.png"
$CONVERT "$SQUARE_FILE" -resize 32x32     "$ICONSET/icon_32x32.png"
$CONVERT "$SQUARE_FILE" -resize 64x64     "$ICONSET/icon_32x32@2x.png"
$CONVERT "$SQUARE_FILE" -resize 128x128   "$ICONSET/icon_128x128.png"
$CONVERT "$SQUARE_FILE" -resize 256x256   "$ICONSET/icon_128x128@2x.png"
$CONVERT "$SQUARE_FILE" -resize 256x256   "$ICONSET/icon_256x256.png"
$CONVERT "$SQUARE_FILE" -resize 512x512   "$ICONSET/icon_256x256@2x.png"
$CONVERT "$SQUARE_FILE" -resize 512x512   "$ICONSET/icon_512x512.png"
$CONVERT "$SQUARE_FILE" -resize 1024x1024 "$ICONSET/icon_512x512@2x.png"

# If iconutil is available (macOS), also build the .icns file
if command -v iconutil >/dev/null 2>&1; then
    info 'Building AppIcon.icns with iconutil...'
    iconutil -c icns -o "$DST_PATH/macos/AppIcon.icns" "$ICONSET"
fi

# ================================================================
#  iOS — Universal icon (1024x1024) + legacy sizes
#  Xcode 15+: a single 1024x1024 is sufficient for all devices.
#  Legacy sizes kept for older Xcode / manual asset catalogs.
# ================================================================
info 'Generating iOS icons...'
IOS="$DST_PATH/ios"

# Single universal icon (Xcode 15+)
$CONVERT "$SQUARE_FILE" -resize 1024x1024 "$IOS/AppIcon-1024.png"

# iPhone Notification 20pt
$CONVERT "$SQUARE_FILE" -resize 20x20   "$IOS/Icon-20.png"
$CONVERT "$SQUARE_FILE" -resize 40x40   "$IOS/Icon-20@2x.png"
$CONVERT "$SQUARE_FILE" -resize 60x60   "$IOS/Icon-20@3x.png"

# iPhone Settings 29pt
$CONVERT "$SQUARE_FILE" -resize 29x29   "$IOS/Icon-29.png"
$CONVERT "$SQUARE_FILE" -resize 58x58   "$IOS/Icon-29@2x.png"
$CONVERT "$SQUARE_FILE" -resize 87x87   "$IOS/Icon-29@3x.png"

# iPhone Spotlight 40pt
$CONVERT "$SQUARE_FILE" -resize 40x40   "$IOS/Icon-40.png"
$CONVERT "$SQUARE_FILE" -resize 80x80   "$IOS/Icon-40@2x.png"
$CONVERT "$SQUARE_FILE" -resize 120x120 "$IOS/Icon-40@3x.png"

# iPhone App 60pt
$CONVERT "$SQUARE_FILE" -resize 60x60   "$IOS/Icon-60.png"
$CONVERT "$SQUARE_FILE" -resize 120x120 "$IOS/Icon-60@2x.png"
$CONVERT "$SQUARE_FILE" -resize 180x180 "$IOS/Icon-60@3x.png"

# iPad App 76pt
$CONVERT "$SQUARE_FILE" -resize 76x76   "$IOS/Icon-76.png"
$CONVERT "$SQUARE_FILE" -resize 152x152 "$IOS/Icon-76@2x.png"

# iPad Pro App 83.5pt
$CONVERT "$SQUARE_FILE" -resize 167x167 "$IOS/Icon-83.5@2x.png"

# App Store
$CONVERT "$SQUARE_FILE" -resize 512x512   "$IOS/iTunesArtwork.png"
$CONVERT "$SQUARE_FILE" -resize 1024x1024 "$IOS/iTunesArtwork@2x.png"

# ================================================================
#  Windows — ICO file + individual PNGs for MSIX / Store
#  Ref: https://learn.microsoft.com/en-us/windows/apps/design/style/iconography/app-icon-design
# ================================================================
info 'Generating Windows icons...'
WIN="$DST_PATH/windows"

# Individual PNG sizes used by MSIX packaging and Windows Store
for sz in 16 24 32 48 64 128 256; do
    $CONVERT "$SQUARE_FILE" -resize ${sz}x${sz} "$WIN/icon-${sz}.png"
done

# Windows Store / MSIX asset sizes (square)
$CONVERT "$SQUARE_FILE" -resize 44x44     "$WIN/Square44x44Logo.png"
$CONVERT "$SQUARE_FILE" -resize 50x50     "$WIN/StoreLogo-50.png"
$CONVERT "$SQUARE_FILE" -resize 71x71     "$WIN/SmallTile-71.png"
$CONVERT "$SQUARE_FILE" -resize 150x150   "$WIN/Square150x150Logo.png"
$CONVERT "$SQUARE_FILE" -resize 310x310   "$WIN/Square310x310Logo.png"
$CONVERT "$SQUARE_FILE" -resize 310x150   "$WIN/Wide310x150Logo.png"

# Scale variants for Square44x44Logo
$CONVERT "$SQUARE_FILE" -resize 44x44     "$WIN/Square44x44Logo.scale-100.png"
$CONVERT "$SQUARE_FILE" -resize 55x55     "$WIN/Square44x44Logo.scale-125.png"
$CONVERT "$SQUARE_FILE" -resize 66x66     "$WIN/Square44x44Logo.scale-150.png"
$CONVERT "$SQUARE_FILE" -resize 88x88     "$WIN/Square44x44Logo.scale-200.png"
$CONVERT "$SQUARE_FILE" -resize 176x176   "$WIN/Square44x44Logo.scale-400.png"

# Scale variants for Square150x150Logo
$CONVERT "$SQUARE_FILE" -resize 150x150   "$WIN/Square150x150Logo.scale-100.png"
$CONVERT "$SQUARE_FILE" -resize 188x188   "$WIN/Square150x150Logo.scale-125.png"
$CONVERT "$SQUARE_FILE" -resize 225x225   "$WIN/Square150x150Logo.scale-150.png"
$CONVERT "$SQUARE_FILE" -resize 300x300   "$WIN/Square150x150Logo.scale-200.png"
$CONVERT "$SQUARE_FILE" -resize 600x600   "$WIN/Square150x150Logo.scale-400.png"

# Target size variants (unplated) for Square44x44Logo
for sz in 16 24 32 48 256; do
    $CONVERT "$SQUARE_FILE" -resize ${sz}x${sz} "$WIN/Square44x44Logo.targetsize-${sz}.png"
done

# Build a multi-resolution .ico (16, 24, 32, 48, 64, 128, 256)
info 'Building app.ico...'
$CONVERT "$WIN/icon-16.png" "$WIN/icon-24.png" "$WIN/icon-32.png" \
         "$WIN/icon-48.png" "$WIN/icon-64.png" "$WIN/icon-128.png" \
         "$WIN/icon-256.png" "$WIN/app.ico"

# ================================================================
#  Android — Adaptive icons, legacy icons, and splash screens
#  Ref: https://developer.android.com/develop/ui/views/launch/icon_design_adaptive
# ================================================================
info 'Generating Android icons...'
ANDROID="$DST_PATH/android/app/src/main/res"

# Logo for web/assets
$CONVERT "$SQUARE_FILE" -resize 512x512 "$DST_PATH/android/app/src/main/assets/public/assets/images/logo.png"

# Google Play Store icon
$CONVERT "$SQUARE_FILE" -resize 512x512 "$DST_PATH/android/play_store_icon.png"

# Adaptive icon foreground (108dp per density)
info 'Generating adaptive icon foreground layers...'
$CONVERT "$SQUARE_FILE" -resize 108x108 "$ANDROID/mipmap-mdpi/ic_launcher_foreground.png"
$CONVERT "$SQUARE_FILE" -resize 162x162 "$ANDROID/mipmap-hdpi/ic_launcher_foreground.png"
$CONVERT "$SQUARE_FILE" -resize 216x216 "$ANDROID/mipmap-xhdpi/ic_launcher_foreground.png"
$CONVERT "$SQUARE_FILE" -resize 324x324 "$ANDROID/mipmap-xxhdpi/ic_launcher_foreground.png"
$CONVERT "$SQUARE_FILE" -resize 432x432 "$ANDROID/mipmap-xxxhdpi/ic_launcher_foreground.png"

# Round icons (from circular source)
info 'Generating round launcher icons...'
$CONVERT "$CIRCULAR_FILE" -resize 48x48   "$ANDROID/mipmap-mdpi/ic_launcher_round.png"
$CONVERT "$CIRCULAR_FILE" -resize 72x72   "$ANDROID/mipmap-hdpi/ic_launcher_round.png"
$CONVERT "$CIRCULAR_FILE" -resize 96x96   "$ANDROID/mipmap-xhdpi/ic_launcher_round.png"
$CONVERT "$CIRCULAR_FILE" -resize 144x144 "$ANDROID/mipmap-xxhdpi/ic_launcher_round.png"
$CONVERT "$CIRCULAR_FILE" -resize 192x192 "$ANDROID/mipmap-xxxhdpi/ic_launcher_round.png"

# Legacy square launcher icons
info 'Generating legacy launcher icons...'
$CONVERT "$SQUARE_FILE" -resize 48x48   "$ANDROID/mipmap-mdpi/ic_launcher.png"
$CONVERT "$SQUARE_FILE" -resize 72x72   "$ANDROID/mipmap-hdpi/ic_launcher.png"
$CONVERT "$SQUARE_FILE" -resize 96x96   "$ANDROID/mipmap-xhdpi/ic_launcher.png"
$CONVERT "$SQUARE_FILE" -resize 144x144 "$ANDROID/mipmap-xxhdpi/ic_launcher.png"
$CONVERT "$SQUARE_FILE" -resize 192x192 "$ANDROID/mipmap-xxxhdpi/ic_launcher.png"

# Monochrome icon (used by Android 13+ themed icons — grayscale of square)
info 'Generating monochrome icons for Android 13+ themed icons...'
$CONVERT "$SQUARE_FILE" -resize 108x108 -colorspace Gray "$ANDROID/mipmap-mdpi/ic_launcher_monochrome.png"
$CONVERT "$SQUARE_FILE" -resize 162x162 -colorspace Gray "$ANDROID/mipmap-hdpi/ic_launcher_monochrome.png"
$CONVERT "$SQUARE_FILE" -resize 216x216 -colorspace Gray "$ANDROID/mipmap-xhdpi/ic_launcher_monochrome.png"
$CONVERT "$SQUARE_FILE" -resize 324x324 -colorspace Gray "$ANDROID/mipmap-xxhdpi/ic_launcher_monochrome.png"
$CONVERT "$SQUARE_FILE" -resize 432x432 -colorspace Gray "$ANDROID/mipmap-xxxhdpi/ic_launcher_monochrome.png"

# Notification icons (white silhouette — just resize; user should provide proper asset)
info 'Generating notification icons...'
$CONVERT "$SQUARE_FILE" -resize 24x24 "$ANDROID/mipmap-mdpi/ic_stat_notify.png"
$CONVERT "$SQUARE_FILE" -resize 36x36 "$ANDROID/mipmap-hdpi/ic_stat_notify.png"
$CONVERT "$SQUARE_FILE" -resize 48x48 "$ANDROID/mipmap-xhdpi/ic_stat_notify.png"
$CONVERT "$SQUARE_FILE" -resize 72x72 "$ANDROID/mipmap-xxhdpi/ic_stat_notify.png"
$CONVERT "$SQUARE_FILE" -resize 96x96 "$ANDROID/mipmap-xxxhdpi/ic_stat_notify.png"

# Splash screens (blank gray placeholders)
info 'Generating splash screens...'
$CONVERT -size 430x320   canvas:"#bbb" "$ANDROID/drawable/splash.png"
$CONVERT -size 800x480   canvas:"#bbb" "$ANDROID/drawable-land-hdpi/splash.png"
$CONVERT -size 480x320   canvas:"#bbb" "$ANDROID/drawable-land-mdpi/splash.png"
$CONVERT -size 1280x720  canvas:"#bbb" "$ANDROID/drawable-land-xhdpi/splash.png"
$CONVERT -size 1600x960  canvas:"#bbb" "$ANDROID/drawable-land-xxhdpi/splash.png"
$CONVERT -size 1920x1280 canvas:"#bbb" "$ANDROID/drawable-land-xxxhdpi/splash.png"
$CONVERT -size 480x800   canvas:"#bbb" "$ANDROID/drawable-port-hdpi/splash.png"
$CONVERT -size 320x480   canvas:"#bbb" "$ANDROID/drawable-port-mdpi/splash.png"
$CONVERT -size 720x1280  canvas:"#bbb" "$ANDROID/drawable-port-xhdpi/splash.png"
$CONVERT -size 960x1600  canvas:"#bbb" "$ANDROID/drawable-port-xxhdpi/splash.png"
$CONVERT -size 1280x1920 canvas:"#bbb" "$ANDROID/drawable-port-xxxhdpi/splash.png"

# ================================================================
info 'All done! Icons generated in:'"$DST_PATH"
