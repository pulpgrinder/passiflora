
if (typeof PassifloraThemes !== "undefined") {

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

/* ── Font stack selectors ─────────────────────────────────────────── */
const baseFontStackOptions = PassifloraThemes.baseFontStackOptions;

const fontSelectors = [
    { id: "body-font-stack",    cssVar: "--body-font-stack",    key: "bodyFont" },
    { id: "heading-font-stack", cssVar: "--heading-font-stack", key: "headingFont" },
    { id: "code-font-stack",    cssVar: "--code-font-stack",    key: "codeFont" }
];

function applyFontVar(cssVar, optionName) {
    const stack = PassifloraThemes.baseFontStackOptions[optionName];
    if (stack) {
        document.documentElement.style.setProperty(cssVar, stack);
    }
}

for (const fs of fontSelectors) {
    const sel = document.getElementById(fs.id);
    for (const name of Object.keys(baseFontStackOptions)) {
        const opt = document.createElement("option");
        opt.value = name;
        opt.textContent = name;
        sel.appendChild(opt);
    }

    /* Set initial value from config */
    const configVal = PassifloraConfig[fs.id];
    if (configVal && baseFontStackOptions[configVal]) {
        sel.value = configVal;
        applyFontVar(fs.cssVar, configVal);
    }

    sel.addEventListener("change", () => {
        applyFontVar(fs.cssVar, sel.value);
        const fields = {};
        fields[fs.key] = sel.value;
        PassifloraThemes._saveConfig(fields);
    });
}

/* Override theme selector and font stacks with VFS-persisted values */
(async function() {
    const cfg = await PassifloraThemes._loadConfig();
    if (cfg.theme && cfg.theme !== themeSelector.value && PassifloraThemes.themeData[cfg.theme]) {
        themeSelector.value = cfg.theme;
    }
    for (const fs of fontSelectors) {
        const saved = cfg[fs.key];
        if (saved && PassifloraThemes.baseFontStackOptions[saved]) {
            const sel = document.getElementById(fs.id);
            sel.value = saved;
            applyFontVar(fs.cssVar, saved);
        }
    }
})();

} /* end PassifloraThemes guard */