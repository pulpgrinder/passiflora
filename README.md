# Passiflora

Passiflora is a no-nonsense cross-platform packager that wraps HTML/JavaScript/CSS/etc. in an executable (similar to Electron and its ilk). Supported platforms include:

* macOS (build on macOS only)
* iOS (build on macOS only)
* Android (build on macOS, Windows, or Linux)
* Windows (build on macOS, Windows, or Linux)
* Linux (build on Linux; definitely needs testing)

What it *doesn't* do:

* Require that you install 50,000 npm packages
* Engage in baroque configuration gymnastics
* Generate 600 terabyte binaries for a helloworld program

Passiflora uses the system's own web browser control rather than bundling an entire browser into the executable, like Electron. Doing that made sense back in the bad old days of incompatible browsers, but things have improved immensely since then. It's my belief that it's now preferable to work through whatever minor inconsistencies that remain than take the enormous hit of bundling an entire browser in the executable.

## Prerequisites

### All Platforms

* C compiler (`cc` / `gcc` / `clang`)
* `make`
* ImageMagick — icon generation (`magick` / `convert`)
  * macOS: `brew install imagemagick`
  * Linux: `sudo apt install imagemagick`
  * Windows: `winget install ImageMagick.ImageMagick` (or https://imagemagick.org)

### macOS (native build: `make`)

* Xcode Command Line Tools — `xcode-select --install`
  Provides: clang, Cocoa.framework, WebKit.framework, xcrun, iconutil, codesign

Additional targets built from macOS:

* **iOS** (`make ios`) — Xcode (full install) with an iOS SDK
* **iOS Simulator** (`make iossim`) — Xcode with Simulator runtime installed
* **Windows cross-compile** (`make windows`):
  * mingw-w64 — `brew install mingw-w64`
  * curl (pre-installed on macOS)
  * xxd (pre-installed via vim)
* **Android** (`make android`):
  * Android SDK (Android Studio or standalone)
  * Android NDK (install via SDK Manager)
  * Java 17+ — `brew install openjdk@17`
  * Gradle — `brew install gradle` (or use the generated `gradlew` wrapper)

### Linux (native build: `make` or `make linux`)

* GCC — `sudo apt install build-essential`
* GTK 3 development files — `sudo apt install libgtk-3-dev`
* WebKit2GTK — `sudo apt install libwebkit2gtk-4.1-dev`
  (falls back to webkit2gtk-4.0 if 4.1 is unavailable)
* pkg-config — `sudo apt install pkg-config`

One-liner (Debian / Ubuntu):

```
sudo apt install build-essential pkg-config libgtk-3-dev \
                 libwebkit2gtk-4.1-dev imagemagick
```

Additional targets from Linux:

* **Android** (`make android`):
  * Android SDK / NDK
  * Java 17+ — `sudo apt install openjdk-17-jdk`
  * Gradle — `sudo apt install gradle` (or use the generated `gradlew` wrapper)

### Windows (native build: `build.bat`)

* MinGW-w64 (GCC for Windows) — https://www.mingw-w64.org or MSYS2: `pacman -S mingw-w64-x86_64-gcc`
* PowerShell 5.1+ (pre-installed on Windows 10/11)
* curl (pre-installed on Windows 10/11)
* Microsoft Edge WebView2 Runtime — pre-installed on Windows 10 (April 2018+) and Windows 11. The WebView2Loader.dll is downloaded automatically at build time from NuGet and embedded into the executable.

Optional:

* windres (from MinGW-w64) — embeds app.ico into the executable

Additional targets from Windows:

* **Android** (`build.bat android`):
  * Android SDK / NDK
  * Java 17+
  * Gradle

## Quick Start

1. Make sure you have the dependencies listed above installed.
2. Check out a fresh copy of this repo.
3. Edit the Makefile (Mac, Linux, Android, iOS) or `build.bat` (native Windows).
   Use `PROGNAME = YourAppName` in the Makefile (`set PROGNAME=YourAppName` in `build.bat` for windows).
4. Put all your HTML/JavaScript/CSS/images/whatever in `src/www`.

## Building

### On macOS

`make` — Build a macOS app bundle (plain `make` with no arguments builds for whatever platform you're on).

`make ios` — Build for a physical iPhone or iPad.

`make iossim` — Build for the iOS Simulator. Also launches the simulator (if it's not already running), transfers the app to it, and runs it.

`make windows` — Cross-compile a Windows binary (requires mingw-w64).

`make android` — Build an Android APK (requires Android SDK/NDK).

`make clean` — Remove all build artifacts.

### On Linux

`make` or `make linux` — Build a native Linux binary.

`make android` — Build an Android APK.

`make clean` — Remove all build artifacts.

### On Windows

`build` or `build.bat` — Build a Windows EXE.

`build android` — Build an Android APK.

`build clean` — Remove all build artifacts.

### Android Release Builds

By default, `make android` and `build android` produce a **debug** APK. To build a signed **release** APK, set the `BUILD_TYPE` environment variable:

**macOS/Linux:**
```
BUILD_TYPE=release make android
```

**Windows:**
```
set BUILD_TYPE=release
build android
```

#### Test keystore (included)

A test keystore (`src/android/release.jks`, password `testtest`) is included in the repo for convenience. It is used automatically when you build a release APK with no further configuration. **Do not ship apps signed with the test keystore** — it is for development and testing only.

#### Using a real keystore for production

1. Generate a keystore:

```
keytool -genkey -v -keystore my-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mykey
```

2. Set these environment variables before building:

```
export RELEASE_KEYSTORE=/path/to/my-release.jks
export RELEASE_KEYSTORE_PASSWORD=your-store-password
export RELEASE_KEY_ALIAS=mykey
export RELEASE_KEY_PASSWORD=your-key-password
```

(On Windows, use `set` instead of `export`.)

3. Build:

```
BUILD_TYPE=release make android
```

The environment variables override the test keystore defaults in `src/android/app/build.gradle`. **Keep your production keystore and passwords out of version control**. 

## Making the App Your Own

Obviously you're gonna want to put your own HTML, JavaScript, CSS, images, and such inside the src/www folder. Here are some other customizations you'll probably want to make before building something for release.

### Icons

Change `roundicon.png` and `squareicon.png` in `src/icons` to whatever images you like. These should be pretty big — around 1,000 pixels square or more. The `squareicon.png` file should be square (duh!), while the `roundicon.png` should be a square image consisting of a round image on a transparent background. Look at the supplied example if this seems confusing.

All of the scads of other icons for the various different systems are generated from these.

Once you've updated the icons, run:

`make icons` (macOS and Linux)

or

`winscripts\buildicons.bat` (Windows)

to generate a new icon set (on Windows `build.bat icons` would also work).

Note that these may need some manual tweaking for legibility, particularly at the smaller sizes, but it's still a substantial time savings over generating them all individually. Icons are *not* regenerated automatically during a normal build, so your hand-tuned versions won't be overwritten.

### Menus

Underneath `src`, each platform has a folder which contains a `menu.txt` file. These are used to generate menus. They will appear in the menu bar (for platforms that have a menu bar, e.g., Mac and Windows). They will also be converted to JavaScript and placed in `src/www/generated/PassifloraMenus.js`, which assigns the menu data to the `PASSIFLORA_MENUS` variable. These can be used to build your own custom menus on mobile platforms.

The format should be clear — the different levels of a menu are expressed with indentation.

For platforms with a menu bar, choosing a menu item will call the `handlemenu()` JavaScript function in your code. For example, if you have:

```
{{progname}}
    About
    Quit
File
    Open
Misc
    More stuff
```

Choosing "More stuff" will call `handlemenu("More stuff")` in your JavaScript.

The default `handlemenu` just pops an alert.

## Miscellaneous

After building for a platform, a generated `src/www/generated/systemid.js` will contain something like:

`PASSIFLORA_OS_NAME = "iOS";`

This can be used in case you need your JavaScript code to do different things on different platforms. This file is auto-generated on every build and should not be edited by hand.

## Make Targets Summary

| Target | Description |
|--------|-------------|
| `make` | Build for current platform (macOS or Linux) |
| `make windows` | Cross-compile Windows exe (from macOS/Linux) |
| `make linux` | Build Linux binary (on Linux only) |
| `make ios` | Cross-compile iOS binary (macOS only) |
| `make iossim` | Build, install, launch in iOS Simulator (macOS only) |
| `make android` | Build Android APK |
| `make icons` | Generate icon sets for all platforms |
| `make clean` | Remove all build artifacts |


