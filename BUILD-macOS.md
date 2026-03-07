# Building Passiflora on macOS

This guide covers building Passiflora natively on macOS, plus cross-compiling for iOS, iOS Simulator, Windows, and Android.

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

This produces `bin/macOS/<progname>.app` — a standard macOS application bundle.

| Command | Description |
|---------|-------------|
| `make` | Build macOS app bundle |
| `make icons` | Generate icon sets for all platforms |
| `make clean` | Remove all build artifacts |

---

## Cross-Compiling for iOS

Builds a `.app` bundle for physical iPhones and iPads.

### Additional Prerequisites

* **Xcode** (full install, not just command line tools) with an iOS SDK.

  Download from the Mac App Store or https://developer.apple.com/xcode/

  After installing, open Xcode at least once to accept the license and install components. Verify the iOS SDK is available:

```
xcrun --sdk iphoneos --show-sdk-path
```

### Build

```
make ios
```

Produces `bin/iOS/<progname>.app`.

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
make iossim
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

To build a signed release APK:

```
BUILD_TYPE=release make android
```

---

## Code Signing

**IMPORTANT: Never put your signing certificates, keystores, passwords, etc. into a folder managed by git or another version control system. Ever.**

---

### Code Signing for macOS

macOS code signing uses Apple certificates managed through Keychain Access.

#### Prerequisites

* **Apple Developer Program membership** ($99/year) — https://developer.apple.com/programs/

  Without it, only ad-hoc signing is available (the app runs only on your Mac; Gatekeeper blocks it elsewhere).

* **Signing certificate** in your Keychain. After joining the Apple Developer Program, create certificates at https://developer.apple.com/account/resources/certificates/list or via Xcode:

  **Xcode → Settings → Accounts → (your team) → Manage Certificates → +**

#### Certificate types

| Certificate | Use |
|-------------|-----|
| **Developer ID Application** | Distribution outside the App Store. Recipients can run without disabling Gatekeeper. |
| **Apple Development** / **Mac Developer** | Local development and testing. The destination Mac must trust your certificate. |
| **Apple Distribution** / **3rd Party Mac Developer Application** | Mac App Store submission (requires additional packaging). |
| **Ad-hoc** (no identity) | The app runs on this Mac only. Gatekeeper blocks it on other machines. |

#### Sign

```
make sign-macos
```

This builds the app bundle and runs an interactive script that:

1. Lists all code signing identities in your Keychain.
2. Describes each option.
3. Prompts you to choose one (ad-hoc is always available).
4. Signs the bundle and displays signature details.

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

#### Interactive signing (`.app` bundle only)

```
make sign-ios
```

Same interactive flow as macOS signing. Suitable for on-device testing via Xcode or Apple Configurator.

#### Building a release-ready `.ipa`

An IPA is the format required for App Store submission, TestFlight, OTA distribution, and Apple Configurator.

```
make iosipa
```

This will:

1. Build the iOS binary and `.app` bundle.
2. Prompt for a provisioning profile (`.mobileprovision`) — or set the `IOS_PROVISIONING_PROFILE` environment variable to skip the prompt:
   ```
   IOS_PROVISIONING_PROFILE=/path/to/MyApp.mobileprovision make iosipa
   ```
3. Embed the profile in the app bundle.
4. Extract entitlements from the profile automatically.
5. List signing identities and prompt you to choose one.
6. Sign the bundle with the profile-derived entitlements.
7. Package everything into `bin/iOS/<progname>.ipa`.

#### iOS Simulator signing

```
make sign-iossim
```

Usually ad-hoc signing is sufficient for Simulator use.

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

`keytool` is included with any JDK installation. It will prompt for a keystore password and certificate details.

If you choose an alias other than `mykey`, set `RELEASE_KEY_ALIAS` to match.

Then use Method 2 above with the appropriate environment variables.
