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
| `make android` | Build Android APK |
| `make sign-android` | Sign the Android APK with a local keystore (macOS and Linux)|
| `make googleplay-android` | Build a release AAB for Google Play upload (under construction) |
| `make linux` | Build Linux binary (Linux only) -- same as `make` if you're on Linux |
| `make linux-docker` | Build Linux binary using a Docker container (macOS only — requires Docker) |
| `make www` | Build plain-browser version in `bin/WWW/` -- useful for debugging using browser tools |
| `make all` | Build *every* platform: macOS, iOS, Windows, Android, Linux via Docker (macOS only) |
| `make sign-all` | Build + sign *every* platform, including Google Play AAB (macOS only — iOS and Android prompt for credentials). Note that Windows signing is not yet supported.|
| `make icons` | Generate icon sets for all platforms |
| `make clean` | Remove all build artifacts |

### Windows hosts

| Target | Description |
|--------|-------------|
| `.\build` or `.\build windows` | Build Windows exe (Windows) |
| `.\build android` | Build Android APK (Windows) |
| `.\build sign-android` |Build a signed Android APK (Windows) |
| `.\build googleplay-android` | Build a release AAB for Google Play upload (Windows) (under construction)|
| `.\build www` | Build plain-browser version in `bin\WWW\` (Windows) -- useful for debugging using browser tools |
| `.\build linux-docker` | Build Linux binary using a Docker container (Windows — requires Docker) |
| `.\build icons` | Generate icon sets (Windows) |
| `.\build clean` | Remove all build artifacts (Windows) |

## Per-Platform Guides

* **[Building on macOS](BUILD-macOS.md)** — native macOS builds, plus cross-compiling for iOS, iOS Simulator, Windows, Android, and WWW
* **[Building on Windows](BUILD-Windows.md)** — native Windows builds, plus cross-compiling for Android and WWW
* **[Building on Linux](BUILD-Linux.md)** — native Linux builds, plus cross-compiling for Windows, Android, and WWW
