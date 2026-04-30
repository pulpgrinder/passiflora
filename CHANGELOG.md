# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **`DISPLAYNAME` support**: New `DISPLAYNAME` setting in `src/config` allows multi-word application names (e.g., "Heckin Chonker"). `DISPLAYNAME` is used for window titles, macOS/iOS `.app` bundle names, the Windows `.exe` filename, the Linux binary filename, the Android launcher label, the Linux `.desktop` `Name=` field, and the Windows VERSIONINFO block. `PROGNAME` (no spaces) remains the internal name used for Apple `CFBundleExecutable`, Android APK filenames, and bundle identifiers. If `DISPLAYNAME` is not set, it falls back to `PROGNAME`.

- **`{{displayname}}` menu template variable**: Menu `.txt` files can now use `{{displayname}}` in addition to `{{progname}}`. On desktop platforms (macOS, Windows, Linux), `{{displayname}}` is the typical choice for the app menu heading. The sliding menu (iOS, Android, WWW) automatically promotes children of any menu whose title matches `progname` or `displayname` to the top level, so app-name items appear directly without an extra submenu.

- **`PassifloraConfig.progname` and `PassifloraConfig.displayname`**: The generated `config.js` now includes both `progname` (internal, no spaces) and `displayname` (user-visible, may contain spaces) fields.

- **Android Emulator instructions**: BUILD-macOS.md, BUILD-Windows.md, and BUILD-Linux.md now include a "Testing in the Android Emulator" section with step-by-step instructions for loading an APK via Android Studio's Device Manager or `adb install`.

### Changed

- **`PROGNAME` and `BUNDLE_ID` centralized in `src/config`**: The program name and bundle identifier are now read from `src/config` by all build scripts (Makefile, build.bat, and Android build.gradle) instead of being hardcoded. Set `PROGNAME` and `BUNDLE_ID` in `src/config` and every platform picks them up automatically. The Android `applicationId` is now read from config at Gradle evaluation time, replacing the old sed/PowerShell rewriting hack in the mkandroid scripts.

### Added

- ** `make googleplay-android`** (`.\build googleplay-android` on Windows): New **Experimental** build target that produces a release Android App Bundle (`.aab`) for upload to the Google Play Console. Uses Gradle's `bundleRelease` task. The signed APK target (`make sign-android`) is unchanged. `make sign-all` now includes both the signed APK and the Google Play AAB.

- **`make sign-windows`** (`.\build sign-windows` on Windows): New build target that signs the Windows `.exe` using Azure Artifact Signing (formerly Azure Trusted Signing) via jsign. Requires an Azure Artifact Signing account, the Azure CLI (`az`), and jsign on PATH. Set `AZURE_SIGNING_ENDPOINT`, `AZURE_SIGNING_ACCOUNT`, and `AZURE_SIGNING_PROFILE` environment variables before running. `make sign-all` now includes `sign-windows`.



### Added

- **Configurable server port** (`src/config`): The `port` setting controls which localhost port the embedded HTTP server uses. If no port is set, the build system auto-generates a random port in the 40000–62000 range and writes it to `src/config` for reuse. A stable port ensures IndexedDB-persisted VFS data survives between runs. If the configured port is unavailable at runtime, the server automatically tries other random ports in the same range.

### Fixed

- **`usepassifloraui` without `usefilesystem`**: The generated WWW bundle no longer includes `fileui.js` when the filesystem layer is disabled, which prevented `generated.js` from crashing at load time with `ReferenceError: PassifloraIO is not defined`.

- **`make sign-macos` temp file cleanup**: Temporary files (entitlements plists, notarization zips, App Store bundle copies) are now guaranteed to be removed on exit, even if the signing workflow fails with an error. Previously, an early failure could leave orphaned files in `/tmp` or the build directory.

- **iOS provisioning profile selection**: `make sign-ios` now lists available `.mobileprovision` files from `~/passiflora-keys` instead of assuming a single `<progname>.mobileprovision` filename. The iOS signing docs now also recommend keeping separate development and App Store profiles, such as `MyAppDevelop.mobileprovision` and `MyAppAppStore.mobileprovision`.

- **`make all` and `make sign-all`**: These targets now actually build all platforms as documented. Previously `make all` only built the macOS app, and `make sign-all` did not exist.



### Changed

- **Android signing default keystore path**: `make sign-android` (and `.\build sign-android` on Windows) now automatically looks for a keystore at `~/passiflora-keys/android-keystore.jks` (`%USERPROFILE%\passiflora-keys\android-keystore.jks` on Windows). If found, it is used without prompting for a path. If not found, you are prompted as before. The recommended `keytool` command in the docs now creates the keystore at this default location.

- **Android SDK auto-detection**: `make sign-android` now auto-detects `ANDROID_HOME` from common SDK locations (`~/Library/Android/sdk` on macOS, `~/Android/Sdk` on Linux) and from `local.properties`, so `apksigner` and `zipalign` are found without needing to export `ANDROID_HOME`.

### Removed

- **Test keystore removed**: The bundled test keystore (`src/android/release.jks`) has been removed. Gradle release builds now require `RELEASE_KEYSTORE` environment variables to be set, or use `make sign-android` for interactive signing.

### Added

- **macOS notarization and App Store packaging**: `make sign-macos` now runs a two-stage interactive workflow. Stage 1 signs the `.app` with a Developer ID certificate, submits it to Apple's notary service, and staples the ticket — producing a notarized app ready for distribution outside the App Store. Stage 2 creates a separate App Store copy, signs it with an App Store application certificate (with App Sandbox), and wraps it in a `.pkg` signed with an installer certificate — ready for upload to App Store Connect. Both stages are optional.

- **iOS App Store upload guidance**: `make sign-ios` documentation now notes that when signed with an Apple Distribution certificate and an App Store provisioning profile, the resulting `.ipa` is ready for direct upload to App Store Connect. Added upload instructions using `xcrun altool` and Transporter.

- **3rd Party Mac Developer Installer certificate**: Added to the certificate types table in BUILD-macOS.md — required for signing the `.pkg` installer for Mac App Store submission.

- **Notarization setup instructions**: BUILD-macOS.md now documents how to generate an app-specific password and store notarization credentials in the Keychain via `xcrun notarytool store-credentials`.

### Previously added

- **Virtual File System (VFS) + IndexedDB**: All file I/O now runs entirely in JavaScript via an in-memory VFS backed by IndexedDB for persistence. The POSIX-style `PassifloraIO` methods (`fopen`, `fread`, `fwrite`, etc.) work on all platforms, including the WWW browser target. Files are hydrated from IndexedDB on startup and persisted on `fclose()`.

- **Directory functions**: `mkdir(path)`, `rmdir(path)`, `chdir(path)`, `getcwd()` — POSIX-style directory management with IndexedDB persistence. Relative paths and `.`/`..` components are resolved automatically. `rename()` now handles directory renames (moves all files and subdirectories under the old path).

- **File import/export**:
  - `PassifloraIO.importFile(extensions, path)` — import a file from the real filesystem into the VFS via the browser file picker. The optional `path` parameter specifies the VFS directory to save into (defaults to `"/"`).
  - `PassifloraIO.exportFile(vfsPath, suggestedName)` — export a VFS file to the real filesystem (uses `showSaveFilePicker()` on Chrome/Edge, download fallback elsewhere).
  - `PassifloraIO.exportVFS()` — bulk-export the entire VFS as a JSON file.
  - `PassifloraIO.importVFS()` — bulk-import a previously exported VFS JSON file.
  - `PassifloraIO.eraseVFS()` — clear all files, directories, and reset the working directory.

- **WWW target on Windows**: Added `www` target to `build.bat` so `.\build www` builds the plain-browser version into `bin\WWW\` on Windows, matching the existing `make www` on macOS/Linux.

- **File Open dialog** (`PassifloraIO.menuOpen`): Sliding-panel file browser for picking files from the VFS. Supports extension filtering, directory navigation with slide animations, and an "All files" toggle.

- **Save As dialog** (`PassifloraIO.menuSaveAs`): Sliding-panel Save As dialog with filename input, overwrite confirmation, and extension-mismatch warnings.

- **Create Folder button**: Both `menuOpen` and `menuSaveAs` panels include a 📁+ button that creates a new directory named "Untitled", "Untitled 2", etc. in the current directory.

- **Long-press rename**: Long-pressing (500 ms) a file or directory name in `menuOpen`, `menuSaveAs`, or `fileBrowser` makes it editable inline. HTML, newlines, and extra whitespace are stripped. Enter confirms; Escape cancels. Normal click behavior is suppressed while editing.

- **File Browser** (`PassifloraIO.fileBrowser`): Sliding-panel file browser for browsing and managing files in the VFS. Clicking a file highlights it without closing the dialog. Supports drag-and-drop to move files into subfolders or the parent directory, extension filtering, Create Folder, long-press rename, and a Done button to close. Remembers the current directory between invocations.

- **WWW browser target** (`make www`): Builds a plain-browser version of the app into `bin/WWW/` with no native compilation needed.

- **iOS horizontal scroll fix**: Added `UIScrollViewDelegate` to the iOS view controller that resets `contentOffset.x` to 0, preventing unwanted horizontal scrolling in the WKWebView.

- **iOS safe-area support**: File dialog panels respect `env(safe-area-inset-top)` on notched iOS devices.

- **DEBUGGING.md**: Remote debugging protocol details, security notes, and usage tips split out from the main README into a dedicated file.

- **VFS preloading**: Files placed in `src/vfs/` are compiled into the app and automatically loaded into the VFS on first startup (when IndexedDB is empty). Build scripts `mkvfspreload.sh` and `mkvfspreload.bat` base64-encode the contents into `vfspreload.js`.

- **`PassifloraIO.resetVFS()`**: Erases the entire VFS and IndexedDB, then repopulates from the compiled-in preload data.

- **App configuration file** (`src/config`): A unified key-value config file that controls permissions and app settings. Supported keys: `uselocation`, `usecamera`, `usemicrophone`, `allowremotedebugging` (`true`/`false`), `orientation` (`portrait`, `landscape`, or `both`), and `port` (server port number). The separate `src/permissions` file has been removed.

- **Documentation**: Added previously undocumented public APIs to the README: `eraseVFS()`, `resetVFS()`, `listDirectory()`, `openExternal()`, `getCurrentPosition()`, `webDownload()`, and `patchLinks()`.

### Changed

- **Native file I/O bridge removed**: The ~540-line C file I/O implementation (`fopen`, `fread`, `fwrite`, `fclose`, `fseek`, etc.) has been removed from `passiflora.c`. All file operations now go through the JavaScript VFS. The `unrestrictedfilesystemaccess` permission has been removed.

- **Recording API returns data directly**: `stopRecording()` now returns the recorded WebM data as a `Uint8Array` instead of writing to a native filesystem path. The C side writes to a temporary file automatically, base64-encodes the result, and deletes the temp file. `startRecording(hasVideo, hasAudio)` no longer takes a `path` parameter. This eliminates the need for callers to manage native file paths — recording data can be stored directly in the VFS.

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
