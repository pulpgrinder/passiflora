![Passiflora](logo.png)

# Passiflora

Passiflora is a no-nonsense cross-platform packager that wraps HTML/JavaScript/CSS/etc. in an executable (similar to Electron and its ilk). 

Note that this should be considered **experimental** at this point. Things are still in a "move fast and break stuff" phase.  Please report any issues. In addition, much of this project was vibe-coded as an experiment. While everything seems to be working fine, I'm not an expert in all these systems and I'm sure there are numerous uglinesses and infelicities present. Again, please raise an issue if you notice anything amiss.

Supported target platforms include:

* macOS (build on macOS only, alas)
* iOS (likewise)
* Android (build on macOS, Windows, or Linux)
* Windows (build on macOS, Windows, or Linux)
* Linux (build on Linux)
* More targets may be added later if they seem useful

What it *doesn't* do:

* Require that you install 50 million dubious npm packages (or a whole freakin' Rust ecosystem, for the love of all that's holy)
* Generate 60 petabyte binaries for a "Hello, world!" program
* Engage in baroque configuration gymnastics -- no need to fool with those nasty-ass package.json scripts

![Ur Doin' It Worng](doingitwrong.jpg)

Passiflora uses the system's own web browser control rather than bundling an entire browser into the executable, like Electron. Similarly, Passiflora doesn't provide a lot of integration with the native OS -- things like file open/save (i.e., upload/download), access to the mic, camera and speaker, GPS data, etc. can now be done from HTML. Bundling a web browser and/or a heavyweight native API bridge made sense back in the bad old days of incompatible browsers and highly-restricted web app functionality, but things have improved immensely since then. It's my belief that it's now preferable to work through or around whatever inconsistencies and shortcomings that remain than take the enormous hit of bundling an entire browser and native API in the executable. It's possible that some native bridging will be added in the future to handle corner cases, but the plan is to continue doing everything with web technology that *can* be done with web technology.

A basic Passiflora "Hello, world!" executable for macOS weighs only about 3.6 MB. 

By comparison, a similar Electron executable for macOS (generated with Electron Forge) weighs over 210 MB.

 Electron and Electron Forge also install 342 (!) npm packages, and generate scads of deprecation/security warnings (and, yes, I'm following the installation/compilation instructions on the Electron website that are current as of today, March 7, 2026).

Yikes!

## Prerequisites and Building

Detailed installation, build, cross-compilation, and code signing instructions are in the per-platform guides:

* **[Building on macOS](BUILD-macOS.md)** — native macOS builds, plus cross-compiling for iOS, iOS Simulator, Windows, and Android
* **[Building on Windows](BUILD-Windows.md)** — native Windows builds, plus cross-compiling for Android
* **[Building on Linux](BUILD-Linux.md)** — native Linux builds, plus cross-compiling for Windows and Android

### Quick Start

1. Install the prerequisites for your host system (see the guide above).
2. Check out this repo.
3. Edit `PROGNAME` in the Makefile (macOS/Linux) or `build.bat` (Windows).
4. Put your HTML/JavaScript/CSS in `src/www`.
5. Build:

**macOS / Linux:**
```
make
```

**Windows (PowerShell):**
```
.\build
```

### Make/Build Targets Summary

| Target | Description |
|--------|-------------|
| `make` | Build for current platform (macOS or Linux) |
| `make windows` | Cross-compile Windows exe (from macOS/Linux) |
| `make linux` | Build Linux binary (on Linux only) |
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

### Icons

Change `roundicon.png` and `squareicon.png` in `src/icons` to whatever images you like. These should be pretty big — around 1,000 pixels square. More is better! The `squareicon.png` file should be square (duh!), while the `roundicon.png` should be a square image consisting of a round image on a transparent background. Look at the supplied example if this seems confusing.

All of the zillions of other icons for the various different systems are generated from these.

Once you've updated the base icons, run:

`make icons` (macOS and Linux)

or

`.\winscripts\buildicons.bat` (Windows)

to generate a new icon set (on Windows `.\build icons` would also work).

Note that these may need some manual tweaking for legibility, particularly at the smaller sizes, but it's still a substantial time savings over generating them all individually. Icons are *not* regenerated automatically during a normal build (not even after make clean). This is so any hand-tuned versions you have won't be overwritten. If you *do* want to wipe out all the generated icons and start over, run `make icons` or `.\build icons` again.

### Menus

Underneath `src`, each platform has a folder which contains a `menu.txt` file. These are used to generate menus on two levels:

1. **Native menu bar** — on platforms that have one (macOS, Windows, Linux), the entries produce a real OS menu bar.
2. **JavaScript sliding menu** — on all platforms, non-native entries are available in `PassifloraConfig.menus` and in the built-in sliding menu UI (see [Sliding Menu](#sliding-menu) below).

#### menu.txt format

Menu hierarchy is expressed with indentation. Submenus can be nested to any depth. Blank lines and separators (`-`) are supported.

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

**Windows** — `*Quit` and `*Exit` close the window. All other `*`-prefixed items show a "no native handler" dialog.

**Linux** — `*Quit` and `*Exit` quit the application (`gtk_main_quit`). All other `*`-prefixed items show a "no native handler" dialog.

**iOS / Android** — these platforms have no native menu bar. The `*` prefix still causes items to be excluded from `PassifloraConfig.menus` and the sliding menu.

#### JavaScript menu handler

For items without the `*` prefix, choosing them from the native menu bar calls `PassifloraConfig.handleMenu(title)` in your JavaScript. The default handler just pops an alert. Override it in your `app.js`:

```javascript
PassifloraConfig.handleMenu = function(title) {
    // your code here
};
```

### Sliding Menu (optional)

Passiflora includes a built-in sliding menu for platforms that don't have a native menu bar (iOS, Android), or for web-style navigation on any platform. **This is entirely optional** — you can use it as-is, customise it, or remove it and replace it with your own menu solution.

The menu is built automatically from `PassifloraConfig.menus` at page load. It slides in from the right edge of the screen, supports arbitrarily nested submenus, and calls `PassifloraConfig.handleMenu(title)` when a leaf item is tapped.

**Triggering the menu:** The hamburger button (≡) is hidden by default to keep the UI clean. To reveal it, **long-press** (hold for 500 ms) on any non-interactive area of the page. The button appears in the top-right corner and stays visible for 3 seconds before fading out again.

**Closing the menu:**

* Tap/click outside the menu panels
* Press **Escape**
* Navigate back through all levels

**Styling:** The menu's appearance is controlled by `src/www/passiflora/menu.css`. You can customise colours, sizes, transitions, etc. by editing this file.

**Files:**

* `src/www/passiflora/buildmenu.js` — menu logic (the `PassifloraMenu` IIFE)
* `src/www/passiflora/menu.css` — menu styling

Items prefixed with `*` in `menu.txt` are excluded from the sliding menu entirely — they only exist in the native menu bar.

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

The `PassifloraConfig.menus` array and `PassifloraConfig.handleMenu` callback are still available regardless. You can use them to build your own menu however you wish, or ignore them entirely.

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

## About this project

This code was developed through an iterative process involving human-guided prompting of a large language model (LLM), followed by review, editing, refinement, and original contributions by the author. To the extent the work contains copyrightable human-authored elements (including structure, modifications, arrangements, and additions), it is Copyright (c) 2026 by Anthony W. Hursh. The project is distributed under the terms of the MIT License (see LICENSE file for full text). Portions generated directly by AI may not be independently copyrightable under current U.S. law.


