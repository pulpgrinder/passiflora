@echo off
REM Passiflora signing environment template (Windows cmd.exe)
REM
REM This file is a TEMPLATE meant to live in the repository root so you can copy it
REM into your private key folder outside source control.
REM
REM WHERE THIS MUST BE PLACED FOR AUTO-LOAD:
REM   %USERPROFILE%\passiflora-keys\signing_setup.bat
REM
REM WHY:
REM   The build targets ".\build sign-windows" and ".\build sign-android" check
REM   for that exact path and CALL it before build/sign operations. CALL keeps these
REM   variables in the same cmd session used by signing commands.
REM
REM SETUP STEPS:
REM   1) Create your private keys directory (if needed):
REM        mkdir "%USERPROFILE%\passiflora-keys"
REM   2) Copy this template to your private directory:
REM        copy signing_setup.bat "%USERPROFILE%\passiflora-keys\signing_setup.bat"
REM   3) Edit the copied file and replace placeholder values with real values.
REM
REM SECURITY:
REM   - Do not store real secrets in this repository copy.
REM   - Keep real credentials only in %USERPROFILE%\passiflora-keys\signing_setup.bat.
REM   - Never commit the private copy to git.
REM
REM VARIABLES USED BY PASSIFLORA:
REM
REM Android release signing (Gradle build-time signing, used by .\build android/.\build googleplay-android):
REM   RELEASE_KEYSTORE
REM   RELEASE_KEYSTORE_PASSWORD
REM   RELEASE_KEY_ALIAS
REM   RELEASE_KEY_PASSWORD
REM
REM Windows Azure Artifact Signing (used by .\build sign-windows):
REM   AZURE_SIGNING_ENDPOINT
REM   AZURE_SIGNING_ACCOUNT
REM   AZURE_SIGNING_PROFILE
REM
REM NOTE:
REM   .\build sign-android also supports interactive password entry and defaults
REM   the keystore path to %USERPROFILE%\passiflora-keys\android-keystore.jks if present.

REM ----------------------------
REM Android signing placeholders
REM ----------------------------
set "RELEASE_KEYSTORE=%USERPROFILE%\passiflora-keys\android-keystore.jks"
set "RELEASE_KEYSTORE_PASSWORD=REPLACE_WITH_YOUR_KEYSTORE_PASSWORD"
set "RELEASE_KEY_ALIAS=REPLACE_WITH_YOUR_KEY_ALIAS"
set "RELEASE_KEY_PASSWORD=REPLACE_WITH_YOUR_KEY_PASSWORD"

REM -----------------------------
REM Windows signing placeholders
REM -----------------------------
set "AZURE_SIGNING_ENDPOINT=https://REPLACE_WITH_REGION.codesigning.azure.net"
set "AZURE_SIGNING_ACCOUNT=REPLACE_WITH_YOUR_SIGNING_ACCOUNT"
set "AZURE_SIGNING_PROFILE=REPLACE_WITH_YOUR_CERT_PROFILE"
