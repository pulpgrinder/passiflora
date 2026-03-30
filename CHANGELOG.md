# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **Virtual File System (VFS) + IndexedDB**: All file I/O now runs entirely in JavaScript via an in-memory VFS backed by IndexedDB for persistence. The POSIX-style `PassifloraIO` methods (`fopen`, `fread`, `fwrite`, etc.) work on all platforms, including the WWW browser target. Files are hydrated from IndexedDB on startup and persisted on `fclose()`.

- **Directory functions**: `mkdir(path)`, `rmdir(path)`, `chdir(path)`, `getcwd()` — POSIX-style directory management with IndexedDB persistence. Relative paths and `.`/`..` components are resolved automatically. `rename()` now handles directory renames (moves all files and subdirectories under the old path).

- **File import/export**:
  - `PassifloraIO.importFile(extensions)` — import a file from the real filesystem into the VFS via the browser file picker.
  - `PassifloraIO.exportFile(vfsPath, suggestedName)` — export a VFS file to the real filesystem (uses `showSaveFilePicker()` on Chrome/Edge, download fallback elsewhere).
  - `PassifloraIO.exportVFS()` — bulk-export the entire VFS as a JSON file.
  - `PassifloraIO.importVFS()` — bulk-import a previously exported VFS JSON file.
  - `PassifloraIO.eraseVFS()` — clear all files, directories, and reset the working directory.

- **File Open dialog** (`PassifloraIO.menuopen`): Sliding-panel file browser for picking files from the VFS. Supports extension filtering, directory navigation with slide animations, and an "All files" toggle.

- **Save As dialog** (`PassifloraIO.menusavas`): Sliding-panel Save As dialog with filename input, overwrite confirmation, and extension-mismatch warnings.

- **Create Folder button**: Both `menuopen` and `menusavas` panels include a 📁+ button that creates a new directory named "Untitled", "Untitled 2", etc. in the current directory.

- **Long-press rename**: Long-pressing (500 ms) a file or directory name in `menuopen` or `menusavas` makes it editable inline. HTML, newlines, and extra whitespace are stripped. Enter confirms; Escape cancels. Normal click behavior is suppressed while editing.

- **WWW browser target** (`make www`): Builds a plain-browser version of the app into `bin/WWW/` with no native compilation needed.

- **iOS horizontal scroll fix**: Added `UIScrollViewDelegate` to the iOS view controller that resets `contentOffset.x` to 0, preventing unwanted horizontal scrolling in the WKWebView.

- **iOS safe-area support**: File dialog panels respect `env(safe-area-inset-top)` on notched iOS devices.

- **DEBUGGING.md**: Remote debugging protocol details, security notes, and usage tips split out from the main README into a dedicated file.

- **VFS preloading**: Files placed in `src/vfs/` are compiled into the app and automatically loaded into the VFS on first startup (when IndexedDB is empty). Build scripts `mkvfspreload.sh` and `mkvfspreload.bat` base64-encode the contents into `vfspreload.js`.

- **`PassifloraIO.resetVFS()`**: Erases the entire VFS and IndexedDB, then repopulates from the compiled-in preload data.

- **App configuration file** (`src/config`): A new key-value config file analogous to `src/permissions`. The first supported setting is `orientation` (`portrait`, `landscape`, or `both`), which controls screen orientation locking on iOS and Android. Desktop platforms ignore this setting.

- **Documentation**: Added previously undocumented public APIs to the README: `eraseVFS()`, `resetVFS()`, `listDirectory()`, `openExternal()`, `getCurrentPosition()`, `webDownload()`, and `patchLinks()`.

### Changed

- **Native file I/O bridge removed**: The ~540-line C file I/O implementation (`fopen`, `fread`, `fwrite`, `fclose`, `fseek`, etc.) has been removed from `passiflora.c`. All file operations now go through the JavaScript VFS. The `unrestrictedfilesystemaccess` permission has been removed.

- **IndexedDB schema version 2**: The `PassifloraVFS` IndexedDB database now has two object stores: `"files"` (file contents) and `"dirs"` (explicitly created directories).

- **CSS overflow fixes**: Global `box-sizing: border-box`, `overflow-x: hidden` on `html`/`body`, and `max-width: 100%` on media elements to prevent horizontal overflow. Panel widths changed from `100vw` to `100%`. Save As filename input uses `min-width: 0` so the Save button no longer overflows on narrow screens. Filter dropdown uses `flex: 1; min-width: 0` instead of `width: 100%`.

- **iOS IPA packaging**: Switched from `zip` to `ditto -c -k --sequesterRsrc --keepParent` for creating the `.ipa` archive, which correctly handles resource forks and extended attributes.

- **iOS code signing guidance**: Clarified that development certificates (not distribution) should be used for sideloading to local devices.

- **VFS path simplification**: Test file paths in `index.html` now use root-relative paths (`/testfile.txt`) rather than `homeFolder + "/testfile.txt"`.

- **README restructured**: Debugger internals moved to DEBUGGING.md; README now contains a short summary with a link.

### Fixed

- **Extended attribute stripping**: `xattr -cr "$APP"` added to `mkiosbundle.sh` to strip `com.apple.provenance` and other extended attributes from the iOS app bundle before signing. Also strips xattrs before `codesign` in the Makefile's `sign-ios` target. Prevents `codesign` and `xcrun simctl install` failures caused by resource forks.

- **Android build script**: Fixed `mkandroid.sh` compatibility issues.

- **Long-press vs. click conflict**: The long-press rename handler now suppresses click events while in edit mode, preventing accidental file selection or directory navigation when the touch/mouse is released after activating edit mode.
