# File I/O

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

## File Open, Save As, and File Browser

Passiflora provides three built-in sliding-panel file dialogs: **`menuOpen`** for opening files, **`menuSaveAs`** for Save As, and **`fileBrowser`** for browsing and managing files. These are methods on the `PassifloraIO` object. The dialogs appear as sliding panels that let the user browse the virtual file system (VFS). To bring files in from the real filesystem or save files out, use **`importFile`** and **`exportFile`** (see [Importing and Exporting Files](#importing-and-exporting-files) below).

### `menuOpen(extensions, defaultFolder)`

Opens a sliding file-browser panel that lets the user navigate the VFS and pick a file.

| Parameter | Type | Description |
|-----------|------|-------------|
| `extensions` | `string[]` | File extensions to filter by (e.g. `['.txt', '.md']`). Pass `[]` or `null` for all files. The user can also switch to "All files" in the dropdown. |
| `defaultFolder` | `string` | Starting directory. If empty/null, defaults to the home folder. |

Returns a Promise that resolves to the chosen file's full path, or `null` if the user cancelled.

```javascript
let path = await PassifloraIO.menuOpen(['.txt', '.md'], '');
if (path) {
    let fh = await fopen(path, 'r');
    let contents = await fgets(fh);
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
let path = await PassifloraIO.menuSaveAs(['.txt'], 'document.txt');
if (path) {
    let fh = await fopen(path, 'w');
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

### `fileBrowser(extensions, defaultFolder)`

Opens a sliding file-browser panel for browsing and managing files in the VFS. Unlike `menuOpen` and `menuSaveAs`, clicking a file only highlights it — it does not trigger a callback or close the dialog.

| Parameter | Type | Description |
|-----------|------|-------------|
| `extensions` | `string[]` | File extensions to filter by (e.g. `['.txt', '.md']`). Pass `[]` or `null` for all files. |
| `defaultFolder` | `string` | Starting directory. If empty/null, uses the remembered directory from the last invocation, or the home folder on first use. |

Returns a Promise that resolves to `null` when the user closes the browser.

```javascript
await PassifloraIO.fileBrowser(['.txt', '.md'], '');
// The user has finished browsing.
```

**UI features:**

- The layout and theme match `menuOpen` and `menuSaveAs` — same sliding panels, extension filter dropdown, 📁+ Create Folder button, and long-press rename.
- **Remembers the current directory** between invocations. Re-opening the file browser returns to wherever the user last navigated.
- **Click to highlight:** Clicking a file highlights it (accent-color outline) but does not close the dialog or fire any callback.
- **Drag and drop:** Files are draggable. Drag a file onto a subfolder row to move it into that folder. Drag a file onto the "📁 .." row to move it to the parent directory.
- **Done button:** A "Done" button in the filter bar closes the browser.
- **Escape or navigate past root:** Pressing Escape, tapping the overlay, or sliding back past the initial directory all close the browser.

### Styling

All three dialogs are styled via `src/passiflora/UI/theme.css` using the `passiflora_fo_*` CSS class prefix. The file browser adds `passiflora_fb_*` classes for selection highlighting (`passiflora_fb_selected`), drag-over feedback (`passiflora_fb_dragover`), and drag-in-progress opacity (`passiflora_fb_dragging`). The confirm dialogs use `passiflora_fo_confirm_*` classes. The dialogs respect iOS safe-area insets (`env(safe-area-inset-top)`).

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

The build scripts (`mkgenerated.sh` / `mkgenerated.bat`) base64-encode every file under `src/vfs/` and concatenate the result into `src/www/generated/generated.js`, which is included in the zip bundle. On startup, if the VFS is empty, the preload data is decoded and written to both the in-memory VFS and IndexedDB.

To reset the VFS back to the compiled-in preload data (erasing any user changes), call:

```javascript
await PassifloraIO.resetVFS();   // clears VFS + IndexedDB, reloads preload data
```

### Limitations

- **Explicit directories are optional:** The VFS is fundamentally a flat key-value store. Directories are inferred from path separators in file paths. You can also create explicit empty directories with `mkdir()`, which are persisted to IndexedDB and appear in directory listings.
- **Recording:** `stopRecording()` returns the recording data as a `Uint8Array` that can be stored directly in the VFS.
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
