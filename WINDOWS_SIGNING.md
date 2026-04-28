# Azure Trusted Signing for Windows

This document covers setting up and using Azure Trusted Signing (formerly Azure Artifact Signing / Azure Code Signing) to sign the Passiflora Windows executable.

> **IMPORTANT: Never put your signing credentials, certificates, or access tokens into a folder managed by git or another version control system. Ever.**

---

## Overview

Azure Trusted Signing is a Microsoft-managed code-signing service. Instead of purchasing and managing a physical code-signing certificate, you create an account in the Azure portal, Azure manages the certificate lifecycle for you, and you authenticate using your Azure identity.

Passiflora uses **jsign** — a cross-platform Java-based signing tool — to integrate with Azure Trusted Signing. jsign obtains an ephemeral access token from the Azure CLI and uses it to sign the `.exe` via Azure's REST signing API.

**Key facts:**

- Azure Trusted Signing certificates have a **3-day validity window**. This sounds alarming but is by design: the build automatically timestamps the signature, which anchors long-term trust to the timestamp authority rather than the certificate.
- You do **not** need to manage or store a private key. The key lives entirely in Azure.
- The service currently supports **EV (Extended Validation) equivalent** certificates suitable for Windows SmartScreen. New publishers may still see SmartScreen warnings until the executable accumulates reputation.

---

## Step 1 — Create an Azure Account

If you don't already have an Azure account, create one at https://azure.microsoft.com/free/

A Pay-As-You-Go subscription is sufficient. Azure Trusted Signing is billed per signing operation (check current pricing at https://azure.microsoft.com/pricing/details/trusted-signing/).

---

## Step 2 — Create a Trusted Signing Account and Certificate Profile

1. Sign in to the [Azure Portal](https://portal.azure.com/).

2. In the search bar, type **Trusted Signing** and select **Trusted Signing Accounts**.

3. Click **+ Create**.

4. Fill in the required fields:
   - **Subscription**: your Azure subscription
   - **Resource group**: create a new one (e.g., `rg-codesigning`) or use an existing one
   - **Name**: a unique name for your signing account (e.g., `my-app-signing`)
   - **Region**: choose the region closest to you — note the endpoint URL, you'll need it later (see [Regional Endpoints](#regional-endpoints))
   - **SKU**: **Basic** is sufficient for most use cases

5. Click **Review + Create**, then **Create**.

6. Once the account is created, open it. In the left panel, select **Certificate profiles**.

7. Click **+ Add**. Fill in:
   - **Profile name**: a short name (e.g., `MyAppProfile`)
   - **Profile type**: **Public Trust** (for public distribution) or **Private Trust** (for internal use)
   - **Include street address**: typically leave unchecked unless required

8. Click **Create**.

9. Your certificate profile will initially be in the **Pending** state while Azure validates your identity.

---

## Step 3 — Identity Validation

Azure requires identity validation before issuing code-signing certificates. The requirements differ by profile type:

| Profile Type | Validation Required |
|---|---|
| Public Trust | Organization or individual identity verification via a third-party identity provider |
| Private Trust | Azure AD tenant verification only |

For **Public Trust** (required to sign software distributed to the public):

1. In your Trusted Signing account, select **Identity validation** from the left panel.
2. Click **+ Add** and choose the verification type:
   - **Organization** — for business entities. Verification is performed by a third-party identity provider (currently [IdentityMap](https://www.identitymap.com/)). Expect 1–5 business days.
   - **Individual** — personal identity verification. Similar timeline.
3. Follow the prompts. You'll typically need to provide business registration documents (for an organization) or a government-issued ID (for an individual).
4. Once validation is approved, your certificate profile status changes to **Active**.

---

## Step 4 — Assign the Signing Role

To sign code, your Azure account must have the **Code Signing Certificate Profile Signer** role on the certificate profile.

1. In the Azure Portal, open your Trusted Signing account.
2. Select **Certificate profiles** → click your profile name.
3. Select **Access control (IAM)** → **+ Add** → **Add role assignment**.
4. Search for **Code Signing Certificate Profile Signer**, select it, click **Next**.
5. Under **Members**, click **+ Select members**, search for your user account (email address), select it, click **Select**.
6. Click **Review + assign** twice to confirm.

If you intend to sign from a CI/CD pipeline, assign this role to a **service principal** or **managed identity** instead of (or in addition to) your personal account.

---

## Step 5 — Install Prerequisites

### Azure CLI

The build uses the Azure CLI to obtain an access token for jsign.

**macOS:**
```
brew install azure-cli
```

**Windows:**
```
winget install Microsoft.AzureCLI
```

Or download from https://learn.microsoft.com/en-us/cli/azure/install-azure-cli

Log in once (opens a browser for interactive authentication):
```
az login
```

To verify your login:
```
az account show
```

### Java 17+

jsign is a Java application and requires a Java 17 (or newer) runtime.

**macOS:**
```
brew install openjdk@17
```

After installing, follow any cask instructions to add it to your PATH:
```
export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"
```

**Windows (winget):**
```
winget install EclipseAdoptium.Temurin.17.JDK
```

**Windows (direct download):**
Download the Windows x64 `.msi` installer from https://adoptium.net/temurin/releases/?version=17 — the installer adds Java to `PATH` automatically.

Verify:
```
java -version
```

> **Note:** If you already have Java installed for Android builds, you can skip this step — jsign uses whatever `java` is on your `PATH`.

### jsign

**macOS:**
```
brew install jsign
```

**Windows (Scoop):**
```
scoop install jsign
```

**Windows (Chocolatey):**
```
choco install jsign
```

**Manual install (any platform):**

Download the latest all-in-one JAR from https://github.com/ebourg/jsign/releases (e.g., `jsign-7.x.jar`). You can then invoke it with:
```
java -jar /path/to/jsign.jar ...
```

If you use the manual JAR, the Makefile/build.bat may not find `jsign` on the PATH. In that case, either create a wrapper script named `jsign` in a directory on your PATH, or set the `JSIGN` environment variable to the full `java -jar /path/to/jsign.jar` invocation.

---

## Step 6 — Configure Environment Variables

The signing scripts read three environment variables:

| Variable | Description | Example |
|---|---|---|
| `AZURE_SIGNING_ENDPOINT` | The regional endpoint URL for your Trusted Signing account | `https://eus.codesigning.azure.net` |
| `AZURE_SIGNING_ACCOUNT` | The name of your Trusted Signing account | `my-app-signing` |
| `AZURE_SIGNING_PROFILE` | The name of your certificate profile | `MyAppProfile` |

Find your endpoint URL in the Azure Portal: open your Trusted Signing account → **Overview** → **Endpoint URI**.

### Regional Endpoints

| Region | Endpoint |
|---|---|
| East US | `https://eus.codesigning.azure.net` |
| West US | `https://wus.codesigning.azure.net` |
| West Central US | `https://wcus.codesigning.azure.net` |
| West US 2 | `https://wus2.codesigning.azure.net` |
| North Europe | `https://neu.codesigning.azure.net` |
| West Europe | `https://weu.codesigning.azure.net` |

Always use the endpoint that matches the region in which you created your account — cross-region signing will fail.

### Setting variables for the session

**macOS / Linux:**
```
export AZURE_SIGNING_ENDPOINT=https://eus.codesigning.azure.net
export AZURE_SIGNING_ACCOUNT=my-app-signing
export AZURE_SIGNING_PROFILE=MyAppProfile
```

Add these lines to `~/.zshrc`, `~/.bash_profile`, or your shell's equivalent to make them persistent.

**Windows (cmd.exe):**
```
set AZURE_SIGNING_ENDPOINT=https://eus.codesigning.azure.net
set AZURE_SIGNING_ACCOUNT=my-app-signing
set AZURE_SIGNING_PROFILE=MyAppProfile
```

**Windows (PowerShell):**
```
$env:AZURE_SIGNING_ENDPOINT = "https://eus.codesigning.azure.net"
$env:AZURE_SIGNING_ACCOUNT  = "my-app-signing"
$env:AZURE_SIGNING_PROFILE  = "MyAppProfile"
```

To persist in PowerShell across sessions:
```
[System.Environment]::SetEnvironmentVariable("AZURE_SIGNING_ENDPOINT","https://eus.codesigning.azure.net","User")
[System.Environment]::SetEnvironmentVariable("AZURE_SIGNING_ACCOUNT","my-app-signing","User")
[System.Environment]::SetEnvironmentVariable("AZURE_SIGNING_PROFILE","MyAppProfile","User")
```

---

## Step 7 — Sign the Windows Executable

Once prerequisites are installed and environment variables are set:

**macOS (cross-compiling):**
```
make sign-windows
```

**Windows:**
```
.\build sign-windows
```

What happens internally:

1. The build compiles the Windows `.exe` (or uses an existing one).
2. `az account get-access-token` is called to obtain a short-lived bearer token.
3. jsign sends the executable to Azure Trusted Signing, which signs it server-side and returns the signature.
4. jsign embeds the signature in the `.exe`.
5. jsign applies an RFC 3161 timestamp from `http://timestamp.acs.microsoft.com`, anchoring the signature to the signing time.

The signed executable is written to `bin/Windows/<displayname>.exe`.

---

## CI/CD Integration

For automated pipelines (GitHub Actions, Azure DevOps, etc.), use a **service principal** instead of interactive `az login`.

### Create a service principal

```
az ad sp create-for-rbac --name "passiflora-signing-sp" --role "Code Signing Certificate Profile Signer" \
  --scopes /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.CodeSigning/codeSigningAccounts/<account>/certificateProfiles/<profile>
```

This outputs `appId`, `password`, and `tenant`. Store these as secrets in your CI system — **never** commit them to source control.

### Log in non-interactively

```
az login --service-principal \
  --username <appId> \
  --password <password> \
  --tenant <tenant>
```

Then set the three `AZURE_SIGNING_*` environment variables as CI secrets and run `make sign-windows` or `.\build sign-windows` as usual.

---

## Troubleshooting

**"az: command not found"**
The Azure CLI is not installed or not on your PATH. See [Install Prerequisites](#step-5--install-prerequisites).

**"AZURE_SIGNING_ENDPOINT is not set"**
The required environment variables are missing. See [Configure Environment Variables](#step-6--configure-environment-variables).

**"Unauthorized" / 403 from Azure**
Your account does not have the **Code Signing Certificate Profile Signer** role on the certificate profile. See [Assign the Signing Role](#step-4--assign-the-signing-role).

**Certificate profile still in "Pending" state**
Identity validation has not completed. Check the status in the Azure Portal under **Identity validation**. Validation can take up to 5 business days.

**"jsign: command not found"**
jsign is not installed or not on your PATH. If you downloaded the JAR manually, create a wrapper script or set the `JSIGN` variable as described in the jsign section above.

**Windows SmartScreen still warns about the signed exe**
SmartScreen trust is reputation-based. A newly issued certificate starts with no reputation. As more users download and run the executable without complaints, SmartScreen stops warning. This is expected behavior and not an error in your signing setup.

**Timestamp server unreachable**
The default timestamp URL is `http://timestamp.acs.microsoft.com`. If this is unreachable from your network, you can override it by setting `TIMESTAMP_URL` in the environment before calling the signing target. Alternatively, you can use a public Authenticode timestamp server such as `http://timestamp.digicert.com`.
