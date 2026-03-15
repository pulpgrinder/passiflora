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
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;

/**
 * Launches the embedded HTTP server (native C, via JNI) then shows a
 * full-screen WebView pointed at localhost.
 */
public class MainActivity extends Activity {

    private static final int LOCATION_PERMISSION_REQUEST = 1;
    private static final int MEDIA_PERMISSION_REQUEST = 2;
    private WebView webView;
    private int serverPort;
    private GeolocationPermissions.Callback pendingGeoCallback;
    private String pendingGeoOrigin;

    static { System.loadLibrary("passiflora"); }

    /** Pass the app-private files directory to native code. */
    private static native void nativeSetFilesDir(String path);

    /** Start the native HTTP server; returns the assigned port. */
    private static native int startServer();

    /** Call native POSIX bridge; returns JSON result string. */
    private static native String nativePosixCall(String params);

    /** Initialize the native debug bridge with a reference to this activity. */
    private native void nativeInitDebug();

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
            return nativePosixCall(params);
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        /* On Android 11+, request all-files access so the POSIX bridge
           can read/write the shared Documents folder directly. */
        if (BuildConfig.PERM_UNRESTRICTEDFILESYSTEMACCESS
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

        nativeSetFilesDir(getFilesDir().getAbsolutePath());
        serverPort = startServer();

        /* Request camera/mic runtime permissions before configuring WebView */
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !hasMediaPermissions()) {
            requestMediaPermissions();
            return; /* configureAndLoadWebView() called after grant */
        }
        configureAndLoadWebView();
    }

    private boolean hasMediaPermissions() {
        boolean ok = true;
        if (BuildConfig.PERM_CAMERA
                && checkSelfPermission(android.Manifest.permission.CAMERA)
                   != PackageManager.PERMISSION_GRANTED) ok = false;
        if (BuildConfig.PERM_MICROPHONE
                && checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)
                   != PackageManager.PERMISSION_GRANTED) ok = false;
        return ok;
    }

    private void requestMediaPermissions() {
        java.util.List<String> perms = new java.util.ArrayList<>();
        if (BuildConfig.PERM_CAMERA) perms.add(android.Manifest.permission.CAMERA);
        if (BuildConfig.PERM_MICROPHONE) perms.add(android.Manifest.permission.RECORD_AUDIO);
        if (!perms.isEmpty()) {
            requestPermissions(perms.toArray(new String[0]), MEDIA_PERMISSION_REQUEST);
        }
    }

    private void configureAndLoadWebView() {
        WebView webView = new WebView(this);
        this.webView = webView;
        WebSettings ws = webView.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setMediaPlaybackRequiresUserGesture(false);
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

            @Override
            public void onPageFinished(WebView view, String url) {
                if (BuildConfig.PERM_REMOTEDEBUGGING) {
                    String ip = getLocalIp().replaceAll("[^0-9a-fA-F.:]", "");
                    view.evaluateJavascript(
                        "PassifloraIO._autoDebug('" + ip + "'," + serverPort + ")",
                        null);
                }
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
        nativeInitDebug();
        webView.loadUrl("http://127.0.0.1:" + serverPort + "/");
    }

    /** Called from native code to evaluate JavaScript in the WebView. */
    @SuppressWarnings("unused")
    public void evalJsFromNative(final String js) {
        if (webView == null || js == null) return;
        runOnUiThread(new Runnable() {
            @Override public void run() {
                webView.evaluateJavascript(js, null);
            }
        });
    }

    /** Get the local LAN IP address via UDP connect trick. */
    private static String getLocalIp() {
        try {
            DatagramSocket sock = new DatagramSocket();
            sock.connect(new InetSocketAddress("8.8.8.8", 53));
            String ip = sock.getLocalAddress().getHostAddress();
            sock.close();
            return ip;
        } catch (Exception e) {
            return "127.0.0.1";
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode,
            String[] permissions, int[] grantResults) {
        if (requestCode == MEDIA_PERMISSION_REQUEST) {
            /* Proceed regardless of grant/deny — WebView will just lack media */
            configureAndLoadWebView();
            return;
        }
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
