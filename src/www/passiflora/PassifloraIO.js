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
    /*  Debug bridge — remote JavaScript execution                      */
    /* ================================================================ */

    _debugKey: null,

    debug: function (on) {
        if (on) {
            /* Generate a UUID v4 as the shared key */
            var key = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(
                /[xy]/g, function (c) {
                    var r = (Math.random() * 16) | 0;
                    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
                });
            PassifloraIO._debugKey = key;
            PassifloraIO._debugLog(JSON.stringify({port: parseInt(location.port), key: key}));
        } else {
            PassifloraIO._debugKey = null;
            PassifloraIO._debugLog('Debug mode OFF');
        }
    },

    _debugLog: function (msg) {
        var el = document.getElementById('_dbg');
        if (!el) {
            el = document.createElement('div');
            el.id = '_dbg';
            el.style.cssText = 'position:fixed;top:0;left:0;right:0;background:#ff0;color:#000;font:12px monospace;padding:4px 4px 8px 4px;z-index:99999;white-space:pre-wrap;max-height:30vh;overflow-y:auto;';
            document.body.appendChild(el);
            document.body.style.marginTop = (el.offsetHeight + 4) + 'px';
        }
        el.textContent += msg + '\n';
        document.body.style.marginTop = (el.offsetHeight + 4) + 'px';
    },

    _debugExec: function (payload) {
        PassifloraIO._debugLog('entry, payload len=' + payload.length);
        if (!PassifloraIO._debugKey) { PassifloraIO._debugLog('FAIL: no key'); return; }
        try {
            var msg = JSON.parse(payload);
        } catch (e) { PassifloraIO._debugLog('FAIL: JSON parse: ' + e.message); return; }
        if (!msg.javascript || typeof msg.javascript !== 'string') { PassifloraIO._debugLog('FAIL: no javascript field'); return; }
        if (!msg.signature || typeof msg.signature !== 'string') { PassifloraIO._debugLog('FAIL: no signature field'); return; }

        PassifloraIO._debugLog('validating sig...');

        if (!crypto || !crypto.subtle) {
            PassifloraIO._debugLog('FAIL: crypto.subtle not available');
            return;
        }

        /* Validate HMAC-SHA256 signature */
        var enc = new TextEncoder();
        var keyData = enc.encode(PassifloraIO._debugKey);
        var msgData = enc.encode(msg.javascript);
        crypto.subtle.importKey(
            'raw', keyData, { name: 'HMAC', hash: 'SHA-256' },
            false, ['sign']
        ).then(function (cryptoKey) {
            return crypto.subtle.sign('HMAC', cryptoKey, msgData);
        }).then(function (sigBuf) {
            var arr = new Uint8Array(sigBuf);
            var hex = '';
            for (var i = 0; i < arr.length; i++)
                hex += ('0' + arr[i].toString(16)).slice(-2);
            PassifloraIO._debugLog('computed: ' + hex.substring(0, 16) + '...');
            PassifloraIO._debugLog('received: ' + msg.signature.substring(0, 16) + '...');
            if (hex !== msg.signature) {
                PassifloraIO._debugLog('FAIL: signature mismatch');
                return;
            }
            PassifloraIO._debugLog('sig OK, evaluating...');
            /* Signature valid — execute via inline script with console capture */
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
                var s = document.createElement('script');
                s.textContent = msg.javascript;
                document.head.appendChild(s);
                document.head.removeChild(s);
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
            if (!__err && !__out.length) resultObj.output = '(no output — use console.log() to see values)';
            fetch('/__passiflora/debug_result', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(resultObj)
            });
            PassifloraIO._debugLog('eval done');
        }).catch(function (e) {
            PassifloraIO._debugLog('FAIL: crypto error: ' + e.message);
        });
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