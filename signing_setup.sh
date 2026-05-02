#!/usr/bin/env sh
# Passiflora signing environment template (Unix-like shells)
#
# This file is a TEMPLATE meant to live in the repository root so you can copy it
# into your private key folder outside source control.
#
# WHERE THIS MUST BE PLACED FOR AUTO-LOAD:
#   $HOME/passiflora-keys/signing_setup.sh
#
# WHY:
#   The Make targets "sign-windows" and "sign-android" automatically check for
#   that exact path and source it before building/signing. Sourcing means any
#   exported variables here are available to the signing commands in the same shell.
#
# SETUP STEPS:
#   1) Create your private keys directory (if needed):
#        mkdir -p "$HOME/passiflora-keys"
#   2) Copy this template to your private directory:
#        cp signing_setup.sh "$HOME/passiflora-keys/signing_setup.sh"
#   3) Edit the copied file and replace placeholder values with real values.
#   4) Lock down permissions on the copied file:
#        chmod 600 "$HOME/passiflora-keys/signing_setup.sh"
#
# SECURITY:
#   - Do not store real secrets in this repository copy.
#   - Keep real credentials only in $HOME/passiflora-keys/signing_setup.sh.
#   - Never commit the private copy to git.
#
# VARIABLES USED BY PASSIFLORA:
#
# Android release signing (Gradle build-time signing, used by make android/googleplay-android):
#   RELEASE_KEYSTORE
#   RELEASE_KEYSTORE_PASSWORD
#   RELEASE_KEY_ALIAS
#   RELEASE_KEY_PASSWORD
#
# Windows Azure Artifact Signing (used by make sign-windows):
#   AZURE_SIGNING_ENDPOINT
#   AZURE_SIGNING_ACCOUNT
#   AZURE_SIGNING_PROFILE
#
# NOTE:
#   make sign-android also supports interactive password entry and defaults the
#   keystore path to ~/passiflora-keys/android-keystore.jks if present.

# ----------------------------
# Android signing placeholders
# ----------------------------
export RELEASE_KEYSTORE="$HOME/passiflora-keys/android-keystore.jks"
export RELEASE_KEYSTORE_PASSWORD="REPLACE_WITH_YOUR_KEYSTORE_PASSWORD"
export RELEASE_KEY_ALIAS="REPLACE_WITH_YOUR_KEY_ALIAS"
export RELEASE_KEY_PASSWORD="REPLACE_WITH_YOUR_KEY_PASSWORD"

# -----------------------------
# Windows signing placeholders
# -----------------------------
export AZURE_SIGNING_ENDPOINT="https://REPLACE_WITH_REGION.codesigning.azure.net"
export AZURE_SIGNING_ACCOUNT="REPLACE_WITH_YOUR_SIGNING_ACCOUNT"
export AZURE_SIGNING_PROFILE="REPLACE_WITH_YOUR_CERT_PROFILE"
