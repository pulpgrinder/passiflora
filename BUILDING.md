# Building

## Make/Build Targets Summary

| Target | Description |
|--------|-------------|
| `make` | Build for current platform (macOS or Linux) |
| `make macos` | Build macOS binary and app bundle (macOS only) |
| `make windows` | Cross-compile Windows exe (from macOS or Linux) |
| `make linux` | Build Linux binary (Linux only) |
| `make sim-ios` | Build, install, launch in iOS Simulator (macOS only) |
| `make sign-ios` | Build, sign, and package iOS .ipa — App Store ready (macOS only) |
| `make android` | Build Android APK |
| `make icons` | Generate icon sets for all platforms |
| `make clean` | Remove all build artifacts |
| `make www` | Build plain-browser version into `bin/WWW/` -- useful for debugging using browser tools |
| `make sign-macos` | Sign, notarize, and package macOS app — produces notarized .app and App Store .pkg (macOS only) |
| `make sign-android` | Sign the Android APK with a local keystore (macOS and Linux)|
| `.\build` or `.\build windows` | Build Windows exe (Windows) |
| `.\build android` | Build Android APK (Windows) |
| `.\build sign-android` | Sign the Android APK (Windows) |
| `.\build www` | Build plain-browser version into `bin\WWW\` (Windows) -- useful for debugging using browser tools |
| `.\build icons` | Generate icon sets (Windows) |
| `.\build clean` | Remove all build artifacts (Windows) |

## Per-Platform Guides

* **[Building on macOS](BUILD-macOS.md)** — native macOS builds, plus cross-compiling for iOS, iOS Simulator, Windows, Android, and WWW
* **[Building on Windows](BUILD-Windows.md)** — native Windows builds, plus cross-compiling for Android and WWW
* **[Building on Linux](BUILD-Linux.md)** — native Linux builds, plus cross-compiling for Windows, Android, and WWW
