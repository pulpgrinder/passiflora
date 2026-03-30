PassifloraIO = {

    /* ================================================================ */
    /*  Geolocation bridge — native location on macOS / iOS             */
    /* ================================================================ */

    _geoCallbacks: {},
    _geoCounter: 0,
    _nativeGeolocation: null,

    _geoResolve: function (id, lat, lon, accuracy, altitude,
                           altitudeAccuracy, heading, speed, timestamp) {
        const cb = PassifloraIO._geoCallbacks[id];
        if (cb) {
            delete PassifloraIO._geoCallbacks[id];
            cb.resolve({
                coords: {
                    latitude: lat,
                    longitude: lon,
                    accuracy: accuracy,
                    altitude: altitudeAccuracy >= 0 ? altitude : null,
                    altitudeAccuracy: altitudeAccuracy >= 0 ? altitudeAccuracy : null,
                    heading: heading >= 0 ? heading : null,
                    speed: speed >= 0 ? speed : null
                },
                timestamp: timestamp
            });
        }
    },

    _geoReject: function (id, code, message) {
        const cb = PassifloraIO._geoCallbacks[id];
        if (cb) {
            delete PassifloraIO._geoCallbacks[id];
            const err = new Error(message);
            err.code = code;
            cb.reject(err);
        }
    },

    getCurrentPosition: function (successCb, errorCb) {
        /* WKWebView bridge (macOS/iOS) */
        if (window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.passifloraGeolocation) {
            const id = "geo_" + (++PassifloraIO._geoCounter);
            PassifloraIO._geoCallbacks[id] = {
                resolve: successCb || function () {},
                reject: errorCb || function () {}
            };
            window.webkit.messageHandlers.passifloraGeolocation.postMessage(id);
            return;
        }
        /* Other platforms — use native API */
        const geo = PassifloraIO._nativeGeolocation || navigator.geolocation;
        if (geo) { geo.getCurrentPosition(successCb, errorCb); return; }
        if (errorCb) errorCb({ code: 2, message: "Geolocation not available" });
    },

    openExternal: function (url) {
        /* Android native bridge */
        if (window.PassifloraBridge && window.PassifloraBridge.openExternal) {
            window.PassifloraBridge.openExternal(url);
            return;
        }
        fetch("/__passiflora/openexternal?url=" + encodeURIComponent(url))
            .then(function (resp) {
                if (!resp.ok) throw new Error();
            })
            .catch(function () {
                window.open(url, "_blank", "noopener,noreferrer");
            });
    },
    patchLinks: function () {
        const links = document.querySelectorAll("a[href]");
        for (let i = 0; i < links.length; i++) {
            (function (a) {
                const href = a.getAttribute("href");
                if (/^https?:\/\//i.test(href)) {
                    a.addEventListener("click", function (e) {
                        e.preventDefault();
                        PassifloraIO.openExternal(a.href);
                    });
                }
            })(links[i]);
        }
    },

    /* ================================================================ */
    /*  POSIX stdio bridge — native calls                               */
    /* ================================================================ */

    _posixCallbacks: {},
    _posixCounter: 0,

    /* Called from native code after a POSIX operation completes.
       id: callback ID (e.g. "posix_1")
       result: parsed JSON object {ok:true,result:...} or {ok:false,error:"..."} */
    _posixResolve: function (id, result) {
        const cb = PassifloraIO._posixCallbacks[id];
        if (cb) {
            delete PassifloraIO._posixCallbacks[id];
            if (result && result.ok) {
                cb.resolve(result.result);
            } else {
                cb.reject(new Error(result ? result.error : "Unknown error"));
            }
        }
    },

    _posixCall: function (fn, params) {
        /* Build URL-encoded params string: func=fn&key=val&... */
        let parts = "func=" + encodeURIComponent(fn);
        const keys = Object.keys(params);
        for (let i = 0; i < keys.length; i++) {
            parts += "&" + encodeURIComponent(keys[i]) + "=" +
                     encodeURIComponent(params[keys[i]]);
        }

        /* Android: synchronous @JavascriptInterface return */
        if (window.PassifloraBridge && window.PassifloraBridge.posixCall) {
            try {
                const json = window.PassifloraBridge.posixCall(parts);
                const result = JSON.parse(json);
                if (result.ok) return Promise.resolve(result.result);
                return Promise.reject(new Error(result.error));
            } catch (e) {
                return Promise.reject(e);
            }
        }

        /* macOS / iOS / Linux: async via WKScriptMessageHandler */
        if (window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.passifloraPosix) {
            const id = "posix_" + (++PassifloraIO._posixCounter);
            return new Promise(function (resolve, reject) {
                PassifloraIO._posixCallbacks[id] = { resolve: resolve, reject: reject };
                window.webkit.messageHandlers.passifloraPosix.postMessage(
                    "id=" + id + "&" + parts);
            });
        }

        /* Windows WebView2: async via chrome.webview.postMessage */
        if (window.chrome && window.chrome.webview) {
            const id = "posix_" + (++PassifloraIO._posixCounter);
            return new Promise(function (resolve, reject) {
                PassifloraIO._posixCallbacks[id] = { resolve: resolve, reject: reject };
                window.chrome.webview.postMessage(
                    "id=" + id + "&" + parts);
            });
        }

        return Promise.reject(new Error("No native POSIX bridge available"));
    },

    SEEK_SET: 0,
    SEEK_CUR: 1,
    SEEK_END: 2,

    fopen: function (path, mode) {
        return PassifloraIO._posixCall("fopen", {
            path: path, mode: mode || "r"
        });
    },

    fclose: function (handle) {
        return PassifloraIO._posixCall("fclose", {handle: handle});
    },

    fread: function (handle, size) {
        return PassifloraIO._posixCall("fread", {
            handle: handle, size: size
        }).then(function (b64) {
            if (b64 === null || b64 === undefined) return null;
            const binary = atob(b64);
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++)
                bytes[i] = binary.charCodeAt(i);
            return bytes;
        });
    },

    fwrite: function (handle, data) {
        let b64;
        if (typeof data === "string") {
            b64 = btoa(unescape(encodeURIComponent(data)));
        } else {
            let binary = "";
            for (let i = 0; i < data.length; i++)
                binary += String.fromCharCode(data[i]);
            b64 = btoa(binary);
        }
        return PassifloraIO._posixCall("fwrite", {
            handle: handle, data: b64
        });
    },

    fgets: function (handle) {
        return PassifloraIO._posixCall("fgets", {handle: handle});
    },

    fputs: function (handle, str) {
        return PassifloraIO._posixCall("fputs", {
            handle: handle, str: str
        });
    },

    fseek: function (handle, offset, whence) {
        return PassifloraIO._posixCall("fseek", {
            handle: handle,
            offset: offset,
            whence: whence !== undefined ? whence : 0
        });
    },

    ftell: function (handle) {
        return PassifloraIO._posixCall("ftell", {handle: handle});
    },

    rewind: function (handle) {
        return PassifloraIO.fseek(handle, 0, 0);
    },

    feof: function (handle) {
        return PassifloraIO._posixCall("feof", {handle: handle});
    },

    fflush: function (handle) {
        return PassifloraIO._posixCall("fflush", {handle: handle});
    },

    remove: function (path) {
        return PassifloraIO._posixCall("remove", {path: path});
    },

    rename: function (oldpath, newpath) {
        return PassifloraIO._posixCall("rename", {
            oldpath: oldpath, newpath: newpath
        });
    },

    getHomeFolder: function () {
        return PassifloraIO._posixCall("getHomeFolder", {});
    },

    listDirectory: function (path) {
        return PassifloraIO._posixCall("listDirectory", {path: path});
    },

    /* ================================================================ */
    /*  Native recording bridge (Linux GStreamer fallback)              */
    /* ================================================================ */

    hasNativeRecording: function () {
        return PassifloraIO._posixCall("hasNativeRecording", {})
            .then(function () { return true; })
            .catch(function () { return false; });
    },

    startRecording: function (path, hasVideo, hasAudio) {
        return PassifloraIO._posixCall("startRecording", {
            path: path,
            video: hasVideo ? "1" : "0",
            audio: hasAudio ? "1" : "0"
        });
    },

    stopRecording: function () {
        return PassifloraIO._posixCall("stopRecording", {});
    },

    diagnoseNativeAudio: function () {
        return PassifloraIO._posixCall("diagnoseNativeAudio", {});
    },

    /* ================================================================ */
    /*  Debug bridge — remote JavaScript execution                      */
    /* ================================================================ */

    _debugKey: null,

    _autoDebug: function (ip, port) {
        var url = ip + ':' + port + '/debug';
        var overlay = document.createElement('div');
        overlay.id = '_passiflora_debug_overlay';
        overlay.style.cssText =
            'position:fixed;top:0;left:0;width:100%;height:100%;' +
            'background:rgba(0,0,0,0.7);z-index:2147483647;' +
            'display:flex;align-items:center;justify-content:center;' +
            'font-family:system-ui,sans-serif';
        var box = document.createElement('div');
        box.style.cssText =
            'background:#fff;border-radius:8px;padding:24px 32px;' +
            'max-width:480px;width:90%;box-shadow:0 4px 24px rgba(0,0,0,0.3)';
        box.innerHTML =
            '<h2 style="margin:0 0 12px;font-size:18px;color:#c00">' +
            '\u26A0 Remote Debugging Enabled</h2>' +
            '<p style="margin:0 0 8px;font-size:13px;color:#666">' +
            'Do <strong>not</strong> ship an app with remote debugging turned on. ' +
            'It allows anyone on your network to execute arbitrary code in the webview. ' +
            'Remove <code>remotedebugging 1</code> from <code>src/permissions</code> before release.</p>' +
            '<p style="margin:0 0 8px;font-size:13px;color:#666">' +
            '<strong>iOS:</strong> The device and your computer must be on the same Wi-Fi network. ' +
            'If the debugger page won\u2019t load, check Settings \u2192 Privacy &amp; Security \u2192 ' +
            'Local Network and make sure this app is allowed.</p>' +
            '<label style="display:block;margin:12px 0 4px;font-weight:bold;font-size:14px">' +
            'Debugger URL (open in a browser on your computer):</label>' +
            '<input id="_pf_dbg_url" type="text" readonly value="http://' + url + '" ' +
            'style="width:calc(100% - 64px);box-sizing:border-box;padding:6px 8px;font:14px monospace;' +
            'border:1px solid #ccc;border-radius:4px 0 0 4px;background:#f8f8f8;cursor:text;' +
            'vertical-align:middle" onclick="this.select()">' +
            '<button id="_pf_dbg_copy" style="width:60px;padding:6px 0;font-size:13px;' +
            'cursor:pointer;border:1px solid #ccc;border-left:none;border-radius:0 4px 4px 0;' +
            'background:#e8e8e8;vertical-align:middle" title="Copy to clipboard">⿻</button>' +
            '<label style="display:block;margin:12px 0 4px;font-weight:bold;font-size:14px">' +
            'Passphrase:</label>' +
            '<input id="_pf_dbg_key" type="password" placeholder="Enter a passphrase" ' +
            'style="width:100%;box-sizing:border-box;padding:6px 8px;font:14px monospace;' +
            'border:1px solid #ccc;border-radius:4px">' +
            '<div style="text-align:right;margin-top:16px">' +
            '<button id="_pf_dbg_ok" style="padding:8px 16px;font-size:14px;' +
            'cursor:pointer;border:none;border-radius:4px;background:#0066cc;color:#fff">' +
            'OK</button></div>';
        overlay.appendChild(box);
        document.body.appendChild(overlay);
        var keyInput = document.getElementById('_pf_dbg_key');
        var urlInput = document.getElementById('_pf_dbg_url');
        var copyBtn = document.getElementById('_pf_dbg_copy');
        keyInput.focus();
        copyBtn.onclick = function () {
            urlInput.select();
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(urlInput.value).then(function () {
                    copyBtn.textContent = 'Copied!';
                    setTimeout(function () { copyBtn.textContent = '⿻'; }, 1500);
                });
            } else {
                document.execCommand('copy');
                copyBtn.textContent = 'Copied!';
                setTimeout(function () { copyBtn.textContent = '⿻'; }, 1500);
            }
        };
        document.getElementById('_pf_dbg_ok').onclick = function () {
            var val = keyInput.value.trim();
            if (!val) { keyInput.focus(); return; }
            PassifloraIO._debugKey = val;
            document.body.removeChild(overlay);
        };
        keyInput.addEventListener('keydown', function (e) {
            if (e.key === 'Enter') document.getElementById('_pf_dbg_ok').click();
        });
    },

    _debugFail: function (reason) {
        fetch('/__passiflora/debug_result', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ error: reason })
        });
    },

    _debugExec: function (payload) {
        if (!PassifloraIO._debugKey) { PassifloraIO._debugFail('debug mode not enabled'); return; }
        try {
            var msg = JSON.parse(payload);
        } catch (e) { PassifloraIO._debugFail('JSON parse: ' + e.message); return; }
        if (!msg.javascript || typeof msg.javascript !== 'string') { PassifloraIO._debugFail('no javascript field'); return; }
        if (!msg.signature || typeof msg.signature !== 'string') { PassifloraIO._debugFail('no signature field'); return; }
        if (typeof msg.nonce !== 'number') { PassifloraIO._debugFail('no nonce'); return; }

        /* Reject replayed nonces — must be strictly increasing */
        if (!PassifloraIO._debugNonce) PassifloraIO._debugNonce = 0;
        if (msg.nonce <= PassifloraIO._debugNonce) {
            PassifloraIO._debugFail('replayed nonce');
            return;
        }

        /* Validate HMAC-SHA256 signature */
        var expected = PassifloraIO._hmacSHA256(PassifloraIO._debugKey, msg.nonce + ':' + msg.javascript);
        if (expected !== msg.signature) {
            PassifloraIO._debugFail('signature mismatch');
            return;
        }

        PassifloraIO._debugNonce = msg.nonce;

        /* Signature valid — execute via indirect eval with console capture */
        var __out = [];
        var __olog = console.log, __oerr = console.error, __owarn = console.warn;
        console.log = function () {
            __out.push(Array.prototype.slice.call(arguments).map(String).join(' '));
            __olog.apply(console, arguments);
        };
        console.error = function () {
            __out.push('ERROR: ' + Array.prototype.slice.call(arguments).map(String).join(' '));
            __oerr.apply(console, arguments);
        };
        console.warn = function () {
            __out.push('WARN: ' + Array.prototype.slice.call(arguments).map(String).join(' '));
            __owarn.apply(console, arguments);
        };
        var __err = null;
        try {
            var __result = (0, eval)(msg.javascript); /* indirect eval = global scope */
            if (__result !== undefined) {
                console.log(__result);
            }
        } catch (e) {
            __err = e.message;
        }
        console.log = __olog;
        console.error = __oerr;
        console.warn = __owarn;
        /* Send result back to server for debugger to retrieve */
        var resultObj = {};
        if (__err) resultObj.error = __err;
        if (__out.length) resultObj.output = __out.join('\n');
        if (!__err && !__out.length) resultObj.output = '(no output)';
        fetch('/__passiflora/debug_result', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(resultObj)
        });
    },

    _sha256bytes: function (bytes) {
        /* Pure-JS SHA-256 (FIPS 180-4) — input: byte array, output: 32-byte array */
        var K = [
            0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
            0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
            0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
            0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
            0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
            0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
            0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
            0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
        ];
        function rr(x,n){return(x>>>n)|(x<<(32-n));}
        var b = bytes.slice();
        var bitLen = b.length * 8;
        b.push(0x80);
        while ((b.length % 64) !== 56) b.push(0);
        for (var s = 56; s >= 0; s -= 8) b.push((bitLen / Math.pow(2, s)) & 0xff);
        var H = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
        for (var off = 0; off < b.length; off += 64) {
            var W = [];
            for (var t = 0; t < 16; t++) W[t] = (b[off+t*4]<<24)|(b[off+t*4+1]<<16)|(b[off+t*4+2]<<8)|b[off+t*4+3];
            for (var t = 16; t < 64; t++) {
                var s0 = rr(W[t-15],7)^rr(W[t-15],18)^(W[t-15]>>>3);
                var s1 = rr(W[t-2],17)^rr(W[t-2],19)^(W[t-2]>>>10);
                W[t] = (W[t-16]+s0+W[t-7]+s1)|0;
            }
            var a=H[0],bb=H[1],c=H[2],d=H[3],e=H[4],f=H[5],g=H[6],h=H[7];
            for (var t = 0; t < 64; t++) {
                var S1=rr(e,6)^rr(e,11)^rr(e,25), ch=(e&f)^(~e&g), temp1=(h+S1+ch+K[t]+W[t])|0;
                var S0=rr(a,2)^rr(a,13)^rr(a,22), maj=(a&bb)^(a&c)^(bb&c), temp2=(S0+maj)|0;
                h=g;g=f;f=e;e=(d+temp1)|0;d=c;c=bb;bb=a;a=(temp1+temp2)|0;
            }
            H[0]=(H[0]+a)|0;H[1]=(H[1]+bb)|0;H[2]=(H[2]+c)|0;H[3]=(H[3]+d)|0;
            H[4]=(H[4]+e)|0;H[5]=(H[5]+f)|0;H[6]=(H[6]+g)|0;H[7]=(H[7]+h)|0;
        }
        var out = [];
        for (var i = 0; i < 8; i++) {
            var v = H[i] >>> 0;
            out.push((v>>24)&0xff,(v>>16)&0xff,(v>>8)&0xff,v&0xff);
        }
        return out;
    },

    _strToBytes: function (s) {
        var bytes = [];
        for (var i = 0; i < s.length; i++) {
            var c = s.charCodeAt(i);
            if (c < 0x80) bytes.push(c);
            else if (c < 0x800) { bytes.push(0xc0|(c>>6), 0x80|(c&0x3f)); }
            else if (c < 0x10000) { bytes.push(0xe0|(c>>12), 0x80|((c>>6)&0x3f), 0x80|(c&0x3f)); }
            else { bytes.push(0xf0|(c>>18), 0x80|((c>>12)&0x3f), 0x80|((c>>6)&0x3f), 0x80|(c&0x3f)); }
        }
        return bytes;
    },

    _hmacSHA256: function (key, message) {
        /* HMAC-SHA256 per RFC 2104 */
        var blockSize = 64;
        var keyBytes = PassifloraIO._strToBytes(key);
        if (keyBytes.length > blockSize)
            keyBytes = PassifloraIO._sha256bytes(keyBytes);
        while (keyBytes.length < blockSize) keyBytes.push(0);
        var ipad = [], opad = [];
        for (var i = 0; i < blockSize; i++) {
            ipad.push(keyBytes[i] ^ 0x36);
            opad.push(keyBytes[i] ^ 0x5c);
        }
        var msgBytes = PassifloraIO._strToBytes(message);
        var inner = PassifloraIO._sha256bytes(ipad.concat(msgBytes));
        var outer = PassifloraIO._sha256bytes(opad.concat(inner));
        var hex = '';
        for (var i = 0; i < outer.length; i++) hex += ('0' + outer[i].toString(16)).slice(-2);
        return hex;
    },

    /* ================================================================ */
    /*  Long-press rename helper for file/folder list items             */
    /* ================================================================ */

    _attachLongPressRename: function (nameEl, oldName, isDir, prefix, dirPath, refreshFn) {
        var RENAME_MS = 500;
        var timer = null;
        var editing = false;

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

            var range = document.createRange();
            range.selectNodeContents(nameEl);
            var sel = window.getSelection();
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

            var raw = nameEl.textContent || nameEl.innerText || "";
            var newName = raw.replace(/[\r\n]+/g, " ").replace(/\s+/g, " ").trim();

            nameEl.textContent = (prefix || "") + (newName || oldName);

            if (!newName || newName === oldName) return;

            var sep = "/";
            function joinPath(dir, name) {
                if (dir.charAt(dir.length - 1) === sep) return dir + name;
                return dir + sep + name;
            }
            var oldPath = joinPath(dirPath, oldName);
            var newPath = joinPath(dirPath, newName);

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
    /*  File-open sliding menu                                          */
    /* ================================================================ */

    menuopen: function (extensions, defaultFolder) {
        /* Normalise arguments */
        if (!extensions) extensions = [];
        if (!defaultFolder) defaultFolder = "";

        /* Lowercase copy of extensions for matching */
        var extsLower = [];
        for (var i = 0; i < extensions.length; i++)
            extsLower.push(extensions[i].toLowerCase().replace(/^\./, ""));

        /* Build the label for the extension filter */
        var extLabel = "";
        if (extensions.length > 0) {
            var parts = [];
            for (var i = 0; i < extensions.length; i++)
                parts.push("*." + extsLower[i]);
            extLabel = parts.join(", ");
        } else {
            extLabel = "All files (*.*)";
        }

        /* ---- helpers ---- */
        function fileMatches(name, filterAll, exts) {
            if (filterAll) return true;
            if (exts.length === 0) return true;
            var dot = name.lastIndexOf(".");
            if (dot < 0) return false;
            var ext = name.substring(dot + 1).toLowerCase();
            for (var i = 0; i < exts.length; i++)
                if (ext === exts[i]) return true;
            return false;
        }

        var SEP = "/";

        function joinPath(dir, name) {
            if (dir.charAt(dir.length - 1) === SEP) return dir + name;
            return dir + SEP + name;
        }

        function parentPath(dir) {
            var idx = dir.lastIndexOf(SEP);
            if (idx <= 0) return null;
            /* Windows drive root like C:\ */
            if (SEP === "\\" && idx <= 2) return dir.substring(0, idx + 1);
            return dir.substring(0, idx);
        }

        /* ---- DOM builder ---- */
        return (defaultFolder
            ? Promise.resolve(defaultFolder)
            : PassifloraIO.getHomeFolder()
        ).then(function (startDir) {

            return new Promise(function (resolve) {

                var overlay = null;
                var wrapper = null;
                var screens = [];
                var depth = 0;
                var initialDepth = 0;   /* depth of the very first screen */
                var filterAll = false;   /* true when "All files" selected */
                var resolved = false;

                function finish(value) {
                    if (resolved) return;
                    resolved = true;
                    teardown();
                    resolve(value);
                }

                /* -- slide helpers (mirror PassifloraMenu) -- */
                function positionScreens() {
                    for (var i = 0; i < screens.length; i++) {
                        var off = (i - depth) * 100;
                        screens[i].style.transform = "translateX(" + off + "%)";
                    }
                }

                function slideForward(screen) {
                    while (screens.length > depth + 1) {
                        var old = screens.pop();
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
                        /* navigated back past first level — cancel */
                        finish(null);
                        return;
                    }
                    depth--;
                    positionScreens();
                    var removed = screens.pop();
                    setTimeout(function () {
                        if (removed.parentNode) removed.parentNode.removeChild(removed);
                    }, 300);
                }

                /* -- build a screen for a directory -- */
                function shortPath(p) {
                    return p.length > 20 ? "\u2026" + p.slice(-20) : p;
                }

                function buildDirScreen(dirPath, title) {
                    var screen = document.createElement("div");
                    screen.className = "passiflora_fo_screen";

                    /* Back header */
                    var back = document.createElement("div");
                    back.className = "passiflora_fo_back";
                    back.textContent = title || shortPath(dirPath);
                    back.addEventListener("click", function () { slideBack(); });
                    screen.appendChild(back);

                    /* File list (placeholder while loading) */
                    var listWrap = document.createElement("div");
                    listWrap.className = "passiflora_fo_list";
                    var loadingMsg = document.createElement("div");
                    loadingMsg.className = "passiflora_fo_loading";
                    loadingMsg.textContent = "Loading\u2026";
                    listWrap.appendChild(loadingMsg);
                    screen.appendChild(listWrap);

                    /* Extension filter select */
                    var filterRow = document.createElement("div");
                    filterRow.className = "passiflora_fo_filterbar";
                    var sel = document.createElement("select");
                    sel.className = "passiflora_fo_select";
                    if (extensions.length > 0) {
                        var opt1 = document.createElement("option");
                        opt1.value = "ext";
                        opt1.textContent = extLabel;
                        sel.appendChild(opt1);
                    }
                    var opt2 = document.createElement("option");
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

                    var newDirBtn = document.createElement("button");
                    newDirBtn.className = "passiflora_fo_newdir";
                    newDirBtn.textContent = "\uD83D\uDCC1+";
                    newDirBtn.title = "Create Folder";
                    newDirBtn.addEventListener("click", function () {
                        var base = "Untitled";
                        var taken = {};
                        if (entries) {
                            for (var ti = 0; ti < entries.length; ti++)
                                taken[entries[ti].name] = true;
                        }
                        var name = base;
                        var n = 2;
                        while (taken[name]) { name = base + " " + n; n++; }
                        var newPath = dirPath === "/" ? "/" + name : dirPath + "/" + name;
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
                    var entries = null;

                    function populateList() {
                        if (!entries) return;
                        listWrap.innerHTML = "";
                        var ul = document.createElement("ul");
                        ul.className = "passiflora_fo_ul";

                        function refreshDir() {
                            PassifloraIO.listDirectory(dirPath).then(function (list) {
                                entries = list;
                                populateList();
                            });
                        }

                        /* ".." entry — go up a folder (only if not at root) */
                        if (dirPath !== "/") {
                            var upLi = document.createElement("li");
                            upLi.className = "passiflora_fo_item passiflora_fo_dir";
                            upLi.textContent = "\uD83D\uDCC1 ..";
                            var upArrow = document.createElement("span");
                            upArrow.className = "passiflora_fo_arrow";
                            upArrow.textContent = "\u276E";
                            upLi.appendChild(upArrow);
                            upLi.addEventListener("click", function () { slideBack(); });
                            ul.appendChild(upLi);
                        }

                        /* Sort: directories first, then alphabetical */
                        var dirs = [], files = [];
                        for (var i = 0; i < entries.length; i++) {
                            if (entries[i].name === "..") continue;
                            if (entries[i].isDir) dirs.push(entries[i]);
                            else files.push(entries[i]);
                        }
                        dirs.sort(function (a, b) { return a.name.localeCompare(b.name); });
                        files.sort(function (a, b) { return a.name.localeCompare(b.name); });

                        for (var i = 0; i < dirs.length; i++) {
                            (function (ent) {
                                var li = document.createElement("li");
                                li.className = "passiflora_fo_item passiflora_fo_dir";
                                var nameSpan = document.createElement("span");
                                nameSpan.textContent = "\uD83D\uDCC1 " + ent.name;
                                li.appendChild(nameSpan);
                                var arrow = document.createElement("span");
                                arrow.className = "passiflora_fo_arrow";
                                arrow.textContent = "\u276F";
                                li.appendChild(arrow);
                                li.addEventListener("click", function () {
                                    var sub = joinPath(dirPath, ent.name);
                                    var newScreen = buildDirScreen(sub, ent.name);
                                    slideForward(newScreen);
                                });
                                PassifloraIO._attachLongPressRename(
                                    nameSpan, ent.name, true,
                                    "\uD83D\uDCC1 ", dirPath, refreshDir);
                                ul.appendChild(li);
                            })(dirs[i]);
                        }

                        for (var i = 0; i < files.length; i++) {
                            (function (ent) {
                                var li = document.createElement("li");
                                var matches = fileMatches(
                                    ent.name, filterAll, extsLower);
                                li.className = "passiflora_fo_item passiflora_fo_file" +
                                    (matches ? " passiflora_fo_match" : " passiflora_fo_dim");
                                var nameSpan = document.createElement("span");
                                nameSpan.textContent = ent.name;
                                li.appendChild(nameSpan);
                                if (matches) {
                                    li.addEventListener("click", function () {
                                        finish(joinPath(dirPath, ent.name));
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
                        var err = document.createElement("div");
                        err.className = "passiflora_fo_loading";
                        err.textContent = "Cannot read directory.";
                        listWrap.appendChild(err);
                    });

                    return screen;
                }

                /* -- teardown -- */
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

                function onKey(e) {
                    if (e.key === "Escape" || e.keyCode === 27) {
                        finish(null);
                    }
                }

                /* -- create overlay & wrapper -- */
                /* Remove any leftover elements from a previous call */
                var stale = document.querySelectorAll(
                    ".passiflora_fo_overlay, .passiflora_fo_wrapper");
                for (var si = 0; si < stale.length; si++)
                    stale[si].parentNode.removeChild(stale[si]);

                /* Force vertical scrollbar so its width doesn't shift layout */
                var prevOverflow = document.documentElement.style.overflowY;
                document.documentElement.style.overflowY = "scroll";

                overlay = document.createElement("div");
                overlay.className = "passiflora_fo_overlay";
                overlay.addEventListener("click", function () { finish(null); });
                document.body.appendChild(overlay);

                wrapper = document.createElement("div");
                wrapper.className = "passiflora_fo_wrapper";
                var track = document.createElement("div");
                track.className = "passiflora_fo_track";
                wrapper.appendChild(track);
                document.body.appendChild(wrapper);

                /* Build and show the root screen */
                var rootScreen = buildDirScreen(startDir, null);
                rootScreen.style.transform = "translateX(0)";
                track.appendChild(rootScreen);
                screens.push(rootScreen);
                initialDepth = 0;

                /* Trigger transitions */
                wrapper.offsetWidth; /* reflow */
                overlay.classList.add("active");
                wrapper.classList.add("active");
                document.addEventListener("keydown", onKey);
            });
        });
    },

    /* ================================================================ */
    /*  Save-As sliding menu                                            */
    /* ================================================================ */

    menusavas: function (extensions, defaultName) {
        /* Normalise arguments */
        if (!extensions) extensions = [];
        if (!defaultName) defaultName = "";

        /* Lowercase copy of extensions for matching */
        var extsLower = [];
        for (var i = 0; i < extensions.length; i++)
            extsLower.push(extensions[i].toLowerCase().replace(/^\./, ""));

        /* Build the label for the extension filter */
        var extLabel = "";
        if (extensions.length > 0) {
            var parts = [];
            for (var i = 0; i < extensions.length; i++)
                parts.push("*." + extsLower[i]);
            extLabel = parts.join(", ");
        } else {
            extLabel = "All files (*.*)";
        }

        /* ---- helpers ---- */
        function fileMatches(name, showAll, exts) {
            if (showAll) return true;
            if (exts.length === 0) return true;
            var dot = name.lastIndexOf(".");
            if (dot < 0) return false;
            var ext = name.substring(dot + 1).toLowerCase();
            for (var i = 0; i < exts.length; i++)
                if (ext === exts[i]) return true;
            return false;
        }

        function nameHasMatchingExt(name, exts) {
            if (exts.length === 0) return true;
            var dot = name.lastIndexOf(".");
            if (dot < 0) return false;
            var ext = name.substring(dot + 1).toLowerCase();
            for (var i = 0; i < exts.length; i++)
                if (ext === exts[i]) return true;
            return false;
        }

        var SEP = "/";

        function joinPath(dir, name) {
            if (dir.charAt(dir.length - 1) === SEP) return dir + name;
            return dir + SEP + name;
        }

        function parentPath(dir) {
            var idx = dir.lastIndexOf(SEP);
            if (idx <= 0) return null;
            if (SEP === "\\" && idx <= 2) return dir.substring(0, idx + 1);
            return dir.substring(0, idx);
        }

        /* ---- DOM builder ---- */
        return PassifloraIO.getHomeFolder().then(function (startDir) {

            return new Promise(function (resolve) {

                var overlay = null;
                var wrapper = null;
                var screens = [];
                var depth = 0;
                var initialDepth = 0;
                var filterAll = false;
                var resolved = false;
                var currentDir = startDir;
                var currentFiles = [];       /* file names in the visible directory */
                var nameInput = null;        /* the filename text field */

                function finish(value) {
                    if (resolved) return;
                    resolved = true;
                    teardown();
                    resolve(value);
                }

                /* -- confirm dialog -- */
                function showConfirm(message) {
                    return new Promise(function (yes) {
                        var box = document.createElement("div");
                        box.className = "passiflora_fo_confirm_overlay";

                        var card = document.createElement("div");
                        card.className = "passiflora_fo_confirm_card";

                        var msg = document.createElement("div");
                        msg.className = "passiflora_fo_confirm_msg";
                        msg.textContent = message;
                        card.appendChild(msg);

                        var btns = document.createElement("div");
                        btns.className = "passiflora_fo_confirm_btns";

                        var cancelBtn = document.createElement("button");
                        cancelBtn.className = "passiflora_fo_confirm_btn";
                        cancelBtn.textContent = "Cancel";
                        cancelBtn.addEventListener("click", function () {
                            box.parentNode.removeChild(box);
                            yes(false);
                        });
                        btns.appendChild(cancelBtn);

                        var okBtn = document.createElement("button");
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
                    var name = (nameInput.value || "").trim();
                    if (!name) return;
                    var fullPath = joinPath(currentDir, name);

                    /* Does the file already exist in the current listing? */
                    var exists = false;
                    for (var ei = 0; ei < currentFiles.length; ei++) {
                        if (currentFiles[ei] === name) { exists = true; break; }
                    }
                    var badExt = !nameHasMatchingExt(name, extsLower);

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
                function positionScreens() {
                    for (var i = 0; i < screens.length; i++) {
                        var off = (i - depth) * 100;
                        screens[i].style.transform = "translateX(" + off + "%)";
                    }
                }

                function slideForward(screen) {
                    while (screens.length > depth + 1) {
                        var old = screens.pop();
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
                    var removed = screens.pop();
                    setTimeout(function () {
                        if (removed.parentNode) removed.parentNode.removeChild(removed);
                    }, 300);
                }

                function shortPath(p) {
                    return p.length > 20 ? "\u2026" + p.slice(-20) : p;
                }

                /* -- build a screen for a directory -- */
                function buildDirScreen(dirPath, title) {
                    var screen = document.createElement("div");
                    screen.className = "passiflora_fo_screen";

                    /* Back header */
                    var back = document.createElement("div");
                    back.className = "passiflora_fo_back";
                    back.textContent = title || shortPath(dirPath);
                    back.addEventListener("click", function () { slideBack(); });
                    screen.appendChild(back);

                    /* File list */
                    var listWrap = document.createElement("div");
                    listWrap.className = "passiflora_fo_list";
                    var loadingMsg = document.createElement("div");
                    loadingMsg.className = "passiflora_fo_loading";
                    loadingMsg.textContent = "Loading\u2026";
                    listWrap.appendChild(loadingMsg);
                    screen.appendChild(listWrap);

                    /* Extension filter select */
                    var filterRow = document.createElement("div");
                    filterRow.className = "passiflora_fo_filterbar";
                    var sel = document.createElement("select");
                    sel.className = "passiflora_fo_select";
                    if (extensions.length > 0) {
                        var opt1 = document.createElement("option");
                        opt1.value = "ext";
                        opt1.textContent = extLabel;
                        sel.appendChild(opt1);
                    }
                    var opt2 = document.createElement("option");
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

                    var newDirBtn = document.createElement("button");
                    newDirBtn.className = "passiflora_fo_newdir";
                    newDirBtn.textContent = "\uD83D\uDCC1+";
                    newDirBtn.title = "Create Folder";
                    newDirBtn.addEventListener("click", function () {
                        var base = "Untitled";
                        var taken = {};
                        if (entries) {
                            for (var ti = 0; ti < entries.length; ti++)
                                taken[entries[ti].name] = true;
                        }
                        var name = base;
                        var n = 2;
                        while (taken[name]) { name = base + " " + n; n++; }
                        var newPath = dirPath === "/" ? "/" + name : dirPath + "/" + name;
                        PassifloraIO.mkdir(newPath).then(function () {
                            return PassifloraIO.listDirectory(dirPath);
                        }).then(function (list) {
                            entries = list;
                            currentFiles = [];
                            for (var fi = 0; fi < list.length; fi++) {
                                if (!list[fi].isDir) currentFiles.push(list[fi].name);
                            }
                            populateList();
                        });
                    });
                    filterRow.appendChild(newDirBtn);
                    screen.appendChild(filterRow);

                    /* Fetch directory listing and populate */
                    var entries = null;

                    function populateList() {
                        if (!entries) return;
                        listWrap.innerHTML = "";
                        var ul = document.createElement("ul");
                        ul.className = "passiflora_fo_ul";

                        function refreshDir() {
                            PassifloraIO.listDirectory(dirPath).then(function (list) {
                                entries = list;
                                currentFiles = [];
                                for (var fi = 0; fi < list.length; fi++) {
                                    if (!list[fi].isDir) currentFiles.push(list[fi].name);
                                }
                                populateList();
                            });
                        }

                        /* ".." entry (only if not at root) */
                        if (dirPath !== "/") {
                            var upLi = document.createElement("li");
                            upLi.className = "passiflora_fo_item passiflora_fo_dir";
                            upLi.textContent = "\uD83D\uDCC1 ..";
                            var upArrow = document.createElement("span");
                            upArrow.className = "passiflora_fo_arrow";
                            upArrow.textContent = "\u276E";
                            upLi.appendChild(upArrow);
                            upLi.addEventListener("click", function () { slideBack(); });
                            ul.appendChild(upLi);
                        }

                        /* Sort: directories first, then alphabetical */
                        var dirs = [], files = [];
                        for (var i = 0; i < entries.length; i++) {
                            if (entries[i].name === "..") continue;
                            if (entries[i].isDir) dirs.push(entries[i]);
                            else files.push(entries[i]);
                        }
                        dirs.sort(function (a, b) { return a.name.localeCompare(b.name); });
                        files.sort(function (a, b) { return a.name.localeCompare(b.name); });

                        for (var i = 0; i < dirs.length; i++) {
                            (function (ent) {
                                var li = document.createElement("li");
                                li.className = "passiflora_fo_item passiflora_fo_dir";
                                var nameSpan = document.createElement("span");
                                nameSpan.textContent = "\uD83D\uDCC1 " + ent.name;
                                li.appendChild(nameSpan);
                                var arrow = document.createElement("span");
                                arrow.className = "passiflora_fo_arrow";
                                arrow.textContent = "\u276F";
                                li.appendChild(arrow);
                                li.addEventListener("click", function () {
                                    var sub = joinPath(dirPath, ent.name);
                                    currentDir = sub;
                                    var newScreen = buildDirScreen(sub, ent.name);
                                    slideForward(newScreen);
                                });
                                PassifloraIO._attachLongPressRename(
                                    nameSpan, ent.name, true,
                                    "\uD83D\uDCC1 ", dirPath, refreshDir);
                                ul.appendChild(li);
                            })(dirs[i]);
                        }

                        for (var i = 0; i < files.length; i++) {
                            (function (ent) {
                                var li = document.createElement("li");
                                var matches = fileMatches(
                                    ent.name, filterAll, extsLower);
                                li.className = "passiflora_fo_item passiflora_fo_file" +
                                    (matches ? " passiflora_fo_match" : " passiflora_fo_dim");
                                var nameSpan = document.createElement("span");
                                nameSpan.textContent = ent.name;
                                li.appendChild(nameSpan);
                                /* Clicking an existing file = overwrite + extension confirm */
                                li.addEventListener("click", function () {
                                    nameInput.value = ent.name;
                                    var badExt = !nameHasMatchingExt(ent.name, extsLower);
                                    var p = Promise.resolve(true);
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
                                        if (ok) finish(joinPath(dirPath, ent.name));
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
                        var r = screen.getBoundingClientRect();
                        if (r.left >= 0 && r.left < 5) currentDir = dirPath;
                    });

                    PassifloraIO.listDirectory(dirPath).then(function (list) {
                        currentDir = dirPath;
                        entries = list;
                        /* Update shared file-name list for trySave's overwrite check */
                        currentFiles = [];
                        for (var fi = 0; fi < list.length; fi++) {
                            if (!list[fi].isDir) currentFiles.push(list[fi].name);
                        }
                        populateList();
                    }).catch(function () {
                        listWrap.innerHTML = "";
                        var err = document.createElement("div");
                        err.className = "passiflora_fo_loading";
                        err.textContent = "Cannot read directory.";
                        listWrap.appendChild(err);
                    });

                    return screen;
                }

                /* -- teardown -- */
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

                function onKey(e) {
                    if (e.key === "Escape" || e.keyCode === 27) {
                        finish(null);
                    }
                }

                /* -- create overlay & wrapper -- */
                var stale = document.querySelectorAll(
                    ".passiflora_fo_overlay, .passiflora_fo_wrapper");
                for (var si = 0; si < stale.length; si++)
                    stale[si].parentNode.removeChild(stale[si]);

                var prevOverflow = document.documentElement.style.overflowY;
                document.documentElement.style.overflowY = "scroll";

                overlay = document.createElement("div");
                overlay.className = "passiflora_fo_overlay";
                overlay.addEventListener("click", function () { finish(null); });
                document.body.appendChild(overlay);

                wrapper = document.createElement("div");
                wrapper.className = "passiflora_fo_wrapper";

                /* Filename input bar at the top */
                var nameBar = document.createElement("div");
                nameBar.className = "passiflora_fo_namebar";

                nameInput = document.createElement("input");
                nameInput.type = "text";
                nameInput.className = "passiflora_fo_nameinput";
                nameInput.placeholder = "Filename";
                nameInput.value = defaultName;
                nameBar.appendChild(nameInput);

                var saveBtn = document.createElement("button");
                saveBtn.className = "passiflora_fo_savebtn";
                saveBtn.textContent = "Save";
                saveBtn.addEventListener("click", function () { trySave(); });
                nameBar.appendChild(saveBtn);

                wrapper.appendChild(nameBar);

                var track = document.createElement("div");
                track.className = "passiflora_fo_track";
                wrapper.appendChild(track);
                document.body.appendChild(wrapper);

                /* Build and show the root screen */
                var rootScreen = buildDirScreen(startDir, null);
                rootScreen.style.transform = "translateX(0)";
                track.appendChild(rootScreen);
                screens.push(rootScreen);
                initialDepth = 0;

                /* Trigger transitions */
                wrapper.offsetWidth;
                overlay.classList.add("active");
                wrapper.classList.add("active");
                document.addEventListener("keydown", onKey);

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
    /*  VFS Export / Import / File Transfer                             */
    /*  Overridden by the VFS+IndexedDB IIFE below.                    */
    /* ================================================================ */

    exportVFS: function () {
        return Promise.reject(new Error("VFS not yet initialized."));
    },

    importVFS: function () {
        return Promise.reject(new Error("VFS not yet initialized."));
    },

    importFile: function () {
        return Promise.reject(new Error("VFS not yet initialized."));
    },

    exportFile: function () {
        return Promise.reject(new Error("VFS not yet initialized."));
    },

    eraseVFS: function () {
        return Promise.reject(new Error("VFS not yet initialized."));
    },

};

/* ================================================================ */
/*  VFS + IndexedDB — persistent virtual file system (all platforms) */
/*  Replaces native POSIX bridge file I/O on every target.           */
/*  Non-file native calls (recording, geolocation) pass through.     */
/* ================================================================ */
(function () {
    if (typeof PassifloraConfig === "undefined") return;

    /* ---------- In-memory virtual file system ---------- */
    var _vfs = {};               /* path -> Uint8Array */
    var _dirs = {};              /* path -> true (explicitly created directories) */
    var _cwd = "/";              /* current working directory */
    var _handles = {};           /* handle_id -> { path, mode, pos } */
    var _handleCounter = 0;

    function _nextHandle() { return "vfsfh_" + (++_handleCounter); }

    /* ---------- IndexedDB persistence layer ---------- */
    var _db = null;

    var _dbReady = new Promise(function (resolve) {
        if (typeof indexedDB === "undefined") { resolve(); return; }
        try {
            var req = indexedDB.open("PassifloraVFS", 2);
            req.onupgradeneeded = function (e) {
                var db = e.target.result;
                if (!db.objectStoreNames.contains("files"))
                    db.createObjectStore("files");
                if (!db.objectStoreNames.contains("dirs"))
                    db.createObjectStore("dirs");
            };
            req.onsuccess = function (e) {
                _db = e.target.result;
                /* Hydrate VFS from IndexedDB */
                var tx = _db.transaction(["files", "dirs"], "readonly");
                var store = tx.objectStore("files");
                var keysReq = store.getAllKeys();
                var valsReq = store.getAll();
                var dirStore = tx.objectStore("dirs");
                var dirKeysReq = dirStore.getAllKeys();
                keysReq.onsuccess = function () {
                    valsReq.onsuccess = function () {
                        var keys = keysReq.result;
                        var vals = valsReq.result;
                        for (var i = 0; i < keys.length; i++)
                            _vfs[keys[i]] = vals[i] instanceof Uint8Array
                                ? vals[i] : new Uint8Array(vals[i]);
                        dirKeysReq.onsuccess = function () {
                            var dk = dirKeysReq.result;
                            for (var i = 0; i < dk.length; i++)
                                _dirs[dk[i]] = true;
                            /* Preload compiled-in data on first run */
                            if (Object.keys(_vfs).length === 0)
                                _loadPreloadData();
                            resolve();
                        };
                        dirKeysReq.onerror = function () { resolve(); };
                    };
                };
                valsReq.onerror = function () { resolve(); };
                keysReq.onerror = function () { resolve(); };
            };
            req.onerror = function () { resolve(); };
        } catch (e) { resolve(); }
    });

    /* ---------- Preload compiled-in VFS data ---------- */
    function _loadPreloadData() {
        if (typeof _PASSIFLORA_VFS_PRELOAD === "undefined" ||
            !_PASSIFLORA_VFS_PRELOAD.length) return;
        for (var i = 0; i < _PASSIFLORA_VFS_PRELOAD.length; i++) {
            var entry = _PASSIFLORA_VFS_PRELOAD[i];
            var raw = atob(entry.data);
            var arr = new Uint8Array(raw.length);
            for (var j = 0; j < raw.length; j++) arr[j] = raw.charCodeAt(j);
            _vfs[entry.path] = arr;
            _dbPut(entry.path, arr);
            /* Create parent directories */
            var parts = entry.path.split("/");
            for (var k = 2; k < parts.length; k++) {
                var dir = parts.slice(0, k).join("/");
                if (!_dirs[dir]) { _dirs[dir] = true; _dbPutDir(dir); }
            }
        }
    }

    function _dbPut(path, data) {
        if (!_db) return;
        try {
            var tx = _db.transaction("files", "readwrite");
            tx.objectStore("files").put(data, path);
        } catch (e) { /* IndexedDB unavailable or quota exceeded */ }
    }

    function _dbDelete(path) {
        if (!_db) return;
        try {
            var tx = _db.transaction("files", "readwrite");
            tx.objectStore("files").delete(path);
        } catch (e) { /* IndexedDB unavailable */ }
    }

    function _dbPutDir(path) {
        if (!_db) return;
        try {
            var tx = _db.transaction("dirs", "readwrite");
            tx.objectStore("dirs").put(true, path);
        } catch (e) { /* IndexedDB unavailable */ }
    }

    function _dbDeleteDir(path) {
        if (!_db) return;
        try {
            var tx = _db.transaction("dirs", "readwrite");
            tx.objectStore("dirs").delete(path);
        } catch (e) { /* IndexedDB unavailable */ }
    }

    /* Resolve a path relative to _cwd into an absolute path */
    function _resolvePath(p) {
        if (p.charAt(0) !== "/") {
            p = (_cwd === "/" ? "/" : _cwd + "/") + p;
        }
        /* Normalise . and .. */
        var parts = p.split("/");
        var out = [];
        for (var i = 0; i < parts.length; i++) {
            if (parts[i] === "" || parts[i] === ".") continue;
            if (parts[i] === "..") { if (out.length) out.pop(); }
            else out.push(parts[i]);
        }
        return "/" + out.join("/");
    }

    /* Request persistent storage so browsers don't evict data */
    if (navigator.storage && navigator.storage.persist) {
        navigator.storage.persist();
    }

    /* -- System info -- */
    PassifloraIO.getHomeFolder = function () {
        return Promise.resolve("/");
    };

    /* -- Directory listing (from VFS) -- */
    PassifloraIO.listDirectory = function (path) {
        return _dbReady.then(function () {
            var prefix = path;
            if (prefix !== "/" && prefix.charAt(prefix.length - 1) !== "/")
                prefix += "/";
            var entries = [];
            var seen = {};
            var keys = Object.keys(_vfs);
            for (var i = 0; i < keys.length; i++) {
                var p = keys[i];
                var rest;
                if (prefix === "/") {
                    rest = p.substring(1);
                } else if (p.indexOf(prefix) === 0) {
                    rest = p.substring(prefix.length);
                } else {
                    continue;
                }
                var slash = rest.indexOf("/");
                var name = slash < 0 ? rest : rest.substring(0, slash);
                if (name && !seen[name]) {
                    seen[name] = true;
                    entries.push({ name: name, isDir: slash >= 0 });
                }
            }
            /* Include explicitly-created (possibly empty) directories */
            var dirKeys = Object.keys(_dirs);
            for (var i = 0; i < dirKeys.length; i++) {
                var d = dirKeys[i];
                var rest;
                if (prefix === "/") {
                    rest = d.substring(1);
                } else if (d.indexOf(prefix) === 0) {
                    rest = d.substring(prefix.length);
                } else {
                    continue;
                }
                var slash = rest.indexOf("/");
                var name = slash < 0 ? rest : rest.substring(0, slash);
                if (name && !seen[name]) {
                    seen[name] = true;
                    entries.push({ name: name, isDir: true });
                }
            }
            return entries;
        });
    };

    /* -- POSIX file I/O (VFS-backed, persisted to IndexedDB) -- */
    PassifloraIO.fopen = function (path, mode) {
        return _dbReady.then(function () {
            mode = mode || "r";
            if (mode.indexOf("r") >= 0 && !_vfs[path]) {
                throw new Error("File not found: " + path);
            }
            if (mode.indexOf("w") >= 0) {
                _vfs[path] = new Uint8Array(0);
            }
            if (mode.indexOf("a") >= 0 && !_vfs[path]) {
                _vfs[path] = new Uint8Array(0);
            }
            var data = _vfs[path] || new Uint8Array(0);
            var pos = mode.indexOf("a") >= 0 ? data.length : 0;
            var h = _nextHandle();
            _handles[h] = { path: path, mode: mode, pos: pos };
            return h;
        });
    };

    PassifloraIO.fclose = function (handle) {
        var fh = _handles[handle];
        if (!fh) { delete _handles[handle]; return Promise.resolve(0); }
        var path = fh.path;
        delete _handles[handle];
        /* Persist to IndexedDB */
        if (_vfs[path]) _dbPut(path, _vfs[path]);
        return Promise.resolve(0);
    };

    PassifloraIO.fread = function (handle, size) {
        var fh = _handles[handle];
        if (!fh) return Promise.reject(new Error("Invalid file handle"));
        var data = _vfs[fh.path] || new Uint8Array(0);
        var end = Math.min(fh.pos + size, data.length);
        if (fh.pos >= data.length) return Promise.resolve(null);
        var slice = data.slice(fh.pos, end);
        fh.pos = end;
        return Promise.resolve(slice);
    };

    PassifloraIO.fwrite = function (handle, inputData) {
        var fh = _handles[handle];
        if (!fh) return Promise.reject(new Error("Invalid file handle"));
        var bytes;
        if (typeof inputData === "string") {
            bytes = new TextEncoder().encode(inputData);
        } else {
            bytes = inputData;
        }
        var existing = _vfs[fh.path] || new Uint8Array(0);
        var needed = fh.pos + bytes.length;
        if (needed > existing.length) {
            var bigger = new Uint8Array(needed);
            bigger.set(existing);
            existing = bigger;
            _vfs[fh.path] = existing;
        }
        existing.set(bytes, fh.pos);
        fh.pos += bytes.length;
        return Promise.resolve(bytes.length);
    };

    PassifloraIO.fgets = function (handle) {
        var fh = _handles[handle];
        if (!fh) return Promise.reject(new Error("Invalid file handle"));
        var data = _vfs[fh.path] || new Uint8Array(0);
        if (fh.pos >= data.length) return Promise.resolve(null);
        var end = fh.pos;
        while (end < data.length && data[end] !== 10) end++;
        if (end < data.length) end++; /* include newline */
        var slice = data.slice(fh.pos, end);
        fh.pos = end;
        return Promise.resolve(new TextDecoder().decode(slice));
    };

    PassifloraIO.fputs = function (handle, str) {
        return PassifloraIO.fwrite(handle, str);
    };

    PassifloraIO.fseek = function (handle, offset, whence) {
        var fh = _handles[handle];
        if (!fh) return Promise.reject(new Error("Invalid file handle"));
        var data = _vfs[fh.path] || new Uint8Array(0);
        if (whence === 0) fh.pos = offset;
        else if (whence === 1) fh.pos += offset;
        else if (whence === 2) fh.pos = data.length + offset;
        if (fh.pos < 0) fh.pos = 0;
        return Promise.resolve(0);
    };

    PassifloraIO.ftell = function (handle) {
        var fh = _handles[handle];
        if (!fh) return Promise.reject(new Error("Invalid file handle"));
        return Promise.resolve(fh.pos);
    };

    PassifloraIO.feof = function (handle) {
        var fh = _handles[handle];
        if (!fh) return Promise.reject(new Error("Invalid file handle"));
        var data = _vfs[fh.path] || new Uint8Array(0);
        return Promise.resolve(fh.pos >= data.length ? 1 : 0);
    };

    PassifloraIO.fflush = function () {
        return Promise.resolve(0);
    };

    PassifloraIO.remove = function (path) {
        return _dbReady.then(function () {
            delete _vfs[path];
            _dbDelete(path);
            return 0;
        });
    };

    PassifloraIO.rename = function (oldpath, newpath) {
        return _dbReady.then(function () {
            oldpath = _resolvePath(oldpath);
            newpath = _resolvePath(newpath);
            /* Rename a directory — move all files under it */
            if (_dirs[oldpath]) {
                var oldPrefix = oldpath + "/";
                var newPrefix = newpath + "/";
                var keys = Object.keys(_vfs);
                for (var i = 0; i < keys.length; i++) {
                    if (keys[i].indexOf(oldPrefix) === 0) {
                        var suffix = keys[i].substring(oldPrefix.length);
                        _vfs[newPrefix + suffix] = _vfs[keys[i]];
                        _dbPut(newPrefix + suffix, _vfs[keys[i]]);
                        delete _vfs[keys[i]];
                        _dbDelete(keys[i]);
                    }
                }
                /* Move sub-directories */
                var dk = Object.keys(_dirs);
                for (var i = 0; i < dk.length; i++) {
                    if (dk[i] === oldpath || dk[i].indexOf(oldPrefix) === 0) {
                        var newDir = newpath + dk[i].substring(oldpath.length);
                        _dirs[newDir] = true;
                        _dbPutDir(newDir);
                        delete _dirs[dk[i]];
                        _dbDeleteDir(dk[i]);
                    }
                }
                return 0;
            }
            /* Rename a file */
            if (!_vfs[oldpath])
                throw new Error("File not found: " + oldpath);
            _vfs[newpath] = _vfs[oldpath];
            delete _vfs[oldpath];
            _dbDelete(oldpath);
            _dbPut(newpath, _vfs[newpath]);
            return 0;
        });
    };

    /* -- POSIX directory functions -- */
    PassifloraIO.getcwd = function () {
        return Promise.resolve(_cwd);
    };

    PassifloraIO.chdir = function (path) {
        return _dbReady.then(function () {
            var resolved = _resolvePath(path);
            if (resolved === "/") { _cwd = "/"; return 0; }
            /* Check if the directory exists (has files under it or is explicit) */
            if (_dirs[resolved]) { _cwd = resolved; return 0; }
            var prefix = resolved + "/";
            var keys = Object.keys(_vfs);
            for (var i = 0; i < keys.length; i++) {
                if (keys[i].indexOf(prefix) === 0) { _cwd = resolved; return 0; }
            }
            /* Also check sub-directories */
            var dk = Object.keys(_dirs);
            for (var i = 0; i < dk.length; i++) {
                if (dk[i].indexOf(prefix) === 0) { _cwd = resolved; return 0; }
            }
            throw new Error("Directory not found: " + resolved);
        });
    };

    PassifloraIO.mkdir = function (path) {
        return _dbReady.then(function () {
            var resolved = _resolvePath(path);
            if (resolved === "/") return 0;
            if (_dirs[resolved]) throw new Error("Directory already exists: " + resolved);
            /* Check if a file has this exact path */
            if (_vfs[resolved]) throw new Error("A file already exists at: " + resolved);
            _dirs[resolved] = true;
            _dbPutDir(resolved);
            return 0;
        });
    };

    PassifloraIO.rmdir = function (path) {
        return _dbReady.then(function () {
            var resolved = _resolvePath(path);
            if (resolved === "/") throw new Error("Cannot remove root directory");
            /* Check the directory is empty */
            var prefix = resolved + "/";
            var keys = Object.keys(_vfs);
            for (var i = 0; i < keys.length; i++) {
                if (keys[i].indexOf(prefix) === 0)
                    throw new Error("Directory not empty: " + resolved);
            }
            var dk = Object.keys(_dirs);
            for (var i = 0; i < dk.length; i++) {
                if (dk[i] !== resolved && dk[i].indexOf(prefix) === 0)
                    throw new Error("Directory not empty: " + resolved);
            }
            if (!_dirs[resolved]) throw new Error("Directory not found: " + resolved);
            delete _dirs[resolved];
            _dbDeleteDir(resolved);
            return 0;
        });
    };

    /* -- Recording: WWW-only stubs (native platforms keep the bridge) -- */
    if (PassifloraConfig.os_name === "WWW") {
        PassifloraIO.hasNativeRecording = function () {
            return Promise.resolve(false);
        };
        PassifloraIO.startRecording = function () {
            return Promise.reject(new Error("Native recording not available on web"));
        };
        PassifloraIO.stopRecording = function () {
            return Promise.reject(new Error("Native recording not available on web"));
        };
        PassifloraIO.diagnoseNativeAudio = function () {
            return Promise.reject(new Error("Native audio diagnostics not available on web"));
        };
    }

    /* -- importFile: pick a file from the real filesystem into VFS -- */
    PassifloraIO.importFile = function (extensions) {
        return new Promise(function (resolve) {
            var input = document.createElement("input");
            input.type = "file";
            if (extensions && extensions.length > 0)
                input.accept = extensions.join(",");
            input.style.display = "none";
            document.body.appendChild(input);
            input.addEventListener("change", function () {
                var file = input.files[0];
                document.body.removeChild(input);
                if (!file) { resolve(null); return; }
                var reader = new FileReader();
                reader.onload = function () {
                    var bytes = new Uint8Array(reader.result);
                    var vpath = "/" + file.name;
                    _vfs[vpath] = bytes;
                    _dbPut(vpath, bytes);
                    resolve(vpath);
                };
                reader.onerror = function () { resolve(null); };
                reader.readAsArrayBuffer(file);
            });
            input.addEventListener("cancel", function () {
                document.body.removeChild(input);
                resolve(null);
            });
            input.click();
        });
    };

    /* -- exportFile: save a VFS file to the real filesystem -- */
    PassifloraIO.exportFile = function (vfsPath, suggestedName) {
        return _dbReady.then(function () {
            var data = _vfs[vfsPath];
            if (!data) throw new Error("File not found in VFS: " + vfsPath);
            suggestedName = suggestedName ||
                vfsPath.substring(vfsPath.lastIndexOf("/") + 1);

            /* File System Access API (Chrome / Edge / Chromium WebViews) */
            if (typeof window.showSaveFilePicker === "function") {
                return window.showSaveFilePicker({ suggestedName: suggestedName })
                    .then(function (fh) { return fh.createWritable(); })
                    .then(function (w) {
                        return w.write(data).then(function () { return w.close(); });
                    })
                    .then(function () { return vfsPath; })
                    .catch(function (err) {
                        if (err.name === "AbortError") return null;
                        throw err;
                    });
            }

            /* Fallback: browser download */
            PassifloraIO.webDownload(vfsPath);
            return vfsPath;
        });
    };

    /* -- webDownload: trigger browser download for a VFS path -- */
    PassifloraIO.webDownload = function (path, mimeType) {
        var data = _vfs[path];
        if (!data) return;
        var filename = path.substring(path.lastIndexOf("/") + 1);
        /* Native WKWebView save panel (macOS / iOS) */
        if (window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.passifloraSaveFile) {
            var binary = "";
            for (var j = 0; j < data.length; j++)
                binary += String.fromCharCode(data[j]);
            window.webkit.messageHandlers.passifloraSaveFile.postMessage({
                filename: filename,
                data: btoa(binary)
            });
            return;
        }
        /* Browser download fallback */
        var blob = new Blob([data], {
            type: mimeType || "application/octet-stream"
        });
        var url = URL.createObjectURL(blob);
        var a = document.createElement("a");
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
    };

    /* -- exportVFS: serialise the entire VFS to a JSON download -- */
    PassifloraIO.exportVFS = function () {
        return _dbReady.then(function () {
            var obj = {};
            var keys = Object.keys(_vfs);
            for (var i = 0; i < keys.length; i++) {
                var data = _vfs[keys[i]];
                var binary = "";
                for (var j = 0; j < data.length; j++)
                    binary += String.fromCharCode(data[j]);
                obj[keys[i]] = btoa(binary);
            }
            var json = JSON.stringify(obj, null, 2);
            /* Native WKWebView save panel (macOS / iOS) */
            if (window.webkit && window.webkit.messageHandlers &&
                window.webkit.messageHandlers.passifloraSaveFile) {
                window.webkit.messageHandlers.passifloraSaveFile.postMessage({
                    filename: "passiflora_vfs.json",
                    data: btoa(unescape(encodeURIComponent(json)))
                });
                return keys.length;
            }
            /* Browser download fallback */
            var blob = new Blob([json], { type: "application/json" });
            var url = URL.createObjectURL(blob);
            var a = document.createElement("a");
            a.href = url;
            a.download = "passiflora_vfs.json";
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
            return keys.length;
        });
    };

    /* -- importVFS: load a previously-exported VFS JSON file -- */
    PassifloraIO.importVFS = function () {
        return new Promise(function (resolve, reject) {
            var input = document.createElement("input");
            input.type = "file";
            input.accept = ".json";
            input.style.display = "none";
            document.body.appendChild(input);
            input.addEventListener("change", function () {
                var file = input.files[0];
                document.body.removeChild(input);
                if (!file) { resolve(0); return; }
                var reader = new FileReader();
                reader.onload = function () {
                    try {
                        var obj = JSON.parse(reader.result);
                        var count = 0;
                        var keys = Object.keys(obj);
                        for (var i = 0; i < keys.length; i++) {
                            var binary = atob(obj[keys[i]]);
                            var bytes = new Uint8Array(binary.length);
                            for (var j = 0; j < binary.length; j++)
                                bytes[j] = binary.charCodeAt(j);
                            _vfs[keys[i]] = bytes;
                            _dbPut(keys[i], bytes);
                            count++;
                        }
                        resolve(count);
                    } catch (e) {
                        reject(new Error("Invalid VFS JSON: " + e.message));
                    }
                };
                reader.onerror = function () {
                    reject(new Error("Failed to read file"));
                };
                reader.readAsText(file);
            });
            input.addEventListener("cancel", function () {
                document.body.removeChild(input);
                resolve(0);
            });
            input.click();
        });
    };

    /* -- eraseVFS: clear every file from the VFS and IndexedDB -- */
    PassifloraIO.eraseVFS = function () {
        return _dbReady.then(function () {
            if (!confirm("Erase all files in the virtual file system?")) {
                return 0;
            }
            /* Close any open file handles */
            _handles = {};
            /* Count files before clearing */
            var count = Object.keys(_vfs).length;
            /* Clear the in-memory VFS */
            var keys = Object.keys(_vfs);
            for (var i = 0; i < keys.length; i++) {
                delete _vfs[keys[i]];
            }
            /* Clear directories */
            var dk = Object.keys(_dirs);
            for (var i = 0; i < dk.length; i++) {
                delete _dirs[dk[i]];
            }
            _cwd = "/";
            /* Clear the IndexedDB object stores */
            return new Promise(function (resolve, reject) {
                var tx = _db.transaction(["files", "dirs"], "readwrite");
                var req1 = tx.objectStore("files").clear();
                var req2 = tx.objectStore("dirs").clear();
                tx.oncomplete = function () { resolve(count); };
                tx.onerror = function () {
                    reject(new Error("Failed to clear IndexedDB: " + tx.error));
                };
            });
        });
    };

    /* -- resetVFS: erase VFS then repopulate from compiled-in preload -- */
    PassifloraIO.resetVFS = function () {
        return _dbReady.then(function () {
            /* Close any open file handles */
            _handles = {};
            /* Clear the in-memory VFS */
            var keys = Object.keys(_vfs);
            for (var i = 0; i < keys.length; i++) {
                delete _vfs[keys[i]];
            }
            /* Clear directories */
            var dk = Object.keys(_dirs);
            for (var i = 0; i < dk.length; i++) {
                delete _dirs[dk[i]];
            }
            _cwd = "/";
            /* Clear the IndexedDB object stores, then reload preload data */
            return new Promise(function (resolve, reject) {
                var tx = _db.transaction(["files", "dirs"], "readwrite");
                tx.objectStore("files").clear();
                tx.objectStore("dirs").clear();
                tx.oncomplete = function () {
                    _loadPreloadData();
                    resolve();
                };
                tx.onerror = function () {
                    reject(new Error("Failed to clear IndexedDB: " + tx.error));
                };
            });
        });
    };

    /* -- _posixCall: intercept closeAllFileHandles, pass through others -- */
    var _origPosixCall = (PassifloraConfig.os_name !== "WWW" &&
        typeof PassifloraIO._posixCall === "function")
        ? PassifloraIO._posixCall.bind(PassifloraIO) : null;

    PassifloraIO._posixCall = function (fn, params) {
        if (fn === "closeAllFileHandles") {
            /* Best-effort flush of open files to IndexedDB */
            var keys = Object.keys(_handles);
            for (var i = 0; i < keys.length; i++) {
                var fh = _handles[keys[i]];
                if (fh && _vfs[fh.path]) _dbPut(fh.path, _vfs[fh.path]);
            }
            _handles = {};
            return Promise.resolve(0);
        }
        if (_origPosixCall) return _origPosixCall(fn, params);
        return Promise.reject(
            new Error("POSIX call '" + fn + "' is not available on web"));
    };
})();

/* POSIX constants (global) */
const SEEK_SET = 0, SEEK_CUR = 1, SEEK_END = 2;

/* Global convenience aliases for POSIX functions */
function fopen(path, mode)         { return PassifloraIO.fopen(path, mode); }
function fclose(handle)            { return PassifloraIO.fclose(handle); }
function fread(handle, size)       { return PassifloraIO.fread(handle, size); }
function fwrite(handle, data)      { return PassifloraIO.fwrite(handle, data); }
function fgets(handle)             { return PassifloraIO.fgets(handle); }
function fputs(handle, str)        { return PassifloraIO.fputs(handle, str); }
function fseek(handle, offset, wh) { return PassifloraIO.fseek(handle, offset, wh); }
function ftell(handle)             { return PassifloraIO.ftell(handle); }
function rewind(handle)            { return PassifloraIO.rewind(handle); }
function feof(handle)              { return PassifloraIO.feof(handle); }
function fflush(handle)            { return PassifloraIO.fflush(handle); }
function remove(path)              { return PassifloraIO.remove(path); }
function rename(oldpath, newpath)  { return PassifloraIO.rename(oldpath, newpath); }
function mkdir(path)               { return PassifloraIO.mkdir(path); }
function rmdir(path)               { return PassifloraIO.rmdir(path); }
function chdir(path)               { return PassifloraIO.chdir(path); }
function getcwd()                  { return PassifloraIO.getcwd(); }

/* Auto-patch remote links once the DOM is ready */
document.addEventListener("DOMContentLoaded", function () {
    PassifloraIO.patchLinks();
});

/* Close leaked file handles on page navigation/reload */
window.addEventListener("beforeunload", function () {
    PassifloraIO._posixCall("closeAllFileHandles", {});
});

/* Geolocation polyfill for WKWebView (macOS/iOS) —
   navigator.geolocation is blocked for non-sandboxed apps,
   so override it with the native CLLocationManager bridge. */
(function () {
    if (window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.passifloraGeolocation) {
        PassifloraIO._nativeGeolocation = navigator.geolocation;
        Object.defineProperty(navigator, 'geolocation', {
            value: {
                getCurrentPosition: function (s, e) {
                    PassifloraIO.getCurrentPosition(s, e);
                },
                watchPosition: function () { return 0; },
                clearWatch: function () {}
            },
            configurable: true
        });
    }
})();