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

};

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