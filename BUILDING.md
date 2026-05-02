# Building

## Make/Build Targets Summary

### Mac and Linux hosts

| Target | Description |
|--------|-------------|
| `make` | Build for current platform (macOS or Linux) |
| `make macos` | Build macOS binary and app bundle (macOS only) -- same as `make` if you're on a Mac |
| `make sign-macos` | Sign, notarize, and package macOS app — produces notarized .app and App Store .pkg (macOS only) |
| `make sim-ios` | Build, install, launch in iOS Simulator (macOS only) |
| `make sign-ios` | Build, sign, and package iOS .ipa — App Store ready (macOS only) |
| `make windows` | Cross-compile Windows exe (from macOS or Linux) |
| `make sign-windows` | Cross-compile and sign Windows exe with Azure Trusted Signing (requires jsign) |
| `make android` | Build Android APK |
| `BUILD_TYPE=release make android` | Build Android release APK |
| `make sign-android` | Build + sign Android release APK with a local keystore (macOS and Linux) |
| `make googleplay-android` | Build a release AAB for Google Play upload (experimental) |
| `make linux` | Build Linux binary (Linux only) -- same as `make` if you're on Linux |
| `make www` | Build plain-browser version in `bin/WWW/` -- useful for debugging using browser tools |
| `make all` | Build *every* platform: macOS, iOS, Windows, Android (macOS only) |
| `make sign-all` | Build + sign *every* platform, including Google Play AAB (macOS only — iOS, Android, and Windows prompt for/require credentials).|
| `make icons` | Generate icon sets for all platforms |
| `make clean` | Remove all build artifacts |

### Windows hosts

| Target | Description |
|--------|-------------|
| `.\build` or `.\build windows` | Build Windows exe (Windows) |
| `.\build sign-windows` | Build + sign Windows exe with Azure Trusted Signing (requires jsign) |
| `.\build android` | Build Android APK (Windows) |
| `set BUILD_TYPE=release && .\build android` | Build Android release APK (Windows cmd.exe) |
| `.\build sign-android` | Build + sign Android release APK (Windows) |
| `.\build googleplay-android` | Build a release AAB for Google Play upload (Windows, experimental) |
| `.\build www` | Build plain-browser version in `bin\WWW\` (Windows) -- useful for debugging using browser tools |
| `.\build icons` | Generate icon sets (Windows) |
| `.\build clean` | Remove all build artifacts (Windows) |

## Signing Guides

* **[Windows signing (Azure Trusted Signing)](WINDOWS_SIGNING.md)**
* **[Google Play signing (Android)](GOOGLE_PLAY_SIGNING.md)**
* **[macOS and iOS signing](MAC_SIGNING.md)**

### Signing Setup Templates

Passiflora includes template files at the repository root:

* `signing_setup.sh`
* `signing_setup.bat`

Copy and customize one of these templates in your home keys folder so signing targets can auto-load credentials:

* macOS / Linux: `~/passiflora-keys/signing_setup.sh`
* Windows: `%USERPROFILE%\passiflora-keys\signing_setup.bat`

The `sign-windows` and `sign-android` targets automatically load these files if present.

### Android Release APK Quick Commands

`sign-android` defaults to `BUILD_TYPE=release` on both Make and Windows build.bat.

macOS / Linux:

```
BUILD_TYPE=release make android
```

Windows (cmd.exe):

```
set BUILD_TYPE=release
.\build android
```

## Per-Platform Guides

Output filenames use the `DISPLAYNAME` from `src/config` (which may contain spaces) for macOS `.app` bundles, Windows `.exe` files, and Linux binaries. Android APKs and iOS `.ipa` files use `PROGNAME` (no spaces). See [CONFIG.md](CONFIG.md) for details.

* **[Building on macOS](BUILD-macOS.md)** — native macOS builds, plus cross-compiling for iOS, iOS Simulator, Windows, Android, and WWW
* **[Building on Windows](BUILD-Windows.md)** — native Windows builds, plus cross-compiling for Android and WWW
* **[Building on Linux](BUILD-Linux.md)** — native Linux builds, plus cross-compiling for Windows, Android, and WWW
