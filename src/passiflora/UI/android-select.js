/* Android WebView: native <select> popups clip long lists and do not
 * scroll to the last options (theme picker, font stacks, etc.).
 * Replace the OS picker with a scrollable in-page sheet. */
(function () {
    function isAndroidHost() {
        try {
            if (typeof PassifloraConfig !== 'undefined' && PassifloraConfig.os_name === 'Android') {
                return true;
            }
        } catch (e) { /* fall through */ }
        return /Android/i.test(navigator.userAgent || '');
    }

    function syncSelectProxy(sel) {
        const wrap = sel && sel.parentNode;
        const btn = wrap && wrap.querySelector && wrap.querySelector('.select-proxy');
        if (!btn || !sel) return;
        const opt = sel.options[sel.selectedIndex];
        btn.textContent = opt ? opt.textContent : '';
        btn.disabled = !!sel.disabled;
    }

    function closeSelectPicker() {
        const overlay = document.getElementById('selectPickerOverlay');
        if (overlay && overlay.parentNode) overlay.parentNode.removeChild(overlay);
    }

    function openSelectPicker(sel) {
        closeSelectPicker();
        const overlay = document.createElement('div');
        overlay.id = 'selectPickerOverlay';
        overlay.className = 'select-picker-overlay';
        overlay.addEventListener('click', function (e) {
            if (e.target === overlay) closeSelectPicker();
        });

        const sheet = document.createElement('div');
        sheet.className = 'select-picker-sheet';
        sheet.setAttribute('role', 'listbox');
        sheet.addEventListener('click', function (e) { e.stopPropagation(); });

        let selectedBtn = null;
        for (let i = 0; i < sel.options.length; i++) {
            const opt = sel.options[i];
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.className = 'select-picker-option';
            btn.setAttribute('role', 'option');
            btn.textContent = opt.textContent;
            if (i === sel.selectedIndex) {
                btn.classList.add('is-selected');
                btn.setAttribute('aria-selected', 'true');
                selectedBtn = btn;
            }
            btn.addEventListener('click', function (value) {
                return function () {
                    sel.value = value;
                    syncSelectProxy(sel);
                    let ev;
                    try {
                        ev = new Event('change', { bubbles: true });
                    } catch (err) {
                        ev = document.createEvent('Event');
                        ev.initEvent('change', true, false);
                    }
                    sel.dispatchEvent(ev);
                    closeSelectPicker();
                };
            }(opt.value));
            sheet.appendChild(btn);
        }

        overlay.appendChild(sheet);
        document.body.appendChild(overlay);
        if (selectedBtn && selectedBtn.scrollIntoView) {
            selectedBtn.scrollIntoView({ block: 'nearest' });
        }
    }

    function enhanceSelect(sel) {
        if (!sel || sel.tagName !== 'SELECT' || sel.dataset.androidPicker) return;
        sel.dataset.androidPicker = '1';
        let wrap = sel.parentNode;
        if (!wrap || !wrap.classList || !wrap.classList.contains('select-wrap')) {
            wrap = document.createElement('div');
            wrap.className = 'select-wrap';
            sel.parentNode.insertBefore(wrap, sel);
            wrap.appendChild(sel);
        }
        sel.classList.add('select-native-hidden');
        const proxy = document.createElement('button');
        proxy.type = 'button';
        proxy.className = 'select-proxy';
        proxy.setAttribute('aria-haspopup', 'listbox');
        wrap.insertBefore(proxy, sel);
        syncSelectProxy(sel);
        proxy.addEventListener('click', function (e) {
            e.preventDefault();
            e.stopPropagation();
            openSelectPicker(sel);
        });
        sel.addEventListener('change', function () { syncSelectProxy(sel); });
        if (typeof MutationObserver !== 'undefined') {
            new MutationObserver(function () { syncSelectProxy(sel); })
                .observe(sel, { childList: true, subtree: true, attributes: true });
        }
    }

    function installAndroidSelectPicker() {
        if (!isAndroidHost()) return;
        document.documentElement.classList.add('is-android');
        const selects = document.querySelectorAll('select');
        for (let i = 0; i < selects.length; i++) enhanceSelect(selects[i]);
        if (typeof MutationObserver === 'undefined' || !document.documentElement) return;
        new MutationObserver(function (muts) {
            for (let i = 0; i < muts.length; i++) {
                const nodes = muts[i].addedNodes;
                for (let j = 0; j < nodes.length; j++) {
                    const n = nodes[j];
                    if (!n || n.nodeType !== 1) continue;
                    if (n.tagName === 'SELECT') enhanceSelect(n);
                    else if (n.querySelectorAll) {
                        const found = n.querySelectorAll('select');
                        for (let k = 0; k < found.length; k++) enhanceSelect(found[k]);
                    }
                }
            }
        }).observe(document.documentElement, { childList: true, subtree: true });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', installAndroidSelectPicker);
    } else {
        installAndroidSelectPicker();
    }
})();
