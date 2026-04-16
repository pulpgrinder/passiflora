The `www/generated/generated.js` file is auto-generated on every build and should not be edited by hand. It includes (among other things) the PassifloraConfig object which contains several useful values.

```javascript
let PassifloraConfig = {
  progname: "HeckinChonker",   // internal name (no spaces), from src/config PROGNAME
  displayname: "Heckin Chonker", // user-visible name (may have spaces), from src/config DISPLAYNAME
  os_name: "iOS",          // or "macOS", "Windows", "Linux", "Android", "WWW"
  theme: "Northern Lights",      // default theme from src/config
  "body-font-stack": "System UI",     // default body font stack name
  "heading-font-stack": "Antique",    // default heading font stack name
  "code-font-stack": "Monospace Code", // default code font stack name
  port: 51299,             // localhost port the embedded server is listening on
  menus: [ ... ],          // menu structure from menu.txt (excludes *-prefixed items)
  handleMenu: function(title) { alert("Menu item clicked: " + title); }
};
```

- **`PassifloraConfig.progname`** — the internal program name from `src/config` (no spaces). Useful for identifiers, file paths, and bundle IDs.
- **`PassifloraConfig.displayname`** — the user-visible name from `src/config`. May contain spaces (e.g., "Heckin Chonker"). Falls back to `progname` if `DISPLAYNAME` is not set in `src/config`.
- **`PassifloraConfig.os_name`** — the target platform, useful if your JavaScript needs to do different things on different platforms.
- **`PassifloraConfig.theme`** — the default theme name from `src/config`. Applied on startup; may be overridden by VFS-persisted choice.
- **`PassifloraConfig["body-font-stack"]`**, **`PassifloraConfig["heading-font-stack"]`**, **`PassifloraConfig["code-font-stack"]`** — default font stack names from `src/config`. Must match keys in `PassifloraThemes.baseFontStackOptions`.
- **`PassifloraConfig.port`** — the localhost port from `src/config`. At runtime, if the configured port was unavailable (collision), `PassifloraIO` automatically updates this to the actual port the server bound to.
- **`PassifloraConfig.menus`** — the menu structure as a nested JSON array, useful for building custom menus. Items prefixed with `*` in `menu.txt` are excluded — they are native-only and never reach JavaScript.
- **`PassifloraConfig.handleMenu`** — called by both the native menu bar and the built-in sliding menu when a (non-native) menu item is selected. Override this in your `app.js` to handle menu actions.

