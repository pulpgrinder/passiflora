# Menus, Themes, and Font Stacks

This document covers Passiflora's menu system (native menus, the sliding menu, and panel screens), the built-in theme engine, and the font stack selector.

## Menus

Underneath `src`, each platform has a folder which contains a `menu.txt` file. These are used to generate menus on two levels:

1. **Native menu bar** — on platforms that have one (macOS, Windows, Linux), the entries produce a real OS menu bar.
2. **JavaScript sliding menu** — on all platforms, non-native entries are available in `PassifloraConfig.menus` and in the (optional) built-in sliding menu UI (see [Sliding Menu](#sliding-menu-optional) below).

### menu.txt format

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

`{{progname}}` is replaced with the internal program name (`PROGNAME` from `src/config`) at build time. `{{displayname}}` is also available and is replaced with the user-visible name (`DISPLAYNAME` from `src/config`, which may contain spaces). On platforms with a native menu bar (macOS, Windows, Linux), `{{displayname}}` is the typical choice for the app menu heading, giving the menu a human-readable title like "Heckin Chonker" instead of "HeckinChonker".

For the **sliding menu** (iOS, Android, WWW), if a top-level menu's title matches either `progname` or `displayname`, its children are promoted to the top level rather than being nested under a submenu. This means the app-name menu items (About, Settings, etc.) appear directly in the menu rather than buried under an extra heading.

### Native vs. JavaScript routing (`*` prefix)

Each leaf menu item is either **native** or **JavaScript**, controlled by an optional `*` prefix:

| Prefix | Behavior |
|--------|----------|
| `*Quit` | Handled by the **native** platform. The `*` is stripped from the display title. If the platform recognizes the item (e.g. "Quit" on macOS maps to `⌘Q`), the native action runs. If not, a dialog says "No native handler for this item on this platform." The item is **never** passed to JavaScript and does **not** appear in `PassifloraConfig.menus` or the sliding menu. |
| `Quit` | Always passed to **JavaScript** via `PassifloraConfig.handleMenu("Quit")`. The native platform does not intercept it, and it **does** appear in `PassifloraConfig.menus` and the sliding menu. |

Matching is **exact** — `*Quit` matches the native "Quit" handler, but `*Quite` does not (it will show the "no native handler" dialog).

Top-level menu names (e.g. `File`, `{{progname}}`) and separators (`-`) are not affected by the `*` prefix.

### Recognized native items by platform

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

**Windows** — `*Quit` and `*Exit` close the window. All other `*`-prefixed items show a "no native handler" dialog (more will be added later).

**Linux** — `*Quit` and `*Exit` quit the application (`gtk_main_quit`). All other `*`-prefixed items show a "no native handler" dialog (more will be added later).

**iOS / Android** — these platforms have no native menu bar. A `*` prefix still causes items to be excluded from `PassifloraConfig.menus` and the sliding menu.

### JavaScript menu handler

For items without the `*` prefix, choosing them from the native menu bar calls `PassifloraConfig.handleMenu(title)` in your JavaScript. The default handler just pops an alert. Override it in your `app.js`:

```javascript
PassifloraConfig.handleMenu = function(title) {
    // your code here
};
```

## Sliding Menu (optional)

Passiflora includes a built-in basic sliding menu for platforms that don't have a native menu bar (iOS, Android), or for web-style navigation on any platform. **This is entirely optional** — you can use it as-is, customize it, or remove it and replace it with your own menu package.

The menu is built automatically from `PassifloraConfig.menus` at page load. It slides in from the right edge of the screen, supports arbitrarily nested submenus, and calls `PassifloraConfig.handleMenu(title)` when a leaf item is tapped.

**Triggering the menu:** The hamburger button (≡) is hidden by default to keep the UI clean. To reveal it, **long-press** (hold for 500 ms) on any non-interactive area of the page. The button appears in the top-right corner and stays visible for 3 seconds before fading out again. You can make the hamburger menu appear somewhere else by changing the `.hamburgermenu` class in `src/www/passiflora/theme.css`.

**Closing the menu:**

You can close the sliding menu without choosing an item in three ways:

* Tap/click outside the menu panels
* Press **Escape**
* Navigate back through all levels

**Files:**

* `src/www/passiflora/buildmenu.js` — menu logic (the `PassifloraMenu` IIFE)
* `src/www/passiflora/theme.css` — menu and panel styling. You can customize colors, sizes, transitions, etc. by editing this file.

Items prefixed with `*` in `menu.txt` are excluded from the sliding menu entirely — they only exist in the native menu bar (if there is one).

### Removing the sliding menu

If you'd rather use your own menu UI (or no menu UI at all), remove these three things from `src/www/index.html`:

1. The CSS link in `<head>`:
   ```html
   <link rel="stylesheet" href="passiflora/theme.css">
   ```
2. The hamburger element in `<body>`:
   ```html
   <div class="hamburgermenu">≡</div>
   ```
3. The script tag:
   ```html
   <script src="passiflora/buildmenu.js"></script>
   ```

You can also delete `src/www/passiflora/buildmenu.js` and `src/www/passiflora/theme.css` if you like, but leaving them in place is harmless — they won't do anything without the above references.

The `PassifloraConfig.menus` array and `PassifloraConfig.handleMenu` callback are still available regardless. You can use them to build your own menu and handle selections however you wish, or ignore them entirely.

## Panel Screens

You can create **panel screens** — full-screen sliding panels that open automatically when a matching leaf menu item is selected. This is useful for settings pages, about screens, or any content you want to present through the menu system.

**How it works:**

1. Place `.html` and (optionally) `.js` files in `src/www/passiflora/panels/`.
2. At build time, each `.html` file is wrapped in a hidden `<div class="passiflora_menu_screen" id="Basename">` and injected into the page. Any `.js` files in the same directory are appended as inline scripts that run after all other scripts have loaded.
3. When a leaf menu item is selected, the sliding menu checks whether a `passiflora_menu_screen` element exists whose `id` matches the item's title text. If a match is found, the menu closes and the panel slides in from the right. If no match is found, `PassifloraConfig.handleMenu(title)` is called as usual.

**Example:** Given the menu template:

```
MyApp
    About
    Settings
```

and a file `src/www/passiflora/panels/Settings.html`:

```html
<label for="themeselector">Theme</label>
<select id="themeselector"></select>
```

with an accompanying `src/www/passiflora/panels/Settings.js`:

```javascript
let themeNames = PassifloraThemes.getPassifloraThemeNames();
let themeSelector = document.getElementById("themeselector");
for (let themeName of themeNames) {
    let option = document.createElement("option");
    option.value = themeName;
    option.textContent = themeName;
    themeSelector.appendChild(option);
}
themeSelector.value = PassifloraThemes.getCurrentThemeName();
themeSelector.addEventListener("change", () => {
    PassifloraThemes.setCurrentTheme(themeSelector.value);
});
```

Selecting **Settings** from the sliding menu will close the menu and slide in the Settings panel. Selecting **About** (which has no matching panel) will call `PassifloraConfig.handleMenu("About")` as normal.

**Closing a panel:** Tap the back header at the top of the panel, click/tap the overlay outside the panel, or press **Escape**.

**Naming convention:** The panel's `id` must match the menu item text exactly (case-sensitive). The `id` is derived from the `.html` filename without its extension — e.g., `Settings.html` → `id="Settings"`.

**Build integration:** The build script `nixscripts/mkpanels.sh` (or `winscripts/mkpanels.bat` on Windows) generates `src/www/generated/panels.js`, which is loaded by a `<script>` tag at the end of `index.html`. This file is regenerated on every build and removed by `make clean`.

**Files:**

* `src/www/passiflora/panels/` — panel source files (`.html` content + optional `.js` logic)
* `src/www/generated/panels.js` — auto-generated; injects panel divs and runs panel scripts
* `nixscripts/mkpanels.sh` — *nix build script
* `winscripts/mkpanels.bat` / `winscripts/mkpanels.ps1` — Windows build scripts

## Themes

Passiflora ships with 122 built-in color themes. Each theme is a set of CSS custom properties applied to `:root`, controlling colors for the body, menu, accents, borders, and overlays.

### CSS variables set by themes

| Variable | Purpose |
|----------|---------|
| `--slide-body-color` | Main text color |
| `--slide-body-background-color` | Page background color |
| `--accent-color` | Primary accent (links, highlights) |
| `--accent2-color` | Secondary accent |
| `--menu-background-color` | Sliding menu background |
| `--menu-color` | Sliding menu text color |
| `--border-color` | Border color |
| `--overlay-color` | Semi-transparent overlay behind menus/panels |

### Default theme

The default theme is set in `src/config` via the `theme` key:

```
theme Graustark
```

This value is compiled into `PassifloraConfig.theme` by the build scripts and applied automatically when the app loads. If the named theme doesn't exist, the app falls back to the "Default" theme.

### Theme persistence

When a user changes the theme at runtime (e.g. via a Settings panel), the choice is persisted to the VFS file `/.passiflora_theme`. On subsequent launches, the VFS-saved theme overrides the config default.

### PassifloraThemes API

Themes are managed through the `PassifloraThemes` object defined in `src/www/passiflora/themes.js`:

| Method | Description |
|--------|-------------|
| `PassifloraThemes.getPassifloraThemeNames()` | Returns a sorted array of all available theme names. |
| `PassifloraThemes.getCurrentThemeName()` | Returns the name of the currently active theme. |
| `PassifloraThemes.setCurrentTheme(name)` | Applies the named theme and persists the choice to the VFS. Returns `true` on success, `false` if the theme doesn't exist. |
| `PassifloraThemes.applyPassifloraTheme(name)` | Applies the named theme without persisting. Used internally. Returns `true` on success, `false` if the theme doesn't exist. |

### Adding a custom theme

Add a new entry to `PassifloraThemes.themeData` in `src/www/passiflora/themes.js`:

```javascript
"My Custom Theme": `:root {
    --slide-body-color: #333333;
    --slide-body-background-color: #ffffff;
    --accent-color: #0066cc;
    --accent2-color: #003366;
    --menu-background-color: #0066cc;
    --menu-color: #ffffff;
    --border-color: #003366;
    --overlay-color: rgba(0, 0, 0, 0.5);
}`,
```

The theme will automatically appear in `getPassifloraThemeNames()` and in any theme selector UI.

**Files:**

* `src/www/passiflora/themes.js` — theme definitions and API
* `src/www/passiflora/theme.css` — base CSS that references the theme variables

## Font Stacks

Passiflora includes a collection of 22 curated font stacks that can be assigned to body text, headings, and code blocks. Each stack includes emoji font fallbacks for cross-platform consistency.

### Config defaults

Default font stacks are set in `src/config`:

```
body-font-stack System UI
heading-font-stack Antique
code-font-stack Monospace Code
```

These are compiled into `PassifloraConfig["body-font-stack"]`, `PassifloraConfig["heading-font-stack"]`, and `PassifloraConfig["code-font-stack"]` by the build scripts.

### CSS variables

Font stack selections are applied as CSS custom properties on the document root:

| Variable | Purpose |
|----------|---------|
| `--body-font-stack` | Font family for body text |
| `--heading-font-stack` | Font family for headings |
| `--code-font-stack` | Font family for `<code>` and `<pre>` elements |

Use these in your CSS:

```css
body {
    font-family: var(--body-font-stack);
}

h1, h2, h3, h4, h5, h6 {
    font-family: var(--heading-font-stack);
}

code, pre {
    font-family: var(--code-font-stack);
}
```

### Font stack persistence

Like themes, font stack selections are persisted to the VFS. Each selector writes to a separate file:

| Selector | VFS path |
|----------|----------|
| Body | `/.passiflora_body_font` |
| Heading | `/.passiflora_heading_font` |
| Code | `/.passiflora_code_font` |

On startup, if a VFS-persisted value exists it overrides the config default.

### Available font stacks

The font stack options are defined in `PassifloraThemes.baseFontStackOptions`:

| Name | Stack |
|------|-------|
| Antique | Superclarendon, Bookman Old Style, Georgia Pro, Georgia, serif |
| Classical Humanist | Optima, Candara, Noto Sans, sans-serif |
| Didone | Didot, Bodoni MT, Noto Serif Display, Sylfaen, serif |
| Fantasy | Papyrus, Comic Sans MS, fantasy |
| Generic Cursive | cursive |
| Generic Monospace | monospace |
| Generic Sans Serif | sans-serif |
| Generic Serif | serif |
| Geometric | Avenir, Montserrat, Corbel, URW Gothic, sans-serif |
| Grotesque | Helvetica Neue, Helvetica, Arial, Nimbus Sans, sans-serif |
| Handwritten | Segoe Print, Bradley Hand, Chilanka, cursive |
| Humanist | Seravek, Gill Sans Nova, Ubuntu, Calibri, sans-serif |
| Industrial | Bahnschrift, DIN Alternate, Franklin Gothic Medium, sans-serif |
| Monospace Code | Cascadia Code, Source Code Pro, Menlo, Consolas, monospace |
| Monospace Slab | Nimbus Mono PS, Courier New, monospace |
| Neo-Grotesque | Inter, Roboto, Helvetica Neue, Arial, sans-serif |
| Old Style | Iowan Old Style, Palatino Linotype, URW Palladio L, serif |
| Rounded Sans | Hiragino Maru Gothic ProN, Quicksand, Comfortaa, sans-serif |
| Slab Serif | Rockwell, Roboto Slab, DejaVu Serif, serif |
| System UI | system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif |
| Transitional | Charter, Bitstream Charter, Sitka Text, Cambria, serif |
| Venetian | Calisto MT, Goudy Old Style, Garamond, Hoefler Text, serif |

All stacks include emoji fallbacks (`Apple Color Emoji`, `Segoe UI Emoji`, `Segoe UI Symbol`, `Noto Color Emoji`).

### The built-in Settings panel

The sample app includes a Settings panel (`src/www/passiflora/panels/Settings.html` and `Settings.js`) that provides drop-down selectors for the theme and all three font stacks, along with sample text to preview changes. This panel is accessed through the sliding menu when a "Settings" menu item exists.

**Files:**

* `src/www/passiflora/themes.js` — defines `PassifloraThemes.baseFontStackOptions`
* `src/www/passiflora/panels/Settings.html` — Settings panel UI (theme + font selectors + preview text)
* `src/www/passiflora/panels/Settings.js` — populates selectors, applies CSS variables, persists to VFS
* `src/config` — default font stack names (`body-font-stack`, `heading-font-stack`, `code-font-stack`)
