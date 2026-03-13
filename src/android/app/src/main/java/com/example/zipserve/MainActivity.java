package com.example.zipserve;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.view.WindowManager;
import android.webkit.GeolocationPermissions;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebChromeClient;
import android.webkit.JsResult;
import android.webkit.JsPromptResult;
import android.webkit.PermissionRequest;
import android.app.AlertDialog;
import android.os.Build;
import android.os.Environment;
import android.provider.Settings;
import android.widget.EditText;

/**
 * Launches the embedded HTTP server (native C, via JNI) then shows a
 * full-screen WebView pointed at localhost.
 */
public class MainActivity extends Activity {

    private static final int LOCATION_PERMISSION_REQUEST = 1;
    private WebView webView;
    private GeolocationPermissions.Callback pendingGeoCallback;
    private String pendingGeoOrigin;

    static { System.loadLibrary("passiflora"); }

    /** Start the native HTTP server; returns the assigned port. */
    private static native int startServer();

    /** Call native POSIX bridge; returns JSON result string. */
    private static native String nativePosixCall(String params);

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
        public String posixCall(String params) {
            /* Intercept getHomeFolder on Android — return shared Documents dir */
            if (params != null && params.contains("func=getHomeFolder")) {
                java.io.File docs = Environment
                    .getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOCUMENTS);
                String appName = getString(R.string.app_name);
                java.io.File dir = new java.io.File(docs, appName);
                dir.mkdirs();
                String path = dir.getAbsolutePath()
                    .replace("\\", "\\\\").replace("\"", "\\\"");
                return "{\"ok\":true,\"result\":\"" + path + "\"}";
            }
            return nativePosixCall(params);
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        /* On Android 11+, request all-files access so the POSIX bridge
           can read/write the shared Documents folder directly. */
        if (BuildConfig.PERM_ANDROIDEXTERNALSTORAGE
                && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                && !Environment.isExternalStorageManager()) {
            Intent intent = new Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:" + getPackageName()));
            startActivity(intent);
        }

        /* Full-screen: extend behind status bar */
        getWindow().addFlags(
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);

        int port = startServer();

        WebView webView = new WebView(this);
        this.webView = webView;
        WebSettings ws = webView.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setGeolocationEnabled(BuildConfig.PERM_LOCATION);

        webView.addJavascriptInterface(new Bridge(), "PassifloraBridge");

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view,
                    android.webkit.WebResourceRequest request) {
                String host = request.getUrl().getHost();
                if ("127.0.0.1".equals(host) || "localhost".equals(host))
                    return false; /* allow localhost navigation */
                /* Block all other navigation — open in system browser */
                String url = request.getUrl().toString();
                if (url.startsWith("http://") || url.startsWith("https://"))
                    startActivity(new Intent(Intent.ACTION_VIEW,
                        request.getUrl()));
                return true;
            }
        });

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
                if (!BuildConfig.PERM_LOCATION) {
                    callback.invoke(origin, false, false);
                    return;
                }
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

            @Override
            public void onPermissionRequest(PermissionRequest request) {
                String[] resources = request.getResources();
                java.util.List<String> granted = new java.util.ArrayList<>();
                for (String r : resources) {
                    if (BuildConfig.PERM_CAMERA
                            && PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(r)) {
                        granted.add(r);
                    }
                    if (BuildConfig.PERM_MICROPHONE
                            && PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(r)) {
                        granted.add(r);
                    }
                }
                if (!granted.isEmpty()) {
                    request.grant(granted.toArray(new String[0]));
                } else {
                    request.deny();
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
    }
}
