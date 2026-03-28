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

    getUsername: function () {
        return PassifloraIO._posixCall("getUsername", {});
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

        var SEP = "/";                       /* path separator */
        if (navigator.platform && navigator.platform.indexOf("Win") >= 0)
            SEP = "\\";

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
                    screen.appendChild(filterRow);

                    /* Fetch directory listing and populate */
                    var entries = null;

                    function populateList() {
                        if (!entries) return;
                        listWrap.innerHTML = "";
                        var ul = document.createElement("ul");
                        ul.className = "passiflora_fo_ul";

                        /* ".." entry — go up a folder */
                        var upLi = document.createElement("li");
                        upLi.className = "passiflora_fo_item passiflora_fo_dir";
                        upLi.textContent = "\uD83D\uDCC1 ..";
                        var upArrow = document.createElement("span");
                        upArrow.className = "passiflora_fo_arrow";
                        upArrow.textContent = "\u276E";
                        upLi.appendChild(upArrow);
                        upLi.addEventListener("click", function () { slideBack(); });
                        ul.appendChild(upLi);

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
                                li.textContent = ent.name;
                                if (matches) {
                                    li.addEventListener("click", function () {
                                        finish(joinPath(dirPath, ent.name));
                                    });
                                }
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
        if (navigator.platform && navigator.platform.indexOf("Win") >= 0)
            SEP = "\\";

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
                    screen.appendChild(filterRow);

                    /* Fetch directory listing and populate */
                    var entries = null;

                    function populateList() {
                        if (!entries) return;
                        listWrap.innerHTML = "";
                        var ul = document.createElement("ul");
                        ul.className = "passiflora_fo_ul";

                        /* ".." entry */
                        var upLi = document.createElement("li");
                        upLi.className = "passiflora_fo_item passiflora_fo_dir";
                        upLi.textContent = "\uD83D\uDCC1 ..";
                        var upArrow = document.createElement("span");
                        upArrow.className = "passiflora_fo_arrow";
                        upArrow.textContent = "\u276E";
                        upLi.appendChild(upArrow);
                        upLi.addEventListener("click", function () { slideBack(); });
                        ul.appendChild(upLi);

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
                                li.textContent = ent.name;
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

};

/* ================================================================ */
/*  WWW (plain browser) polyfill                                     */
/*  When os_name === "WWW", replace native POSIX bridge calls with   */
/*  in-memory virtual filesystem + HTML File / download APIs.        */
/* ================================================================ */
(function () {
    if (typeof PassifloraConfig === "undefined" ||
        PassifloraConfig.os_name !== "WWW") return;

    /* ---------- In-memory virtual file system ---------- */
    var _vfs = {};               /* path -> Uint8Array */
    var _handles = {};           /* handle_id -> { path, mode, pos } */
    var _handleCounter = 0;
    var _savePaths = {};         /* paths from menusavas awaiting download on fclose */
    var _saveHandles = {};       /* paths from menusavas → FileSystemFileHandle (File System Access API) */

    function _nextHandle() { return "webfh_" + (++_handleCounter); }

    /* -- System info -- */
    PassifloraIO.getUsername = function () {
        return Promise.resolve("web_user");
    };

    PassifloraIO.getHomeFolder = function () {
        return Promise.resolve("/");
    };

    PassifloraIO.listDirectory = function (path) {
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
        return Promise.resolve(entries);
    };

    /* -- POSIX file I/O -- */
    PassifloraIO.fopen = function (path, mode) {
        mode = mode || "r";
        if (mode.indexOf("r") >= 0 && !_vfs[path]) {
            return Promise.reject(new Error("File not found: " + path));
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
        return Promise.resolve(h);
    };

    PassifloraIO.fclose = function (handle) {
        var fh = _handles[handle];
        if (!fh) { delete _handles[handle]; return Promise.resolve(0); }

        /* File System Access API handle (showSaveFilePicker) */
        if (_saveHandles[fh.path]) {
            var fileHandle = _saveHandles[fh.path];
            delete _saveHandles[fh.path];
            delete _handles[handle];
            var data = _vfs[fh.path] || new Uint8Array(0);
            return fileHandle.createWritable().then(function (writable) {
                return writable.write(data).then(function () {
                    return writable.close();
                });
            }).then(function () { return 0; });
        }

        /* Legacy fallback: auto-download */
        if (_savePaths[fh.path]) {
            delete _savePaths[fh.path];
            PassifloraIO.webDownload(fh.path);
        }
        delete _handles[handle];
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
        delete _vfs[path];
        return Promise.resolve(0);
    };

    PassifloraIO.rename = function (oldpath, newpath) {
        if (!_vfs[oldpath])
            return Promise.reject(new Error("File not found: " + oldpath));
        _vfs[newpath] = _vfs[oldpath];
        delete _vfs[oldpath];
        return Promise.resolve(0);
    };

    /* -- Recording: not natively available, fall back to MediaRecorder -- */
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

    /* -- menuopen: HTML <input type="file"> -- */
    PassifloraIO.menuopen = function (extensions) {
        return new Promise(function (resolve) {
            var input = document.createElement("input");
            input.type = "file";
            if (extensions && extensions.length > 0) {
                input.accept = extensions.join(",");
            }
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

    /* -- menusavas: native save-file picker (showSaveFilePicker) -- */
    PassifloraIO.menusavas = function (extensions, defaultName) {
        /* Build accept types for showSaveFilePicker */
        var types = [];
        if (extensions && extensions.length > 0) {
            var exts = [];
            for (var i = 0; i < extensions.length; i++) {
                var ext = extensions[i].toLowerCase();
                if (ext.charAt(0) !== ".") ext = "." + ext;
                exts.push(ext);
            }
            types.push({
                description: "Allowed files",
                accept: { "application/octet-stream": exts }
            });
        }

        /* Try the File System Access API (Chrome / Edge) */
        if (typeof window.showSaveFilePicker === "function") {
            var opts = { suggestedName: defaultName || "untitled" };
            if (types.length) opts.types = types;
            return window.showSaveFilePicker(opts).then(function (fileHandle) {
                var name = fileHandle.name;
                var vpath = "/" + name;
                _vfs[vpath] = new Uint8Array(0);
                _saveHandles[vpath] = fileHandle;
                return vpath;
            }).catch(function (err) {
                /* User cancelled the picker */
                if (err.name === "AbortError") return null;
                throw err;
            });
        }

        /* Fallback (Safari / Firefox): use defaultName and trigger a
           browser download on fclose.  The download bar / sheet IS the
           browser's native save experience for these engines. */
        var name = defaultName || "untitled";
        if (extensions && extensions.length > 0) {
            var hasExt = false;
            for (var j = 0; j < extensions.length; j++) {
                var e = extensions[j].toLowerCase().replace(/^\./, "");
                if (name.toLowerCase().endsWith("." + e)) {
                    hasExt = true; break;
                }
            }
            if (!hasExt) {
                var first = extensions[0];
                name += first.charAt(0) === "." ? first : "." + first;
            }
        }
        var vpath = "/" + name;
        if (!_vfs[vpath]) _vfs[vpath] = new Uint8Array(0);
        _savePaths[vpath] = true;
        return Promise.resolve(vpath);
    };

    /* -- webDownload: trigger browser download for a VFS path -- */
    PassifloraIO.webDownload = function (path, mimeType) {
        var data = _vfs[path];
        if (!data) return;
        var blob = new Blob([data], {
            type: mimeType || "application/octet-stream"
        });
        var url = URL.createObjectURL(blob);
        var a = document.createElement("a");
        a.href = url;
        a.download = path.substring(path.lastIndexOf("/") + 1);
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
    };

    /* -- _posixCall: stub so closeAllFileHandles etc. don't throw -- */
    PassifloraIO._posixCall = function (fn) {
        if (fn === "closeAllFileHandles") {
            _handles = {};
            return Promise.resolve(0);
        }
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