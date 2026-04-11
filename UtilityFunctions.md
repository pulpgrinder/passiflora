These are methods on `PassifloraIO` (not available as bare globals).

| Function | Description |
|----------|-------------|
| `PassifloraIO.openExternal(url)` | Open a URL in the system's default browser. On Android uses the native bridge; on other platforms issues a request to the embedded server's `openexternal` endpoint. Only `http://` and `https://` URLs are allowed. |
| `PassifloraIO.getCurrentPosition(successCb, errorCb)` | Get the device's current GPS position. On macOS/iOS uses the native CLLocationManager bridge; on other platforms delegates to `navigator.geolocation`. Callbacks follow the standard Geolocation API signature. |
| `PassifloraIO.webDownload(path, mimeType)` | Trigger a browser download for a VFS file. On macOS/iOS uses the native save panel via `passifloraSaveFile`; on other platforms creates a temporary download link. `mimeType` defaults to `"application/octet-stream"` if omitted. |
| `PassifloraIO.patchLinks()` | Scan the DOM for `<a href>` elements with `http://` or `https://` URLs and attach click handlers that route them through `openExternal()` instead of navigating the webview. Called automatically on `DOMContentLoaded`. |
| `PassifloraIO.hasNativeRecording()` | Returns a Promise resolving to `true` if recording is available on this platform, `false` otherwise. |
| `PassifloraIO.startRecording(hasVideo, hasAudio)` | Start recording. `hasVideo` and `hasAudio` are booleans selecting which tracks to capture. Returns a Promise that resolves when recording has started. |
| `PassifloraIO.stopRecording()` | Stop a recording in progress. Returns a Promise resolving to a `Uint8Array` containing the recorded WebM data (or `null` if no data). |
| `PassifloraIO.diagnoseNativeAudio()` | Run audio diagnostics. Returns a Promise resolving to a diagnostic string. |