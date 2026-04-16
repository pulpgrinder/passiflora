/* ================================================================ *
 *  fileui.js  —  File-dialog UI for PassifloraIO                   *
 *  (menuOpen, menuSaveAs, fileBrowser and shared helpers)           *
 *                                                                   *
 *  Loaded AFTER PassifloraIO.js — extends the existing object.      *
 * ================================================================ */

Object.assign(PassifloraIO, {

    /* ================================================================ */
    /*  Long-press rename helper for file/folder list items             */
    /* ================================================================ */

    _attachLongPressRename: function (nameEl, oldName, isDir, prefix, dirPath, refreshFn) {
        const RENAME_MS = 500;
        let timer = null;
        let editing = false;

        function cancelTimer() {
            if (timer) { clearTimeout(timer); timer = null; }
        }

        function startEdit(e) {
            e.preventDefault();
            e.stopPropagation();
            cancelTimer();
            editing = true;

            nameEl.textContent = oldName;
            nameEl.contentEditable = "plaintext-only";
            if (nameEl.contentEditable !== "plaintext-only")
                nameEl.contentEditable = "true";
            nameEl.focus();

            const range = document.createRange();
            range.selectNodeContents(nameEl);
            const sel = window.getSelection();
            sel.removeAllRanges();
            sel.addRange(range);

            nameEl.addEventListener("blur", finishEdit, { once: true });
            nameEl.addEventListener("keydown", onEditKey);
        }

        function onEditKey(e) {
            if (e.key === "Enter" || e.keyCode === 13) {
                e.preventDefault();
                nameEl.blur();
            }
            if (e.key === "Escape" || e.keyCode === 27) {
                editing = false;
                nameEl.contentEditable = "false";
                nameEl.removeEventListener("keydown", onEditKey);
                nameEl.textContent = (prefix || "") + oldName;
            }
        }

        function finishEdit() {
            editing = false;
            nameEl.removeEventListener("keydown", onEditKey);
            nameEl.contentEditable = "false";

            const raw = nameEl.textContent || nameEl.innerText || "";
            const newName = raw.replace(/[\r\n]+/g, " ").replace(/\s+/g, " ").trim();

            nameEl.textContent = (prefix || "") + (newName || oldName);

            if (!newName || newName === oldName) return;

            const sep = "/";
            function joinPath(dir, name) {
                if (dir.charAt(dir.length - 1) === sep) return dir + name;
                return dir + sep + name;
            }
            const oldPath = joinPath(dirPath, oldName);
            const newPath = joinPath(dirPath, newName);

            PassifloraIO.rename(oldPath, newPath).then(function () {
                if (refreshFn) refreshFn();
            }).catch(function () {
                nameEl.textContent = (prefix || "") + oldName;
            });
        }

        /* Suppress clicks while in edit mode — prevents the li click
           handler from firing when the long-press touchend/mouseup
           generates a click event. */
        nameEl.addEventListener("click", function (e) {
            if (editing) { e.stopPropagation(); e.preventDefault(); }
        });

        nameEl.addEventListener("touchstart", function (e) {
            cancelTimer();
            timer = setTimeout(function () { startEdit(e); }, RENAME_MS);
        }, { passive: false });
        nameEl.addEventListener("touchend", cancelTimer);
        nameEl.addEventListener("touchcancel", cancelTimer);
        nameEl.addEventListener("touchmove", cancelTimer);

        nameEl.addEventListener("mousedown", function (e) {
            cancelTimer();
            timer = setTimeout(function () { startEdit(e); }, RENAME_MS);
        });
        nameEl.addEventListener("mouseup", cancelTimer);
        nameEl.addEventListener("mouseleave", cancelTimer);
    },

    /* ================================================================ */
    /*  Shared file-dialog helpers (used by menuOpen & menuSaveAs)      */
    /* ================================================================ */

    _prepareExts: function (extensions) {
        if (!extensions) extensions = [];
        const extsLower = [];
        for (let i = 0; i < extensions.length; i++)
            extsLower.push(extensions[i].toLowerCase().replace(/^\./, ""));
        let extLabel = "";
        if (extensions.length > 0) {
            const parts = [];
            for (let i = 0; i < extensions.length; i++)
                parts.push("*." + extsLower[i]);
            extLabel = parts.join(", ");
        } else {
            extLabel = "All files (*.*)";
        }
        return { extsLower: extsLower, extLabel: extLabel };
    },

    _fileMatchesExt: function (name, filterAll, exts) {
        if (filterAll) return true;
        if (exts.length === 0) return true;
        const dot = name.lastIndexOf(".");
        if (dot < 0) return false;
        const ext = name.substring(dot + 1).toLowerCase();
        for (let i = 0; i < exts.length; i++)
            if (ext === exts[i]) return true;
        return false;
    },

    _joinPath: function (dir, name) {
        if (dir.charAt(dir.length - 1) === "/") return dir + name;
        return dir + "/" + name;
    },

    _shortPath: function (p) {
        return p.length > 20 ? "\u2026" + p.slice(-20) : p;
    },

    _initFileDialogDOM: function (finish) {
        /* Remove any leftover elements from a previous call */
        const stale = document.querySelectorAll(
            ".passiflora_fo_overlay, .passiflora_fo_wrapper");
        for (let si = 0; si < stale.length; si++)
            stale[si].parentNode.removeChild(stale[si]);

        const prevOverflow = document.documentElement.style.overflowY;
        document.documentElement.style.overflowY = "scroll";

        const overlay = document.createElement("div");
        overlay.className = "passiflora_fo_overlay";
        overlay.addEventListener("click", function () { finish(null); });
        document.body.appendChild(overlay);

        const wrapper = document.createElement("div");
        wrapper.className = "passiflora_fo_wrapper";

        function onKey(e) {
            if (e.key === "Escape" || e.keyCode === 27) {
                finish(null);
            }
        }

        function teardown() {
            if (overlay && overlay.parentNode) {
                overlay.classList.remove("active");
                setTimeout(function () {
                    if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
                }, 300);
            }
            if (wrapper && wrapper.parentNode) {
                wrapper.classList.remove("active");
                setTimeout(function () {
                    if (wrapper.parentNode) wrapper.parentNode.removeChild(wrapper);
                }, 300);
            }
            document.removeEventListener("keydown", onKey);
            document.documentElement.style.overflowY = prevOverflow;
        }

        return {
            overlay: overlay,
            wrapper: wrapper,
            teardown: teardown,
            onKey: onKey
        };
    },

    _slidePositionScreens: function (screens, depth) {
        for (let i = 0; i < screens.length; i++) {
            const off = (i - depth) * 100;
            screens[i].style.transform = "translateX(" + off + "%)";
        }
    },

    /* ================================================================ */
    /*  File-open sliding menu                                          */
    /* ================================================================ */

    menuOpen: function (extensions, defaultFolder) {
        /* Normalise arguments */
        if (!extensions) extensions = [];
        if (!defaultFolder) defaultFolder = "";

        const extInfo = PassifloraIO._prepareExts(extensions);
        const extsLower = extInfo.extsLower;
        const extLabel = extInfo.extLabel;

        /* ---- DOM builder ---- */
        return (defaultFolder
            ? Promise.resolve(defaultFolder)
            : PassifloraIO.getHomeFolder()
        ).then(function (startDir) {

            return new Promise(function (resolve) {

                let overlay = null;
                let wrapper = null;
                const screens = [];
                let depth = 0;
                let initialDepth = 0;   /* depth of the very first screen */
                let filterAll = false;   /* true when "All files" selected */
                let resolved = false;

                function finish(value) {
                    if (resolved) return;
                    resolved = true;
                    teardown();
                    resolve(value);
                }

                /* -- slide helpers -- */
                function positionScreens() {
                    PassifloraIO._slidePositionScreens(screens, depth);
                }

                function slideForward(screen) {
                    while (screens.length > depth + 1) {
                        const old = screens.pop();
                        if (old.parentNode) old.parentNode.removeChild(old);
                    }
                    screen.style.transform = "translateX(100%)";
                    wrapper.querySelector(".passiflora_fo_track").appendChild(screen);
                    screens.push(screen);
                    screen.offsetWidth; /* reflow */
                    depth++;
                    positionScreens();
                }

                function slideBack() {
                    if (depth <= initialDepth) {
                        finish(null);
                        return;
                    }
                    depth--;
                    positionScreens();
                    const removed = screens.pop();
                    setTimeout(function () {
                        if (removed.parentNode) removed.parentNode.removeChild(removed);
                    }, 300);
                }

                function buildDirScreen(dirPath, title) {
                    const screen = document.createElement("div");
                    screen.className = "passiflora_fo_screen";

                    /* Back header */
                    const back = document.createElement("div");
                    back.className = "passiflora_fo_back";
                    back.textContent = title || PassifloraIO._shortPath(dirPath);
                    back.addEventListener("click", function () { slideBack(); });
                    screen.appendChild(back);

                    /* File list (placeholder while loading) */
                    const listWrap = document.createElement("div");
                    listWrap.className = "passiflora_fo_list";
                    const loadingMsg = document.createElement("div");
                    loadingMsg.className = "passiflora_fo_loading";
                    loadingMsg.textContent = "Loading\u2026";
                    listWrap.appendChild(loadingMsg);
                    screen.appendChild(listWrap);

                    /* Extension filter select */
                    const filterRow = document.createElement("div");
                    filterRow.className = "passiflora_fo_filterbar";
                    const sel = document.createElement("select");
                    sel.className = "passiflora_fo_select";
                    if (extensions.length > 0) {
                        const opt1 = document.createElement("option");
                        opt1.value = "ext";
                        opt1.textContent = extLabel;
                        sel.appendChild(opt1);
                    }
                    const opt2 = document.createElement("option");
                    opt2.value = "all";
                    opt2.textContent = "All files (*.*)";
                    sel.appendChild(opt2);
                    if (extensions.length === 0) sel.value = "all";
                    else sel.value = filterAll ? "all" : "ext";
                    sel.addEventListener("change", function () {
                        filterAll = (sel.value === "all");
                        populateList();
                    });
                    filterRow.appendChild(sel);

                    const newDirBtn = document.createElement("button");
                    newDirBtn.className = "passiflora_fo_newdir";
                    newDirBtn.textContent = "\uD83D\uDCC1+";
                    newDirBtn.title = "Create Folder";
                    newDirBtn.addEventListener("click", function () {
                        const base = "Untitled";
                        const taken = {};
                        if (entries) {
                            for (let ti = 0; ti < entries.length; ti++)
                                taken[entries[ti].name] = true;
                        }
                        let name = base;
                        let n = 2;
                        while (taken[name]) { name = base + " " + n; n++; }
                        const newPath = dirPath === "/" ? "/" + name : dirPath + "/" + name;
                        PassifloraIO.mkdir(newPath).then(function () {
                            return PassifloraIO.listDirectory(dirPath);
                        }).then(function (list) {
                            entries = list;
                            populateList();
                        });
                    });
                    filterRow.appendChild(newDirBtn);
                    screen.appendChild(filterRow);

                    /* Fetch directory listing and populate */
                    let entries = null;

                    function populateList() {
                        if (!entries) return;
                        listWrap.innerHTML = "";
                        const ul = document.createElement("ul");
                        ul.className = "passiflora_fo_ul";

                        function refreshDir() {
                            PassifloraIO.listDirectory(dirPath).then(function (list) {
                                entries = list;
                                populateList();
                            });
                        }

                        /* ".." entry — go up a folder (only if not at root) */
                        if (dirPath !== "/") {
                            const upLi = document.createElement("li");
                            upLi.className = "passiflora_fo_item passiflora_fo_dir";
                            upLi.textContent = "\uD83D\uDCC1 ..";
                            const upArrow = document.createElement("span");
                            upArrow.className = "passiflora_fo_arrow";
                            upArrow.textContent = "\u276E";
                            upLi.appendChild(upArrow);
                            upLi.addEventListener("click", function () { slideBack(); });
                            ul.appendChild(upLi);
                        }

                        /* Sort: directories first, then alphabetical */
                        const dirs = [], files = [];
                        for (let i = 0; i < entries.length; i++) {
                            if (entries[i].name === "..") continue;
                            if (entries[i].isDir) dirs.push(entries[i]);
                            else files.push(entries[i]);
                        }
                        dirs.sort(function (a, b) { return a.name.localeCompare(b.name); });
                        files.sort(function (a, b) { return a.name.localeCompare(b.name); });

                        for (let i = 0; i < dirs.length; i++) {
                            (function (ent) {
                                const li = document.createElement("li");
                                li.className = "passiflora_fo_item passiflora_fo_dir";
                                const nameSpan = document.createElement("span");
                                nameSpan.textContent = "\uD83D\uDCC1 " + ent.name;
                                li.appendChild(nameSpan);
                                const arrow = document.createElement("span");
                                arrow.className = "passiflora_fo_arrow";
                                arrow.textContent = "\u276F";
                                li.appendChild(arrow);
                                li.addEventListener("click", function () {
                                    const sub = PassifloraIO._joinPath(dirPath, ent.name);
                                    const newScreen = buildDirScreen(sub, ent.name);
                                    slideForward(newScreen);
                                });
                                PassifloraIO._attachLongPressRename(
                                    nameSpan, ent.name, true,
                                    "\uD83D\uDCC1 ", dirPath, refreshDir);
                                ul.appendChild(li);
                            })(dirs[i]);
                        }

                        for (let i = 0; i < files.length; i++) {
                            (function (ent) {
                                const li = document.createElement("li");
                                const matches = PassifloraIO._fileMatchesExt(
                                    ent.name, filterAll, extsLower);
                                li.className = "passiflora_fo_item passiflora_fo_file" +
                                    (matches ? " passiflora_fo_match" : " passiflora_fo_dim");
                                const nameSpan = document.createElement("span");
                                nameSpan.textContent = ent.name;
                                li.appendChild(nameSpan);
                                if (matches) {
                                    li.addEventListener("click", function () {
                                        finish(PassifloraIO._joinPath(dirPath, ent.name));
                                    });
                                }
                                PassifloraIO._attachLongPressRename(
                                    nameSpan, ent.name, false,
                                    "", dirPath, refreshDir);
                                ul.appendChild(li);
                            })(files[i]);
                        }

                        listWrap.appendChild(ul);
                    }

                    PassifloraIO.listDirectory(dirPath).then(function (list) {
                        entries = list;
                        populateList();
                    }).catch(function () {
                        listWrap.innerHTML = "";
                        const err = document.createElement("div");
                        err.className = "passiflora_fo_loading";
                        err.textContent = "Cannot read directory.";
                        listWrap.appendChild(err);
                    });

                    return screen;
                }

                /* -- init DOM via shared helper -- */
                const dom = PassifloraIO._initFileDialogDOM(finish);
                overlay = dom.overlay;
                wrapper = dom.wrapper;
                const teardown = dom.teardown;

                const track = document.createElement("div");
                track.className = "passiflora_fo_track";
                wrapper.appendChild(track);
                document.body.appendChild(wrapper);

                /* Build and show the root screen */
                const rootScreen = buildDirScreen(startDir, null);
                rootScreen.style.transform = "translateX(0)";
                track.appendChild(rootScreen);
                screens.push(rootScreen);
                initialDepth = 0;

                /* Trigger transitions */
                wrapper.offsetWidth; /* reflow */
                overlay.classList.add("active");
                wrapper.classList.add("active");
                document.addEventListener("keydown", dom.onKey);
            });
        });
    },

    /* ================================================================ */
    /*  Save-As sliding menu                                            */
    /* ================================================================ */

    menuSaveAs: function (extensions, defaultName) {
        /* Normalise arguments */
        if (!extensions) extensions = [];
        if (!defaultName) defaultName = "";

        const extInfo = PassifloraIO._prepareExts(extensions);
        const extsLower = extInfo.extsLower;
        const extLabel = extInfo.extLabel;

        function nameHasMatchingExt(name, exts) {
            return PassifloraIO._fileMatchesExt(name, false, exts);
        }

        /* ---- DOM builder ---- */
        return PassifloraIO.getHomeFolder().then(function (startDir) {

            return new Promise(function (resolve) {

                const screens = [];
                let depth = 0;
                let initialDepth = 0;
                let filterAll = false;
                let resolved = false;
                let currentDir = startDir;
                let currentFiles = [];       /* file names in the visible directory */
                let nameInput = null;        /* the filename text field */

                function finish(value) {
                    if (resolved) return;
                    resolved = true;
                    teardown();
                    resolve(value);
                }

                /* -- init DOM via shared helper -- */
                const dom = PassifloraIO._initFileDialogDOM(finish);
                const overlay = dom.overlay;
                const wrapper = dom.wrapper;
                const teardown = dom.teardown;

                /* -- confirm dialog -- */
                function showConfirm(message) {
                    return new Promise(function (yes) {
                        const box = document.createElement("div");
                        box.className = "passiflora_fo_confirm_overlay";

                        const card = document.createElement("div");
                        card.className = "passiflora_fo_confirm_card";

                        const msg = document.createElement("div");
                        msg.className = "passiflora_fo_confirm_msg";
                        msg.textContent = message;
                        card.appendChild(msg);

                        const btns = document.createElement("div");
                        btns.className = "passiflora_fo_confirm_btns";

                        const cancelBtn = document.createElement("button");
                        cancelBtn.className = "passiflora_fo_confirm_btn";
                        cancelBtn.textContent = "Cancel";
                        cancelBtn.addEventListener("click", function () {
                            box.parentNode.removeChild(box);
                            yes(false);
                        });
                        btns.appendChild(cancelBtn);

                        const okBtn = document.createElement("button");
                        okBtn.className = "passiflora_fo_confirm_btn passiflora_fo_confirm_ok";
                        okBtn.textContent = "OK";
                        okBtn.addEventListener("click", function () {
                            box.parentNode.removeChild(box);
                            yes(true);
                        });
                        btns.appendChild(okBtn);

                        card.appendChild(btns);
                        box.appendChild(card);
                        wrapper.appendChild(box);
                    });
                }

                /* -- attempt to save -- */
                function trySave() {
                    const name = (nameInput.value || "").trim();
                    if (!name) return;
                    const fullPath = PassifloraIO._joinPath(currentDir, name);

                    /* Does the file already exist in the current listing? */
                    let exists = false;
                    for (let ei = 0; ei < currentFiles.length; ei++) {
                        if (currentFiles[ei] === name) { exists = true; break; }
                    }
                    const badExt = !nameHasMatchingExt(name, extsLower);

                    if (badExt && exists) {
                        showConfirm(
                            "\"" + name + "\" does not have one of the expected extensions (" +
                            extLabel + "). Save anyway?"
                        ).then(function (ok) {
                            if (!ok) return;
                            return showConfirm(
                                "\"" + name + "\" already exists. Overwrite?"
                            );
                        }).then(function (ok) {
                            if (ok) finish(fullPath);
                        });
                        return;
                    }
                    if (badExt) {
                        showConfirm(
                            "\"" + name + "\" does not have one of the expected extensions (" +
                            extLabel + "). Save anyway?"
                        ).then(function (ok) {
                            if (ok) finish(fullPath);
                        });
                        return;
                    }
                    if (exists) {
                        showConfirm(
                            "\"" + name + "\" already exists. Overwrite?"
                        ).then(function (ok) {
                            if (ok) finish(fullPath);
                        });
                        return;
                    }

                    finish(fullPath);
                }

                /* -- slide helpers -- */
                /* -- slide helpers -- */
                function positionScreens() {
                    PassifloraIO._slidePositionScreens(screens, depth);
                }

                function slideForward(screen) {
                    while (screens.length > depth + 1) {
                        const old = screens.pop();
                        if (old.parentNode) old.parentNode.removeChild(old);
                    }
                    screen.style.transform = "translateX(100%)";
                    wrapper.querySelector(".passiflora_fo_track").appendChild(screen);
                    screens.push(screen);
                    screen.offsetWidth;
                    depth++;
                    positionScreens();
                }

                function slideBack() {
                    if (depth <= initialDepth) {
                        finish(null);
                        return;
                    }
                    depth--;
                    positionScreens();
                    const removed = screens.pop();
                    setTimeout(function () {
                        if (removed.parentNode) removed.parentNode.removeChild(removed);
                    }, 300);
                }

                /* -- build a screen for a directory -- */
                function buildDirScreen(dirPath, title) {
                    const screen = document.createElement("div");
                    screen.className = "passiflora_fo_screen";

                    /* Back header */
                    const back = document.createElement("div");
                    back.className = "passiflora_fo_back";
                    back.textContent = title || PassifloraIO._shortPath(dirPath);
                    back.addEventListener("click", function () { slideBack(); });
                    screen.appendChild(back);

                    /* File list */
                    const listWrap = document.createElement("div");
                    listWrap.className = "passiflora_fo_list";
                    const loadingMsg = document.createElement("div");
                    loadingMsg.className = "passiflora_fo_loading";
                    loadingMsg.textContent = "Loading\u2026";
                    listWrap.appendChild(loadingMsg);
                    screen.appendChild(listWrap);

                    /* Extension filter select */
                    const filterRow = document.createElement("div");
                    filterRow.className = "passiflora_fo_filterbar";
                    const sel = document.createElement("select");
                    sel.className = "passiflora_fo_select";
                    if (extensions.length > 0) {
                        const opt1 = document.createElement("option");
                        opt1.value = "ext";
                        opt1.textContent = extLabel;
                        sel.appendChild(opt1);
                    }
                    const opt2 = document.createElement("option");
                    opt2.value = "all";
                    opt2.textContent = "All files (*.*)";
                    sel.appendChild(opt2);
                    if (extensions.length === 0) sel.value = "all";
                    else sel.value = filterAll ? "all" : "ext";
                    sel.addEventListener("change", function () {
                        filterAll = (sel.value === "all");
                        populateList();
                    });
                    filterRow.appendChild(sel);

                    const newDirBtn = document.createElement("button");
                    newDirBtn.className = "passiflora_fo_newdir";
                    newDirBtn.textContent = "\uD83D\uDCC1+";
                    newDirBtn.title = "Create Folder";
                    newDirBtn.addEventListener("click", function () {
                        const base = "Untitled";
                        const taken = {};
                        if (entries) {
                            for (let ti = 0; ti < entries.length; ti++)
                                taken[entries[ti].name] = true;
                        }
                        let name = base;
                        let n = 2;
                        while (taken[name]) { name = base + " " + n; n++; }
                        const newPath = dirPath === "/" ? "/" + name : dirPath + "/" + name;
                        PassifloraIO.mkdir(newPath).then(function () {
                            return PassifloraIO.listDirectory(dirPath);
                        }).then(function (list) {
                            entries = list;
                            currentFiles = [];
                            for (let fi = 0; fi < list.length; fi++) {
                                if (!list[fi].isDir) currentFiles.push(list[fi].name);
                            }
                            populateList();
                        });
                    });
                    filterRow.appendChild(newDirBtn);
                    screen.appendChild(filterRow);

                    /* Fetch directory listing and populate */
                    let entries = null;

                    function populateList() {
                        if (!entries) return;
                        listWrap.innerHTML = "";
                        const ul = document.createElement("ul");
                        ul.className = "passiflora_fo_ul";

                        function refreshDir() {
                            PassifloraIO.listDirectory(dirPath).then(function (list) {
                                entries = list;
                                currentFiles = [];
                                for (let fi = 0; fi < list.length; fi++) {
                                    if (!list[fi].isDir) currentFiles.push(list[fi].name);
                                }
                                populateList();
                            });
                        }

                        /* ".." entry (only if not at root) */
                        if (dirPath !== "/") {
                            const upLi = document.createElement("li");
                            upLi.className = "passiflora_fo_item passiflora_fo_dir";
                            upLi.textContent = "\uD83D\uDCC1 ..";
                            const upArrow = document.createElement("span");
                            upArrow.className = "passiflora_fo_arrow";
                            upArrow.textContent = "\u276E";
                            upLi.appendChild(upArrow);
                            upLi.addEventListener("click", function () { slideBack(); });
                            ul.appendChild(upLi);
                        }

                        /* Sort: directories first, then alphabetical */
                        const dirs = [], files = [];
                        for (let i = 0; i < entries.length; i++) {
                            if (entries[i].name === "..") continue;
                            if (entries[i].isDir) dirs.push(entries[i]);
                            else files.push(entries[i]);
                        }
                        dirs.sort(function (a, b) { return a.name.localeCompare(b.name); });
                        files.sort(function (a, b) { return a.name.localeCompare(b.name); });

                        for (let i = 0; i < dirs.length; i++) {
                            (function (ent) {
                                const li = document.createElement("li");
                                li.className = "passiflora_fo_item passiflora_fo_dir";
                                const nameSpan = document.createElement("span");
                                nameSpan.textContent = "\uD83D\uDCC1 " + ent.name;
                                li.appendChild(nameSpan);
                                const arrow = document.createElement("span");
                                arrow.className = "passiflora_fo_arrow";
                                arrow.textContent = "\u276F";
                                li.appendChild(arrow);
                                li.addEventListener("click", function () {
                                    const sub = PassifloraIO._joinPath(dirPath, ent.name);
                                    currentDir = sub;
                                    const newScreen = buildDirScreen(sub, ent.name);
                                    slideForward(newScreen);
                                });
                                PassifloraIO._attachLongPressRename(
                                    nameSpan, ent.name, true,
                                    "\uD83D\uDCC1 ", dirPath, refreshDir);
                                ul.appendChild(li);
                            })(dirs[i]);
                        }

                        for (let i = 0; i < files.length; i++) {
                            (function (ent) {
                                const li = document.createElement("li");
                                const matches = PassifloraIO._fileMatchesExt(
                                    ent.name, filterAll, extsLower);
                                li.className = "passiflora_fo_item passiflora_fo_file" +
                                    (matches ? " passiflora_fo_match" : " passiflora_fo_dim");
                                const nameSpan = document.createElement("span");
                                nameSpan.textContent = ent.name;
                                li.appendChild(nameSpan);
                                /* Clicking an existing file = overwrite + extension confirm */
                                li.addEventListener("click", function () {
                                    nameInput.value = ent.name;
                                    const badExt = !nameHasMatchingExt(ent.name, extsLower);
                                    let p = Promise.resolve(true);
                                    if (badExt) {
                                        p = showConfirm(
                                            "\"" + ent.name + "\" does not have one of the expected extensions (" +
                                            extLabel + "). Save anyway?"
                                        );
                                    }
                                    p.then(function (ok) {
                                        if (!ok) return;
                                        return showConfirm(
                                            "\"" + ent.name + "\" already exists. Overwrite?"
                                        );
                                    }).then(function (ok) {
                                        if (ok) finish(PassifloraIO._joinPath(dirPath, ent.name));
                                    });
                                });
                                PassifloraIO._attachLongPressRename(
                                    nameSpan, ent.name, false,
                                    "", dirPath, refreshDir);
                                ul.appendChild(li);
                            })(files[i]);
                        }

                        listWrap.appendChild(ul);
                    }

                    /* Track the current directory when this screen becomes active */
                    screen.addEventListener("transitionend", function () {
                        const r = screen.getBoundingClientRect();
                        if (r.left >= 0 && r.left < 5) currentDir = dirPath;
                    });

                    PassifloraIO.listDirectory(dirPath).then(function (list) {
                        currentDir = dirPath;
                        entries = list;
                        /* Update shared file-name list for trySave's overwrite check */
                        currentFiles = [];
                        for (let fi = 0; fi < list.length; fi++) {
                            if (!list[fi].isDir) currentFiles.push(list[fi].name);
                        }
                        populateList();
                    }).catch(function () {
                        listWrap.innerHTML = "";
                        const err = document.createElement("div");
                        err.className = "passiflora_fo_loading";
                        err.textContent = "Cannot read directory.";
                        listWrap.appendChild(err);
                    });

                    return screen;
                }

                /* Filename input bar at the top */
                const nameBar = document.createElement("div");
                nameBar.className = "passiflora_fo_namebar";

                nameInput = document.createElement("input");
                nameInput.type = "text";
                nameInput.className = "passiflora_fo_nameinput";
                nameInput.placeholder = "Filename";
                nameInput.value = defaultName;
                nameBar.appendChild(nameInput);

                const saveBtn = document.createElement("button");
                saveBtn.className = "passiflora_fo_savebtn";
                saveBtn.textContent = "Save";
                saveBtn.addEventListener("click", function () { trySave(); });
                nameBar.appendChild(saveBtn);

                wrapper.appendChild(nameBar);

                const track = document.createElement("div");
                track.className = "passiflora_fo_track";
                wrapper.appendChild(track);
                document.body.appendChild(wrapper);

                /* Build and show the root screen */
                const rootScreen = buildDirScreen(startDir, null);
                rootScreen.style.transform = "translateX(0)";
                track.appendChild(rootScreen);
                screens.push(rootScreen);
                initialDepth = 0;

                /* Trigger transitions */
                wrapper.offsetWidth;
                overlay.classList.add("active");
                wrapper.classList.add("active");
                document.addEventListener("keydown", dom.onKey);

                /* Enter key in the filename field triggers Save */
                nameInput.addEventListener("keydown", function (e) {
                    if (e.key === "Enter" || e.keyCode === 13) {
                        e.preventDefault();
                        e.stopPropagation();
                        trySave();
                    }
                });
            });
        });
    },

    /* ================================================================ */
    /*  File Browser                                                    */
    /* ================================================================ */

    _fileBrowserDir: null,   /* remembered across invocations */

    fileBrowser: function (extensions, defaultFolder) {
        if (!extensions) extensions = [];
        if (!defaultFolder) defaultFolder = "";

        const extInfo = PassifloraIO._prepareExts(extensions);
        const extsLower = extInfo.extsLower;
        const extLabel  = extInfo.extLabel;

        /* Determine start directory: remembered > supplied > home */
        let startPromise;
        if (PassifloraIO._fileBrowserDir) {
            startPromise = Promise.resolve(PassifloraIO._fileBrowserDir);
        } else if (defaultFolder) {
            startPromise = Promise.resolve(defaultFolder);
        } else {
            startPromise = PassifloraIO.getHomeFolder();
        }

        return startPromise.then(function (startDir) {

            return new Promise(function (resolve) {

                let overlay  = null;
                let wrapper  = null;
                const screens  = [];
                let depth    = 0;
                let initialDepth = 0;
                let filterAll = false;
                let resolved  = false;
                let currentDir = startDir;
                let selectedLi = null;          /* currently highlighted <li> */

                function finish(value) {
                    if (resolved) return;
                    resolved = true;
                    PassifloraIO._fileBrowserDir = currentDir;
                    teardown();
                    resolve(value);
                }

                /* -- slide helpers -- */
                function positionScreens() {
                    PassifloraIO._slidePositionScreens(screens, depth);
                }

                function slideForward(screen) {
                    while (screens.length > depth + 1) {
                        const old = screens.pop();
                        if (old.parentNode) old.parentNode.removeChild(old);
                    }
                    screen.style.transform = "translateX(100%)";
                    wrapper.querySelector(".passiflora_fo_track").appendChild(screen);
                    screens.push(screen);
                    screen.offsetWidth; /* reflow */
                    depth++;
                    positionScreens();
                }

                function slideBack() {
                    if (depth <= initialDepth) {
                        finish(null);
                        return;
                    }
                    depth--;
                    positionScreens();
                    const removed = screens.pop();
                    setTimeout(function () {
                        if (removed.parentNode) removed.parentNode.removeChild(removed);
                    }, 300);
                }

                /* -- highlight helper -- */
                function highlightItem(li) {
                    if (selectedLi) selectedLi.classList.remove("passiflora_fb_selected");
                    selectedLi = li;
                    if (li) li.classList.add("passiflora_fb_selected");
                }

                /* -- move a file into a directory via the file system -- */
                function moveFile(fileName, fromDir, toDir, refreshFn) {
                    const oldPath = PassifloraIO._joinPath(fromDir, fileName);
                    const newPath = PassifloraIO._joinPath(toDir, fileName);
                    PassifloraIO.rename(oldPath, newPath).then(function () {
                        if (refreshFn) refreshFn();
                    }).catch(function () {
                        /* rename failed — silently ignore */
                    });
                }

                /* -- build a screen for a directory -- */
                function buildDirScreen(dirPath, title) {
                    const screen = document.createElement("div");
                    screen.className = "passiflora_fo_screen";

                    /* Back header */
                    const back = document.createElement("div");
                    back.className = "passiflora_fo_back";
                    back.textContent = title || PassifloraIO._shortPath(dirPath);
                    back.addEventListener("click", function () { slideBack(); });
                    screen.appendChild(back);

                    /* File list */
                    const listWrap = document.createElement("div");
                    listWrap.className = "passiflora_fo_list";
                    const loadingMsg = document.createElement("div");
                    loadingMsg.className = "passiflora_fo_loading";
                    loadingMsg.textContent = "Loading\u2026";
                    listWrap.appendChild(loadingMsg);
                    screen.appendChild(listWrap);

                    /* Filter bar + Create Folder + Done */
                    const filterRow = document.createElement("div");
                    filterRow.className = "passiflora_fo_filterbar";

                    const sel = document.createElement("select");
                    sel.className = "passiflora_fo_select";
                    if (extensions.length > 0) {
                        const opt1 = document.createElement("option");
                        opt1.value = "ext";
                        opt1.textContent = extLabel;
                        sel.appendChild(opt1);
                    }
                    const opt2 = document.createElement("option");
                    opt2.value = "all";
                    opt2.textContent = "All files (*.*)";
                    sel.appendChild(opt2);
                    if (extensions.length === 0) sel.value = "all";
                    else sel.value = filterAll ? "all" : "ext";
                    sel.addEventListener("change", function () {
                        filterAll = (sel.value === "all");
                        populateList();
                    });
                    filterRow.appendChild(sel);

                    const newDirBtn = document.createElement("button");
                    newDirBtn.className = "passiflora_fo_newdir";
                    newDirBtn.textContent = "\uD83D\uDCC1+";
                    newDirBtn.title = "Create Folder";
                    newDirBtn.addEventListener("click", function () {
                        const base = "Untitled";
                        const taken = {};
                        if (entries) {
                            for (let ti = 0; ti < entries.length; ti++)
                                taken[entries[ti].name] = true;
                        }
                        let name = base;
                        let n = 2;
                        while (taken[name]) { name = base + " " + n; n++; }
                        const newPath = dirPath === "/" ? "/" + name : dirPath + "/" + name;
                        PassifloraIO.mkdir(newPath).then(function () {
                            return PassifloraIO.listDirectory(dirPath);
                        }).then(function (list) {
                            entries = list;
                            populateList();
                        });
                    });
                    filterRow.appendChild(newDirBtn);

                    const doneBtn = document.createElement("button");
                    doneBtn.className = "passiflora_fo_newdir";
                    doneBtn.textContent = "Done";
                    doneBtn.addEventListener("click", function () { finish(null); });
                    filterRow.appendChild(doneBtn);

                    screen.appendChild(filterRow);

                    /* Fetch directory listing and populate */
                    let entries = null;

                    function populateList() {
                        if (!entries) return;
                        listWrap.innerHTML = "";
                        const ul = document.createElement("ul");
                        ul.className = "passiflora_fo_ul";

                        function refreshDir() {
                            PassifloraIO.listDirectory(dirPath).then(function (list) {
                                entries = list;
                                populateList();
                            });
                        }

                        /* ".." entry — go up (doubles as drop target for parent) */
                        if (dirPath !== "/") {
                            const upLi = document.createElement("li");
                            upLi.className = "passiflora_fo_item passiflora_fo_dir";
                            upLi.textContent = "\uD83D\uDCC1 ..";
                            const upArrow = document.createElement("span");
                            upArrow.className = "passiflora_fo_arrow";
                            upArrow.textContent = "\u276E";
                            upLi.appendChild(upArrow);
                            upLi.addEventListener("click", function () { slideBack(); });

                            /* Drop target: move file to parent directory */
                            upLi.addEventListener("dragover", function (e) {
                                e.preventDefault();
                                e.dataTransfer.dropEffect = "move";
                                upLi.classList.add("passiflora_fb_dragover");
                            });
                            upLi.addEventListener("dragleave", function () {
                                upLi.classList.remove("passiflora_fb_dragover");
                            });
                            upLi.addEventListener("drop", function (e) {
                                e.preventDefault();
                                upLi.classList.remove("passiflora_fb_dragover");
                                const fileName = e.dataTransfer.getData("text/plain");
                                if (!fileName) return;
                                const parentDir = dirPath.replace(/\/[^\/]+$/, "") || "/";
                                moveFile(fileName, dirPath, parentDir, refreshDir);
                            });

                            ul.appendChild(upLi);
                        }

                        /* Sort: directories first, then alphabetical */
                        const dirs = [], files = [];
                        for (let i = 0; i < entries.length; i++) {
                            if (entries[i].name === "..") continue;
                            if (entries[i].isDir) dirs.push(entries[i]);
                            else files.push(entries[i]);
                        }
                        dirs.sort(function (a, b) { return a.name.localeCompare(b.name); });
                        files.sort(function (a, b) { return a.name.localeCompare(b.name); });

                        for (let di = 0; di < dirs.length; di++) {
                            (function (ent) {
                                const li = document.createElement("li");
                                li.className = "passiflora_fo_item passiflora_fo_dir";
                                const nameSpan = document.createElement("span");
                                nameSpan.textContent = "\uD83D\uDCC1 " + ent.name;
                                li.appendChild(nameSpan);
                                const arrow = document.createElement("span");
                                arrow.className = "passiflora_fo_arrow";
                                arrow.textContent = "\u276F";
                                li.appendChild(arrow);
                                li.addEventListener("click", function () {
                                    const sub = PassifloraIO._joinPath(dirPath, ent.name);
                                    currentDir = sub;
                                    const newScreen = buildDirScreen(sub, ent.name);
                                    slideForward(newScreen);
                                });

                                /* Drop target: move file into this subfolder */
                                li.addEventListener("dragover", function (e) {
                                    e.preventDefault();
                                    e.dataTransfer.dropEffect = "move";
                                    li.classList.add("passiflora_fb_dragover");
                                });
                                li.addEventListener("dragleave", function () {
                                    li.classList.remove("passiflora_fb_dragover");
                                });
                                li.addEventListener("drop", function (e) {
                                    e.preventDefault();
                                    li.classList.remove("passiflora_fb_dragover");
                                    const fileName = e.dataTransfer.getData("text/plain");
                                    if (!fileName) return;
                                    const targetDir = PassifloraIO._joinPath(dirPath, ent.name);
                                    moveFile(fileName, dirPath, targetDir, refreshDir);
                                });

                                PassifloraIO._attachLongPressRename(
                                    nameSpan, ent.name, true,
                                    "\uD83D\uDCC1 ", dirPath, refreshDir);
                                ul.appendChild(li);
                            })(dirs[di]);
                        }

                        for (let fi = 0; fi < files.length; fi++) {
                            (function (ent) {
                                const li = document.createElement("li");
                                const matches = PassifloraIO._fileMatchesExt(
                                    ent.name, filterAll, extsLower);
                                li.className = "passiflora_fo_item passiflora_fo_file" +
                                    (matches ? " passiflora_fo_match" : " passiflora_fo_dim");

                                /* Make file items draggable */
                                li.draggable = true;
                                li.addEventListener("dragstart", function (e) {
                                    e.dataTransfer.setData("text/plain", ent.name);
                                    e.dataTransfer.effectAllowed = "move";
                                    li.classList.add("passiflora_fb_dragging");
                                });
                                li.addEventListener("dragend", function () {
                                    li.classList.remove("passiflora_fb_dragging");
                                });

                                const nameSpan = document.createElement("span");
                                nameSpan.textContent = ent.name;
                                li.appendChild(nameSpan);

                                /* Click just highlights — no callback, no close */
                                li.addEventListener("click", function () {
                                    highlightItem(li);
                                });

                                PassifloraIO._attachLongPressRename(
                                    nameSpan, ent.name, false,
                                    "", dirPath, refreshDir);
                                ul.appendChild(li);
                            })(files[fi]);
                        }

                        listWrap.appendChild(ul);
                    }

                    /* Track the current directory when this screen becomes visible */
                    screen.addEventListener("transitionend", function () {
                        const r = screen.getBoundingClientRect();
                        if (r.left >= 0 && r.left < 5) currentDir = dirPath;
                    });

                    PassifloraIO.listDirectory(dirPath).then(function (list) {
                        currentDir = dirPath;
                        entries = list;
                        populateList();
                    }).catch(function () {
                        listWrap.innerHTML = "";
                        const err = document.createElement("div");
                        err.className = "passiflora_fo_loading";
                        err.textContent = "Cannot read directory.";
                        listWrap.appendChild(err);
                    });

                    return screen;
                }

                /* -- init DOM via shared helper -- */
                const dom = PassifloraIO._initFileDialogDOM(finish);
                overlay = dom.overlay;
                wrapper = dom.wrapper;
                const teardown = dom.teardown;

                const track = document.createElement("div");
                track.className = "passiflora_fo_track";
                wrapper.appendChild(track);
                document.body.appendChild(wrapper);

                /* Build and show the root screen */
                const rootScreen = buildDirScreen(startDir, null);
                rootScreen.style.transform = "translateX(0)";
                track.appendChild(rootScreen);
                screens.push(rootScreen);
                initialDepth = 0;

                /* Trigger transitions */
                wrapper.offsetWidth; /* reflow */
                overlay.classList.add("active");
                wrapper.classList.add("active");
                document.addEventListener("keydown", dom.onKey);
            });
        });
    }
});
