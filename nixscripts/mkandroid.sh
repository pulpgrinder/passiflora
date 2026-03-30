#!/bin/sh
# mkandroid.sh — Build Android APK from the Gradle project.
#
# Usage: mkandroid.sh <progname> [bundleid] [version]
#
# Requires:
#   - Android SDK (ANDROID_HOME or ~/Library/Android/sdk)
#   - gradle on PATH  (brew install gradle)
#   - Java 17+        (brew install openjdk@17)
#
# Produces: bin/Android/<progname>.apk
#
set -e

PROGNAME="${1:?Usage: $0 <progname> [bundleid] [version]}"
BUNDLE_ID="${2:-com.example.passiflora}"
VERSION="${3:-1.0.0}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANDROID_DIR="$PROJECT_ROOT/src/android"
BUILD_TYPE="${BUILD_TYPE:-debug}"

# ── Read src/permissions ───────────────────────────────────────────
PERM_LOCATION=0
PERM_CAMERA=0
PERM_MICROPHONE=0
PERM_REMOTEDEBUGGING=0
PERM_FILE="$PROJECT_ROOT/src/permissions"
if [ -f "$PERM_FILE" ]; then
    while IFS=' ' read -r name val rest || [ -n "$name" ]; do
        case "$name" in
            location)    PERM_LOCATION="$val" ;;
            camera)      PERM_CAMERA="$val" ;;
            microphone)  PERM_MICROPHONE="$val" ;;
            remotedebugging)  PERM_REMOTEDEBUGGING="$val" ;;
        esac
    done < "$PERM_FILE"
fi

# ── Generate AndroidManifest.xml with only enabled permissions ─────
MANIFEST="$ANDROID_DIR/app/src/main/AndroidManifest.xml"
{
    printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>'
    printf '%s\n' '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
    printf '\n'
    printf '%s\n' '    <uses-permission android:name="android.permission.INTERNET" />'
    [ "$PERM_LOCATION" = "1" ] && {
        printf '%s\n' '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />'
        printf '%s\n' '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />'
    }
    [ "$PERM_CAMERA" = "1" ] && \
        printf '%s\n' '    <uses-permission android:name="android.permission.CAMERA" />'
    [ "$PERM_MICROPHONE" = "1" ] && \
        printf '%s\n' '    <uses-permission android:name="android.permission.RECORD_AUDIO" />'
    [ "$PERM_MICROPHONE" = "1" ] && \
        printf '%s\n' '    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />'
    printf '\n'
    # Hardware feature declarations (optional, so required=false)
    [ "$PERM_CAMERA" = "1" ] && {
        printf '%s\n' '    <uses-feature android:name="android.hardware.camera" android:required="false" />'
        printf '%s\n' '    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />'
    }
    [ "$PERM_MICROPHONE" = "1" ] && \
        printf '%s\n' '    <uses-feature android:name="android.hardware.microphone" android:required="false" />'
    cat <<'MANIFEST_APP'
    <!-- Allow cleartext HTTP to localhost -->
    <application
        android:label="@string/app_name"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:usesCleartextTraffic="true"
        android:hardwareAccelerated="true"
        android:theme="@android:style/Theme.DeviceDefault.NoActionBar">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:configChanges="orientation|screenSize|keyboardHidden">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
MANIFEST_APP
} > "$MANIFEST"
echo "mkandroid: generated AndroidManifest.xml (location=$PERM_LOCATION camera=$PERM_CAMERA mic=$PERM_MICROPHONE)"

# ── Locate Android SDK ─────────────────────────────────────────────
if [ -z "$ANDROID_HOME" ]; then
    for d in \
        "$HOME/Library/Android/sdk" \
        "$HOME/Android/Sdk" \
        "/opt/android-sdk"; do
        if [ -d "$d" ]; then ANDROID_HOME="$d"; break; fi
    done
fi
if [ -z "$ANDROID_HOME" ] || [ ! -d "$ANDROID_HOME" ]; then
    echo "mkandroid: ANDROID_HOME not found. Set ANDROID_HOME." >&2
    exit 1
fi
export ANDROID_HOME

# ── Locate gradle ──────────────────────────────────────────────────
GRADLE=""
if [ -x "$ANDROID_DIR/gradlew" ]; then
    GRADLE="$ANDROID_DIR/gradlew"
elif command -v gradle >/dev/null 2>&1; then
    GRADLE="gradle"
else
    # Try Android Studio's bundled gradle (macOS)
    if [ -d "/Applications/Android Studio.app" ]; then
        _BIN=$(find "/Applications/Android Studio.app/Contents" \
               -name "gradle" -path "*/bin/gradle" 2>/dev/null \
               | head -1)
        [ -n "$_BIN" ] && GRADLE="$_BIN"
    fi
fi
if [ -z "$GRADLE" ]; then
    echo "mkandroid: gradle not found." >&2
    echo "  Install with:  brew install gradle" >&2
    exit 1
fi

# ── Write local.properties ─────────────────────────────────────────
echo "sdk.dir=$ANDROID_HOME" > "$ANDROID_DIR/local.properties"

# ── Generate gradle wrapper if missing ─────────────────────────────
if [ ! -x "$ANDROID_DIR/gradlew" ]; then
    echo "mkandroid: generating gradle wrapper..."
    (cd "$ANDROID_DIR" && "$GRADLE" wrapper --gradle-version=8.5 \
        --quiet 2>/dev/null || "$GRADLE" wrapper --quiet)
    GRADLE="$ANDROID_DIR/gradlew"
fi

# ── Copy Android icons into res/ if builticons exist ───────────────
ICON_SRC="$PROJECT_ROOT/src/icons/builticons/android/app/src/main/res"
RES_DIR="$ANDROID_DIR/app/src/main/res"
if [ -d "$ICON_SRC" ]; then
    # Copy all mipmap and drawable directories
    for d in "$ICON_SRC"/mipmap-* "$ICON_SRC"/drawable-* "$ICON_SRC"/drawable; do
        [ -d "$d" ] || continue
        DNAME=$(basename "$d")
        mkdir -p "$RES_DIR/$DNAME"
        cp "$d"/*.png "$RES_DIR/$DNAME/" 2>/dev/null || true
    done
fi

# ── Update app_name from PROGNAME ──────────────────────────────────
STRINGS="$RES_DIR/values/strings.xml"
if [ -f "$STRINGS" ]; then
    sed -i.bak "s|>.*</string>|>$PROGNAME</string>|" "$STRINGS"
    rm -f "$STRINGS.bak"
fi

# ── Update applicationId / versionName if non-default ──────────────
# NOTE: namespace must stay 'com.example.zipserve' to match the Java
# package.  Only applicationId (the Play Store identity) changes.
APP_GRADLE="$ANDROID_DIR/app/build.gradle"
if [ "$BUNDLE_ID" != "com.example.passiflora" ]; then
    sed -i.bak "s|applicationId \"com.example.passiflora\"|applicationId \"$BUNDLE_ID\"|" \
        "$APP_GRADLE"
    rm -f "$APP_GRADLE.bak"
fi
if [ "$VERSION" != "1.0.0" ]; then
    sed -i.bak "s|versionName \"1.0.0\"|versionName \"$VERSION\"|" "$APP_GRADLE"
    rm -f "$APP_GRADLE.bak"
fi

# ── Build ──────────────────────────────────────────────────────────
GRADLE_TASK="assemble$(echo "$BUILD_TYPE" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
echo "mkandroid: building $BUILD_TYPE APK ($GRADLE_TASK)..."
(cd "$ANDROID_DIR" && "$GRADLE" "$GRADLE_TASK" --quiet \
    -PPERM_LOCATION="$PERM_LOCATION" \
    -PPERM_CAMERA="$PERM_CAMERA" \
    -PPERM_MICROPHONE="$PERM_MICROPHONE" \
    -PPERM_REMOTEDEBUGGING="$PERM_REMOTEDEBUGGING" \
    --project-cache-dir "$PROJECT_ROOT/bin/Android/gradle-cache")

# ── Copy APK to bin/Android/ ───────────────────────────────────────
APK=$(find "$PROJECT_ROOT/bin/Android/gradle-build/app/outputs/apk/$BUILD_TYPE" \
      -name "*.apk" 2>/dev/null | head -1)
if [ -n "$APK" ]; then
    mkdir -p "$PROJECT_ROOT/bin/Android"
    cp "$APK" "$PROJECT_ROOT/bin/Android/${PROGNAME}.apk"
    echo "mkandroid: bin/Android/${PROGNAME}.apk created"
else
    echo "mkandroid: APK not found in build output" >&2
    exit 1
fi
