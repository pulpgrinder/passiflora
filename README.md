![Passiflora](logo.png)

# Passiflora

Passiflora is a no-nonsense cross-platform packager that wraps HTML/JavaScript/CSS/etc. in an executable (similar to Electron and its ilk). 

Things are still "moving fast", but it's getting to a stage where I'm going to try to avoid "breaking things". However, this system is still in a state of flux.  Please report any issues. In addition, much of this project was vibe coded as an experiment. The basic idea for this has been hanging around my todo list, along with code snippets, for several years. I finally decided to use it as a proof of concept for vibe coding. If it's of interest, the vibe code per se was mostly written with GitHub Copilot using Claude Opus 4.6. Configuration questions and similar (e.g., "Why aren't location services working on my Ubuntu Linux system running in a Parallels Desktop VM?") were mostly handled with Grok 4.0.

While everything seems to be working fine, I'm far from an expert in all these systems and I'm sure there are numerous uglinesses and infelicities present. Again, please raise an issue if you notice anything amiss (especially security issues).

Supported target platforms include:

* macOS (build on macOS only, alas)
* iOS (likewise)
* Android (build on macOS, Windows, or Linux)
* Windows (build on macOS, Windows, or Linux)
* Linux (build on Linux)
* WWW (plain browser — build on any platform, serve with `python3 webserver.py` (obviously requires having python3 installed) or any other webserver of your choice).
* Need a different target? Open an issue... all suggestions will be considered, within the limits of time and efficiency.

Features:

* Access to device location data, cameras, mics, etc.
* Remote debugging
* POSIX(-ish) file system

What it *doesn't* do:

* Require that you install 50 million dubious npm packages (or a whole freakin' Rust ecosystem, for the love of all that's holy -- tauri, I'm looking in your direction)
* Generate 60 petabyte binaries for a "Hello, world!" program
* Require baroque configuration gymnastics -- there's no need to fool with nasty-ass package.json scripts or even nastier-ass XML files. We won't even go into Gradle 🤮, the only good thing about which is that it's not Maven or Ant (Passiflora does *use* Gradle (technically gradlew) for Android builds, but you don't have to get the stench of it on you).

![Ur Doin' It Worng](doingitwrong.jpg)

Passiflora uses the system's own web browser control rather than bundling an entire browser into the executable, like Electron. Bundling a web browser made sense back in the bad old days of incompatible browsers and highly-restricted web app functionality, but things have improved immensely since then. It's my belief that it's now preferable to work through or around whatever inconsistencies and shortcomings that remain than take the enormous hit of bundling an entire browser. Passiflora does do some native bridging (e.g., geolocation, audio recording, opening external URLs), and it's possible that more native bridging will be added in the future, but the plan is to continue doing everything with web technology that *can* be done with web technology.

### Executable Size

The sample program weighs 1.5 MB when built for macOS, 1.1 MB of which is accounted for by the .icns icon file, leaving around 400 KB for the actual binary executable. 

By comparison, the same program when built for macOS using Electron/Electron Forge weighs **211 MB**. Yikes!


Electron and Electron Forge also install **342** (!) npm packages, which generate scads of deprecation/security warnings (and, yes, I'm following the installation/compilation instructions on the Electron website that are current as of today, March 7, 2026).


## Prerequisites and Building

Detailed installation, build, cross-compilation, and code signing instructions are in the per-platform guides:

* **[Building on macOS](BUILD-macOS.md)** — native macOS builds, plus cross-compiling for iOS, iOS Simulator, Windows, and Android
* **[Building on Windows](BUILD-Windows.md)** — native Windows builds, plus cross-compiling for Android
* **[Building on Linux](BUILD-Linux.md)** — native Linux builds, plus cross-compiling for Windows and Android

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

Obviously you're gonna want to put your own HTML, JavaScript, CSS, images, and such inside the src/www folder. Here are some other customizations you'll probably want to make before building something for release.

### Setting the Program Name

Edit `PROGNAME` in the `Makefile` (macOS/Linux) or `build.bat` (Windows) to your preferred name for the package.

### Config

The file `src/config` controls permissions, orientation, and other app-level settings. Each line has the form `key value` (case-insensitive). Permissions use `true` / `false` values and default to `false` if omitted. For apps you're planning to distribute, you should set everything to `false` except the ones you actually need (good security policy in general, plus app stores frown on unnecessary permissions).

| Setting | Values | Default | Description |
|---------|--------|---------|-------------|
| `uselocation` | `true`, `false` | `false` | Enables GPS / geolocation. On iOS and macOS this links CoreLocation and adds the required `NSLocation*` plist keys. On Android it adds `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` to the manifest and enables the WebView geolocation prompt. |
| `usecamera` | `true`, `false` | `false` | Enables camera access (screenshots, image capture, video recording). On iOS / macOS this links AVFoundation and adds `NSCameraUsageDescription`. On Android it adds the `CAMERA` manifest permission. |
| `usemicrophone` | `true`, `false` | `false` | Enables microphone access (audio recording, video with audio). On iOS / macOS this adds `NSMicrophoneUsageDescription`. On Android it adds `RECORD_AUDIO` to the manifest. |
| `allowremotedebugging` | `true`, `false` | `false` | When `true`, the embedded HTTP server listens on all network interfaces (`0.0.0.0`), allowing remote debugging connections from other devices on the same network. When `false` (default for production), the server binds to `127.0.0.1` (localhost only) and remote debugging is not possible. |
| `orientation` | `portrait`, `landscape`, `both` | `both` | Controls whether the app is locked to portrait or landscape orientation, or rotates freely. On iOS this sets `UISupportedInterfaceOrientations` in the Info.plist. On Android it sets `android:screenOrientation` on the main activity. Desktop platforms ignore this setting. |
| `theme` | theme name | `Default` | The color theme applied on startup. Must match a key in `PassifloraThemes.themeData`. See [MENUS-AND-THEMES.md](MENUS-AND-THEMES.md) for the full list of built-in themes. |
| `body-font-stack` | font stack name | `System UI` | Default font stack for body text. Must match a key in `PassifloraThemes.baseFontStackOptions`. See [MENUS-AND-THEMES.md](MENUS-AND-THEMES.md#font-stacks). |
| `heading-font-stack` | font stack name | `System UI` | Default font stack for headings. Same values as `body-font-stack`. |
| `code-font-stack` | font stack name | `Monospace Code` | Default font stack for code blocks. Same values as `body-font-stack`. |

### Icons

Change `roundicon.png` and `squareicon.png` in `src/icons` to whatever PNG images you like. These should be pretty big — around 1,000 pixels square. More is better! The `squareicon.png` file should be square (duh!), while the `roundicon.png` should be a square image consisting of a round image on a transparent background (I realize that may sound a little confusing... look at the supplied `roundicon.png` if you need clarification).

All of the zillions of other icons for the various different systems are generated from these.

Once you've updated the base icons, run:

`make icons` (macOS and Linux)

or

`.\build icons` (Windows)

to generate a new icon set.

Note that these may need some manual tweaking for legibility, particularly at the smaller sizes, but it's still a substantial time savings over generating them all individually. Icons are *not* regenerated automatically during a normal build (not even after `make clean`). This is so any hand-tuned versions you've created won't be overwritten. If you *do* want to wipe out all existing icons and start over, run `make icons` or `.\build icons` again.

### Menus, Themes, and Font Stacks

Passiflora includes a menu system (native menu bar + sliding menu + panel screens), 122 built-in color themes, and a curated set of font stacks. Full documentation is in **[MENUS-AND-THEMES.md](MENUS-AND-THEMES.md)**.

## PassifloraConfig

Each build generates `src/www/generated/config.js`, which defines a `PassifloraConfig` object containing:

```javascript
var PassifloraConfig = {
  os_name: "iOS",          // or "macOS", "Windows", "Linux", "Android", "WWW"
  theme: "Graustark",      // default theme from src/config
  "body-font-stack": "System UI",     // default body font stack name
  "heading-font-stack": "Antique",    // default heading font stack name
  "code-font-stack": "Monospace Code", // default code font stack name
  menus: [ ... ],          // menu structure from menu.txt (excludes *-prefixed items)
  handleMenu: function(title) { alert("Menu item clicked: " + title); }
};
```

- **`PassifloraConfig.os_name`** — the target platform, useful when your JavaScript needs to do different things on different platforms.
- **`PassifloraConfig.theme`** — the default theme name from `src/config`. Applied on startup; may be overridden by VFS-persisted choice.
- **`PassifloraConfig["body-font-stack"]`**, **`PassifloraConfig["heading-font-stack"]`**, **`PassifloraConfig["code-font-stack"]`** — default font stack names from `src/config`. Must match keys in `PassifloraThemes.baseFontStackOptions`.
- **`PassifloraConfig.menus`** — the menu structure as a nested JSON array, useful for building custom menus. Items prefixed with `*` in `menu.txt` are excluded — they are native-only and never reach JavaScript.
- **`PassifloraConfig.handleMenu`** — called by both the native menu bar and the built-in sliding menu when a (non-native) menu item is selected. Override this in your `app.js` to handle menu actions.

This file is auto-generated on every build and should not be edited by hand.

## File I/O

Passiflora includes POSIX-style file functions, Open/Save As dialogs, and a virtual file system backed by IndexedDB. Full documentation is in **[FILE_IO.md](FILE_IO.md)**.

## Utility Functions

These are methods on `PassifloraIO` (not available as bare globals).

| Function | Description |
|----------|-------------|
| `PassifloraIO.openExternal(url)` | Open a URL in the system's default browser. On Android uses the native bridge; on other platforms issues a request to the embedded server's `openexternal` endpoint. Only `http://` and `https://` URLs are allowed. |
| `PassifloraIO.getCurrentPosition(successCb, errorCb)` | Get the device's current GPS position. On macOS/iOS uses the native CLLocationManager bridge; on other platforms delegates to `navigator.geolocation`. Callbacks follow the standard Geolocation API signature. |
| `PassifloraIO.webDownload(path, mimeType)` | Trigger a browser download for a VFS file. On macOS/iOS uses the native save panel via `passifloraSaveFile`; on other platforms creates a temporary download link. `mimeType` defaults to `"application/octet-stream"` if omitted. |
| `PassifloraIO.patchLinks()` | Scan the DOM for `<a href>` elements with `http://` or `https://` URLs and attach click handlers that route them through `openExternal()` instead of navigating the webview. Called automatically on `DOMContentLoaded`. |
W| `PassifloraIO.hasNativeRecording()` | Returns a Promise resolving to `true` if recording is available on this platform, `false` otherwise. |
| `PassifloraIO.startRecording(hasVideo, hasAudio)` | Start recording. `hasVideo` and `hasAudio` are booleans selecting which tracks to capture. Returns a Promise that resolves when recording has started. |
| `PassifloraIO.stopRecording()` | Stop a recording in progress. Returns a Promise resolving to a `Uint8Array` containing the recorded WebM data (or `null` if no data). |
| `PassifloraIO.diagnoseNativeAudio()` | Run audio diagnostics. Returns a Promise resolving to a diagnostic string. |

## Remote Debugging

Passiflora includes a built-in remote debugging facility that lets you execute JavaScript in a running app from an external browser. This is useful for inspecting app state, testing code snippets, and diagnosing issues on platforms where browser DevTools aren't available (iOS, Android, etc.).

Remote debugging is compile-gated — set `allowremotedebugging` to `true` in `src/config` to enable it. When enabled, a setup overlay appears at app startup where you enter a shared passphrase and copy the debugger URL. Open that URL in a browser on another device to send JavaScript commands to the running app.

For the full protocol details, security notes, and usage tips, see **[DEBUGGING.md](DEBUGGING.md)**.

## About this project

This code was developed through an iterative process involving human-guided prompting of a large language model (LLM), followed by review, editing, refinement, and original contributions by the author. To the extent the work contains copyrightable human-authored elements (including structure, modifications, arrangements, and additions), it is Copyright (c) 2026 by Anthony W. Hursh. The project is distributed under the terms of the MIT License (see LICENSE file for full text). Portions generated directly by AI may not be independently copyrightable under current U.S. law.


