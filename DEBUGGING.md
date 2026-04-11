# Debugging

If you build for the WWW target, you'll be able to use normal browser dev tools for debugging. For binaries, Passiflora includes a built-in remote debugging facility that lets you execute JavaScript in a running app from an external browser. This is useful for inspecting app state, testing code snippets, and diagnosing issues on platforms where browser dev tools aren't available (iOS, Android, etc.).

Remote debugging is compile-gated. It is only available when `allowremotedebugging` is set to `true` in `src/config`.

## Enabling Debug Mode

When the `remotedebugging` permission is enabled, debug mode activates automatically at app startup. A full-screen overlay appears with:

- A red **⚠️ Remote Debugging Enabled** warning banner and a reminder not to ship apps with remote debugging turned on.
- A read-only **Debugger URL** field (e.g. `http://192.168.1.42:60810/debug`) with a copy button. Open this URL in a web browser on another machine to use the debugger. Do this before entering your passphrase and clicking OK, as the dialog will disappear after that.
- A **Passphrase** input (masked) where you enter a shared secret used to authenticate debug commands.

After entering a passphrase and clicking **OK**, the overlay closes and the app is ready to accept debug commands.

## How It Works

1. The external debugger computes an HMAC-SHA256 signature of `nonce + ':' + javascript` using the shared passphrase, then POSTs `{"javascript": "...", "signature": "...", "nonce": <number>}` to `http://<host>:<port>/__passiflora/debug`.
2. The app's embedded HTTP server relays the payload to the webview via `passiflora_eval_js()`.
3. Inside the webview, `PassifloraIO._debugExec()` validates the HMAC-SHA256 signature using a pure-JavaScript implementation. If the signature doesn't match, execution is refused and an error is sent back to the debugger. If the nonce is not strictly greater than the previous nonce, the request is rejected as a replay.
4. If valid, the code is executed via indirect `eval()` in global scope.
5. Return values (if not `undefined`) are automatically captured. `console.log()`, `console.error()`, and `console.warn()` output is also captured during execution and POSTed back to `/__passiflora/debug_result`.
6. The debugger polls `/__passiflora/debug_result` and displays the captured output. If no result is ready, the server returns HTTP 204. If a result is still pending from a previous command, the server returns HTTP 429.

## Seeing Output

`console.log()` output and non-`undefined` return values are both captured:

```javascript
// Both of these produce output:
document.title
console.log(document.title)
```

`console.error()` and `console.warn()` output is captured with `ERROR:` or `WARN:` prefixes. `alert()` and other side effects work normally but don't produce captured output.

## Security Notes

- By default, the embedded server listens only on `127.0.0.1` (localhost). Remote debugging connections are blocked unless `allowremotedebugging` is set to `true` in `src/config`, which makes the server listen on all network interfaces (`0.0.0.0`).
- Every command must be signed with HMAC-SHA256 using the shared passphrase and an incrementing nonce. Commands with invalid signatures or replayed nonces are rejected.
- The passphrase input in the app overlay is masked (`type="password"`).
- Debug mode is compile-gated: it is completely absent from the binary unless `allowremotedebugging true` is set in `src/config`.
- Use a strong passphrase, especially when debugging over a network.
- For production releases, set `allowremotedebugging false` in `src/config` (or remove the line entirely).
