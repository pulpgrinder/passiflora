# Building Passiflora Apps on macOS

This guide covers building Passiflora apps natively on macOS, plus cross-compiling for iOS, iOS Simulator, Windows, Android, and WWW.

## Native macOS Build

### Prerequisites

1. **Xcode Command Line Tools** (provides `clang`, `make`, etc.):

```
xcode-select --install
```

2. **ImageMagick** (for icon generation):

```
brew install imagemagick
```

If you don't have Homebrew, install it from https://brew.sh/

### Build

```
make
```
or:

```
make macos
```

This produces `bin/macOS/<progname>.app` — a standard macOS application bundle.

| Command | Description |
|---------|-------------|
| `make` | Build macOS app bundle |
| `make macos` | Build macOS app bundle (same as plain `make` on this platform) |
| `make sign-macos` | Sign, notarize, and package for distribution (see [Code Signing for macOS](#code-signing-for-macos)) |
| `make android` | Builds an Android .apk|
| `make sign-android` | Builds an Android apk |
| `make googleplay-android` | Build a release AAB for Google Play upload (under construction) |
| `make www` | Build plain-browser version into `bin/WWW/` — useful for debugging using browser tools |
| `make linux-docker` | Build Linux binary using a Docker container (requires Docker) |
| `make all` | Build every platform: macOS, iOS, Windows, Android, Linux (via Docker) |
| `make sign-all` | Build + sign every platform, including Google Play AAB (experimental) (iOS and Android prompt for credentials) |
| `make icons` | Generate icon sets for all platforms |
| `make clean` | Remove all build artifacts |

### Bundle Identifier

Every macOS and iOS app needs a **bundle identifier** — a reverse-DNS string that uniquely identifies your app (e.g., `com.yourcompany.YourApp`). Set it in `src/config`:

```
BUNDLE_ID com.yourcompany.YourApp
```

The Makefile, build.bat, and Android `build.gradle` all read `BUNDLE_ID` from this file. You should change this before distributing your app.

**Rules for bundle identifiers:**

* Use reverse-DNS notation: `com.yourcompany.appname` or `org.yourproject.appname`.
* Only alphanumeric characters, hyphens, and periods are allowed.
* Each component must start with a letter.
* The `com.example.*` prefix is reserved for examples and will be rejected by app stores.
* The identifier must match what you register in your Apple Developer account (for signed/distributed apps) and in your provisioning profile (for iOS).
* For Android, the same `BUNDLE_ID` is used as the `applicationId` in build.gradle. Google Play uses it to identify your app, and it cannot be changed after publishing.

Pick your bundle identifier wisely and early — changing it later means the OS treats it as a different app (losing user data, preferences, keychain items, etc.).

---

## Building for WWW / Plain Browser

Builds a plain-browser version that can be served with any web server. No additional prerequisites beyond the base macOS build tools.

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

## Cross-Compiling for iOS

Builds a signed `.ipa` for physical iPhones and iPads.

### Additional Prerequisites

* **Xcode** (full install, not just command line tools) with an iOS SDK.

  Download from the Mac App Store or https://developer.apple.com/xcode/

  After installing, open Xcode at least once to accept the license and install components. Verify the iOS SDK is available:

```
xcrun --sdk iphoneos --show-sdk-path
```

### Build

```
make sign-ios
```

This compiles the iOS binary, creates the `.app` bundle, then walks you through signing and IPA packaging (see [Code Signing for iOS](#code-signing-for-ios) below).

The build automatically looks for a provisioning profile at `~/passiflora-keys/<progname>.mobileprovision`. If found, it is used automatically. If not, you are prompted to enter the path.

To override the default location, set the environment variable:

```
IOS_PROVISIONING_PROFILE=/path/to/MyApp.mobileprovision make sign-ios
```

Produces `bin/iOS/<progname>.ipa`.

---

## Cross-Compiling for iOS Simulator

### Additional Prerequisites

Same as iOS above, plus an **iOS Simulator runtime**. Install one via:

**Xcode → Settings → Platforms → + → iOS Simulator**

Or from the command line:

```
xcodebuild -downloadPlatform iOS
```

### Build

```
make sim-ios
```

This builds the binary, creates the `.app` bundle, boots a Simulator (if needed), installs the app, and launches it.

---

## Cross-Compiling for Windows

Produces a Windows `.exe` from macOS using MinGW-w64.

### Additional Prerequisites

* **MinGW-w64** (cross-compiler):

```
brew install mingw-w64
```

* **curl** and **xxd** — pre-installed on macOS.

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
brew install openjdk@17
```

   After installing, follow the cask instructions to symlink it, or add to your shell profile:

```
export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"
```

   Verify with `java -version`.

2. **Android SDK and NDK**. You have two options:

   **Option A — Android Studio** (easiest):

   Download from https://developer.android.com/studio

   Open Android Studio → **Settings → Languages & Frameworks → Android SDK**:
   - Under **SDK Platforms**, check the latest Android API (e.g., API 35).
   - Under **SDK Tools**, check **NDK (Side by side)** and **Android SDK Build-Tools**.
   - Click **Apply** to install.

   Android Studio installs the SDK to `~/Library/Android/sdk` by default. Passiflora auto-detects this location.

   **Option B — Command-line only** (no Android Studio):

```
brew install --cask android-commandlinetools
```

   Then install the required SDK components:

```
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;29.0.14206865"
```

   Set `ANDROID_HOME` if installed to a non-default location:

```
export ANDROID_HOME="$HOME/Library/Android/sdk"
```

3. **Gradle** (optional — the included `gradlew` wrapper works without it):

```
brew install gradle
```

### Build

```
make android
```

Produces `bin/Android/<progname>.apk` (debug build by default).


```
make sign-android
```

Produces a signed `bin/Android/<progname>.apk` (debug build by default).

To build a signed release APK:

```
BUILD_TYPE=release make android
```

### Google Play (AAB)

Google Play requires an Android App Bundle (AAB) instead of an APK:

```
make googleplay-android
```

This is currently **EXPERIMENTAL**. Produces `bin/Android/<progname>.aab` — a signed release bundle ready for upload to the Google Play Console. Requires `RELEASE_KEYSTORE`, `RELEASE_KEYSTORE_PASSWORD`, `RELEASE_KEY_ALIAS`, and `RELEASE_KEY_PASSWORD` environment variables to be set (see [Code Signing for Android](#code-signing-for-android)).

This target is also included in `make sign-all`.

---

## Cross-Compiling for Linux (via Docker)

Builds a native Linux (x86_64 or arm64) binary inside a Docker container, without needing a Linux toolchain on macOS.

### Additional Prerequisites

* **Docker Desktop** (https://www.docker.com/products/docker-desktop/) or **OrbStack** (https://orbstack.dev/). Make sure the Docker daemon is running.

### Build

```
make linux-docker
```

On the first run, this builds a local Docker image (`passiflora-linux-build`) with all required build dependencies (`gcc`, `libgtk-3-dev`, `libwebkit2gtk-4.1-dev`, `libgstreamer1.0-dev`, etc.) pre-installed. Subsequent runs reuse the cached image, so only the actual compilation runs — no re-downloading packages.

The project directory is bind-mounted into the container, so the output lands directly in `bin/Linux/<progname>` on your Mac.

To use a different base image:

```
make linux-docker LINUX_DOCKER_IMAGE=ubuntu:22.04
```

To force a rebuild of the Docker image (e.g. after changing the base image or package list):

```
docker rmi passiflora-linux-build
```

> **Note:** The resulting binary is a native Linux ELF executable — it won't run directly on macOS. Transfer it to a Linux machine (or run it inside the same Docker container) to test.

---

## Building All Platforms at Once

Two convenience targets build every platform from a single command on macOS:

### `make all` — unsigned builds

```
make all
```

Runs `make clean`, then builds macOS, iOS, Windows (cross-compile), Android, and Linux (Docker) in sequence, cleaning intermediate files between each platform. Produces:

| Platform | Output |
|----------|--------|
| macOS | `bin/macOS/<progname>.app` |
| iOS | `bin/iOS/<progname>.app` (unsigned) |
| Windows | `bin/Windows/<progname>.exe` |
| Android | `bin/Android/<progname>.apk` |
| Linux | `bin/Linux/<progname>` |
| WWW | `bin/WWW/` |

### `make sign-all` — signed builds

```
make sign-all
```

Same as `make all`, but uses `make sign-macos`, `make sign-ios`, `make sign-android`, and `make googleplay-android` for platforms that support code signing. iOS and Android will prompt interactively for signing credentials (provisioning profile, keystore, etc.). Windows and Linux builds are identical to the unsigned versions since signing isn't (yet) supported on those platforms.

Produces:

| Platform | Output |
|----------|--------|
| macOS | `bin/macOS/<progname>.app` (signed + notarized) |
| iOS | `bin/iOS/<progname>.ipa` (signed) |
| Windows | `bin/Windows/<progname>.exe` |
| Android | `bin/Android/<progname>.apk` (signed) |
| Android (Google Play) | `bin/Android/<progname>.aab` |
| Linux | `bin/Linux/<progname>` |
| WWW | `bin/WWW/` |

> **Prerequisites:** These targets require all cross-compilation prerequisites to be installed (Xcode, MinGW-w64, Android SDK/NDK, Docker). See the sections above for each platform's requirements.

---

## Code Signing

**IMPORTANT: Never put your signing certificates, keystores, passwords, etc. into a folder managed by git or another version control system. Ever.**

---

### Code Signing for macOS

macOS code signing uses Apple certificates managed through Keychain Access.

`make sign-macos` produces up to two distribution-ready artifacts:

1. **Notarized `.app`** — for distribution outside the App Store (Developer ID). Ready for direct download, DMG, etc.
2. **Signed `.pkg`** — for Mac App Store submission. Ready for upload to App Store Connect.

Each step is optional and prompted interactively.

#### Prerequisites

* **Apple Developer Program membership** ($99/year) — https://developer.apple.com/programs/

  Without it, only ad-hoc signing is available (the app runs only on your Mac; Gatekeeper blocks it elsewhere).

* **Signing certificates** in your Keychain. After joining the Apple Developer Program, create certificates at https://developer.apple.com/account/resources/certificates/list or via Xcode:

  **Xcode → Settings → Accounts → (your team) → Manage Certificates → +**

#### Certificate types

| Certificate | Use |
|-------------|-----|
| **Developer ID Application** | Distribution outside the App Store. Recipients can run without disabling Gatekeeper. |
| **Apple Development** / **Mac Developer** | Local development and testing. The destination Mac must trust your certificate. |
| **Apple Distribution** / **3rd Party Mac Developer Application** | Mac App Store submission (signs the `.app` inside the `.pkg`). |
| **3rd Party Mac Developer Installer** | Signs the `.pkg` installer for Mac App Store submission. |
| **Ad-hoc** (no identity) | The app runs on this Mac only. Gatekeeper blocks it on other machines. |

#### Sign

```
make sign-macos
```

This builds the app bundle and runs an interactive workflow with two stages:

**Stage 1 — Developer ID distribution (outside App Store):**

1. Lists Developer ID signing identities in your Keychain.
2. Signs the `.app` bundle with hardened runtime.
3. Submits to Apple's notary service (requires Apple ID + app-specific password, or a stored keychain profile).
4. Staples the notarization ticket to the `.app`.

The resulting `.app` is ready for distribution outside the App Store — recipients can run it without disabling Gatekeeper.

**Stage 2 — Mac App Store `.pkg`:**

1. Creates a separate copy of the `.app` for App Store signing.
2. Signs the copy with your App Store application certificate (Apple Distribution / 3rd Party Mac Developer Application), including the App Sandbox entitlement.
3. Wraps it in a `.pkg` signed with your installer certificate (3rd Party Mac Developer Installer).

The resulting `.pkg` is ready for upload to App Store Connect via Transporter or `xcrun altool`.

Both stages are optional — you can skip either one when prompted.

#### Notarization setup

Notarization requires an **app-specific password** (not your regular Apple ID password). Generate one at https://appleid.apple.com/account/manage under **Sign-In and Security → App-Specific Passwords**.

For repeated use, store credentials in the Keychain so you only need to enter them once:

```
xcrun notarytool store-credentials "notary-profile" \
    --apple-id your@apple.id \
    --team-id YOURTEAMID \
    --password <app-specific-password>
```

The script will ask for the profile name if you have one, or prompt for credentials directly.

#### Uploading to the Mac App Store

After `make sign-macos` produces the `.pkg`, upload it to App Store Connect:

```
xcrun altool --upload-app -f bin/macOS/<progname>.pkg -t macos -u your@apple.id -p @keychain:AC_PASSWORD
```

Or use the **Transporter** app (free on the Mac App Store).

---

### Code Signing for iOS

iOS apps must be signed and include an **embedded provisioning profile** to run on devices or be submitted to the App Store.

#### Prerequisites

* **Apple Developer Program membership** ($99/year) — https://developer.apple.com/programs/

* **Signing certificate** in your Keychain (see macOS section above for how to create one). For iOS you need:

| Certificate | Use |
|-------------|-----|
| **Apple Development** / **iPhone Developer** | Running on your own devices registered in your developer account. |
| **Apple Distribution** / **iPhone Distribution** | App Store submission or enterprise distribution. |
| **Ad-hoc** | Minimal signature. Will NOT install on devices without a provisioning profile. |

* **Provisioning profile** (`.mobileprovision`). Create one at:

  https://developer.apple.com/account/resources/profiles/list

  Or via Xcode: **Xcode → Settings → Accounts → (your team) → Download Manual Profiles**

  The profile must match your bundle identifier, certificate, and (for development) your registered device UDIDs.

#### Building a release-ready `.ipa`

The `make sign-ios` target performs the full build-sign-package workflow:

1. Build the iOS binary and `.app` bundle.
2. Look for a provisioning profile at `~/passiflora-keys/<progname>.mobileprovision`. If found, it is used automatically. If not found, prompt for the path. You can also set the `IOS_PROVISIONING_PROFILE` environment variable to override:
   ```
   IOS_PROVISIONING_PROFILE=/path/to/MyApp.mobileprovision make sign-ios
   ```
3. Embed the profile in the app bundle.
4. Extract entitlements from the profile automatically.
5. List signing identities and prompt you to choose one.
6. Sign the bundle with the profile-derived entitlements.
7. Package everything into `bin/iOS/<progname>.ipa`.

When signed with an **Apple Distribution** certificate and an **App Store provisioning profile**, the resulting `.ipa` is ready for upload to App Store Connect — no additional packaging is needed.

#### Uploading to the App Store

Upload the signed `.ipa` using `altool` or Transporter:

```
xcrun altool --upload-app -f bin/iOS/<progname>.ipa -t ios -u your@apple.id -p @keychain:AC_PASSWORD
```

Or use the **Transporter** app (free on the Mac App Store). Testers can then receive the build through TestFlight.

#### Installing the IPA on a physical device

Once you have the signed `.ipa`, there are several ways to get it onto an iPhone or iPad:

**Apple Configurator (recommended for ad-hoc/development):**

1. Install [Apple Configurator](https://apps.apple.com/app/apple-configurator/id1037126344) from the Mac App Store.
2. Connect the device via USB.
3. Open Apple Configurator, select the device, click **Add (+) → Apps**, and choose the `.ipa` file.

**Xcode Devices window:**

1. Open Xcode → **Window → Devices and Simulators**.
2. Select the connected device.
3. Under **Installed Apps**, click the **+** button and choose the `.ipa` file.

**`ideviceinstaller` (command-line):**

```
brew install ideviceinstaller
ideviceinstaller -i bin/iOS/HeckinChonker.ipa
```

**TestFlight / App Store Connect:**

When signed with an Apple Distribution certificate and an App Store provisioning profile, the `.ipa` is ready for upload:

```
xcrun altool --upload-app -f bin/iOS/HeckinChonker.ipa -t ios -u your@apple.id -p @keychain:AC_PASSWORD
```

Or use the **Transporter** app (free on the Mac App Store). Testers will receive the build through the TestFlight app.

> **Note:** The device's UDID must be registered in the provisioning profile for ad-hoc and development builds. App Store and enterprise profiles do not have this restriction.

---

### Code Signing for Android

There are two ways to sign an Android APK.

#### Method 1 — Interactive post-build signing (`apksigner`)

Uses `apksigner` from the Android SDK build-tools to sign the APK after it's built. Good for manual/one-off signing.

**Additional prerequisites:**

The Android SDK build-tools (installed above) include `apksigner` and `zipalign`. They are located automatically — the build checks `ANDROID_HOME`, the standard macOS SDK location (`~/Library/Android/sdk`), and `local.properties`. If they still can't be found, add the build-tools directory to your `PATH`:

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
export RELEASE_KEYSTORE=/path/to/my-release.jks
export RELEASE_KEYSTORE_PASSWORD=your-store-password
export RELEASE_KEY_ALIAS=mykey
export RELEASE_KEY_PASSWORD=your-key-password
BUILD_TYPE=release make android
```

The resulting APK is already signed. Do **not** also run `make sign-android` — that would attempt to double-sign.

#### Creating a keystore for production

Generate a keystore somewhere **outside** the Passiflora tree. The recommended path is `~/passiflora-keys/android-keystore.jks` — `make sign-android` checks there automatically:

```
mkdir -p ~/passiflora-keys
keytool -genkey -v -keystore ~/passiflora-keys/android-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mykey
```

`keytool` is included with any JDK installation. It will prompt for a keystore password and certificate details.

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
