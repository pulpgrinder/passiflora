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
* WWW (plain browser — build on any platform, serve with `python3 webserver.py`)
* More targets may be added later if they seem useful

Features:

* Access to device location data, cameras, mics, etc.
* Remote debugging
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
| `make www` | Build plain-browser version into `bin/WWW/` (no native compile) |
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
| `unrestrictedfilesystemaccess` | All platforms | Controls filesystem scope for the POSIX file I/O bridge. When **on** (`1`), JavaScript can read and write anywhere the OS permits. When **off** (`0`, recommended for production), all file operations (fopen, remove, rename, startRecording) are restricted to an app-specific documents folder. The `getHomeFolder()` bridge always returns this folder. On Android, this setting also controls whether the `MANAGE_EXTERNAL_STORAGE` manifest permission is included and whether the all-files-access prompt appears. Note that on Android this folder is private storage for the app. I'm still looking for a good solution to make a publicly-readable files on Android without turning on unrestrictedfilesystemaccess.
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

## File Open and Save As Menus

Passiflora provides two built-in sliding-panel file dialogs that work on all platforms (including WWW): **`menuopen`** for opening files and **`menusavas`** for Save As. These are methods on the `PassifloraIO` object.

### `menuopen(extensions, defaultFolder)`

Opens a sliding file-browser panel that lets the user navigate the filesystem and pick a file.

| Parameter | Type | Description |
|-----------|------|-------------|
| `extensions` | `string[]` | File extensions to filter by (e.g. `['.txt', '.md']`). Pass `[]` or `null` for all files. The user can also switch to "All files" in the dropdown. |
| `defaultFolder` | `string` | Starting directory. If empty/null, defaults to the home folder. |

Returns a Promise that resolves to the chosen file's full path, or `null` if the user cancelled.

```javascript
var path = await PassifloraIO.menuopen(['.txt', '.md'], '');
if (path) {
    var fh = await fopen(path, 'r');
    var contents = await fgets(fh);
    await fclose(fh);
}
```

**UI features:**

- Directories are shown with a 📁 icon and can be navigated into (slides forward) or backed out of (slides back).
- Files matching the extension filter are selectable; non-matching files are dimmed.
- An extension-filter dropdown at the bottom lets the user switch between the specified extensions and "All files".
- Long paths in the back-navigation header are truncated to the last 20 characters with a `…` prefix.
- Pressing Escape or tapping outside the panel cancels the dialog.

### `menusavas(extensions, defaultName)`

Opens a sliding Save As panel that lets the user navigate to a directory, type a filename, and save.

| Parameter | Type | Description |
|-----------|------|-------------|
| `extensions` | `string[]` | Allowed file extensions (e.g. `['.txt']`). Used for the filter dropdown and for extension-mismatch warnings. |
| `defaultName` | `string` | Pre-filled filename (e.g. `'untitled.txt'`). |

Returns a Promise that resolves to the chosen file's full path, or `null` if cancelled.

```javascript
var path = await PassifloraIO.menusavas(['.txt'], 'document.txt');
if (path) {
    var fh = await fopen(path, 'w');
    await fputs(fh, 'Hello, world!\n');
    await fclose(fh);
}
```

**UI features:**

- A text field and **Save** button appear at the top of the panel, pre-filled with `defaultName`.
- The directory listing works the same as `menuopen` (navigate folders, extension filter).
- Clicking an existing file fills the filename field with that file's name.
- **Overwrite warning:** If a file with the entered name already exists in the current directory, a confirmation dialog asks whether to overwrite it.
- **Extension mismatch warning:** If the entered filename doesn't match any of the specified extensions, a confirmation dialog warns the user. Both warnings can chain (extension mismatch first, then overwrite).

### Styling

Both dialogs are styled via `src/www/passiflora/menu.css` using the `passiflora_fo_*` CSS class prefix. The confirm dialogs use `passiflora_fo_confirm_*` classes. The dialogs respect iOS safe-area insets (`env(safe-area-inset-top)`).

## WWW Target — In-Memory Virtual File System

When built for the WWW target (`make www`), Passiflora runs as a plain web page served by any HTTP server — there is no native executable and no embedded HTTP server. Since a browser cannot access the host filesystem directly, the WWW build replaces the native POSIX bridge with an **in-memory virtual file system (VFS)** that provides the same API surface.

The polyfill activates automatically when `PassifloraConfig.os_name === "WWW"`. All `PassifloraIO` methods are overridden transparently — application code does not need any changes to work on the WWW target.

### How the VFS Works

**Storage model:** Files are stored in a plain JavaScript object (`_vfs`) that maps path strings to `Uint8Array` values. For example, after writing a file at `/hello.txt`, `_vfs["/hello.txt"]` holds its byte contents.

**File handles:** When you call `fopen()`, the polyfill creates a handle object that tracks the file path, open mode, and current read/write position — the same information a C `FILE*` would hold. All subsequent I/O calls (`fread`, `fwrite`, `fgets`, `fputs`, `fseek`, `ftell`, `feof`) operate on this handle's position within the `Uint8Array`.

**Write operations** (`fwrite`, `fputs`) grow the `Uint8Array` as needed by allocating a larger buffer, copying existing data, and appending the new bytes. The position pointer advances accordingly.

**Read operations** (`fread`, `fgets`) slice from the current position and advance the pointer. `fgets` scans for a newline character (byte 10) to return one line at a time, just like C's `fgets`.

**Directory listing** (`listDirectory`) synthesizes a directory listing by scanning the keys of `_vfs` for paths that fall under the requested directory prefix. It deduplicates entries and infers whether each entry is a file or subdirectory based on remaining path separators.

**Home folder:** `getHomeFolder()` returns `"/"` (the VFS root). `getUsername()` returns `"web_user"`.

### Saving Files to Disk

Since browser JavaScript runs in a sandbox, the VFS needs a way to get data *out* to the user's real filesystem. This is handled at `fclose()` time via two mechanisms:

**File System Access API (Chrome / Edge):** When `menusavas` is called, the polyfill invokes `showSaveFilePicker()`, which shows the browser's native save dialog. The resulting `FileSystemFileHandle` is stored alongside the VFS path. When `fclose()` is later called on that file, the polyfill writes the VFS data to the real file via `FileSystemFileHandle.createWritable()`.

**Download fallback (Safari / Firefox):** These browsers don't support `showSaveFilePicker()`. Instead, `menusavas` records the VFS path for download. When `fclose()` is called, the polyfill creates a `Blob` from the VFS data, generates a temporary object URL, and triggers a browser download via a programmatically-clicked `<a download>` element. The user sees the browser's standard download bar or save sheet.

### Opening Files from Disk

On the WWW target, `menuopen` uses an HTML `<input type="file">` element instead of the sliding file-browser panel (since the VFS has no pre-existing directory tree to browse). The browser shows its native file-open dialog. When the user selects a file, its contents are read via `FileReader.readAsArrayBuffer()` and stored in the VFS at `/<filename>`. The VFS path is returned to the caller, and subsequent `fopen`/`fread`/`fgets` calls read from the VFS copy.

### Limitations

- **No persistence:** The VFS lives in memory. All files are lost when the page is refreshed or closed. Files opened from disk are *copies* in the VFS; changes don't write back to the original unless the save mechanism is used.
- **No real directories:** The VFS is a flat key-value store. Directories are inferred from path separators, but you cannot create empty directories.
- **No native recording:** `startRecording` / `stopRecording` are not available on the WWW target. The standard `MediaRecorder` API can still be used directly via JavaScript.
- **Single-tab scope:** Each browser tab has its own independent VFS instance.

### Building and Running the WWW Target

```bash
make www                   # copies src/www/ → bin/WWW/ with WWW config
python3 webserver.py       # serves bin/WWW/ on http://localhost:8000
```

The `webserver.py` script is a minimal Python HTTP server that serves `bin/WWW/` on port 8000 (pass a different port as a command-line argument if needed).

## Remote Debugging

Passiflora includes a built-in remote debugging facility that lets you execute JavaScript in a running app from an external browser. This is useful for inspecting app state, testing code snippets, and diagnosing issues on platforms where browser DevTools aren't available (iOS, Android, etc.).

Remote debugging is compile-gated. It is only available when `remotedebugging` is set to `1` in `src/permissions`.

### Enabling Debug Mode

When the `remotedebugging` permission is enabled, debug mode activates automatically at app startup. A full-screen overlay appears with:

- A red **⚠️ Remote Debugging Enabled** warning banner and a reminder not to ship apps with remote debugging turned on.
- A read-only **Debugger URL** field (e.g. `http://192.168.1.42:60810/debug`) with a copy button. Open this URL in a web browser on another machine to use the debugger.Do this before entering your passphrase and clicking OK, as the dialog will disappear after that.
- A **Passphrase** input (masked) where you enter a shared secret used to authenticate debug commands.

After entering a passphrase and clicking **OK**, the overlay closes and the app is ready to accept debug commands.


### How It Works

1. The external debugger computes an HMAC-SHA256 signature of `nonce + ':' + javascript` using the shared passphrase, then POSTs `{"javascript": "...", "signature": "...", "nonce": <number>}` to `http://<host>:<port>/__passiflora/debug`.
2. The app's embedded HTTP server relays the payload to the webview via `passiflora_eval_js()`.
3. Inside the webview, `PassifloraIO._debugExec()` validates the HMAC-SHA256 signature using a pure-JavaScript implementation. If the signature doesn't match, execution is refused and an error is sent back to the debugger. If the nonce is not strictly greater than the previous nonce, the request is rejected as a replay.
4. If valid, the code is executed via indirect `eval()` in global scope.
5. Return values (if not `undefined`) are automatically captured. `console.log()`, `console.error()`, and `console.warn()` output is also captured during execution and POSTed back to `/__passiflora/debug_result`.
6. The debugger polls `/__passiflora/debug_result` and displays the captured output. If no result is ready, the server returns HTTP 204. If a result is still pending from a previous command, the server returns HTTP 429.

### Seeing Output

`console.log()` output and non-`undefined` return values are both captured:

```javascript
// Both of these produce output:
document.title
console.log(document.title)
```

`console.error()` and `console.warn()` output is captured with `ERROR:` or `WARN:` prefixes. `alert()` and other side effects work normally but don't produce captured output.

### Security Notes

- By default, the embedded server listens only on `127.0.0.1` (localhost). Remote debugging connections are blocked unless `remotedebugging` is set to `1` in `src/permissions`, which makes the server listen on all network interfaces (`0.0.0.0`).
- Every command must be signed with HMAC-SHA256 using the shared passphrase and an incrementing nonce. Commands with invalid signatures or replayed nonces are rejected.
- The passphrase input in the app overlay is masked (`type="password"`).
- Debug mode is compile-gated: it is completely absent from the binary unless `remotedebugging 1` is set in `src/permissions`.
- Use a strong passphrase, especially when debugging over a network.
- For production releases, set `remotedebugging 0` in `src/permissions`.

## About this project

This code was developed through an iterative process involving human-guided prompting of a large language model (LLM), followed by review, editing, refinement, and original contributions by the author. To the extent the work contains copyrightable human-authored elements (including structure, modifications, arrangements, and additions), it is Copyright (c) 2026 by Anthony W. Hursh. The project is distributed under the terms of the MIT License (see LICENSE file for full text). Portions generated directly by AI may not be independently copyrightable under current U.S. law.


