# Mac and iOS Code Signing

This document covers everything needed to sign, notarize, and distribute Passiflora apps for macOS and iOS, including Mac App Store and iOS App Store submission.

> **IMPORTANT: Never put your certificates, provisioning profiles, private keys, or app-specific passwords into a folder managed by git or another version control system. Ever.**

---

## Overview

Apple requires all distributed software to be signed. The requirements differ by target:

| Target | Signing required | Notarization required |
|---|---|---|
| macOS — run on your own Mac | Ad-hoc or developer signing | No |
| macOS — distribute outside App Store | Developer ID Application cert | Yes (Apple Gatekeeper blocks unsigned/un-notarized apps) |
| macOS — Mac App Store | Apple Distribution + Installer cert | No (App Store Connect handles it) |
| iOS — run on registered devices | Apple Development cert + provisioning profile | No |
| iOS — App Store | Apple Distribution cert + App Store provisioning profile | No (App Store Connect handles it) |

Passiflora provides two signing commands:

| Command | Description |
|---|---|
| `make sign-macos` | Sign + notarize macOS `.app`, optionally package `.pkg` for Mac App Store |
| `make sign-ios` | Build, sign, and package iOS `.ipa` |

---

## Prerequisites

### Apple Developer Program

Both macOS distribution and iOS distribution require an **Apple Developer Program** membership ($99/year):

https://developer.apple.com/programs/

Without membership you can only ad-hoc-sign (the app runs on your own Mac only; Gatekeeper blocks it everywhere else, and you cannot install on iOS devices without registering them).

### Xcode

Full Xcode (not just command-line tools) is required for iOS builds and for managing certificates and provisioning profiles.

Download Xcode from the Mac App Store or from https://developer.apple.com/xcode/

After installing, open Xcode at least once to accept the license and install additional components:

```
sudo xcodebuild -license accept
```

Verify the iOS SDK is available:

```
xcrun --sdk iphoneos --show-sdk-path
```

### Bundle Identifier

Every app needs a bundle identifier — a reverse-DNS string that uniquely identifies your app. Set it in `src/config`:

```
BUNDLE_ID com.yourcompany.YourApp
```

The bundle identifier must match what you register in your Apple Developer account, your provisioning profiles, and (for the App Store) your App Store Connect record. It cannot be changed after publishing without creating a new app listing.

---

## Certificates

### Creating certificates

Certificates are created and managed at https://developer.apple.com/account/resources/certificates/list, or through Xcode.

**Via Xcode (recommended):**

1. Open **Xcode → Settings → Accounts**.
2. Add your Apple ID if not already present.
3. Select your team, click **Manage Certificates**.
4. Click **+** to add a certificate type.

**Via the Developer Portal:**

1. Go to https://developer.apple.com/account/resources/certificates/list
2. Click **+**, choose the certificate type, follow the wizard.
3. Download the `.cer` file and double-click it to install into Keychain Access.

### Certificate types

| Certificate | Platform | Use |
|---|---|---|
| **Apple Development** | macOS + iOS | Running on your own registered devices during development. |
| **Apple Distribution** | macOS + iOS | App Store submission (both Mac App Store and iOS App Store). Also used for iOS enterprise/Ad Hoc distribution. |
| **Developer ID Application** | macOS only | Signing macOS apps for distribution **outside** the App Store. Required for notarization. |
| **Developer ID Installer** | macOS only | Signing `.pkg` installers for distribution outside the App Store. |
| **3rd Party Mac Developer Application** | macOS only | Older name for Apple Distribution (macOS). Functionally equivalent. |
| **3rd Party Mac Developer Installer** | macOS only | Older name for Developer ID Installer. Signs the `.pkg` for Mac App Store upload. |

Your installed certificates are listed in **Keychain Access → login → My Certificates**. `make sign-macos` and `make sign-ios` list them for you during the signing workflow.

---

## Code Signing for macOS

### What `make sign-macos` does

Running `make sign-macos` performs an interactive two-stage workflow:

**Stage 1 — Developer ID distribution (Gatekeeper-compliant, outside App Store):**

1. Lists your Developer ID signing identities.
2. You select one (or accept the default if only one exists).
3. Signs the `.app` bundle with the hardened runtime entitlement (`--options runtime`). Hardened runtime is required for notarization.
4. Submits the signed `.app` to Apple's notary service.
5. Polls until notarization is approved (typically 1–5 minutes).
6. Staples the notarization ticket to the `.app`.

Output: `bin/macOS/<displayname>.app` — signed and notarized, ready for direct distribution (DMG, zip, etc.)

**Stage 2 — Mac App Store `.pkg`:**

1. Creates a separate copy of the `.app`.
2. Signs it with your App Store application certificate.
3. Wraps it in a `.pkg` signed with your installer certificate.

Output: `bin/macOS/<progname>.pkg` — ready for upload to App Store Connect.

Both stages are optional — you can skip either when prompted.

### Notarization setup

Notarization requires an **app-specific password** — not your regular Apple ID password. Generate one at:

https://appleid.apple.com/ → **Sign-In and Security → App-Specific Passwords → Generate an App-Specific Password**

Label it something identifiable (e.g., `passiflora-notarize`). Copy the generated password — you cannot view it again.

#### Storing notarization credentials (recommended)

To avoid re-entering credentials on every build, store them as a named profile in the macOS Keychain:

```
xcrun notarytool store-credentials "notary-profile" \
    --apple-id your@email.com \
    --team-id YOURTEAMID \
    --password <app-specific-password>
```

Replace:
- `your@email.com` — your Apple ID
- `YOURTEAMID` — your 10-character team ID (find it at https://developer.apple.com/account/ → **Membership**)
- `<app-specific-password>` — the app-specific password you generated above

The profile name `notary-profile` is the name `make sign-macos` looks for. If you use a different name, set the `NOTARY_PROFILE` environment variable:

```
NOTARY_PROFILE=my-custom-profile make sign-macos
```

Alternatively, you can pass credentials directly each time (less convenient):

```
xcrun notarytool submit bin/macOS/MyApp.app \
    --apple-id your@email.com \
    --team-id YOURTEAMID \
    --password <app-specific-password> \
    --wait
```

### Manual notarization (if needed)

If you need to re-notarize or inspect a submission:

```
# Submit
xcrun notarytool submit bin/macOS/MyApp.app \
    --keychain-profile "notary-profile" \
    --wait

# Check submission history
xcrun notarytool history --keychain-profile "notary-profile"

# View full log for a specific submission ID
xcrun notarytool log <submission-id> --keychain-profile "notary-profile"

# Staple the ticket
xcrun stapler staple bin/macOS/MyApp.app
```

### Verifying the signature and notarization

```
# Check code signature
codesign --verify --deep --strict --verbose=2 bin/macOS/MyApp.app

# Check Gatekeeper acceptance
spctl --assess --type exec --verbose bin/macOS/MyApp.app

# Check notarization staple
xcrun stapler validate bin/macOS/MyApp.app
```

### Uploading to the Mac App Store

After `make sign-macos` produces the `.pkg`, upload to App Store Connect:

**Using `altool`:**
```
xcrun altool --upload-app \
    -f bin/macOS/<progname>.pkg \
    -t macos \
    -u your@email.com \
    -p @keychain:AC_PASSWORD
```

Where `AC_PASSWORD` is the item name of (another) app-specific password stored in Keychain. Store it with:

```
xcrun altool --store-password-in-keychain-item "AC_PASSWORD" \
    -u your@email.com \
    -p <app-specific-password>
```

**Using Transporter:** Download the **Transporter** app from the Mac App Store (free). Drag and drop your `.pkg` into the window and click **Deliver**.

---

## Code Signing for iOS

### What `make sign-ios` does

`make sign-ios` performs the complete build-sign-package pipeline:

1. Compiles the iOS binary for the `iphoneos` architecture.
2. Creates the `.app` bundle.
3. Locates the provisioning profile:
   - Checks `~/passiflora-keys/<progname>.mobileprovision` automatically.
   - If not found, prompts for the path.
   - Can be overridden with the `IOS_PROVISIONING_PROFILE` environment variable.
4. Embeds the profile in the `.app`.
5. Extracts entitlements from the profile.
6. Lists signing identities in your Keychain and prompts you to choose one.
7. Signs the bundle with `codesign`.
8. Packages the signed bundle into `bin/iOS/<progname>.ipa`.

### Provisioning profiles

A provisioning profile links your app (bundle ID), your certificate, and (for development) your registered device UDIDs. You must create one matching your use case before signing.

**Create a provisioning profile at:**

https://developer.apple.com/account/resources/profiles/list

Click **+**, choose the profile type:

| Profile type | Use |
|---|---|
| **iOS App Development** | Running on registered devices during development. Device UDIDs must be registered. |
| **Ad Hoc** | Distributing to a limited group (up to 100 registered devices). Device UDIDs must be registered. |
| **App Store Connect** | Submitting to the iOS App Store (or TestFlight). No device restriction. |

For each profile:
- Select the **App ID** matching your bundle identifier.
- Select the **certificate(s)** to associate.
- For development/Ad Hoc: select the **device UDIDs** to include.
- Download the `.mobileprovision` file.

**Download profiles via Xcode:**

**Xcode → Settings → Accounts → (your team) → Download Manual Profiles**

This downloads all profiles associated with your account.

### Installing profiles and certificates

Downloaded `.mobileprovision` files are installed by double-clicking them (they are copied to `~/Library/MobileDevice/Provisioning Profiles/`).

Certificates are installed by double-clicking the `.cer` file (this imports them into Keychain Access).

### Storing the provisioning profile for automatic use

Copy the profile to the default location so `make sign-ios` picks it up automatically:

```
cp /path/to/MyApp.mobileprovision ~/passiflora-keys/<progname>.mobileprovision
```

Where `<progname>` is the value of `PROGNAME` in `src/config` (typically the lowercase, no-spaces app name).

Or specify the profile at build time:

```
IOS_PROVISIONING_PROFILE=/path/to/MyApp.mobileprovision make sign-ios
```

### Registering device UDIDs (for development/Ad Hoc)

For development and Ad Hoc profiles, each test device's UDID must be registered in your developer account.

**Find a device UDID:**

- Connect the device to a Mac, open Xcode → **Window → Devices and Simulators**. The UDID appears under the device name.
- Or in Finder: connect the device, click on it in the sidebar, click on the model name repeatedly to cycle through identifiers until the UDID appears.

**Register the UDID:**

1. Go to https://developer.apple.com/account/resources/devices/list
2. Click **+**, enter the device name and UDID.
3. Regenerate and re-download any provisioning profiles that need to include the new device.

### Building for iOS Simulator

`make sim-ios` builds for the Simulator (no signing required). See [BUILD-macOS.md](BUILD-macOS.md) for prerequisites.

### Uploading to the iOS App Store

After `make sign-ios` produces the `.ipa` (signed with an Apple Distribution certificate and an App Store provisioning profile):

**Using `altool`:**
```
xcrun altool --upload-app \
    -f bin/iOS/<progname>.ipa \
    -t ios \
    -u your@email.com \
    -p @keychain:AC_PASSWORD
```

**Using Transporter:** drag and drop the `.ipa` into the Transporter app.

Once uploaded, the build appears in App Store Connect under **TestFlight** within a few minutes. After processing (typically 15–30 minutes), it can be distributed to internal testers immediately, or submitted for App Store review.

### Installing the IPA on a physical device

**Apple Configurator 2** (recommended for development/Ad Hoc):

1. Install [Apple Configurator 2](https://apps.apple.com/app/apple-configurator/id1037126344) from the Mac App Store.
2. Connect the device via USB.
3. Select the device, click **Add → Apps**, choose the `.ipa`.

**Xcode Devices window:**

1. **Window → Devices and Simulators**.
2. Select the device, click **+** under Installed Apps, choose the `.ipa`.

**`ideviceinstaller` (command-line):**

```
brew install ideviceinstaller
ideviceinstaller --install bin/iOS/<progname>.ipa
```

**TestFlight:**

Upload the `.ipa` (as described above) and invite testers via App Store Connect. Testers install the **TestFlight** app and accept the invitation.

> **Note:** For development and Ad Hoc builds, the device UDID must be in the provisioning profile. App Store and TestFlight builds have no device restriction.

---

## Key Storage Recommendations

| Item | Recommended location |
|---|---|
| iOS provisioning profiles | `~/passiflora-keys/<progname>.mobileprovision` |
| Notarytool credential profile | macOS Keychain (stored by `xcrun notarytool store-credentials`) |
| App-specific password for altool | macOS Keychain (stored by `xcrun altool --store-password-in-keychain-item`) |
| Code-signing certificates | macOS Keychain (installed via `.cer` file or Xcode) |
| Private keys (`.p12` exports) | Encrypted backup only — offline storage or encrypted vault |

Never store any of the above in a location that is version-controlled, synced to a shared server without encryption, or accessible to unauthorized users.

---

## Troubleshooting

**"No signing identities found"**
No code-signing certificates are installed in your Keychain, or none match the required type. Open Keychain Access and look under **My Certificates** for items beginning with "Apple Development", "Apple Distribution", or "Developer ID Application". If missing, create them via the Developer Portal or Xcode as described above.

**"errSecInternalComponent" during codesign**
The private key for the certificate is not accessible (e.g., locked keychain, or certificate was imported without its private key). Re-import the certificate as a `.p12` (which includes the private key), or create a fresh certificate in Xcode.

**"Profile doesn't match bundle identifier"**
The bundle ID in `src/config` does not match the App ID in the provisioning profile. Both must be identical (or the profile must use a wildcard App ID like `com.yourcompany.*`).

**"The provisioning profile is expired"**
Development profiles expire after 1 year; Ad Hoc profiles expire after 1 year; App Store profiles expire after 1 year. Renew in the Developer Portal and re-download.

**Notarization fails: "The signature of the binary is invalid"**
The app was modified after signing, or was not signed with `--options runtime`. Make sure you run notarization immediately after signing without modifying the bundle.

**Notarization fails: "The executable does not have the hardened runtime enabled"**
The binary must be signed with `--options runtime`. `make sign-macos` handles this automatically — if you are signing manually, add the flag.

**Gatekeeper blocks the app after distribution**
The most common causes are: (1) not notarized, or (2) the notarization ticket was not stapled. Run `xcrun stapler staple` on the `.app` after notarization completes, before distributing.

**`spctl` reports "rejected" after stapling**
Check the Apple security updates — the certificate may have been revoked, or the app's entitlements may violate App Sandbox policies. Run `xcrun notarytool log <submission-id>` to inspect the rejection reason.

**Xcode says "Provisioning profile doesn't include the currently selected device"**
Register the device UDID in your Developer account, regenerate the profile, and re-download it.
