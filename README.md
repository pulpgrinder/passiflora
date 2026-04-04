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


### Make/Build Targets Summary

| Target | Description |
|--------|-------------|
| `make` | Build for current platform (macOS or Linux) |
| `make macos` | Build macOS binary and app bundle (macOS only) |
| `make windows` | Cross-compile Windows exe (from macOS or Linux) |
| `make linux` | Build Linux binary (Linux only) |
| `make sim-ios` | Build, install, launch in iOS Simulator (macOS only) |
| `make sign-ios` | Build, sign, and package iOS .ipa (macOS only) |
| `make android` | Build Android APK |
| `make icons` | Generate icon sets for all platforms |
| `make clean` | Remove all build artifacts |
| `make www` | Build plain-browser version into `bin/WWW/` -- useful for debugging using browser tools |
| `make sign-macos` | Interactively sign the macOS app bundle |
| `make sign-android` | Sign the Android APK with a local keystore (macOS and Linux)|
| `.\build` or `.\build windows` | Build Windows exe (Windows) |
| `.\build android` | Build Android APK (Windows) |
| `.\build sign-android` | Sign the Android APK (Windows) |
| `.\build www` | Build plain-browser version into `bin\WWW\` (Windows) -- useful for debugging using browser tools |
| `.\build icons` | Generate icon sets (Windows) |
| `.\build clean` | Remove all build artifacts (Windows) |



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

## POSIX Functions

Passiflora provides a subset of C's stdio file I/O functions that operate on the in-memory **virtual file system (VFS)** backed by **IndexedDB** for persistence. All functions are **async** and return Promises. They are available both as global functions and as methods on `PassifloraIO`. An effort has been made to keep these as similar to the standard POSIX functions as possible.

### Quick Example

```javascript
// Write a file
let f = await fopen("/hello.txt", "w");
await fputs(f, "Hello from Passiflora!\n");
await fclose(f);

// Read it back
f = await fopen("/hello.txt", "r");
let line = await fgets(f);
await fclose(f);
alert(line);  // "Hello from Passiflora!\n"
```

### File Open / Close

| Function | Description |
|----------|-------------|
| `fopen(path, mode)` | Open a file. Returns a string handle (e.g. `"vfsfh_1"`). `mode` defaults to `"r"` if omitted. Modes are the standard C modes: `"r"`, `"w"`, `"a"`, `"r+"`, `"w+"`, `"a+"` (append `"b"` for binary, e.g. `"rb"`). Throws if the file does not exist when opening for read. |
| `fclose(handle)` | Close a previously opened file handle and persist its contents to IndexedDB. Returns `0`. |

### Text I/O

| Function | Description |
|----------|-------------|
| `fgets(handle)` | Read one line (up to the next `\n`). Returns the line as a string (including the newline), or `null` at EOF. |
| `fputs(handle, str)` | Write a string to the file. Returns the number of bytes written. |

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
| `rewind(handle)` | Rewind to the beginning (equivalent to `fseek(handle, 0, SEEK_SET)`). |
| `feof(handle)` | Return `1` if the file position is at end-of-file, `0` otherwise. |
| `fflush(handle)` | No-op in the VFS (data is persisted to IndexedDB on `fclose`). Returns `0`. |

### Filesystem Operations

| Function | Description |
|----------|-------------|
| `remove(path)` | Delete a file from the VFS and IndexedDB. |
| `rename(oldpath, newpath)` | Rename or move a file or directory. When renaming a directory, all files and subdirectories under it are moved to the new path. |

### Directory Operations

| Function | Description |
|----------|-------------|
| `mkdir(path)` | Create a directory. Intermediate directories must already exist. Throws if the directory (or a file at that path) already exists. |
| `rmdir(path)` | Remove an empty directory. Throws if the directory contains files or subdirectories, or does not exist. |
| `chdir(path)` | Change the current working directory. The target must be an existing directory (either explicitly created with `mkdir` or implied by files stored under it). |
| `getcwd()` | Return the current working directory (initially `"/"`). |
| `PassifloraIO.listDirectory(path)` | List the contents of a directory. Returns a Promise resolving to an array of `{name, isDir}` objects. Both files stored under the path and explicitly created empty directories are included. |

Paths passed to `mkdir`, `rmdir`, `chdir`, and `rename` may be absolute or relative to the current working directory. `.` and `..` components are resolved automatically.

### Using via `PassifloraIO`

All functions are also available as methods on the `PassifloraIO` object:

```javascript
let f = await PassifloraIO.fopen("/data.bin", "rb");
let bytes = await PassifloraIO.fread(f, 1024);
await PassifloraIO.fclose(f);

await PassifloraIO.remove("/old.txt");
await PassifloraIO.rename("/a.txt", "/b.txt");
```

### Constants

The following constants are available globally and on `PassifloraIO`:

| Constant | Value | Meaning |
|----------|-------|---------|
| `SEEK_SET` | 0 | Seek from start of file |
| `SEEK_CUR` | 1 | Seek from current position |
| `SEEK_END` | 2 | Seek from end of file |

### Error Handling

All functions throw an `Error` on failure. Use try/catch:

```javascript
try {
    let f = await fopen("/nonexistent.txt", "r");
} catch (e) {
    console.error("Open failed:", e.message);
}
```

### Working Directory

The current working directory starts at `"/"` on all platforms. Use `chdir()` and `getcwd()` to navigate. Paths passed to `fopen`, `fread`, etc. should be absolute (starting with `/`). The directory functions (`mkdir`, `rmdir`, `chdir`, `rename`) resolve relative paths against the current working directory.

### Notes

* All file I/O operates on the in-memory VFS — there is no native bridge involvement for file operations. Data is persisted to IndexedDB when files are closed.
* There is no hard limit on the number of simultaneously open files.
* The `beforeunload` handler automatically flushes and closes all open file handles.

## File Open and Save As Menus

Passiflora provides two built-in sliding-panel file dialogs: **`menuOpen`** for opening files and **`menuSaveAs`** for Save As. These are methods on the `PassifloraIO` object. The dialogs appear as sliding panels that let the user browse the virtual file system (VFS). To bring files in from the real filesystem or save files out, use **`importFile`** and **`exportFile`** (see [Importing and Exporting Files](#importing-and-exporting-files) below).

### `menuOpen(extensions, defaultFolder)`

Opens a sliding file-browser panel that lets the user navigate the VFS and pick a file.

| Parameter | Type | Description |
|-----------|------|-------------|
| `extensions` | `string[]` | File extensions to filter by (e.g. `['.txt', '.md']`). Pass `[]` or `null` for all files. The user can also switch to "All files" in the dropdown. |
| `defaultFolder` | `string` | Starting directory. If empty/null, defaults to the home folder. |

Returns a Promise that resolves to the chosen file's full path, or `null` if the user cancelled.

```javascript
var path = await PassifloraIO.menuOpen(['.txt', '.md'], '');
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
- A **Create Folder** button (📁+) next to the filter dropdown creates a new directory named "Untitled", "Untitled 2", etc. in the current directory.
- **Long-press rename:** Long-pressing (500 ms) on any file or directory name makes it editable inline. The name becomes a plain-text contenteditable field. Edit the name and tap/click away (or press Enter) to rename; press Escape to cancel. HTML markup, newlines, and extra whitespace are stripped automatically.
- Long paths in the back-navigation header are truncated to the last 20 characters with a `…` prefix.
- Pressing Escape or tapping outside the panel cancels the dialog.

### `menuSaveAs(extensions, defaultName)`

Opens a sliding Save As panel that lets the user navigate to a directory, type a filename, and save.

| Parameter | Type | Description |
|-----------|------|-------------|
| `extensions` | `string[]` | Allowed file extensions (e.g. `['.txt']`). Used for the filter dropdown and for extension-mismatch warnings. |
| `defaultName` | `string` | Pre-filled filename (e.g. `'untitled.txt'`). |

Returns a Promise that resolves to the chosen file's full path, or `null` if cancelled.

```javascript
var path = await PassifloraIO.menuSaveAs(['.txt'], 'document.txt');
if (path) {
    var fh = await fopen(path, 'w');
    await fputs(fh, 'Hello, world!\n');
    await fclose(fh);
}
```

**UI features:**

- A text field and **Save** button appear at the top of the panel, pre-filled with `defaultName`.
- The directory listing works the same as `menuOpen` (navigate folders, extension filter).
- Clicking an existing file fills the filename field with that file's name.
- **Overwrite warning:** If a file with the entered name already exists in the current directory, a confirmation dialog asks whether to overwrite it.
- **Extension mismatch warning:** If the entered filename doesn't match any of the specified extensions, a confirmation dialog warns the user. Both warnings can chain (extension mismatch first, then overwrite).
- A **Create Folder** button and **long-press rename** are available, working the same as in `menuOpen` (see above).

### Styling

Both dialogs are styled via `src/www/passiflora/theme.css` using the `passiflora_fo_*` CSS class prefix. The confirm dialogs use `passiflora_fo_confirm_*` classes. The dialogs respect iOS safe-area insets (`env(safe-area-inset-top)`).

## Virtual File System + IndexedDB

On **all platforms** (macOS, iOS, Linux, Windows, Android, and WWW), Passiflora stores files in a **virtual file system (VFS)** backed by **IndexedDB** for persistence. The POSIX-style `PassifloraIO` methods (`fopen`, `fread`, `fwrite`, `fclose`, etc.) operate entirely in JavaScript — the native C bridge is no longer used for file I/O.

### How the VFS Works

**Storage model:** Files are stored in a plain JavaScript object (`_vfs`) that maps path strings to `Uint8Array` values. For example, after writing a file at `/hello.txt`, `_vfs["/hello.txt"]` holds its byte contents.

**IndexedDB persistence:** On startup an IndexedDB database (`PassifloraVFS`) is opened and every stored file is loaded (hydrated) into the in-memory `_vfs`. When a file is closed with `fclose()`, its contents are persisted back to IndexedDB. `remove()` and `rename()` also update IndexedDB immediately. The browser's persistent-storage permission (`navigator.storage.persist()`) is requested automatically to reduce the chance of eviction.

**File handles:** `fopen()` creates a handle object that tracks the file path, open mode, and current read/write position — the same information a C `FILE*` would hold. All subsequent I/O calls (`fread`, `fwrite`, `fgets`, `fputs`, `fseek`, `ftell`, `feof`) operate on this handle's position within the `Uint8Array`.

**Write operations** (`fwrite`, `fputs`) grow the `Uint8Array` as needed by allocating a larger buffer, copying existing data, and appending the new bytes.

**Read operations** (`fread`, `fgets`) slice from the current position and advance the pointer. `fgets` scans for a newline character (byte 10) to return one line at a time.

**Directories:** Explicit directories are tracked in a separate in-memory set (`_dirs`) and persisted to an IndexedDB object store (`"dirs"`). `mkdir()` creates an entry; `rmdir()` removes it (if empty). `chdir()` and `getcwd()` manage a current working directory that is used to resolve relative paths.

**Directory listing** (`listDirectory`) synthesizes a directory listing by scanning the keys of `_vfs` for paths under the requested directory prefix **and** checking `_dirs` for explicitly created empty directories, deduplicating entries and inferring file-vs-directory from remaining path separators.

**Home folder:** `getHomeFolder()` returns `"/"`.

### Importing and Exporting Files

Since the VFS is a self-contained store, Passiflora provides methods to move files between the VFS and the real filesystem:

| Function | Description |
|----------|-------------|
| `PassifloraIO.importFile(extensions, path)` | Shows the browser/OS file picker (`<input type="file">`). The selected file is read and stored in the VFS at `path/filename`, and persisted to IndexedDB. `path` defaults to `"/"` if omitted. Returns a Promise resolving to the VFS path, or `null` if cancelled. |
| `PassifloraIO.exportFile(vfsPath, suggestedName)` | Saves a VFS file to the real filesystem. On Chrome/Edge uses `showSaveFilePicker()`; on other browsers triggers a download. Returns a Promise resolving to the VFS path exported, or `null` if cancelled. |

### Bulk VFS Export / Import

| Function | Description |
|----------|-------------|
| `PassifloraIO.exportVFS()` | Serialises every file in the VFS to a JSON file (`passiflora_vfs.json`) and triggers a browser download. Each file's contents are base64-encoded. Returns a Promise resolving to the number of files exported. |
| `PassifloraIO.importVFS()` | Opens a file picker for a `.json` file previously created by `exportVFS`, parses it, loads all files into the VFS, and persists them to IndexedDB. Returns a Promise resolving to the number of files imported (0 if cancelled). |

### VFS Management

| Function | Description |
|----------|-------------|
| `PassifloraIO.eraseVFS()` | Prompts the user for confirmation, then clears every file and directory from the VFS and IndexedDB. Resets the working directory to `"/"`. Returns a Promise resolving to the number of files erased (0 if the user cancels). |
| `PassifloraIO.resetVFS()` | Erases the entire VFS and IndexedDB (without prompting), then repopulates from the compiled-in preload data (see VFS Preloading below). Returns a Promise. |

### VFS Preloading

Files placed in `src/vfs/` are compiled into the app and automatically loaded into the VFS on first startup (i.e. when IndexedDB is empty). The directory structure under `src/vfs/` is preserved — for example, `src/vfs/data/config.json` becomes `/data/config.json` in the VFS.

The build scripts (`mkvfspreload.sh` / `mkvfspreload.bat`) base64-encode every file under `src/vfs/` into `src/www/generated/vfspreload.js`, which is included in the zip bundle. On startup, if the VFS is empty, the preload data is decoded and written to both the in-memory VFS and IndexedDB.

To reset the VFS back to the compiled-in preload data (erasing any user changes), call:

```javascript
await PassifloraIO.resetVFS();   // clears VFS + IndexedDB, reloads preload data
```

### Limitations

- **Explicit directories are optional:** The VFS is fundamentally a flat key-value store. Directories are inferred from path separators in file paths. You can also create explicit empty directories with `mkdir()`, which are persisted to IndexedDB and appear in directory listings.
- **No native recording on WWW:** `startRecording` / `stopRecording` are not available on the WWW target. On native platforms, `stopRecording()` returns the recording data as a `Uint8Array` that can be stored directly in the VFS.
- **IndexedDB quotas:** Browsers limit IndexedDB storage (Chrome: ~80% of disk, Firefox: ~5%, Safari: ~1 GB). Very large datasets may hit these limits.

### Building and Running the WWW Target

**macOS / Linux:**
```bash
make www                   # copies src/www/ → bin/WWW/ with WWW config
python3 webserver.py       # serves bin/WWW/ on http://localhost:8000
```

**Windows:**
```bat
.\build www                REM copies src\www\ → bin\WWW\ with WWW config
python webserver.py        REM serves bin\WWW\ on http://localhost:8000
```

The `webserver.py` script is a minimal Python HTTP server that serves `bin/WWW/` on port 8000 (pass a different port as a command-line argument if needed).

## Utility Functions

These are methods on `PassifloraIO` (not available as bare globals).

| Function | Description |
|----------|-------------|
| `PassifloraIO.openExternal(url)` | Open a URL in the system's default browser. On Android uses the native bridge; on other platforms issues a request to the embedded server's `openexternal` endpoint. Only `http://` and `https://` URLs are allowed. |
| `PassifloraIO.getCurrentPosition(successCb, errorCb)` | Get the device's current GPS position. On macOS/iOS uses the native CLLocationManager bridge; on other platforms delegates to `navigator.geolocation`. Callbacks follow the standard Geolocation API signature. |
| `PassifloraIO.webDownload(path, mimeType)` | Trigger a browser download for a VFS file. On macOS/iOS uses the native save panel via `passifloraSaveFile`; on other platforms creates a temporary download link. `mimeType` defaults to `"application/octet-stream"` if omitted. |
| `PassifloraIO.patchLinks()` | Scan the DOM for `<a href>` elements with `http://` or `https://` URLs and attach click handlers that route them through `openExternal()` instead of navigating the webview. Called automatically on `DOMContentLoaded`. |
| `PassifloraIO.hasNativeRecording()` | Returns a Promise resolving to `true` if GStreamer-based native recording is available (Linux with `usecamera` or `usemicrophone` enabled in `src/config`), `false` otherwise. |
| `PassifloraIO.startRecording(hasVideo, hasAudio)` | Start native recording via GStreamer. `hasVideo` and `hasAudio` are booleans selecting which tracks to capture. The recording is written to a temporary file on the native filesystem automatically. Returns a Promise. Not available on the WWW target. |
| `PassifloraIO.stopRecording()` | Stop a native recording in progress. Returns a Promise resolving to a `Uint8Array` containing the recorded WebM data (or `null` if no data). The temporary native file is deleted automatically. Not available on the WWW target. |
| `PassifloraIO.diagnoseNativeAudio()` | Run GStreamer audio diagnostics. Returns a Promise resolving to a diagnostic string. Not available on the WWW target. |

## Remote Debugging

Passiflora includes a built-in remote debugging facility that lets you execute JavaScript in a running app from an external browser. This is useful for inspecting app state, testing code snippets, and diagnosing issues on platforms where browser DevTools aren't available (iOS, Android, etc.).

Remote debugging is compile-gated — set `allowremotedebugging` to `true` in `src/config` to enable it. When enabled, a setup overlay appears at app startup where you enter a shared passphrase and copy the debugger URL. Open that URL in a browser on another device to send JavaScript commands to the running app.

For the full protocol details, security notes, and usage tips, see **[DEBUGGING.md](DEBUGGING.md)**.

## About this project

This code was developed through an iterative process involving human-guided prompting of a large language model (LLM), followed by review, editing, refinement, and original contributions by the author. To the extent the work contains copyrightable human-authored elements (including structure, modifications, arrangements, and additions), it is Copyright (c) 2026 by Anthony W. Hursh. The project is distributed under the terms of the MIT License (see LICENSE file for full text). Portions generated directly by AI may not be independently copyrightable under current U.S. law.


