# Google Play Code Signing for Android

This document covers everything needed to sign Android APKs and App Bundles (AABs) for Google Play distribution using Passiflora.

> **IMPORTANT: Never put your keystore file, passwords, or signing credentials into a folder managed by git or another version control system. Ever.**

---

## Overview

Android apps must be signed before they can be installed or distributed. Google Play requires **release-signed** builds. There are two layers of signing to understand:

| Layer | What it is |
|---|---|
| **App signing key (upload key)** | A keystore you create and control. You use this key to sign your APK or AAB before uploading to the Play Console. |
| **Google Play App Signing** | Google re-signs the APK delivered to users with a Google-managed key. This is mandatory for new apps and recommended for all apps. |

When you enroll in Google Play App Signing, the key that reaches users' devices is managed by Google. Your upload key is only used to authenticate uploads to the Play Console — if you lose your upload key you can request a reset from Google.

Passiflora produces two Android artifacts:

| Command | Output | Use |
|---|---|---|
| `make sign-android` / `.\build sign-android` | `bin/Android/<progname>.apk` | Direct device installation (sideloading), ad-hoc testing |
| `make googleplay-android` / `.\build googleplay-android` | `bin/Android/<progname>.aab` | Google Play upload |

---

## Step 1 — Create a Google Play Developer Account

1. Go to https://play.google.com/console/signup
2. Pay the one-time registration fee ($25 USD at time of writing).
3. Complete account details and agree to Google Play Developer Distribution Agreement.
4. Your console is available at https://play.google.com/console/

---

## Step 2 — Create a Signing Keystore

You need a Java keystore (`.jks`) containing your signing key. Generate one with `keytool`, which is included with any JDK installation.

Store the keystore **outside** the Passiflora source tree. The recommended path is:

| Platform | Default path |
|---|---|
| macOS / Linux | `~/passiflora-keys/android-keystore.jks` |
| Windows | `%USERPROFILE%\passiflora-keys\android-keystore.jks` |

`make sign-android` and `.\build sign-android` check these paths automatically — if the keystore is found there, you will not be prompted for a path.

### Generate the keystore

**macOS / Linux:**
```
mkdir -p ~/passiflora-keys
keytool -genkey -v \
  -keystore ~/passiflora-keys/android-keystore.jks \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -alias mykey
```

**Windows:**
```
mkdir "%USERPROFILE%\passiflora-keys"
keytool -genkey -v ^
  -keystore "%USERPROFILE%\passiflora-keys\android-keystore.jks" ^
  -keyalg RSA ^
  -keysize 4096 ^
  -validity 10000 ^
  -alias mykey
```

`keytool` will prompt for:
- **Keystore password** — use a strong password and record it somewhere safe (a password manager, not a text file in your repo)
- **Your name / organization / location** — this becomes part of the certificate's Distinguished Name (DN). For a public app, use accurate information.
- **Key password** — can be the same as the keystore password or different

> **On key validity:** 10,000 days (~27 years) is the standard recommendation. Google Play requires the certificate to be valid past October 22, 2033 for new apps as of the Play policy at time of writing.

> **On key size:** 4096-bit RSA is recommended for new keys. 2048-bit is still accepted by Google Play but 4096 is more future-proof.

### Keystore backup

Back up the keystore file and both passwords immediately. If you lose the keystore and are not enrolled in Google Play App Signing, Google cannot help you — you will be unable to update the app on the Play Store and must publish under a new package name.

Store backups:
- Encrypted backup in cloud storage (e.g., a password-manager-protected vault)
- Offline copy (USB drive, printed QR code of the encrypted keystore)

---

## Step 3 — Sign the APK or AAB

### Method 1 — Interactive signing (`make sign-android`)

This method is best for one-off or local signing. The build finds and calls `apksigner` from the Android SDK build-tools automatically.

**macOS:**
```
make sign-android
```

**Windows:**
```
.\build sign-android
```

You will be prompted for:
1. **Keystore path** — only if the keystore is not found at the default location
2. **Keystore password** — typed securely (characters hidden)

The build then:
1. Compiles and assembles the APK.
2. Runs `zipalign` (aligns uncompressed data to 4-byte boundaries for runtime performance).
3. Signs with `apksigner` using V1 (JAR signing) + V2 (APK signature scheme) signatures.
4. Verifies the signature.

Output: `bin/Android/<progname>.apk`

To build a release (non-debug) APK:

**macOS:**
```
BUILD_TYPE=release make sign-android
```

**Windows:**
```
set BUILD_TYPE=release
.\build sign-android
```

### Method 2 — Environment variable signing (Gradle, good for CI/CD)

Gradle signs the APK automatically during the build when the following environment variables are set:

| Variable | Description | Example |
|---|---|---|
| `RELEASE_KEYSTORE` | Absolute path to the `.jks` keystore file | `/home/user/passiflora-keys/android-keystore.jks` |
| `RELEASE_KEYSTORE_PASSWORD` | Keystore password | `s3cr3tpass` |
| `RELEASE_KEY_ALIAS` | Key alias inside the keystore | `mykey` |
| `RELEASE_KEY_PASSWORD` | Key password (may equal keystore password) | `s3cr3tpass` |

**macOS:**
```
export RELEASE_KEYSTORE=~/passiflora-keys/android-keystore.jks
export RELEASE_KEYSTORE_PASSWORD=your-store-password
export RELEASE_KEY_ALIAS=mykey
export RELEASE_KEY_PASSWORD=your-key-password
BUILD_TYPE=release make android
```

**Windows:**
```
set RELEASE_KEYSTORE=%USERPROFILE%\passiflora-keys\android-keystore.jks
set RELEASE_KEYSTORE_PASSWORD=your-store-password
set RELEASE_KEY_ALIAS=mykey
set RELEASE_KEY_PASSWORD=your-key-password
set BUILD_TYPE=release
.\build android
```

> **Do not** run `make sign-android` / `.\build sign-android` after a Gradle-signed build — Gradle already embedded the signature. Double-signing will corrupt the APK.

### Google Play AAB

Google Play requires an **Android App Bundle** (AAB) rather than a direct APK. The AAB is signed with the same keystore.

Set the signing environment variables (Method 2 above), then:

**macOS:**
```
make googleplay-android
```

**Windows:**
```
.\build googleplay-android
```

Output: `bin/Android/<progname>.aab`

---

## Step 4 — Enroll in Google Play App Signing (Strongly Recommended)

Google Play App Signing protects you against losing your upload key. With it enabled, Google manages the key that is delivered to users' devices; your upload key only needs to match for each upload.

1. In the [Play Console](https://play.google.com/console/), open your app (or create a new app).
2. Go to **Release → Setup → App signing**.
3. If this is a new app, Google Play App Signing is enabled automatically.
4. If this is an existing app, follow the on-screen migration steps to upload your existing app signing key. You can then generate a separate upload key.

To generate a new upload key (optional, after migration):

```
keytool -genkey -v \
  -keystore ~/passiflora-keys/android-upload-key.jks \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -alias upload
```

Then request Google to associate this new upload key with your app in the Play Console under **App signing → Request upload key reset**.

---

## Step 5 — Upload to Google Play

1. Open the [Play Console](https://play.google.com/console/).
2. Select your app → **Release → Production** (or **Internal testing**, **Closed testing**, etc.).
3. Click **Create new release**.
4. Under **App bundles**, click **Upload** and select `bin/Android/<progname>.aab`.
5. Fill in a release name and release notes.
6. Click **Save**, then **Review release**, then **Start rollout**.

Production rollouts can be staged (e.g., 10% of users first) or full (100%). New apps go through a review period before appearing publicly.

---

## Verifying a Signed APK or AAB

To confirm the APK is properly signed:

```
apksigner verify --verbose bin/Android/<progname>.apk
```

To inspect the signing certificate:

```
apksigner verify --print-certs bin/Android/<progname>.apk
```

To verify a keystore contains the expected key:

```
keytool -list -keystore ~/passiflora-keys/android-keystore.jks
```

---

## CI/CD Integration

For automated builds (GitHub Actions, etc.), store signing credentials as **encrypted secrets**, never as plaintext in repository files.

Example GitHub Actions workflow excerpt:

```yaml
- name: Build and sign AAB
  env:
    RELEASE_KEYSTORE: /tmp/android-keystore.jks
    RELEASE_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
    RELEASE_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
    RELEASE_KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
  run: |
    echo "${{ secrets.ANDROID_KEYSTORE_B64 }}" | base64 --decode > /tmp/android-keystore.jks
    BUILD_TYPE=release make googleplay-android
```

To encode your keystore as a base64 secret:

```
base64 -i ~/passiflora-keys/android-keystore.jks | pbcopy   # macOS — copies to clipboard
base64 -w 0 ~/passiflora-keys/android-keystore.jks           # Linux — prints to stdout
```

Paste the output as the value of the `ANDROID_KEYSTORE_B64` secret in your repository's **Settings → Secrets and variables → Actions**.

---

## Troubleshooting

**"RELEASE_KEYSTORE is not set" or keystore not found**
The environment variable is missing or the file does not exist at the path specified. Double-check the path and that the file exists.

**"apksigner: command not found"**
The Android SDK build-tools are not on your PATH. Add them:

macOS: `export PATH="$ANDROID_HOME/build-tools/35.0.0:$PATH"`

Windows: `set PATH=%ANDROID_HOME%\build-tools\35.0.0;%PATH%`

**"INSTALL_FAILED_UPDATE_INCOMPATIBLE" when installing via adb**
The APK is signed with a different key than the version already installed on the device. Uninstall the existing version first: `adb uninstall <bundle-id>`

**Play Console rejects the upload: "Your APK or Android App Bundle needs to be signed"**
Upload an AAB (not an APK) and make sure it is built with `make googleplay-android` with the signing environment variables set.

**Play Console rejects the upload: "Invalid signature"**
The AAB may be signed with a debug key or the wrong keystore. Verify with `apksigner verify --print-certs bin/Android/<progname>.aab` and confirm the signing certificate DN matches the one registered in the Play Console under **App signing**.
