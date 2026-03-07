# Building Passiflora on Windows

This guide covers building Passiflora natively on Windows, plus cross-compiling for Android.

> **Note:** On Windows, use `.\build` (or `.\build.bat`) instead of `make`. If you are using PowerShell (the default terminal on modern Windows), you **must** prefix the command with `.\` — e.g. `.\build windows`. In cmd.exe you can just type `build windows`.

## Native Windows Build

### Prerequisites

1. **MinGW-w64** (provides `gcc`, `windres`, etc.):

   **Option A — MSYS2** (recommended):

   Download and install from https://www.msys2.org/

   After installation, open the **MSYS2 UCRT64** terminal and run:

   ```
   pacman -S mingw-w64-ucrt-x86_64-gcc
   ```

   Then add the MSYS2 `bin` directory to your Windows `PATH`:
   
   ```
   C:\msys64\ucrt64\bin
   ```

   (Settings → System → About → Advanced system settings → Environment Variables → Path → Edit → New)

   **Option B — Standalone MinGW-w64**:

   Download from https://www.mingw-w64.org/downloads/ or https://github.com/niXman/mingw-builds-binaries/releases

   Extract and add the `bin` directory to your `PATH`.

   Verify installation in a new terminal:

   ```
   gcc --version
   ```

2. **ImageMagick** (for icon generation):

   ```
   winget install ImageMagick.ImageMagick
   ```

   Or download from https://imagemagick.org/script/download.php#windows — choose the installer that says "Install" and check "Add to PATH" during setup.

3. **curl** — pre-installed on Windows 10/11.

4. **PowerShell 5.1+** — pre-installed on Windows 10/11.

5. **WebView2 Runtime** — pre-installed on Windows 10 (version 21H2+) and Windows 11. If missing, download from https://developer.microsoft.com/en-us/microsoft-edge/webview2/

### Build

```
.\build
```

or equivalently:

```
.\build windows
```

Produces `bin\Windows\<progname>.exe`. The build automatically downloads and embeds `WebView2Loader.dll` from NuGet.

| Command | Description |
|---------|-------------|
| `.\build` or `.\build windows` | Build Windows exe |
| `.\build icons` | Generate icon sets for all platforms |
| `.\build clean` | Remove all build artifacts |

---

## Cross-Compiling for Android

### Additional Prerequisites

1. **Java 17+**:

   **Option A — winget**:

   ```
   winget install EclipseAdoptium.Temurin.17.JDK
   ```

   **Option B — Direct download**:

   Download from https://adoptium.net/temurin/releases/?version=17 — choose the Windows x64 `.msi` installer. The installer adds Java to `PATH` automatically.

   Verify with:

   ```
   java -version
   ```

2. **Android SDK and NDK**:

   **Option A — Android Studio** (easiest):

   Download from https://developer.android.com/studio

   Open Android Studio → **Settings → Languages & Frameworks → Android SDK**:
   - Under **SDK Platforms**, check the latest Android API (e.g., API 35).
   - Under **SDK Tools**, check **NDK (Side by side)** and **Android SDK Build-Tools**.
   - Click **Apply** to install.

   Android Studio installs the SDK to `%LOCALAPPDATA%\Android\Sdk` by default. Passiflora auto-detects this location.

   **Option B — Command-line only** (no Android Studio):

   Download the command-line tools from https://developer.android.com/studio#command-line-tools-only

   Extract to a directory (e.g., `C:\Android\cmdline-tools\latest\`).

   Set `ANDROID_HOME` and add cmdline-tools to `PATH`:

   ```
   set ANDROID_HOME=C:\Android
   set PATH=%ANDROID_HOME%\cmdline-tools\latest\bin;%PATH%
   ```

   Install SDK components:

   ```
   sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;29.0.14206865"
   ```

3. **Gradle** (optional — the included `gradlew` wrapper works without it):

   ```
   winget install Gradle.Gradle
   ```

   Or download from https://gradle.org/releases/ — extract and add the `bin` directory to your `PATH`.

### Build

```
.\build android
```

Produces `bin\Android\<progname>.apk` (debug build by default).

To build a signed release APK:

```
set BUILD_TYPE=release
.\build android
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

The Android SDK build-tools (installed above) include `apksigner.bat` and `zipalign.exe`. They are located automatically via `ANDROID_HOME`. If not found, add the build-tools directory to your `PATH`:

```
set PATH=%LOCALAPPDATA%\Android\Sdk\build-tools\35.0.0;%PATH%
```

**Sign:**

```
.\build sign-android
```

This builds the APK, then interactively prompts for:
1. Keystore file path
2. Keystore password (entered securely — characters are hidden)

It then zipaligns (if available), signs, and verifies the APK.

By default this builds a **debug** APK. To sign a release APK:

```
set BUILD_TYPE=release
.\build sign-android
```

#### Method 2 — Gradle build-time signing (environment variables)

Gradle signs the APK automatically during the build. No interactive prompts. Better for CI/CD and automated builds.

Set environment variables and build:

```
set RELEASE_KEYSTORE=C:\path\to\my-release.jks
set RELEASE_KEYSTORE_PASSWORD=your-store-password
set RELEASE_KEY_ALIAS=mykey
set RELEASE_KEY_PASSWORD=your-key-password
set BUILD_TYPE=release
.\build android
```

The resulting APK is already signed. Do **not** also run `.\build sign-android` — that would attempt to double-sign.

#### Test keystore (included)

A test keystore (`src\android\release.jks`, password `testtest`, alias `mykey`) is included for development convenience. It is used automatically for release builds when no environment variables are set.

**Do not ship apps signed with the test keystore.**

#### Creating a real keystore for production

Generate a keystore somewhere **outside** the Passiflora tree:

```
keytool -genkey -v -keystore "%USERPROFILE%\my-release.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias mykey
```

`keytool` is included with any JDK installation. It will prompt for a keystore password and certificate details.

If you choose an alias other than `mykey`, set `RELEASE_KEY_ALIAS` to match.

Then use Method 2 above with the appropriate environment variables.
