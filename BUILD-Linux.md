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

3. **GitHub CLI** (required by `make newproject`):

```
sudo apt install gh
```

   If `gh` is not available in your distro's repositories, install from the official repo:

```
(type -p wget >/dev/null || sudo apt install wget) \
  && sudo mkdir -p -m 755 /etc/apt/keyrings \
  && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt update \
  && sudo apt install gh
```

   Then log in once:

```
gh auth login
```

   Follow the prompts to authenticate with your GitHub account.

4. If location services aren't working, you may need to install GeoClue2
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

Produces `bin/Linux/<displayname>`.

| Command | Description |
|---------|-------------|
| `make` or `make linux` | Build native Linux binary |
| `make android` | Build Android APK |
| `BUILD_TYPE=release make android` | Build Android release APK |
| `make sign-android` | Build + sign Android APK |
| `make sign-windows` | Sign the Windows exe with Azure Trusted Signing (requires jsign) |
| `make googleplay-android` | Build a release AAB for Google Play upload. Experimental! |
| `make www` | Build plain-browser version into `bin/WWW/` — useful for debugging using browser tools |
| `make icons` | Generate icon sets for all platforms |
| `make clean` | Remove all build artifacts |

### Desktop Integration (Ubuntu / GNOME)

The first time you run the Linux binary, it automatically installs its icon and a `.desktop` file so the app appears in the GNOME dock, launcher, and file manager:

* **Icon** → `~/.local/share/icons/hicolor/256x256/apps/<progname>.png`
* **Desktop entry** → `~/.local/share/applications/<progname>.desktop`

The `.desktop` file’s `Name=` field uses `DISPLAYNAME` (e.g., "Heckin Chonker"), so the app appears with its full multi-word name in the GNOME launcher.

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

> **Note:** Opening `index.html` directly with a `file://` URL may disable some browser features. For full functionality, serve `bin/WWW/` over HTTP using a local web server.

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

Produces `bin/Windows/<displayname>.exe`. The build automatically downloads and embeds `WebView2Loader.dll` from NuGet.

To build **and sign** the exe with Azure Artifact Signing:

```
make sign-windows
```

See [Code Signing for Windows](#code-signing-for-windows) for prerequisites and setup.

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

### Google Play (AAB)

Google Play requires an Android App Bundle (AAB) instead of an APK:

```
make googleplay-android
```

Produces `bin/Android/<progname>.aab` — a signed release bundle ready for upload to the Google Play Console. Requires `RELEASE_KEYSTORE`, `RELEASE_KEYSTORE_PASSWORD`, `RELEASE_KEY_ALIAS`, and `RELEASE_KEY_PASSWORD` environment variables to be set (see [Code Signing for Android](#code-signing-for-android)).

### Testing in the Android Emulator

If you have Android Studio installed, you can load the built APK into the Android Emulator:

1. Open Android Studio.
2. Open the **Device Manager** (the phone+tablet icon in the toolbar, or **Tools → Device Manager**).
3. Create a virtual device if you haven't already: click **Create Device**, choose a hardware profile (e.g., Pixel 8), select a system image, and click **Finish**.
4. Start the emulator by clicking the **Play** button next to your virtual device.
5. Once the emulator is running, drag and drop the `.apk` file from `bin/Android/` onto the emulator window. Android will install and launch it automatically.

   Alternatively, you can install from the command line with `adb`:

   ```
   adb install bin/Android/<progname>.apk
   ```

---

## Code Signing

**IMPORTANT: Never put your signing certificates, keystores, passwords, etc. into a folder managed by git or another version control system. Ever.**

---

### Code Signing for Windows

> **See also:** [WINDOWS_SIGNING.md](WINDOWS_SIGNING.md) — full setup guide for Azure Trusted Signing account creation, identity validation, and CI/CD integration.

Windows code signing uses [Azure Artifact Signing](https://learn.microsoft.com/en-us/azure/trusted-signing/overview) (formerly Azure Trusted Signing) via **jsign**, a cross-platform signing tool.

#### Prerequisites

1. **Azure Artifact Signing account** with identity validation and a certificate profile. Your Azure account must have the **"Code Signing Certificate Profile Signer"** role.

2. **Azure CLI** — for obtaining access tokens:

   ```
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   ```

   Log in once:

   ```
   az login
   ```

3. **Java 17+** — jsign requires a Java runtime (already installed if you build for Android).

4. **jsign**:

   ```
   brew install jsign
   ```

   Or download the all-in-one JAR from https://github.com/ebourg/jsign/releases and run with `java -jar jsign.jar`.

#### Sign

Create your local signing setup file from the template in the repo root, then run:

```
mkdir -p ~/passiflora-keys
cp signing_setup.sh ~/passiflora-keys/signing_setup.sh
$EDITOR ~/passiflora-keys/signing_setup.sh
make sign-windows
```

`make sign-windows` auto-loads `~/passiflora-keys/signing_setup.sh` if it exists, so you do not need to re-export variables every shell session.

Required variables in that file are:

```
AZURE_SIGNING_ENDPOINT
AZURE_SIGNING_ACCOUNT
AZURE_SIGNING_PROFILE
```

This builds the Windows exe, obtains an Azure access token via `az account get-access-token`, and signs the exe with jsign. Timestamping is automatic (using `http://timestamp.acs.microsoft.com`).

> **Note:** Azure Artifact Signing certificates have a 3-day validity. The automatic timestamping ensures the signature remains valid long-term.

The `AZURE_SIGNING_ENDPOINT` must match the region where your Artifact Signing account was created. See the [Azure docs](https://learn.microsoft.com/en-us/azure/trusted-signing/how-to-signing-integrations) for the full list of regional endpoints.

---

### Code Signing for Android

> **See also:** [GOOGLE_PLAY_SIGNING.md](GOOGLE_PLAY_SIGNING.md) — full setup guide for keystore creation, Google Play App Signing enrollment, and CI/CD integration.

There are two ways to sign an Android APK.

#### Method 1 — Interactive post-build signing (`apksigner`)

Uses `apksigner` from the Android SDK build-tools to sign the APK after it's built. Good for manual/one-off signing.

**Additional prerequisites:**

The Android SDK build-tools (installed above) include `apksigner` and `zipalign`. They are located automatically — the build checks `ANDROID_HOME`, common SDK locations (`~/Android/Sdk`, `/usr/local/lib/android/sdk`), and `local.properties`. If they still can't be found, add the build-tools directory to your `PATH`:

```
export PATH="$ANDROID_HOME/build-tools/35.0.0:$PATH"
```

**Sign:**

```
make sign-android
```

This builds the APK, then signs it with `apksigner`. The build automatically looks for a keystore at `~/passiflora-keys/android-keystore.jks`. If found, it is used automatically. If not found, you are prompted to enter the path.

You will be prompted for:
1. Keystore file path (only if the default is not found)
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
mkdir -p ~/passiflora-keys
cp signing_setup.sh ~/passiflora-keys/signing_setup.sh
$EDITOR ~/passiflora-keys/signing_setup.sh
. ~/passiflora-keys/signing_setup.sh
BUILD_TYPE=release make android
```

Required Android variables in `~/passiflora-keys/signing_setup.sh` are:

```
RELEASE_KEYSTORE
RELEASE_KEYSTORE_PASSWORD
RELEASE_KEY_ALIAS
RELEASE_KEY_PASSWORD
```

The resulting APK is already signed. Do **not** also run `make sign-android` — that would attempt to double-sign.

#### Creating a keystore for production

Generate a keystore somewhere **outside** the Passiflora tree. The recommended path is `~/passiflora-keys/android-keystore.jks` — `make sign-android` checks there automatically:

```
mkdir -p ~/passiflora-keys
keytool -genkey -v -keystore ~/passiflora-keys/android-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mykey
```

`keytool` is included with any JDK installation (`openjdk-17-jdk` installed above). It will prompt for a keystore password and certificate details.

If you choose an alias other than `mykey`, set `RELEASE_KEY_ALIAS` to match.

Then use Method 2 above with the appropriate environment variables.

#### Installing the APK on a physical device

Connect your Android device via USB with [USB debugging enabled](https://developer.android.com/studio/debug/dev-options#enable), then use `adb`:

```
adb install bin/Android/<progname>.apk
```

If `adb` is not on your PATH:

```
$ANDROID_HOME/platform-tools/adb install bin/Android/<progname>.apk
```

To install on a specific device when multiple are connected:

```
adb devices                          # list connected devices
adb -s DEVICE_SERIAL install bin/Android/<progname>.apk
```

To replace an existing installation (keeping app data):

```
adb install -r bin/Android/<progname>.apk
```

Alternatively, copy the signed `.apk` to the device (via USB, email, cloud storage, web server, etc.) and open it — Android will prompt to install. You may need to enable **Install from unknown sources** in the device settings.
