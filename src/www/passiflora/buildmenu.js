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
                        deactivate();
                        if (PassifloraConfig && typeof PassifloraConfig.handleMenu === "function") {
                            PassifloraConfig.handleMenu(item.title);
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

    function onKeyDown(e) {
        if (e.key === "Escape" || e.keyCode === 27) {
            deactivate();
        }
    }

    /* ── Long-press to reveal hamburger ────────────────────── */
    const LONG_PRESS_MS = 500;   // hold duration to trigger
    const VISIBLE_MS   = 3000;   // how long hamburger stays visible
    let pressTimer   = null;
    let hideTimer    = null;
    let hamburgers   = [];

    const INTERACTIVE = "A,BUTTON,INPUT,SELECT,TEXTAREA,LABEL";
    function isInteractive(el) {
        while (el && el !== document.body) {
            if (el.matches && el.matches(INTERACTIVE)) return true;
            if (el.getAttribute && el.getAttribute("onclick")) return true;
            if (el.classList && el.classList.contains("hamburgermenu")) return true;
            el = el.parentNode;
        }
        return false;
    }

    function showHamburgers() {
        if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
        for (let i = 0; i < hamburgers.length; i++)
            hamburgers[i].classList.add("visible");
        hideTimer = setTimeout(hideHamburgers, VISIBLE_MS);
    }

    function hideHamburgers() {
        for (let i = 0; i < hamburgers.length; i++)
            hamburgers[i].classList.remove("visible");
        hideTimer = null;
    }

    function cancelPress() {
        if (pressTimer) { clearTimeout(pressTimer); pressTimer = null; }
    }

    function onPressStart(e) {
        const target = e.target || e.srcElement;
        if (isInteractive(target)) return;
        cancelPress();
        pressTimer = setTimeout(showHamburgers, LONG_PRESS_MS);
    }

    function onPressEnd() {
        cancelPress();
    }

    /* Wire up hamburger click + long-press listeners */
    document.addEventListener("DOMContentLoaded", function () {
        hamburgers = [].slice.call(
            document.querySelectorAll(".hamburgermenu"));
        for (let i = 0; i < hamburgers.length; i++) {
            hamburgers[i].addEventListener("click", function () {
                hideHamburgers();
                activate();
            });
        }

        /* Mouse long-press */
        document.addEventListener("mousedown",  onPressStart);
        document.addEventListener("mouseup",    onPressEnd);
        document.addEventListener("mouseleave", onPressEnd);

        /* Touch long-press */
        document.addEventListener("touchstart", onPressStart, {passive: true});
        document.addEventListener("touchend",   onPressEnd);
        document.addEventListener("touchcancel", onPressEnd);
    });

    return {
        activate: activate,
        deactivate: deactivate
    };
})();
