# Building Passiflora Apps on Linux

This guide covers building Passiflora apps natively on Linux (Debian/Ubuntu), plus cross-compiling for Windows, Android, and WWW.

> **Note:** Instructions use `apt` (Debian/Ubuntu). Adjust for your distro's package manager as needed (e.g., `dnf` on Fedora, `pacman` on Arch).

## Native Linux Build

### Prerequisites

1. **Build toolchain and WebKitGTK**:

```
sudo apt update
sudo apt install build-essential pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev
```

   If `libwebkit2gtk-4.1-dev` is not available on your distro version, use `libwebkit2gtk-4.0-dev` instead — the Makefile auto-detects which is present.

2. **ImageMagick** (for icon generation):

```
sudo apt install imagemagick
```
3. If location services aren't working, you may need to install GeoClue2
```
sudo apt install geoclue-2.0
```
### Build

```
make
```

or equivalently:

```
make linux
```

Produces `bin/Linux/<progname>`.

| Command | Description |
|---------|-------------|
| `make` or `make linux` | Build native Linux binary |
| `make www` | Build plain-browser version into `bin/WWW/` — useful for debugging using browser tools |
| `make icons` | Generate icon sets for all platforms |
| `make clean` | Remove all build artifacts |

### Desktop Integration (Ubuntu / GNOME)

The first time you run the Linux binary, it automatically installs its icon and a `.desktop` file so the app appears in the GNOME dock, launcher, and file manager:

* **Icon** → `~/.local/share/icons/hicolor/256x256/apps/<progname>.png`
* **Desktop entry** → `~/.local/share/applications/<progname>.desktop`

If you move the binary, the next launch updates the `Exec=` path automatically. No manual steps are needed.

> **Note:** After the first run, the file manager (Nautilus/Files) may not display the custom icon until you navigate away from the directory and back. This is a Nautilus caching behavior.

---

## Building for WWW / Plain Browser

Builds a plain-browser version that can be served with any web server. No additional prerequisites beyond the base Linux build tools.

### Build

```
make www
```

Produces `bin/WWW/` — open `index.html` directly or serve with:

```
python3 webserver.py
```

or any other web server of your choice.

---

## Cross-Compiling for Windows

Produces a Windows `.exe` from Linux using MinGW-w64.

### Additional Prerequisites

```
sudo apt install mingw-w64 xxd unzip
```

`curl` is usually pre-installed. If not:

```
sudo apt install curl
```

### Build

```
make windows
```

Produces `bin/Windows/<progname>.exe`. The build automatically downloads and embeds `WebView2Loader.dll` from NuGet.

---

## Cross-Compiling for Android

### Additional Prerequisites

1. **Java 17+**:

```
sudo apt install openjdk-17-jdk
```

   Verify with `java -version`. If multiple Java versions are installed, select 17:

```
sudo update-alternatives --config java
```

2. **Android SDK and NDK**:

   **Option A — Android Studio** (easiest):

   Download from https://developer.android.com/studio

   Extract the tarball and run `studio.sh`:

   ```
   tar xzf android-studio-*.tar.gz
   cd android-studio/bin
   ./studio.sh
   ```

   Open Android Studio → **Settings → Languages & Frameworks → Android SDK**:
   - Under **SDK Platforms**, check the latest Android API (e.g., API 35).
   - Under **SDK Tools**, check **NDK (Side by side)** and **Android SDK Build-Tools**.
   - Click **Apply** to install.

   Android Studio installs the SDK to `~/Android/Sdk` by default.

   Add to your `~/.bashrc` or `~/.profile`:

   ```
   export ANDROID_HOME="$HOME/Android/Sdk"
   export PATH="$ANDROID_HOME/platform-tools:$PATH"
   ```

   **Option B — Command-line only** (no Android Studio):

   Download the command-line tools from https://developer.android.com/studio#command-line-tools-only

   ```
   mkdir -p ~/Android/Sdk/cmdline-tools
   unzip commandlinetools-linux-*.zip -d ~/Android/Sdk/cmdline-tools
   mv ~/Android/Sdk/cmdline-tools/cmdline-tools ~/Android/Sdk/cmdline-tools/latest
   ```

   Add to `~/.bashrc`:

   ```
   export ANDROID_HOME="$HOME/Android/Sdk"
   export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
   ```

   Source and install SDK components:

   ```
   source ~/.bashrc
   sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;29.0.14206865"
   ```

3. **Gradle** (optional — the included `gradlew` wrapper works without it):

```
sudo apt install gradle
```

### Build

```
make android
```

Produces `bin/Android/<progname>.apk` (debug build by default).

To build a signed release APK:

```
BUILD_TYPE=release make android
```

---

## Code Signing

**IMPORTANT: Never put your signing certificates, keystores, passwords, etc. into a folder managed by git or another version control system. Ever.**

---

### Code Signing for Android

There are two ways to sign an Android APK.

#### Method 1 — Interactive post-build signing (`apksigner`)

Uses `apksigner` from the Android SDK build-tools to sign the APK after it's built. Good for manual/one-off signing.

**Additional prerequisites:**

The Android SDK build-tools (installed above) include `apksigner` and `zipalign`. They are located automatically via `ANDROID_HOME`. If not found, add the build-tools directory to your `PATH`:

```
export PATH="$ANDROID_HOME/build-tools/35.0.0:$PATH"
```

**Sign:**

```
make sign-android
```

This builds the APK, then interactively prompts for:
1. Keystore file path
2. Keystore password

It then zipaligns (if available), signs, and verifies the APK.

By default this builds a **debug** APK. To sign a release APK:

```
BUILD_TYPE=release make sign-android
```

#### Method 2 — Gradle build-time signing (environment variables)

Gradle signs the APK automatically during the build. No interactive prompts. Better for CI/CD and automated builds.

Set environment variables and build:

```
export RELEASE_KEYSTORE=/path/to/my-release.jks
export RELEASE_KEYSTORE_PASSWORD=your-store-password
export RELEASE_KEY_ALIAS=mykey
export RELEASE_KEY_PASSWORD=your-key-password
BUILD_TYPE=release make android
```

The resulting APK is already signed. Do **not** also run `make sign-android` — that would attempt to double-sign.

#### Test keystore (included)

A test keystore (`src/android/release.jks`, password `testtest`, alias `mykey`) is included for development convenience. It is used automatically for release builds when no environment variables are set.

**Do not ship apps signed with the test keystore.**

#### Creating a real keystore for production

Generate a keystore somewhere **outside** the Passiflora tree:

```
keytool -genkey -v -keystore ~/my-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mykey
```

`keytool` is included with any JDK installation (`openjdk-17-jdk` installed above). It will prompt for a keystore password and certificate details.

If you choose an alias other than `mykey`, set `RELEASE_KEY_ALIAS` to match.

Then use Method 2 above with the appropriate environment variables.

#### Installing the APK on a physical device

Connect your Android device via USB with [USB debugging enabled](https://developer.android.com/studio/debug/dev-options#enable), then use `adb`:

```
adb install bin/Android/HeckinChonker.apk
```

If `adb` is not on your PATH:

```
$ANDROID_HOME/platform-tools/adb install bin/Android/HeckinChonker.apk
```

To install on a specific device when multiple are connected:

```
adb devices                          # list connected devices
adb -s DEVICE_SERIAL install bin/Android/HeckinChonker.apk
```

To replace an existing installation (keeping app data):

```
adb install -r bin/Android/HeckinChonker.apk
```

Alternatively, copy the signed `.apk` to the device (via USB, email, cloud storage, web server, etc.) and open it — Android will prompt to install. You may need to enable **Install from unknown sources** in the device settings.
