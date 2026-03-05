![Passiflora](logo.png)

# Passiflora

Passiflora is a no-nonsense cross-platform packager that wraps HTML/JavaScript/CSS/etc. in an executable (similar to Electron and its ilk). Note that this should be considered **experimental** at this point. Please report any issues.

Supported platforms include:

* macOS (build on macOS only, alas)
* iOS (likewise)
* Android (build on macOS, Windows, or Linux)
* Windows (build on macOS, Windows, or Linux)
* Linux (build on Linux)
* More targets may be added later if they seem useful

What it *doesn't* do:

* Require that you install 50 million dubious npm packages (or a whole freakin' rust ecosystem, for the love of all that's holy)
* Engage in baroque configuration gymnastics
* Generate 60 petabyte binaries for a "Hello, world!" program

Passiflora uses the system's own web browser control rather than bundling an entire browser into the executable, like Electron. Similarly, Passiflora doesn't provide a lot of integration with the native OS -- things like file open/save (i.e., upload/download), access to the mic, camera and speaker, gps data, etc. can now be done from HTML. Doing these things made sense back in the bad old days of incompatible browsers and highly-restricted web app functionality, but things have improved immensely since then.It's my belief that it's now preferable to work through whatever inconsistencies and shortcomings that remain than take the enormous hit of bundling an entire browser and native API in the executable. It's possible that some native integration will be added in the future, but the plan is to to continue doing everything with web technology that *can* be done with web technology.

Binary sizes for a bare program that simply displays "Hello, world!":

Passiflora: 3.6 MB

## Prerequisites

The table below shows what to install for each combination of target platform and build host. Start with the **all** row for your host OS, then add anything listed in the row for your target.

On Windows, native builds use `build.bat` instead of `make`. PowerShell 5.1+ and curl are pre-installed on Windows 10/11.

<table>
<tr>
  <th></th>
  <th colspan="3" align="center"><em>on</em></th>
</tr>
<tr>
  <th><em>To build</em></th>
  <th>macOS</th>
  <th>Linux (Debian/Ubuntu)</th>
  <th>Windows</th>
</tr>

<tr>
  <td><strong>all</strong><br>(base toolchain)</td>
  <td>
    <code>xcode-select --install</code><br>
    <code>brew install imagemagick</code>
  </td>
  <td>
    <code>sudo apt install build-essential imagemagick</code>
  </td>
  <td>
    MinGW-w64 &mdash; <a href="https://www.mingw-w64.org">mingw-w64.org</a> or MSYS2:<br>
    <code>pacman -S mingw-w64-x86_64-gcc</code><br>
    <code>winget install ImageMagick.ImageMagick</code>
  </td>
</tr>

<tr>
  <td><strong>macOS</strong></td>
  <td><em>(nothing beyond base)</em></td>
  <td>&mdash;</td>
  <td>&mdash;</td>
</tr>

<tr>
  <td><strong>iOS</strong></td>
  <td>Xcode (full install) with an iOS SDK</td>
  <td>&mdash;</td>
  <td>&mdash;</td>
</tr>

<tr>
  <td><strong>iOS Simulator</strong></td>
  <td>Xcode with Simulator runtime installed</td>
  <td>&mdash;</td>
  <td>&mdash;</td>
</tr>

<tr>
  <td><strong>Windows</strong></td>
  <td>
    <code>brew install mingw-w64</code><br>
    (curl, xxd pre-installed)
  </td>
  <td>
    <code>sudo apt install mingw-w64 xxd unzip</code><br>
    curl is often pre-installed. If not,<code>sudo apt install curl</code>
  </td>
  <td>
    <em>(nothing beyond base)</em><br>
    WebView2 Runtime (pre-installed on Win&nbsp;10+)<br>
    Optional: <code>windres</code> (from MinGW-w64) embeds app icon
  </td>
</tr>

<tr>
  <td><strong>Linux</strong></td>
  <td>&mdash;</td>
  <td>
    <code>sudo apt install pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev</code><br>
    (falls back to <code>webkit2gtk-4.0</code> if 4.1 is unavailable)
  </td>
  <td>&mdash;</td>
</tr>

<tr>
  <td><strong>Android</strong></td>
  <td>
    Android SDK + NDK<sup>†</sup><br>
    <code>brew install openjdk@17 gradle</code>
  </td>
  <td>
    Android SDK + NDK<sup>†</sup><br>
    <code>sudo apt install openjdk-17-jdk gradle</code>
  </td>
  <td>
    Android SDK + NDK<sup>†</sup><br>
    Java 17+, Gradle
  </td>
</tr>
</table>

**&mdash;** = not supported from that host.

<sup>†</sup> Install the NDK via the Android SDK Manager. You can use Android Studio or the standalone SDK. The included `gradlew` wrapper can substitute for a system Gradle install.

## Configuring

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

`make windows` — Cross-compile a Windows binary

`make android` — Build an Android APK

`make clean` — Remove all build artifacts.

### On Linux

`make` or `make linux` — Build a native Linux binary.

`make windows` — Cross-compile a Windows binary

`make android` — Build an Android APK.

`make clean` — Remove all build artifacts.

#### Desktop Integration (Ubuntu / GNOME)

The first time you run the Linux binary, it automatically installs its icon and a `.desktop` file so the app shows up properly in the GNOME dock, launcher, and file manager:

* **Icon** → `~/.local/share/icons/hicolor/256x256/apps/PROGNAME.png` (written from embedded PNG data)
* **Desktop entry** → `~/.local/share/applications/PROGNAME.desktop`

If you move the binary to a new location, the next launch updates the `Exec=` path in the `.desktop` file automatically. No manual steps are needed.

> **Note:** After the first run, the file manager (Nautilus/Files) may not display the custom icon for the binary until you navigate away from the directory and back. This is a Nautilus caching behaviour and not something the application can control.

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

Note that these may need some manual tweaking for legibility, particularly at the smaller sizes, but it's still a substantial time savings over generating them all individually. Icons are *not* regenerated automatically during a normal build, so your hand-tuned versions won't be overwritten (unless, of course, you run `make icons` or `build icons`).

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
| `make sign-macos` | Interactively sign the macOS app bundle |
| `make sign-ios` | Interactively sign the iOS app bundle |
| `make sign-iossim` | Interactively sign the iOS Simulator app bundle |
| `make sign-android` | Sign the Android APK with a local keystore |


## Code Signing for macOS and iOS

Passiflora provides interactive signing targets for macOS, iOS, and iOS Simulator builds:

* `make sign-macos` — Sign the macOS app bundle
* `make sign-ios` — Sign the iOS app bundle (physical device)
* `make sign-iossim` — Sign the iOS Simulator app bundle

These targets invoke the interactive script `nixscripts/signapp.sh`, which:

1. Lists all available code signing identities on your Mac.
2. Describes each signing option (Developer ID, Apple Development, Distribution, Ad-hoc, etc.).
3. Prompts you to select an identity or choose ad-hoc signing.
4. Signs the app bundle with your chosen identity and displays signature details.

**Signing options explained:**

**IMPORTANT: Never, ever, ever put your signing certificates, keystores, passwords, etc. into a folder managed by git or another version control system. Ever.**

* **macOS:**
  * Developer ID Application — For distribution outside the App Store.
  * Apple Development / Mac Developer — For local development/testing.
  * Apple Distribution / 3rd Party Mac Developer Application — For Mac App Store submission.
  * Ad-hoc — No identity; runs only on your Mac (Gatekeeper blocks elsewhere).

* **iOS:**
  * Apple Development / iPhone Developer — For running on your own devices.
  * Apple Distribution / iPhone Distribution — For App Store or enterprise distribution.
  * Ad-hoc — Minimal signature; will NOT install on devices without a provisioning profile.

* **iOS Simulator:**
  * Apple Development — Standard development signing for Simulator.
  * Ad-hoc — Usually sufficient for Simulator use.

If no identities are found, ad-hoc signing is always available. The script will guide you through the process and show signature details when complete.

Each signing target automatically builds the corresponding app bundle first, so there is no need to run a separate build step beforehand.

## Code Signing for Android

`make sign-android` (or `build sign-android` on Windows) builds the Android APK and then signs it with a local keystore. The target will:

1. Build the APK (runs the `android` target first).
2. Prompt you for the keystore file path.
3. Prompt you for the keystore password.
4. Zipalign the APK (if `zipalign` is available).
5. Sign the APK using `apksigner` from the Android SDK build-tools.
6. Verify the signature.

**Prerequisites:**

* Android SDK with build-tools installed (`apksigner` and optionally `zipalign`). These are located automatically via `ANDROID_HOME`; alternatively, add the build-tools directory to your `PATH`.
* A Java keystore (`.jks` or `.keystore` file). Generate one with:

```
keytool -genkey -v -keystore my-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mykey
```

**Usage:**

```
make sign-android          # macOS / Linux
build sign-android          # Windows
```

You will be prompted interactively for the keystore file and password. The signed APK is written to `bin/Android/<progname>.apk`.

**IMPORTANT: This bears repeating. Never, ever, ever put your signing certificates, keystores, passwords, etc. into a folder managed by git or another version control system. Ever.**


