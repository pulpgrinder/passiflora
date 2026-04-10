/* PassifloraMenu — sliding menu built at runtime from PassifloraConfig.menus
 *
 * Usage:
 *   <script src="passiflora/buildmenu.js"></script>
 *   PassifloraMenu.activate();        // show the top-level menu
 *   PassifloraMenu.deactivate();      // hide and reset
 *
 * Clicking a leaf item calls PassifloraConfig.handleMenu(title).
 * Clicking an item with children slides the child screen into view.
 * Each child screen has a "Back" header that slides back.
 */
const PassifloraMenu = (function () {
    "use strict";

    let overlay = null;   // dark backdrop
    let wrapper = null;   // contains all screens, clips overflow
    let screens = [];     // array of screen elements
    let depth = 0;        // current screen index

    /* ── DOM helpers ──────────────────────────────────────────── */
    function buildScreen(items, title) {
        const screen = document.createElement("div");
        screen.className = "passiflora_menu_screen";
        screen.addEventListener("click", function (e) {
            if (e.target === screen) deactivate();
        });

        if (title) {
            const back = document.createElement("div");
            back.className = "passiflora_menu_back";
            back.textContent = title;
            back.addEventListener("click", function () { slideBack(); });
            screen.appendChild(back);
        } else {
            /* Top-level screen: show a close bar with just the arrow */
            const close = document.createElement("div");
            close.className = "passiflora_menu_back";
            close.textContent = "\u00A0"; /* non-breaking space keeps the bar height */
            close.addEventListener("click", function () { deactivate(); });
            screen.appendChild(close);
        }

        const ul = document.createElement("ul");
        ul.className = "passiflora_menu";

        for (let i = 0; i < items.length; i++) {
            (function (item) {
                if (item.separator) {
                    const sep = document.createElement("li");
                    sep.className = "passiflora_menu_separator";
                    ul.appendChild(sep);
                    return;
                }

                const li = document.createElement("li");
                const hasChildren = item.items && item.items.length > 0;

                const label = document.createTextNode(item.title);
                li.appendChild(label);

                if (hasChildren) {
                    const arrow = document.createElement("span");
                    arrow.className = "passiflora_menu_arrow";
                    arrow.textContent = "\u276F";
                    li.appendChild(arrow);
                    li.addEventListener("click", function () {
                        slideForward(item.items, item.title);
                    });
                } else {
                    li.addEventListener("click", function () {
                        if (showPanel(item.title)) {
                            deactivateInstant();
                        } else {
                            deactivate();
                            if (PassifloraConfig && typeof PassifloraConfig.handleMenu === "function") {
                                PassifloraConfig.handleMenu(item.title);
                            }
                        }
                    });
                }

                ul.appendChild(li);
            })(items[i]);
        }

        screen.appendChild(ul);
        return screen;
    }

    /* Build the top-level list: one entry per menu, each with children */
    function topLevelItems() {
        const menus = (PassifloraConfig && PassifloraConfig.menus) || [];
        const out = [];
        for (let i = 0; i < menus.length; i++) {
            out.push({
                title: menus[i].title,
                items: menus[i].items || []
            });
        }
        return out;
    }

    /* ── Slide navigation ────────────────────────────────────── */
    function positionScreens() {
        for (let i = 0; i < screens.length; i++) {
            const offset = (i - depth) * 100;
            screens[i].style.transform = "translateX(" + offset + "%)";
        }
    }

    function slideForward(items, title) {
        /* Remove any screens beyond the current depth */
        while (screens.length > depth + 1) {
            const old = screens.pop();
            old.parentNode.removeChild(old);
        }

        const screen = buildScreen(items, title);
        screen.style.transform = "translateX(100%)";
        wrapper.querySelector(".passiflora_menu_track").appendChild(screen);
        screens.push(screen);

        /* Force a reflow so the transition fires */
        screen.offsetWidth; // jshint ignore:line
        depth++;
        positionScreens();
    }

    function slideBack() {
        if (depth <= 0) return;
        depth--;
        positionScreens();
        /* Remove the off-screen panel after the transition */
        const removed = screens.pop();
        setTimeout(function () {
            if (removed.parentNode) removed.parentNode.removeChild(removed);
        }, 300);
    }

    /* ── Public API ──────────────────────────────────────────── */
    function activate() {
        if (!overlay) {
            overlay = document.createElement("div");
            overlay.className = "passiflora_menu_overlay";
            overlay.addEventListener("click", deactivate);
            document.body.appendChild(overlay);
        }

        if (!wrapper) {
            wrapper = document.createElement("div");
            wrapper.className = "passiflora_menu_wrapper";

            const track = document.createElement("div");
            track.className = "passiflora_menu_track";
            track.addEventListener("click", function (e) {
                if (e.target === track) deactivate();
            });
            wrapper.appendChild(track);

            document.body.appendChild(wrapper);
        }

        /* Reset */
        const track = wrapper.querySelector(".passiflora_menu_track");
        track.innerHTML = "";
        screens = [];
        depth = 0;

        const root = buildScreen(topLevelItems(), null);
        root.style.transform = "translateX(0)";
        track.appendChild(root);
        screens.push(root);

        /* Force reflow then activate transitions */
        wrapper.offsetWidth; // jshint ignore:line
        overlay.classList.add("active");
        wrapper.classList.add("active");
        document.addEventListener("keydown", onKeyDown);
    }

    function deactivate() {
        if (overlay) overlay.classList.remove("active");
        if (wrapper) wrapper.classList.remove("active");
        document.removeEventListener("keydown", onKeyDown);
    }

    /* Hide menu instantly (no transition) — used when handing off to a panel */
    function deactivateInstant() {
        document.removeEventListener("keydown", onKeyDown);
        if (wrapper) {
            wrapper.style.transition = "none";
            wrapper.classList.remove("active");
            wrapper.offsetWidth; // jshint ignore:line
            wrapper.style.transition = "";
        }
        if (overlay) {
            overlay.style.transition = "none";
            overlay.classList.remove("active");
            overlay.offsetWidth; // jshint ignore:line
            overlay.style.transition = "";
        }
    }

    function onKeyDown(e) {
        if (e.key === "Escape" || e.keyCode === 27) {
            deactivate();
        }
    }

    /* Wire up hamburger click listener */
    document.addEventListener("DOMContentLoaded", function () {
        const hamburgers = [].slice.call(
            document.querySelectorAll(".hamburgermenu"));
        for (let i = 0; i < hamburgers.length; i++) {
            hamburgers[i].addEventListener("click", function () {
                activate();
            });
        }
    });

    /* ── Panel screens (menu-item → sliding full-screen panel) ─── */
    let panelOverlay = null;
    let panelWrapper = null;
    let panelBody = null;
    let activePanelSrc = null;

    function showPanel(id) {
        const src = document.getElementById(id);
        if (!src || !src.classList.contains("passiflora_menu_screen")) return false;

        if (!panelOverlay) {
            panelOverlay = document.createElement("div");
            panelOverlay.className = "passiflora_panel_overlay";
            panelOverlay.addEventListener("click", hidePanel);
            document.body.appendChild(panelOverlay);
        }

        if (!panelWrapper) {
            panelWrapper = document.createElement("div");
            panelWrapper.className = "passiflora_panel_wrapper";

            const back = document.createElement("div");
            back.className = "passiflora_menu_back";
            back.addEventListener("click", hidePanel);
            panelWrapper.appendChild(back);

            panelBody = document.createElement("div");
            panelBody.className = "passiflora_panel_body";
            panelWrapper.appendChild(panelBody);

            document.body.appendChild(panelWrapper);
        }

        /* Move live DOM nodes from the hidden source div into the panel
         * so that event listeners and populated content are preserved,
         * and duplicate element IDs are avoided. */
        panelWrapper.querySelector(".passiflora_menu_back").textContent = id;
        while (src.firstChild) {
            panelBody.appendChild(src.firstChild);
        }
        activePanelSrc = src;

        /* Force reflow then slide in */
        panelWrapper.offsetWidth; // jshint ignore:line
        panelOverlay.classList.add("active");
        panelWrapper.classList.add("active");

        document.addEventListener("keydown", onPanelKeyDown);
        return true;
    }

    function hidePanel() {
        if (panelOverlay) panelOverlay.classList.remove("active");
        if (panelWrapper) panelWrapper.classList.remove("active");

        /* Move nodes back to the hidden source div */
        if (activePanelSrc && panelBody) {
            while (panelBody.firstChild) {
                activePanelSrc.appendChild(panelBody.firstChild);
            }
        }
        activePanelSrc = null;
        document.removeEventListener("keydown", onPanelKeyDown);
    }

    function onPanelKeyDown(e) {
        if (e.key === "Escape" || e.keyCode === 27) {
            hidePanel();
        }
    }

    return {
        activate: activate,
        deactivate: deactivate,
        showPanel: showPanel,
        hidePanel: hidePanel
    };
})();
