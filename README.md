![Passiflora](logo.png)

# Passiflora

Passiflora is a no-nonsense cross-platform packager that wraps HTML/JavaScript/CSS/etc. in an executable (similar to Electron and its ilk, but far, far more efficiently). 

Much of this project was vibe coded as an experiment (see below).

Things are still "moving fast", but it's getting to a stage where I'm going to try to avoid "breaking things". However, I'm sure there are still some uglinesses and infelicities present. Please raise an issue if you notice anything amiss (especially security issues).

Supported host platforms include:

* macOS (available targets macOS, iOS, Android, Windows, WWW, and Linux (via Docker))
* Windows (available targets Windows, Android, and WWW)
* Linux (available targets Linux, Windows, Android, WWW)
* Need a different host or target? Open an issue... all suggestions will be considered, within the limits of time and efficiency.
Features:

* Access to device location data, cameras, mics, etc.
* Remote debugging
* POSIX(-ish) file system
* Produce signed app-store ready binaries for macOS, iOS, and Android, both side-loaded and Google Play (experimental) All of these are relatively new and need thorough testing.

What it *doesn't* do:

* Require that you install 50 million dubious npm packages (or a whole freakin' Rust ecosystem)
* Generate 60 petabyte binaries for a "Hello, world!" program
* Require configuration gymnastics -- there's no need to fool with nasty-ass package.json scripts or even nastier-ass XML files -- no Maven, Ant, or Gradle config (Passiflora does *use* Gradle (technically gradlew) for Android builds, but you don't have to get the stench of it on you).

Unlike Electron, Passiflora uses the system's own embeddable web browser control rather than bundling an entire browser into the executable. Bundling a web browser made sense back in the bad old days of incompatible browsers and highly-restricted web app functionality, but things have improved immensely since then.

### Executable Size

The sample program weighs 1.5 MB when built for macOS, 1.1 MB of which is accounted for by the .icns icon file, leaving around 400 KB for the actual binary executable. 

By comparison, the same program when built for macOS using Electron/Electron Forge weighs **211 MB** --  more than **500 times larger**. Yikes!


Electron and Electron Forge also install **342** (!) npm packages, which generate scads of deprecation/security warnings (and, yes, I'm following the installation/compilation instructions on the Electron website that are current as of today, March 7, 2026).


## Prerequisites and Building

Detailed installation, build, cross-compilation, and code signing instructions are in the per-platform guides:

* **[Building on macOS](BUILD-macOS.md)** — native macOS builds, plus cross-compiling for iOS, iOS Simulator, Windows, Android, and WWW
* **[Building on Windows](BUILD-Windows.md)** — native Windows builds, plus cross-compiling for Android and WWW
* **[Building on Linux](BUILD-Linux.md)** — native Linux builds, plus cross-compiling for Windows, Android, and WWW

For signing targets, start from the top-level templates `signing_setup.sh` and `signing_setup.bat`, then copy to your private home keys folder (`~/passiflora-keys/` or `%USERPROFILE%\passiflora-keys\`) as documented in [BUILDING.md](BUILDING.md), [WINDOWS_SIGNING.md](WINDOWS_SIGNING.md), and [GOOGLE_PLAY_SIGNING.md](GOOGLE_PLAY_SIGNING.md).

### Quick Start

1. Install the prerequisites for your host system (see the guide above).
2. Check out a fresh copy of this repo.
3. Step 3 is only necessary if you want to create a new GitHub project for your app. If you don't care about that, skip to Step 4.

    To do this you'll (obviously) need a GitHub account. You'll also need the [GitHub CLI](https://cli.github.com/).
    
    Create your own project from the checkout:

**macOS / Linux:**
```
make newproject
```

**Windows (PowerShell):**
```
.\build newproject
```

You'll be prompted for a new project name. This removes the connection to the Passiflora repo, creates a fresh Git history, and pushes to a new private GitHub repository under your account.

4. Put your HTML/JavaScript/CSS in `src/www` (making sure to leave the `passiflora` folder intact). As one might expect, your startup file should be named `index.html`.
5. Build:

**macOS / Linux:**
```
make
```

**Windows (PowerShell):**
```
.\build
```

6. Your app should now build as a functioning binary. You'll probably want to customize some settings to set your app's name, icon, and so on (see below).

For information on cross-compiling (e.g., building iOS apps on macOS), all available make/build targets, and per-platform guides, see **[BUILDING.md](BUILDING.md)**.


## Making the App Your Own

Obviously you're gonna want to put your own HTML, JavaScript, CSS, images, and such inside the src/www folder.  Use whatever framework, UI library, etc. you want --- or just plain vanilla HTML/JS/CSS. It's all good, mang (or womang, as you prefer).

Here are some other customizations you'll probably want to make before building something for release.

### Config

The file `src/config` controls the program name, bundle identifier, permissions, orientation, and other app-level settings. Each line has the form `key value` (case-insensitive). Permissions use `true` / `false` values and default to `false` if omitted. The supplied sample config file has pretty much everything turned on. For apps you're planning to distribute, you should set everything to `false` except the ones you actually need (good security policy in general, plus app stores frown on unnecessary permissions).

| Setting | Values | Default |
|---------|--------|---------|
| `PROGNAME` | any name | `HeckinChonker` |
| `BUNDLE_ID` | reverse-DNS string | `com.pulpgrinder.HeckinChonker` |
| `uselocation` | `true`, `false` | `false` |
| `usecamera` | `true`, `false` | `false` |
| `usemicrophone` | `true`, `false` | `false` |
| `allowremotedebugging` | `true`, `false` | `false` |
| `orientation` | `portrait`, `landscape`, `both` | `both` |
| `theme` | theme name | `Default` |
| `body-font-stack` | font stack name | `System UI` |
| `heading-font-stack` | font stack name | `System UI` |
| `code-font-stack` | font stack name | `Monospace Code` |
| `port` | `40000`–`62000` | auto-generated |

Setting details:

- **`PROGNAME`**: Program name used for the output binary, app bundle, APK, and window title. Build scripts read this from `src/config`.
- **`BUNDLE_ID`**: Apple bundle ID (macOS/iOS) and Android `applicationId`. Must be unique. App stores reject `com.example.*`. See [BUILD-macOS.md](BUILD-macOS.md).
- **`uselocation`**: Enables GPS/geolocation. iOS/macOS links CoreLocation and adds `NSLocation*` keys. Android adds `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION`.
- **`usecamera`**: Enables camera access. iOS/macOS links AVFoundation and adds `NSCameraUsageDescription`. Android adds `CAMERA` permission.
- **`usemicrophone`**: Enables microphone access. iOS/macOS adds `NSMicrophoneUsageDescription`. Android adds `RECORD_AUDIO` permission.
- **`allowremotedebugging`**: When `true`, server binds to `0.0.0.0` for LAN debugging. When `false`, binds to `127.0.0.1` (localhost only).
- **`orientation`**: `portrait`, `landscape`, or `both`. Sets iOS `UISupportedInterfaceOrientations` and Android `android:screenOrientation`. Ignored on desktop.
- **`theme`**: Startup color theme. Must match a key in `PassifloraThemes.themeData`. See [MENUS-AND-THEMES.md](MENUS-AND-THEMES.md).
- **`body-font-stack`**, **`heading-font-stack`**, **`code-font-stack`**: Default font stacks. Must match keys in `PassifloraThemes.baseFontStackOptions`. See [Font Stacks](MENUS-AND-THEMES.md#font-stacks).
- **`port`**: Embedded HTTP server port. If omitted, build scripts choose a random port in `40000`-`62000` and write it to `src/config` for reuse. Changing the port changes origin and can hide prior IndexedDB-backed VFS data.

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

Each build generates `src/www/generated/config.js` and `src/www/generated/generated.js`, which include a runtime `PassifloraConfig` object containing values that may be useful at runtime. See **[PASSIFLORA-CONFIG.md](PASSIFLORA-CONFIG.md)**.

Note that this is not the same as `src/config`, where you set icons, names, and other build-time settings. The build process uses `src/config` (and other compile-time information) to generate the runtime files in `src/www/generated/`. You generally should not edit generated files by hand, since they are regenerated on the next build.

```javascript
let PassifloraConfig = {
  os_name: "iOS",          // or "macOS", "Windows", "Linux", "Android", "WWW"
  theme: "Northern Lights",      // default theme from src/config
  "body-font-stack": "System UI",     // default body font stack name
  "heading-font-stack": "Antique",    // default heading font stack name
  "code-font-stack": "Monospace Code", // default code font stack name
  port: 51299,             // localhost port the embedded server is listening on
  menus: [ ... ],          // menu structure from menu.txt (excludes *-prefixed items)
  handleMenu: function(title) { alert("Menu item clicked: " + title); }
};
```

- **`PassifloraConfig.os_name`** — the target platform, useful if your JavaScript needs to do different things on different platforms.
- **`PassifloraConfig.theme`** — the default theme name from `src/config`. Applied on startup; may be overridden by VFS-persisted choice.
- **`PassifloraConfig["body-font-stack"]`**, **`PassifloraConfig["heading-font-stack"]`**, **`PassifloraConfig["code-font-stack"]`** — default font stack names from `src/config`. Must match keys in `PassifloraThemes.baseFontStackOptions`.
- **`PassifloraConfig.port`** — the localhost port from `src/config`. At runtime, if the configured port was unavailable (collision), `PassifloraIO` automatically updates this to the actual port the server bound to.
- **`PassifloraConfig.menus`** — the menu structure as a nested JSON array, useful for building custom menus. Items prefixed with `*` in `menu.txt` are excluded — they are native-only and never reach JavaScript.
- **`PassifloraConfig.handleMenu`** — called by both the native menu bar and the built-in sliding menu when a (non-native) menu item is selected. Override this in your `app.js` to handle menu actions.

This file is auto-generated on every build and should not be edited by hand.

## File I/O

Passiflora includes POSIX-style file functions, Open/Save As/File Browser dialogs, and a virtual file system backed by IndexedDB. Full documentation is in **[FILE_IO.md](FILE_IO.md)**.

## Utility Functions

These are methods on `PassifloraIO` (not available as bare globals).

| Function | Description |
|----------|-------------|
| `PassifloraIO.openExternal(url)` | Open a URL in the system's default browser. On Android uses the native bridge; on other platforms issues a request to the embedded server's `openexternal` endpoint. Only `http://` and `https://` URLs are allowed. |
| `PassifloraIO.getCurrentPosition(successCb, errorCb)` | Get the device's current GPS position. On macOS/iOS uses the native CLLocationManager bridge; on other platforms delegates to `navigator.geolocation`. Callbacks follow the standard Geolocation API signature. |
| `PassifloraIO.webDownload(path, mimeType)` | Trigger a browser download for a VFS file. On macOS/iOS uses the native save panel via `passifloraSaveFile`; on other platforms creates a temporary download link. `mimeType` defaults to `"application/octet-stream"` if omitted. |
| `PassifloraIO.patchLinks()` | Scan the DOM for `<a href>` elements with `http://` or `https://` URLs and attach click handlers that route them through `openExternal()` instead of navigating the webview. Called automatically on `DOMContentLoaded`. |
| `PassifloraIO.hasNativeRecording()` | Returns a Promise resolving to `true` if recording is available on this platform, `false` otherwise. |
| `PassifloraIO.startRecording(hasVideo, hasAudio)` | Start recording. `hasVideo` and `hasAudio` are booleans selecting which tracks to capture. Returns a Promise that resolves when recording has started. |
| `PassifloraIO.stopRecording()` | Stop a recording in progress. Returns a Promise resolving to a `Uint8Array` containing the recorded WebM data (or `null` if no data). |
| `PassifloraIO.diagnoseNativeAudio()` | Run audio diagnostics. Returns a Promise resolving to a diagnostic string. |

## Debugging

If you build for the WWW target, you'll be able to use normal browser dev tools for debugging. For binaries, Passiflora includes a built-in remote debugging facility that lets you execute JavaScript in a running app from an external browser. This is useful for inspecting app state, testing code snippets, and diagnosing issues on platforms where browser dev tools aren't available (iOS, Android, etc.).

Remote debugging is compile-gated — set `allowremotedebugging` to `true` in `src/config` to enable it. When enabled, a setup overlay appears at app startup where you enter a shared passphrase and copy the debugger URL. Open that URL in a browser on another device to send JavaScript commands to the running app.

For the full protocol details, security notes, and usage tips, see **[DEBUGGING.md](DEBUGGING.md)**.

## About this project

This code was developed through an iterative process involving human-guided prompting of a large language model (LLM), followed by review, editing, refinement, and original contributions by the author. To the extent the work contains copyrightable human-authored elements (including structure, modifications, arrangements, and additions), it is Copyright (c) 2026 by Anthony W. Hursh. The project is distributed under the terms of the MIT License (see LICENSE file for full text). Portions generated directly by AI may not be independently copyrightable under current U.S. law.

### Details

The basic idea for this has been hanging around my todo list, along with code snippets, for several years. I finally decided to use it as a proof of concept for vibe coding. If it's of interest, the code per se was mostly written with GitHub Copilot using Claude Opus 4.6. Configuration questions and similar (e.g., "Why aren't location services working on my Ubuntu Linux system running in a Parallels Desktop VM?") were mostly handled with Grok 4.0.



