![Passiflora](logo.png)

# Passiflora

Passiflora is a no-nonsense cross-platform packager that wraps HTML/JavaScript/CSS/etc. in an executable (similar to Electron and its ilk, but far, far more efficiently). 

Follow on X: https://x.com/TonyHursh

Much of this project was vibe coded as an experiment (see below).

I'm still moving fast, though it's to a stage where I'm going to try to avoid breaking things. I expect to have a release candidate by the end of this week (April 17, 2026). However, I'm sure there are still some uglinesses and infelicities present. Please raise an issue if you notice anything amiss (especially security issues).

Supported host platforms include:

* macOS  -- available targets: macOS, iOS, Android, Windows, WWW, and Linux (via Docker)
* Windows -- available targets: Windows, Android, and WWW
* Linux -- available targets: Linux, Windows, Android, WWW
* Need a different host or target? Open an issue... all suggestions will be considered, within the limits of time and efficiency.

Features:

* Access to device location data, cameras, mics, etc.
* Remote debugging
* POSIX(-ish) file system
* Code signing for macOS, iOS, and Android (support for the Google Play app store is under construction). These are still experimental. Please report any issues. Code signing for Windows is expected in a future release.

What it *doesn't* do:

* Require that you install 50 million dubious npm packages (or a whole freakin' Rust ecosystem)
* Generate 60 petabyte binaries for a "Hello, world!" program
* Require configuration gymnastics -- there's no need to fool with nasty-ass package.json scripts or even nastier-ass XML files -- no Maven, Ant, or Gradle config. Passiflora does *use* Gradle (technically gradlew) for Android builds, but you don't have to get the stench of it on you.

Unlike Electron, Passiflora uses the system's own embeddable web view object rather than bundling an entire browser into the executable. Bundling a web browser made sense back in the bad old days of incompatible browsers and highly-restricted web app functionality, but things have improved immensely since then.

### Executable Size

The sample program weighs 1.5 MB when built for macOS, 1.1 MB of which is accounted for by the .icns icon file, leaving around 400 KB for the actual binary executable. 

By comparison, the same program when built for macOS using Electron/Electron Forge weighs **211 MB** --  more than **500 times larger**. Yikes!


Electron and Electron Forge also install **342** (!) npm packages, which generate scads of deprecation/security warnings (and, yes, I'm following the installation/compilation instructions on the Electron website that are current as of today, March 7, 2026).


## Prerequisites and Building

Detailed installation, build, cross-compilation, and code signing instructions are in the per-platform guides:

* **[Building on macOS](BUILD-macOS.md)** — native macOS builds, plus cross-compiling for iOS, Windows, Android, WWW, and Linux (via Docker)
* **[Building on Windows](BUILD-Windows.md)** — native Windows builds, plus cross-compiling for Android and WWW
* **[Building on Linux](BUILD-Linux.md)** — native Linux builds, plus cross-compiling for Windows, Android, and WWW

### Quick Start

1. Install the prerequisites for your host system (see the guide above).
2. Check out a fresh copy of this repo.
3. Put your HTML/JavaScript/CSS in `src/www` (making sure to leave the `passiflora` folder intact).
4. Build:

**macOS / Linux:**
```
make
```

**Windows (PowerShell):**
```
.\build
```

5. There is no step 5, at least in the sense of building a functioning binary. You'll probably want to customize some of the settings to (e.g.) set your app's name, icon, and so on (see below).

For information on cross-compiling (e.g., building iOS apps on macOS), all available make/build targets, and per-platform guides, see **[BUILDING.md](BUILDING.md)**.


## Making the App Your Own

Obviously you're gonna want to put your own HTML, JavaScript, CSS, images, and such inside the src/www folder.  Use whatever framework, UI library, etc. you want --- or just plain vanilla HTML/JS/CSS. It's all good, mang (or womang, as you prefer).

Here are some other customizations you'll probably want to make before building something for release.

### Config

The file `src/config` controls the program name, bundle identifier, permissions, orientation, and other app-level settings. Each line has the form `key value` (case-insensitive). Permissions use `true` / `false` values and default to `false` if omitted. The supplied sample config file has pretty much everything turned on so you can test things. For apps you're planning to distribute, you should set everything to `false` except the ones you actually need (good security policy in general, plus app stores frown on unnecessary permissions).

- **`PROGNAME`** — Values: any name — Default: `HeckinChonker`
  The program name used for the output binary, app bundle, APK, and window title. All build scripts (Makefile, build.bat, Gradle) read this from `src/config`.

- **`BUNDLE_ID`** — Values: reverse-DNS string — Default: `com.example.HeckinChonker`
  The bundle identifier is used as the Apple bundle ID (macOS/iOS) and Android `applicationId`. Must be unique — app stores reject `com.example.*`. See the [macOS Build Guide](BUILD-macOS.md) for rules.

- **`uselocation`** — Values: `true`, `false` — Default: `false`
  Enables GPS / geolocation. On iOS and macOS this links CoreLocation and adds the required `NSLocation*` plist keys. On Android it adds `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` to the manifest and enables the WebView geolocation prompt.

- **`usecamera`** — Values: `true`, `false` — Default: `false`
  Enables camera access (screenshots, image capture, video recording). On iOS / macOS this links AVFoundation and adds `NSCameraUsageDescription`. On Android it adds the `CAMERA` manifest permission.

- **`usemicrophone`** — Values: `true`, `false` — Default: `false`
  Enables microphone access (audio recording, video with audio). On iOS / macOS this adds `NSMicrophoneUsageDescription`. On Android it adds `RECORD_AUDIO` to the manifest.

- **`allowremotedebugging`** — Values: `true`, `false` — Default: `false`
  When `true`, the embedded HTTP server listens on all network interfaces (`0.0.0.0`), allowing remote debugging connections from other devices on the same network. When `false` (default for production), the server binds to `127.0.0.1` (localhost only) and remote debugging is not possible.

- **`orientation`** — Values: `portrait`, `landscape`, `both` — Default: `both`
  Controls whether the app is locked to portrait or landscape orientation, or rotates freely. On iOS this sets `UISupportedInterfaceOrientations` in the Info.plist. On Android it sets `android:screenOrientation` on the main activity. Desktop platforms ignore this setting.

- **`theme`** — Values: theme name — Default: `Northern Lights`
  The color theme applied on startup. Must match a key in `PassifloraThemes.themeData`. See [MENUS-AND-THEMES.md](MENUS-AND-THEMES.md) for the full list of built-in themes.

- **`body-font-stack`** — Values: font stack name — Default: `System UI`
  Default font stack for body text. Must match a key in `PassifloraThemes.baseFontStackOptions`. See [MENUS-AND-THEMES.md](MENUS-AND-THEMES.md#font-stacks).

- **`heading-font-stack`** — Values: font stack name — Default: `Antique`
  Default font stack for headings. Same values as `body-font-stack`.

- **`code-font-stack`** — Values: font stack name — Default: `Monospace Code`
  Default font stack for code blocks. Same values as `body-font-stack`.

- **`port`** — Values: `40000`–`62000` — Default: auto-generated
  The localhost port the embedded HTTP server listens on. If omitted, the build system picks a random port in the 40000–62000 range and writes it back to `src/config` so subsequent builds reuse the same port. A stable port is important because IndexedDB storage is scoped by origin (including port) — changing it loses persisted VFS data. If the configured port is unavailable at runtime, the server tries random ports in the same range.

### Icons

Change `roundicon.png` and `squareicon.png` in `src/icons` to whatever PNG images you like. These should be pretty big — around 1,000 pixels square. More is better! The `squareicon.png` file should be square (duh!), while the `roundicon.png` should be a square image with an inscribed round image on a transparent background (I realize that may sound a little confusing... look at the supplied `roundicon.png` if you need clarification).

All of the zillions of other icons for the various different systems are generated from these.

Once you've updated the base icons, run:

`make icons` (macOS and Linux)

or

`.\build icons` (Windows)

to generate a new icon set.

Note that these may need some manual tweaking for legibility, particularly at the smaller sizes, but it's still a substantial time savings over generating them all individually. Icons are *not* regenerated automatically during a normal build (not even after `make clean`). This is so any hand-tuned versions you've created won't be overwritten. If you *do* want to wipe out all existing icons and start over, run `make icons` or `.\build icons` again.

### Menus, Themes, and Font Stacks

Passiflora includes a basic menu system (native menu bar + sliding menu + panel screens), 122 built-in color themes, and a curated set of font stacks. Full documentation is in **[MENUS-AND-THEMES.md](MENUS-AND-THEMES.md)**. Of course, you're welcome to ignore this and roll your own UI, including the menu system.

## PassifloraConfig

Each build generates `src/www/generated/config.js`, which defines a `PassifloraConfig` object containing numerous useful values. See **[PassifloraConfig.md](PassifloraConfig.md)**.

## File I/O

Passiflora includes POSIX-style file functions, Open/Save As/File Browser dialogs, and a virtual file system backed by IndexedDB. Full documentation is in **[FILE_IO.md](FILE_IO.md)**.

## Utility Functions

There are numerous utility functions defined on the PassifloraIO object. See  **[UtilityFunctions.md](UtilityFunctions.md)**.

## Debugging

If you build for the WWW target, you'll be able to use normal browser dev tools for debugging. For binaries, Passiflora includes a built-in remote debugging facility that lets you execute JavaScript in a running app from an external browser. This is useful for inspecting app state, testing code snippets, and diagnosing issues on platforms where browser dev tools aren't available (iOS, Android, etc.).

Remote debugging is compile-gated — set `allowremotedebugging` to `true` in `src/config` to enable it. When enabled, a setup overlay appears at app startup where you enter a shared passphrase and copy the debugger URL. Open that URL in a browser on another device to send JavaScript commands to the running app.

For the full protocol details, security notes, and usage tips, see **[DEBUGGING.md](DEBUGGING.md)**.

## About this project

This code was developed through an iterative process involving human-guided prompting of a large language model (LLM), followed by review, editing, refinement, and original contributions by the author. To the extent the work contains copyrightable human-authored elements (including structure, modifications, arrangements, and additions), it is Copyright (c) 2026 by Anthony W. Hursh. The project is distributed under the terms of the MIT License (see LICENSE file for full text). Portions generated directly by AI may not be independently copyrightable under current U.S. law.

### Details

The basic idea for this has been hanging around my todo list, along with code snippets, for several years. I finally decided to use it as a proof of concept for vibe coding. If it's of interest, the code per se was mostly written with GitHub Copilot using Claude Opus 4.6. Configuration questions and similar (e.g., "Why aren't location services working on my Ubuntu Linux system running in a Parallels Desktop VM?") were mostly handled with Grok 4.0.



