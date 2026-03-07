![Passiflora](logo.png)

# Passiflora

Passiflora is a no-nonsense cross-platform packager that wraps HTML/JavaScript/CSS/etc. in an executable (similar to Electron and its ilk). Note that this should be considered **experimental** at this point. Things are still in a "move fast and break stuff" phase.  Please report any issues.

Supported target platforms include:

* macOS (build on macOS only, alas)
* iOS (likewise)
* Android (build on macOS, Windows, or Linux)
* Windows (build on macOS, Windows, or Linux)
* Linux (build on Linux)
* More targets may be added later if they seem useful

What it *doesn't* do:

* Require that you install 50 million dubious npm packages (or the whole freakin' Rust ecosystem, for the love of all that's holy)
* Generate 60 petabyte binaries for a "Hello, world!" program
* Engage in baroque configuration gymnastics

Passiflora uses the system's own web browser control rather than bundling an entire browser into the executable, like Electron. Similarly, Passiflora doesn't provide a lot of integration with the native OS -- things like file open/save (i.e., upload/download), access to the mic, camera and speaker, GPS data, etc. can now be done from HTML. Doing these things made sense back in the bad old days of incompatible browsers and highly-restricted web app functionality, but things have improved immensely since then. It's my belief that it's now preferable to work through whatever inconsistencies and shortcomings that remain than take the enormous hit of bundling an entire browser and native API in the executable. It's possible that some native bridging/integration will be added in the future, but the plan is to continue doing everything with web technology that *can* be done with web technology.

A basic Passiflora "Hello, world!" executable for Windows weighs only 859 KB.

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

Underneath `src`, each platform has a folder which contains a `menu.txt` file. These are used to generate menus. They will appear in the menu bar (for platforms that have a menu bar, e.g., Mac and Windows). The menu data is also available in JavaScript via `PassifloraConfig.menus` (see below), which can be used to build your own custom menus on mobile platforms.

The format should be clear — the different levels of a menu are expressed with indentation.

For platforms with a menu bar, choosing a menu item will call `PassifloraConfig.handleMenu(title)` in your JavaScript. For example, if you have:

```
{{progname}}
    About
    Quit
File
    Open
Misc
    More stuff
```

Choosing "More stuff" will call `PassifloraConfig.handleMenu("More stuff")` in your JavaScript.

The default `handleMenu` just pops an alert. To provide your own handler, set it in your `app.js`:

```javascript
PassifloraConfig.handleMenu = function(title) {
    // your code here
};
```

## PassifloraConfig

Each build generates `src/www/generated/config.js`, which defines a `PassifloraConfig` object containing:

```javascript
var PassifloraConfig = {
  os_name: "iOS",     // or "macOS", "Windows", "Linux", "Android"
  menus: [ ... ],     // menu structure from menu.txt
  handleMenu: function(title) { alert("Menu item clicked: " + title); }
};
```

- **`PassifloraConfig.os_name`** — the target platform, useful when your JavaScript needs to do different things on different platforms.
- **`PassifloraConfig.menus`** — the menu structure as a JSON array, useful for building custom menus on mobile.
- **`PassifloraConfig.handleMenu`** — called by the native menu bar when a menu item is selected. Override this in your `app.js` to handle menu actions.

This file is auto-generated on every build and should not be edited by hand.

## About this project

This code was developed through an iterative process involving human-guided prompting of a large language model (LLM), followed by review, editing, refinement, and original contributions by the author.To the extent the work contains copyrightable human-authored elements (including structure, modifications, arrangements, and additions), it is Copyright (c) 2026 by Anthony W. Hursh. The project is distributed under the terms of the MIT License (see LICENSE file for full text). Portions generated directly by AI may not be independently copyrightable under current U.S. law.


