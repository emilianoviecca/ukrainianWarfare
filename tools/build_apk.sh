#!/usr/bin/env bash
# Compila l'APK Android. Uso: GODOT=/percorso/godot KEYSTORE=/percorso/release.keystore KEY_ALIAS=... KEY_PASS=... tools/build_apk.sh
set -euo pipefail
mkdir -p build
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$KEY_ALIAS"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$KEY_PASS"
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --export-release "Android" build/UkrainianWarfare.apk
