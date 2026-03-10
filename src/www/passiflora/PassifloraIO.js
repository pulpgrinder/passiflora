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

};

/* Auto-patch remote links once the DOM is ready */
document.addEventListener("DOMContentLoaded", function () {
    PassifloraIO.patchLinks();
});