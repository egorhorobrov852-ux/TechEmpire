#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_DIR="${TECH_EMPIRE_TOOLS_DIR:-"$PROJECT_ROOT/../.tech-empire-tools"}"
TOOLS_DIR="$(realpath -m "$TOOLS_DIR")"
export ANDROID_HOME="${ANDROID_HOME:-"$TOOLS_DIR/android-sdk"}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-"$TOOLS_DIR/android-user"}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-"$TOOLS_DIR/xdg/data"}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-"$TOOLS_DIR/xdg/config"}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-"$TOOLS_DIR/xdg/cache"}"
mkdir -p "$TOOLS_DIR/downloads" "$ANDROID_HOME" "$ANDROID_USER_HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

GODOT_VERSION=4.6.3
GODOT_ARCHIVE="$TOOLS_DIR/downloads/godot-templates.tpz"
TEMPLATES_DIR="$XDG_DATA_HOME/godot/export_templates/$GODOT_VERSION.stable"
if [[ ! -s "$TEMPLATES_DIR/android_debug.apk" || ! -s "$TEMPLATES_DIR/android_release.apk" ]]; then
  if [[ ! -s "$GODOT_ARCHIVE" ]]; then
    curl --fail --location --retry 3 "https://github.com/godotengine/godot/releases/download/$GODOT_VERSION-stable/Godot_v$GODOT_VERSION-stable_export_templates.tpz" --output "$GODOT_ARCHIVE.partial"
    mv "$GODOT_ARCHIVE.partial" "$GODOT_ARCHIVE"
  fi
  mkdir -p "$TEMPLATES_DIR"
  unzip -j -o -q "$GODOT_ARCHIVE" templates/android_debug.apk templates/android_release.apk templates/version.txt -d "$TEMPLATES_DIR"
fi

if [[ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]]; then
  curl --fail --location --retry 3 https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip --output "$TOOLS_DIR/downloads/android-commandline.zip"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  unzip -q "$TOOLS_DIR/downloads/android-commandline.zip" -d "$ANDROID_HOME/cmdline-tools"
  mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
fi

# sdkmanager does not read HTTP_PROXY itself. Preserve the configured proxy and TLS.
python3 "$PROJECT_ROOT/tools/android/install_sdk.py"
printf 'Android SDK: %s\nGodot templates: %s\n' "$ANDROID_HOME" "$TEMPLATES_DIR"
