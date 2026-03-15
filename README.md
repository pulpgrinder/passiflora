![Passiflora](logo.png)

# Passiflora

Passiflora is a no-nonsense cross-platform packager that wraps HTML/JavaScript/CSS/etc. in an executable (similar to Electron and its ilk). 

Note that this should be considered **experimental** at this point. Things are still in a "move fast and break stuff" phase.  Please report any issues. In addition, much of this project was vibe coded as an experiment. The basic idea for this has been hanging around my todo list, along with code snippets, for several years. I finally decided to use it as a proof of concept for vibe coding. If it's of interest, the vibe code per se was mostly written with GitHub Copilot using Claude Opus 4.6. Configuration questions and similar (e.g., "Why aren't location services working on my Ubuntu Linux system running in a Parallels Desktop VM?") were mostly handled with Grok 4.0.

While everything seems to be working fine, I'm far from an expert in all these systems and I'm sure there are numerous uglinesses and infelicities present. Again, please raise an issue if you notice anything amiss (especially security issues).

Supported target platforms include:

* macOS (build on macOS only, alas)
* iOS (likewise)
* Android (build on macOS, Windows, or Linux)
* Windows (build on macOS, Windows, or Linux)
* Linux (build on Linux)
* More targets may be added later if they seem useful

Features:

* Access to device location data, cameras, mics, etc.
* POSIX(-ish) file system

What it *doesn't* do:

* Require that you install 50 million dubious npm packages (or a whole freakin' Rust ecosystem, for the love of all that's holy -- tauri, I'm looking in your direction)
* Generate 60 petabyte binaries for a "Hello, world!" program
* Require baroque configuration gymnastics -- there's no need to fool with nasty-ass package.json scripts or even nastier-ass XML files. We won't even go into Gradle 🤮, the only good thing about which is that it's not Maven or Ant (Passiflora does *use* Gradle (technically gradlew) for Android builds, but you don't have to get the stench of it on you).

![Ur Doin' It Worng](doingitwrong.jpg)

Passiflora uses the system's own web browser control rather than bundling an entire browser into the executable, like Electron. Bundling a web browser made sense back in the bad old days of incompatible browsers and highly-restricted web app functionality, but things have improved immensely since then. It's my belief that it's now preferable to work through or around whatever inconsistencies and shortcomings that remain than take the enormous hit of bundling an entire browser. Passiflora does do some native bridging (e.g., the Posix-like file system), and it's possible that more native bridging will be added in the future, but the plan is to continue doing everything with web technology that *can* be done with web technology.

### Executable Size

The sample program weighs 1.5 MB when built for macOS, 1.1 MB of which is accounted for by the .icns icon file, leaving around 400 KB for the actual binary executable. 

By comparison, the same program when built for macOS using Electron/Electron Forge weighs **211 MB**. Yikes!


---

Electron and Electron Forge also install 342 (!) npm packages, which generate scads of deprecation/security warnings (and, yes, I'm following the installation/compilation instructions on the Electron website that are current as of today, March 7, 2026).


## Prerequisites and Building

Detailed installation, build, cross-compilation, and code signing instructions are in the per-platform guides:

* **[Building on macOS](BUILD-macOS.md)** — native macOS builds, plus cross-compiling for iOS, iOS Simulator, Windows, and Android
* **[Building on Windows](BUILD-Windows.md)** — native Windows builds, plus cross-compiling for Android
* **[Building on Linux](BUILD-Linux.md)** — native Linux builds, plus cross-compiling for Windows and Android

### Quick Start

1. Install the prerequisites for your host system (see the guide above).
2. Check out this repo.
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

5. There is no step 5, at least in the sense of building a functioning binary. You'll probably want to customize some of the settings to (e.g.) set your app's name and so on (see below).


### Make/Build Targets Summary

| Target | Description |
|--------|-------------|
| `make` | Build for current platform (macOS or Linux) |
| `make macos` | Build macOS binary and app bundle (macOS only) |
| `make windows` | Cross-compile Windows exe (from macOS or Linux) |
| `make linux` | Build Linux binary (Linux only) |
| `make ios` | Cross-compile iOS binary (macOS only) |
| `make iossim` | Build, install, launch in iOS Simulator (macOS only) |
| `make iosipa` | Build, sign, and package iOS .ipa (macOS only) |
| `make android` | Build Android APK |
| `make icons` | Generate icon sets for all platforms |
| `make clean` | Remove all build artifacts |
| `make sign-macos` | Interactively sign the macOS app bundle |
| `make sign-ios` | Interactively sign the iOS app bundle |
| `make sign-iossim` | Interactively sign the iOS Simulator app bundle |
| `make sign-android` | Sign the Android APK with a local keystore |
| `.\build` or `.\build windows` | Build Windows exe (Windows) |
| `.\build android` | Build Android APK (Windows) |
| `.\build sign-android` | Sign the Android APK (Windows) |
| `.\build icons` | Generate icon sets (Windows) |
| `.\build clean` | Remove all build artifacts (Windows) |



## Making the App Your Own

Obviously you're gonna want to put your own HTML, JavaScript, CSS, images, and such inside the src/www folder. Here are some other customizations you'll probably want to make before building something for release.

### Setting the Program Name

Edit `PROGNAME` in the `Makefile` (macOS/Linux) or `build.bat` (Windows) to your preferred name for the package.

### Permissions

The file `src/permissions` controls which platform capabilities are compiled into the app. Each line has the form `name 0` or `name 1`. Permissions default to off (0) if omitted. By default, all permissions are turned on. For apps you're planning to distribute, you should turn everything off except the ones you actually need (app stores frown on unnecessary permissions).

| Permission | Affects | Description |
|------------|---------|-------------|
| `location` | All platforms | Enables GPS / geolocation. On iOS and macOS this links CoreLocation and adds the required `NSLocation*` plist keys. On Android it adds `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` to the manifest and enables the WebView geolocation prompt. |
| `camera` | All platforms | Enables camera access (screenshots, image capture, video recording). On iOS / macOS this links AVFoundation and adds `NSCameraUsageDescription`. On Android it adds the `CAMERA` manifest permission. |
| `microphone` | All platforms | Enables microphone access (audio recording, video with audio). On iOS / macOS this adds `NSMicrophoneUsageDescription`. On Android it adds `RECORD_AUDIO` to the manifest. |
| `unrestrictedfilesystemaccess` | All platforms | Controls filesystem scope for the POSIX file I/O bridge. When **on** (`1`), JavaScript can read and write anywhere the OS permits. When **off** (`0`, recommended for production), all file operations (fopen, remove, rename, startRecording) are restricted to an app-specific documents folder — `~/Documents/PROGNAME` on macOS/Linux, the system Documents folder on Windows, the iOS documents directory, or `$HOME/PROGNAME` on Android. The `getHomeFolder()` bridge always returns this folder. On Android, this setting also controls whether the `MANAGE_EXTERNAL_STORAGE` manifest permission is included and whether the all-files-access prompt appears. |
| `remotedebugging` | All platforms | When on, the embedded HTTP server listens on all network interfaces (`0.0.0.0`), allowing remote debugging connections from other devices on the same network. When off (default for production), the server binds to `127.0.0.1` (localhost only) and remote debugging is not possible. |


### Icons

Change `roundicon.png` and `squareicon.png` in `src/icons` to whatever images you like. These should be pretty big — around 1,000 pixels square. More is better! The `squareicon.png` file should be square (duh!), while the `roundicon.png` should be a square image consisting of a round image on a transparent background (I realize that may sound a little confusing... look at the supplied `roundicon.png` if you need clarification).

All of the zillions of other icons for the various different systems are generated from these.

Once you've updated the base icons, run:

`make icons` (macOS and Linux)

or

`.\build icons` (Windows)

to generate a new icon set.

Note that these may need some manual tweaking for legibility, particularly at the smaller sizes, but it's still a substantial time savings over generating them all individually. Icons are *not* regenerated automatically during a normal build (not even after `make clean`). This is so any hand-tuned versions you've created won't be overwritten. If you *do* want to wipe out all existing icons and start over, run `make icons` or `.\build icons` again.

### Menus

Underneath `src`, each platform has a folder which contains a `menu.txt` file. These are used to generate menus on two levels:

1. **Native menu bar** — on platforms that have one (macOS, Windows, Linux), the entries produce a real OS menu bar.
2. **JavaScript sliding menu** — on all platforms, non-native entries are available in `PassifloraConfig.menus` and in the (optional) built-in sliding menu UI (see [Sliding Menu](#sliding-menu) below).

#### menu.txt format

Menu hierarchy is expressed with simple four-space indentation. Submenus can be nested to any depth. Blank lines and separators (`-`) are supported.

```
{{progname}}
    *About
    -
    *Quit
File
    Open
Misc
    More stuff
    Still more stuff
        Stuff at an even lower level
```

`{{progname}}` is replaced with the program name at build time.

#### Native vs. JavaScript routing (`*` prefix)

Each leaf menu item is either **native** or **JavaScript**, controlled by an optional `*` prefix:

| Prefix | Behavior |
|--------|----------|
| `*Quit` | Handled by the **native** platform. The `*` is stripped from the display title. If the platform recognises the item (e.g. "Quit" on macOS maps to `⌘Q`), the native action runs. If not, a dialog says "No native handler for this item on this platform." The item is **never** passed to JavaScript and does **not** appear in `PassifloraConfig.menus` or the sliding menu. |
| `Quit` | Always passed to **JavaScript** via `PassifloraConfig.handleMenu("Quit")`. The native platform does not intercept it, and it **does** appear in `PassifloraConfig.menus` and the sliding menu. |

Matching is **exact** — `*Quit` matches the native "Quit" handler, but `*Quite` does not (it will show the "no native handler" dialog).

Top-level menu names (e.g. `File`, `{{progname}}`) and separators (`-`) are not affected by the `*` prefix.

#### Recognised native items by platform

**macOS** — the following items have built-in native handlers when prefixed with `*`:

| Item | Action | Shortcut |
|------|--------|----------|
| About | Standard About panel | — |
| Hide | Hide application | ⌘H |
| Hide Others | Hide other applications | ⌥⌘H |
| Show All | Unhide all applications | — |
| Quit | Terminate | ⌘Q |
| Undo | Undo | ⌘Z |
| Redo | Redo | ⇧⌘Z |
| Cut | Cut | ⌘X |
| Copy | Copy | ⌘C |
| Paste | Paste | ⌘V |
| Select All | Select all | ⌘A |
| Close | Close window | ⌘W |
| Minimize | Minimize window | ⌘M |
| Zoom | Zoom window | — |
| Bring All to Front | Arrange in front | — |

**Windows** — `*Quit` and `*Exit` close the window. All other `*`-prefixed items show a "no native handler" dialog (more may be added later)

**Linux** — `*Quit` and `*Exit` quit the application (`gtk_main_quit`). All other `*`-prefixed items show a "no native handler" dialog (more may be added later).

**iOS / Android** — these platforms have no native menu bar. A `*` prefix still causes items to be excluded from `PassifloraConfig.menus` and the sliding menu.

#### JavaScript menu handler

For items without the `*` prefix, choosing them from the native menu bar calls `PassifloraConfig.handleMenu(title)` in your JavaScript. The default handler just pops an alert. Override it in your `app.js`:

```javascript
PassifloraConfig.handleMenu = function(title) {
    // your code here
};
```

### Sliding Menu (optional)

Passiflora includes a built-in basic sliding menu for platforms that don't have a native menu bar (iOS, Android), or for web-style navigation on any platform. **This is entirely optional** — you can use it as-is, customise it, or remove it and replace it with your own menu package.

The menu is built automatically from `PassifloraConfig.menus` at page load. It slides in from the right edge of the screen, supports arbitrarily nested submenus, and calls `PassifloraConfig.handleMenu(title)` when a leaf item is tapped.

**Triggering the menu:** The hamburger button (≡) is hidden by default to keep the UI clean. To reveal it, **long-press** (hold for 500 ms) on any non-interactive area of the page. The button appears in the top-right corner and stays visible for 3 seconds before fading out again.

**Closing the menu:**

You can close the sliding menu without choosing an item in three ways:

* Tap/click outside the menu panels
* Press **Escape**
* Navigate back through all levels
 

**Files:**

* `src/www/passiflora/buildmenu.js` — menu logic (the `PassifloraMenu` IIFE)
* `src/www/passiflora/menu.css` — menu styling. You can customize colours, sizes, transitions, etc. by editing this file.

Items prefixed with `*` in `menu.txt` are excluded from the sliding menu entirely — they only exist in the native menu bar (if there is one).

#### Removing the sliding menu

If you'd rather use your own menu UI (or no menu UI at all), remove these three things from `src/www/index.html`:

1. The CSS link in `<head>`:
   ```html
   <link rel="stylesheet" href="passiflora/menu.css">
   ```
2. The hamburger element in `<body>`:
   ```html
   <div class="hamburgermenu">≡</div>
   ```
3. The script tag:
   ```html
   <script src="passiflora/buildmenu.js"></script>
   ```

You can also delete `src/www/passiflora/buildmenu.js` and `src/www/passiflora/menu.css` if you like, but leaving them in place is harmless — they won't do anything without the above references.

The `PassifloraConfig.menus` array and `PassifloraConfig.handleMenu` callback are still available regardless. You can use them to build your own menu and handle selections however you wish, or ignore them entirely.

## PassifloraConfig

Each build generates `src/www/generated/config.js`, which defines a `PassifloraConfig` object containing:

```javascript
var PassifloraConfig = {
  os_name: "iOS",     // or "macOS", "Windows", "Linux", "Android"
  menus: [ ... ],     // menu structure from menu.txt (excludes *-prefixed items)
  handleMenu: function(title) { alert("Menu item clicked: " + title); }
};
```

- **`PassifloraConfig.os_name`** — the target platform, useful when your JavaScript needs to do different things on different platforms.
- **`PassifloraConfig.menus`** — the menu structure as a nested JSON array, useful for building custom menus. Items prefixed with `*` in `menu.txt` are excluded — they are native-only and never reach JavaScript.
- **`PassifloraConfig.handleMenu`** — called by both the native menu bar and the built-in sliding menu when a (non-native) menu item is selected. Override this in your `app.js` to handle menu actions.

This file is auto-generated on every build and should not be edited by hand.

## POSIX Functions

Passiflora bridges a subset of C's stdio file I/O functions so that your JavaScript can read and write files on the host filesystem. All functions are **async** and return Promises. They are available both as global functions and as methods on `PassifloraIO`. An effort has been made to keep these as similar to the standard POSIX functions as possible.

### Quick Example

```javascript
// Write a file
let f = await fopen("(some file path)", "w");
await fputs(f, "Hello from Passiflora!\n");
await fclose(f);

// Read it back
f = await fopen("(some file path)", "r");
let line = await fgets(f);
await fclose(f);
alert(line);  // "Hello from Passiflora!\n"
```

Obviously `(some file path)` has to be somewhere your app is allowed to write files. Consult the permissions section above and the code in the sample index.html for some tips.

### File Open / Close

| Function | Description |
|----------|-------------|
| `fopen(path, mode)` | Open a file. Returns a numeric handle. `mode` defaults to `"r"` if omitted. Modes are the standard C modes: `"r"`, `"w"`, `"a"`, `"r+"`, `"w+"`, `"a+"` (append `"b"` for binary, e.g. `"rb"`). |
| `fclose(handle)` | Close a previously opened file handle. |

### Text I/O

| Function | Description |
|----------|-------------|
| `fgets(handle)` | Read one line (up to 64 KB, including the newline). Returns the line as a string, or `null` at EOF. |
| `fputs(handle, str)` | Write a string to the file. |

### Binary I/O

| Function | Description |
|----------|-------------|
| `fread(handle, size)` | Read up to `size` bytes. Returns a `Uint8Array`, or `null` at EOF. |
| `fwrite(handle, data)` | Write `data` (a string or `Uint8Array`) to the file. Returns the number of bytes written. |

### Seeking / Position

| Function | Description |
|----------|-------------|
| `fseek(handle, offset, whence)` | Seek to a position. `whence`: `SEEK_SET` (0) = from start, `SEEK_CUR` (1) = from current, `SEEK_END` (2) = from end. |
| `ftell(handle)` | Return the current byte offset in the file. |
| `frewind(handle)` | Rewind to the beginning (equivalent to `fseek(handle, 0, SEEK_SET)`). |
| `feof(handle)` | Return `true` if the file position is at end-of-file. |
| `fflush(handle)` | Flush buffered writes to disk. |

### Filesystem Operations

| Function | Description |
|----------|-------------|
| `fremove(path)` | Delete a file. |
| `frename(oldpath, newpath)` | Rename or move a file. |

### Using via `PassifloraIO`

All functions are also available as methods on the `PassifloraIO` object. The method names match the C originals (without the `f` prefix on `remove`/`rename`):

```javascript
let f = await PassifloraIO.fopen("data.bin", "rb");
let bytes = await PassifloraIO.fread(f, 1024);
await PassifloraIO.fclose(f);

await PassifloraIO.remove("old.txt");
await PassifloraIO.rename("a.txt", "b.txt");
```

### Constants

The following constants are available globally and on `PassifloraIO`:

| Constant | Value | Meaning |
|----------|-------|---------|
| `SEEK_SET` | 0 | Seek from start of file |
| `SEEK_CUR` | 1 | Seek from current position |
| `SEEK_END` | 2 | Seek from end of file |

### Error Handling

All functions throw an `Error` on failure. The error message comes from the C runtime (e.g. `"No such file or directory"`). Use try/catch:

```javascript
try {
    let f = await fopen("nonexistent.txt", "r");
} catch (e) {
    console.error("Open failed:", e.message);
}
```

### Working Directory

File paths are relative to the process's current working directory, which varies by platform:

* **macOS / Linux / Windows** — wherever you launched the app from.
* **Android** — the app's private data directory.
* **iOS** — the app's sandbox container.

Use absolute paths if you need predictable locations. Again, see the code in the sample index.html to get a handle on where you're allowed to write files.

### Notes

* Calls go through the native WebView bridge (not HTTP), so they are only accessible to code running inside the app's own WebView.
* On Android, calls are synchronous via `@JavascriptInterface`. On all other platforms they use async message handlers with callbacks.
* Up to 63 files may be open simultaneously.
* `fread` reads a maximum of 16 MB per call. For larger files, read in a loop.
* `fwrite` data is base64-encoded in transit; very large writes may be slow.
* Path traversal (`..`) is rejected for `fopen`, `fremove`, and `frename`.

## Remote Debugging

Passiflora includes a built-in remote debugging facility that lets you execute JavaScript in a running app from an external browser. This is useful for inspecting app state, testing code snippets, and diagnosing issues on platforms where browser DevTools aren't available (iOS, Android, etc.).

### Enabling Debug Mode

Call `PassifloraIO.debug(true)` from your app's JavaScript, or click the "Toggle Debugging" button in the sample app. You'll be prompted to enter a passphrase:

```javascript
PassifloraIO.debug(true);
// A prompt dialog asks for a passphrase
```

A yellow debug banner appears at the top of the app window showing the port and passphrase as JSON:

```
{"port":60810,"key":"my secret passphrase"}
```

Note the port number — you'll need it along with the device's IP address to connect from the debugger.

To disable debug mode:

```javascript
PassifloraIO.debug(false);
```

### Using the Debugger

Open `debugger.html` (in the project root) in any web browser. It has four fields:

1. **Host** — the IP address or hostname of the device running the app (defaults to `127.0.0.1` for local debugging)
2. **Port** — the port number shown in the app's debug banner
3. **Passphrase** — the passphrase you entered when enabling debug mode
4. **JavaScript** — the code you want to execute

Click **Execute**. The debugger signs the code with HMAC-SHA256 using the passphrase, sends it to the app, and displays the result.

For remote debugging (e.g. a mobile device on the same network), enter the device's local IP address in the Host field.

### How It Works

1. The external debugger computes an HMAC-SHA256 signature of the JavaScript text using the shared passphrase, then POSTs `{"javascript": "...", "signature": "..."}` to `http://<host>:<port>/__passiflora/debug`.
2. The app's embedded HTTP server relays the payload to the webview via `passiflora_eval_js()`.
3. Inside the webview, `PassifloraIO._debugExec()` validates the HMAC-SHA256 signature using the Web Crypto API. If the signature doesn't match, execution is refused and an error is sent back to the debugger.
4. If valid, the code is executed via inline `<script>` injection (which works under the app's Content Security Policy without requiring `unsafe-eval`).
5. `console.log()`, `console.error()`, and `console.warn()` output is captured during execution and POSTed back to `/__passiflora/debug_result`.
6. The debugger polls `/__passiflora/debug_result` and displays the captured output.

### Seeing Output

Since code runs via `<script>` injection rather than `eval()`, bare expression values aren't returned. Use `console.log()` to see values:

```javascript
// This won't show a result:
document.title

// This will:
console.log(document.title)
```

`alert()` and other side effects work normally but don't produce captured output.

### Security Notes

- By default, the embedded server listens only on `127.0.0.1` (localhost). Remote debugging connections are blocked unless `remotedebugging` is set to `1` in `src/permissions`, which makes the server listen on all network interfaces (`0.0.0.0`).
- Every command must be signed with the correct HMAC-SHA256 passphrase. Without it, commands are rejected and an error is returned to the debugger.
- Debug mode must be explicitly enabled by the user, who chooses the passphrase. It is not on by default.
- Use a strong passphrase, especially when debugging over a network.
- For production releases, set `remotedebugging 0` in `src/permissions` and remove the "Toggle Debugging" button and any `PassifloraIO.debug(true)` calls.

### Debug Banner

When debug mode is on, a yellow banner appears at the top of the app showing diagnostic messages: connection info, signature validation status, and execution results. The banner scrolls if it grows beyond 30% of the viewport height, and pushes page content down so nothing is hidden.

## About this project

This code was developed through an iterative process involving human-guided prompting of a large language model (LLM), followed by review, editing, refinement, and original contributions by the author. To the extent the work contains copyrightable human-authored elements (including structure, modifications, arrangements, and additions), it is Copyright (c) 2026 by Anthony W. Hursh. The project is distributed under the terms of the MIT License (see LICENSE file for full text). Portions generated directly by AI may not be independently copyrightable under current U.S. law.


