PassifloraIO = {

    _geoCallbacks: {},
    _geoCounter: 0,

    _geoResolve: function (id, lat, lon, accuracy) {
        var cb = PassifloraIO._geoCallbacks[id];
        if (cb) {
            delete PassifloraIO._geoCallbacks[id];
            cb.resolve({
                coords: { latitude: lat, longitude: lon, accuracy: accuracy,
                          altitude: null, altitudeAccuracy: null,
                          heading: null, speed: null },
                timestamp: Date.now()
            });
        }
    },

    _geoReject: function (id, code, message) {
        var cb = PassifloraIO._geoCallbacks[id];
        if (cb) {
            delete PassifloraIO._geoCallbacks[id];
            var err = new Error(message);
            err.code = code;
            cb.reject(err);
        }
    },

    getCurrentPosition: function () {
        /* Use native bridge if available (WKWebView on macOS/iOS/Linux) */
        if (window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.passifloraGeolocation) {
            var id = "geo_" + (++PassifloraIO._geoCounter);
            return new Promise(function (resolve, reject) {
                PassifloraIO._geoCallbacks[id] = { resolve: resolve, reject: reject };
                window.webkit.messageHandlers.passifloraGeolocation.postMessage(id);
            });
        }
        /* Android native bridge */
        if (window.PassifloraBridge && window.PassifloraBridge.requestLocation) {
            var id = "geo_" + (++PassifloraIO._geoCounter);
            return new Promise(function (resolve, reject) {
                PassifloraIO._geoCallbacks[id] = { resolve: resolve, reject: reject };
                window.PassifloraBridge.requestLocation(id);
            });
        }
        /* Fallback to standard Geolocation API (regular browsers) */
        if (!navigator.geolocation) {
            return Promise.reject(new Error("Geolocation API not supported"));
        }
        return new Promise(function (resolve, reject) {
            navigator.geolocation.getCurrentPosition(resolve, reject);
        }); 
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
        var links = document.querySelectorAll("a[href]");
        for (var i = 0; i < links.length; i++) {
            (function (a) {
                var href = a.getAttribute("href");
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
        var cb = PassifloraIO._posixCallbacks[id];
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
        var parts = "func=" + encodeURIComponent(fn);
        var keys = Object.keys(params);
        for (var i = 0; i < keys.length; i++) {
            parts += "&" + encodeURIComponent(keys[i]) + "=" +
                     encodeURIComponent(params[keys[i]]);
        }

        /* Android: synchronous @JavascriptInterface return */
        if (window.PassifloraBridge && window.PassifloraBridge.posixCall) {
            try {
                var json = window.PassifloraBridge.posixCall(parts);
                var result = JSON.parse(json);
                if (result.ok) return Promise.resolve(result.result);
                return Promise.reject(new Error(result.error));
            } catch (e) {
                return Promise.reject(e);
            }
        }

        /* macOS / iOS / Linux: async via WKScriptMessageHandler */
        if (window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.passifloraPosix) {
            var id = "posix_" + (++PassifloraIO._posixCounter);
            return new Promise(function (resolve, reject) {
                PassifloraIO._posixCallbacks[id] = { resolve: resolve, reject: reject };
                window.webkit.messageHandlers.passifloraPosix.postMessage(
                    "id=" + id + "&" + parts);
            });
        }

        /* Windows WebView2: async via chrome.webview.postMessage */
        if (window.chrome && window.chrome.webview) {
            var id = "posix_" + (++PassifloraIO._posixCounter);
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
            var binary = atob(b64);
            var bytes = new Uint8Array(binary.length);
            for (var i = 0; i < binary.length; i++)
                bytes[i] = binary.charCodeAt(i);
            return bytes;
        });
    },

    fwrite: function (handle, data) {
        var b64;
        if (typeof data === "string") {
            b64 = btoa(unescape(encodeURIComponent(data)));
        } else {
            var binary = "";
            for (var i = 0; i < data.length; i++)
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

};

/* POSIX constants (global) */
var SEEK_SET = 0, SEEK_CUR = 1, SEEK_END = 2;

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