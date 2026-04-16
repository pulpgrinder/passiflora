The file `src/config` controls the program name, bundle identifier, permissions, orientation, and other app-level settings. Each line has the form `key value` (case-insensitive). Permissions use `true` / `false` values and default to `false` if omitted. The supplied sample config file has pretty much everything turned on so you can test things. For apps you're planning to distribute, you should set everything to `false` except the ones you actually need (good security policy in general, plus app stores frown on unnecessary permissions).

- **`PROGNAME`** — Values: any name (no spaces) — Default: `HeckinChonker`
  The internal program name. Used for the Android APK filename, Apple `CFBundleExecutable`, and as a fallback when `DISPLAYNAME` is not set. Must not contain spaces. All build scripts (Makefile, build.bat, Gradle) read this from `src/config`.

- **`DISPLAYNAME`** — Values: any name (spaces allowed) — Default: value of `PROGNAME`
  The user-visible application name. Used for:
  - Window titles (macOS, Windows, Linux)
  - The macOS `.app` bundle name and `CFBundleDisplayName`
  - The iOS `.app` bundle name and `CFBundleDisplayName`
  - The Windows `.exe` filename (e.g., `Heckin Chonker.exe`)
  - The Windows title bar and VERSIONINFO block
  - The Linux binary filename (e.g., `Heckin Chonker`)
  - The Linux `.desktop` `Name=` field
  - The Android launcher label
  
  May contain spaces. If omitted, falls back to `PROGNAME`.

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

- **`usefilesystem`** — Values: `true`, `false` — Default: `false`
  When `true`, the build includes the virtual file system (VFS) and `PassifloraIO` core I/O library in `generated.js`. This provides POSIX-style file functions (`fopen`, `fread`, `fwrite`, etc.) backed by IndexedDB, plus VFS preloading of files from `src/vfs/`. See [FILE-IO.md](FILE-IO.md).

- **`usepassifloraui`** — Values: `true`, `false` — Default: `false`
  When `true`, the build includes the Passiflora UI layer in `generated.js` and `generated.css`: the file UI dialogs (`fileui.js`), sliding menu system (`buildmenu.js`), theme engine with 122 built-in color themes (`themes.js` + `theme.css`), and compiled panel screens from `src/www/panels/`. See [MENUS-AND-THEMES.md](MENUS-AND-THEMES.md) and [FILE-IO.md](FILE-IO.md).
