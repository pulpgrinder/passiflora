package com.example.zipserve;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.location.Criteria;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.WindowManager;
import android.webkit.GeolocationPermissions;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebChromeClient;
import android.webkit.JsResult;
import android.webkit.JsPromptResult;
import android.app.AlertDialog;
import android.widget.EditText;

/**
 * Launches the embedded HTTP server (native C, via JNI) then shows a
 * full-screen WebView pointed at localhost.
 */
public class MainActivity extends Activity {

    private static final int LOCATION_PERMISSION_REQUEST = 1;
    private static final int BRIDGE_LOCATION_PERMISSION = 2;
    private WebView webView;
    private GeolocationPermissions.Callback pendingGeoCallback;
    private String pendingGeoOrigin;
    private String pendingBridgeGeoId;

    static { System.loadLibrary("passiflora"); }

    /** Start the native HTTP server; returns the assigned port. */
    private static native int startServer();

    /* Bridge exposed to JavaScript as window.PassifloraBridge */
    private class Bridge {
        @JavascriptInterface
        public void openExternal(String url) {
            if (url == null || url.isEmpty()) return;
            if (!url.startsWith("http://") && !url.startsWith("https://")) return;
            Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
            startActivity(intent);
        }

        @JavascriptInterface
        public void requestLocation(final String callbackId) {
            if (checkSelfPermission(
                    android.Manifest.permission.ACCESS_FINE_LOCATION)
                    != PackageManager.PERMISSION_GRANTED) {
                pendingBridgeGeoId = callbackId;
                runOnUiThread(() -> requestPermissions(
                    new String[]{
                        android.Manifest.permission.ACCESS_FINE_LOCATION,
                        android.Manifest.permission.ACCESS_COARSE_LOCATION
                    },
                    BRIDGE_LOCATION_PERMISSION));
                return;
            }
            doLocationRequest(callbackId);
        }
    }

    private void doLocationRequest(final String callbackId) {
        if (checkSelfPermission(
                android.Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            rejectGeo(callbackId, 1, "Location permission denied");
            return;
        }
        LocationManager lm = (LocationManager)
            getSystemService(LOCATION_SERVICE);
        if (lm == null) {
            rejectGeo(callbackId, 2, "LocationManager unavailable");
            return;
        }

        /* Pick the best enabled provider via Criteria */
        Criteria criteria = new Criteria();
        criteria.setAccuracy(Criteria.ACCURACY_FINE);
        String provider = lm.getBestProvider(criteria, true);

        if (provider == null) {
            rejectGeo(callbackId, 2,
                "No location provider available – enable Location in device Settings");
            return;
        }

        /* Check for a cached location first (< 60 s old) */
        Location last = lm.getLastKnownLocation(provider);
        if (last != null
                && System.currentTimeMillis() - last.getTime() < 60_000) {
            resolveGeo(callbackId, last.getLatitude(),
                       last.getLongitude(), last.getAccuracy());
            return;
        }

        /* Request a fresh fix with a 15-second timeout */
        final boolean[] responded = { false };
        Handler handler = new Handler(Looper.getMainLooper());

        LocationListener listener = new LocationListener() {
            @Override
            public void onLocationChanged(Location loc) {
                if (responded[0]) return;
                responded[0] = true;
                resolveGeo(callbackId, loc.getLatitude(),
                           loc.getLongitude(), loc.getAccuracy());
            }
            @Override public void onProviderDisabled(String p) {
                if (responded[0]) return;
                responded[0] = true;
                rejectGeo(callbackId, 2, "Provider disabled");
            }
            @Override public void onProviderEnabled(String p) {}
            @Override public void onStatusChanged(String p, int s, Bundle e) {}
        };

        lm.requestSingleUpdate(provider, listener, Looper.getMainLooper());

        handler.postDelayed(() -> {
            if (responded[0]) return;
            responded[0] = true;
            lm.removeUpdates(listener);
            /* Timeout — try last known from any provider as fallback */
            Location fallback = lm.getLastKnownLocation(provider);
            if (fallback == null)
                fallback = lm.getLastKnownLocation(
                    LocationManager.GPS_PROVIDER);
            if (fallback == null)
                fallback = lm.getLastKnownLocation(
                    LocationManager.NETWORK_PROVIDER);
            if (fallback != null) {
                resolveGeo(callbackId, fallback.getLatitude(),
                           fallback.getLongitude(), fallback.getAccuracy());
            } else {
                rejectGeo(callbackId, 2, "Location request timed out");
            }
        }, 15_000);
    }

    private void resolveGeo(String id, double lat, double lon, double acc) {
        String js = String.format(
            "PassifloraIO._geoResolve('%s', %.8f, %.8f, %.2f);",
            id, lat, lon, acc);
        runOnUiThread(() -> webView.evaluateJavascript(js, null));
    }

    private void rejectGeo(String id, int code, String msg) {
        String js = String.format(
            "PassifloraIO._geoReject('%s', %d, '%s');",
            id, code, msg.replace("'", "\\'"));
        runOnUiThread(() -> webView.evaluateJavascript(js, null));
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        /* Full-screen: extend behind status bar */
        getWindow().addFlags(
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);

        int port = startServer();

        WebView webView = new WebView(this);
        this.webView = webView;
        WebSettings ws = webView.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setGeolocationEnabled(true);

        webView.addJavascriptInterface(new Bridge(), "PassifloraBridge");

        webView.setWebViewClient(new WebViewClient());

        /* Handle JavaScript alert / confirm / prompt */
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onJsAlert(WebView view, String url,
                                     String message, JsResult result) {
                new AlertDialog.Builder(MainActivity.this)
                    .setMessage(message)
                    .setPositiveButton("OK",
                        (d, w) -> result.confirm())
                    .setOnCancelListener(d -> result.cancel())
                    .show();
                return true;
            }

            @Override
            public boolean onJsConfirm(WebView view, String url,
                                       String message, JsResult result) {
                new AlertDialog.Builder(MainActivity.this)
                    .setMessage(message)
                    .setPositiveButton("OK",
                        (d, w) -> result.confirm())
                    .setNegativeButton("Cancel",
                        (d, w) -> result.cancel())
                    .setOnCancelListener(d -> result.cancel())
                    .show();
                return true;
            }

            @Override
            public boolean onJsPrompt(WebView view, String url,
                                      String message, String defaultValue,
                                      JsPromptResult result) {
                EditText input = new EditText(MainActivity.this);
                if (defaultValue != null) input.setText(defaultValue);
                new AlertDialog.Builder(MainActivity.this)
                    .setMessage(message)
                    .setView(input)
                    .setPositiveButton("OK",
                        (d, w) -> result.confirm(
                            input.getText().toString()))
                    .setNegativeButton("Cancel",
                        (d, w) -> result.cancel())
                    .setOnCancelListener(d -> result.cancel())
                    .show();
                return true;
            }

            @Override
            public void onGeolocationPermissionsShowPrompt(
                    String origin,
                    GeolocationPermissions.Callback callback) {
                if (checkSelfPermission(
                        android.Manifest.permission.ACCESS_FINE_LOCATION)
                        == PackageManager.PERMISSION_GRANTED) {
                    callback.invoke(origin, true, false);
                } else {
                    pendingGeoCallback = callback;
                    pendingGeoOrigin = origin;
                    requestPermissions(
                        new String[]{
                            android.Manifest.permission.ACCESS_FINE_LOCATION,
                            android.Manifest.permission.ACCESS_COARSE_LOCATION
                        },
                        LOCATION_PERMISSION_REQUEST);
                }
            }
        });

        setContentView(webView);
        webView.loadUrl("http://127.0.0.1:" + port + "/");
    }

    @Override
    public void onRequestPermissionsResult(int requestCode,
            String[] permissions, int[] grantResults) {
        if (requestCode == LOCATION_PERMISSION_REQUEST
                && pendingGeoCallback != null) {
            boolean granted = grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED;
            pendingGeoCallback.invoke(pendingGeoOrigin, granted, false);
            pendingGeoCallback = null;
            pendingGeoOrigin = null;
        }
        if (requestCode == BRIDGE_LOCATION_PERMISSION
                && pendingBridgeGeoId != null) {
            String id = pendingBridgeGeoId;
            pendingBridgeGeoId = null;
            boolean granted = grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED;
            if (granted) {
                doLocationRequest(id);
            } else {
                rejectGeo(id, 1, "Location permission denied");
            }
        }
    }
}
