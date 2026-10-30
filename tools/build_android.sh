#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${TECH_EMPIRE_TOOLS_DIR:-"$PROJECT_ROOT/../.tech-empire-tools"}"
TOOLS_DIR="$(realpath -m "$TOOLS_DIR")"
export ANDROID_HOME="${ANDROID_HOME:-"$TOOLS_DIR/android-sdk"}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-"$TOOLS_DIR/android-user"}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-"$TOOLS_DIR/xdg/data"}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-"$TOOLS_DIR/xdg/config"}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-"$TOOLS_DIR/xdg/cache"}"
export XDG_DATA_HOME="$(realpath -m "$XDG_DATA_HOME")"
export XDG_CONFIG_HOME="$(realpath -m "$XDG_CONFIG_HOME")"
export XDG_CACHE_HOME="$(realpath -m "$XDG_CACHE_HOME")"
GODOT_BIN="${GODOT_BIN:-godot}"
if [[ -z "${JAVA_HOME:-}" ]]; then
  JAVA_EXECUTABLE="$(readlink -f "$(command -v java)")"
  export JAVA_HOME="$(dirname "$(dirname "$JAVA_EXECUTABLE")")"
fi
mkdir -p "$TOOLS_DIR" "$ANDROID_USER_HOME" "$XDG_CACHE_HOME" "$PROJECT_ROOT/artifacts/logs"
touch "$PROJECT_ROOT/artifacts/.gdignore"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"

EXPECTED_GODOT=4.6.3
ACTUAL_GODOT="$($GODOT_BIN --version)"
[[ "$ACTUAL_GODOT" == "$EXPECTED_GODOT".* ]] || { printf 'Godot %s required, found %s\n' "$EXPECTED_GODOT" "$ACTUAL_GODOT" >&2; exit 1; }
for REQUIRED in "$ANDROID_HOME/platform-tools/adb" "$ANDROID_HOME/build-tools/36.0.0/apksigner" "$XDG_DATA_HOME/godot/export_templates/$EXPECTED_GODOT.stable/android_debug.apk"; do
  [[ -s "$REQUIRED" ]] || { printf 'Missing tool/template: %s\nRun tools/android/bootstrap.sh first.\n' "$REQUIRED" >&2; exit 1; }
done

# These standard Android debug credentials sign installable development builds only.
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$TOOLS_DIR/debug.keystore"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
if [[ ! -s "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" ]]; then
  "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Android Debug,O=Android,C=US'
fi
python3 "$PROJECT_ROOT/tools/android/configure_editor.py"

run_godot() {
  local log_file="$1"
  shift
  timeout --kill-after=10s "${GODOT_TIMEOUT_SECONDS:-300}s" "$GODOT_BIN" --headless --path "$PROJECT_ROOT" "$@" 2>&1 | tee "$log_file"
  if rg -n 'SCRIPT ERROR:|Parse Error:|Compile Error:|^ERROR:' "$log_file"; then
    printf 'Godot reported errors in %s\n' "$log_file" >&2
    return 1
  fi
}
run_godot "$PROJECT_ROOT/artifacts/logs/import.log" --editor --quit
shopt -s nullglob
SUITE_FILES=("$PROJECT_ROOT"/tests/test_*.gd)
[[ ${#SUITE_FILES[@]} -gt 0 ]] || { printf 'No GDScript test suites found.\n' >&2; exit 1; }
for SUITE_FILE in "${SUITE_FILES[@]}"; do
  SUITE="$(basename "$SUITE_FILE" .gd)"
  run_godot "$PROJECT_ROOT/artifacts/logs/$SUITE.log" --script "res://tests/$SUITE.gd"
done
APK="$PROJECT_ROOT/artifacts/.TECH-EMPIRE-building.apk"
APK_FINAL="$PROJECT_ROOT/artifacts/TECH-EMPIRE-debug.apk"
rm -f "$APK" "$APK.idsig"
run_godot "$PROJECT_ROOT/artifacts/logs/android-export.log" --export-debug Android "$APK"
test -s "$APK"
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose --print-certs "$APK" | tee "$PROJECT_ROOT/artifacts/logs/apk-signature.log"
"$ANDROID_HOME/build-tools/36.0.0/aapt" dump badging "$APK" | tee "$PROJECT_ROOT/artifacts/logs/apk-metadata.log"
"$ANDROID_HOME/build-tools/36.0.0/zipalign" -c -P 16 4 "$APK" | tee "$PROJECT_ROOT/artifacts/logs/apk-alignment.log"
python3 "$PROJECT_ROOT/tools/android/inspect_apk.py" "$APK" --project "$PROJECT_ROOT" --report "$PROJECT_ROOT/artifacts/logs/apk-resources.json"
python3 - "$APK" "$APK_FINAL" <<'PY'
from pathlib import Path
import hashlib
import sys
import zipfile
apk = Path(sys.argv[1])
final = Path(sys.argv[2])
with zipfile.ZipFile(apk) as archive:
    names = set(archive.namelist())
    for required in ("AndroidManifest.xml", "classes.dex", "lib/arm64-v8a/libgodot_android.so"):
        if required not in names:
            raise SystemExit(f"Incomplete Android package: missing {required}")
digest = hashlib.sha256(apk.read_bytes()).hexdigest()
apk.replace(final)
checksum = final.with_suffix(".apk.sha256")
temporary_checksum = checksum.with_suffix(".sha256.tmp")
temporary_checksum.write_text(f"{digest}  {final.name}\n")
temporary_checksum.replace(checksum)
print(f"Verified debug APK: {final} ({final.stat().st_size:,} bytes), SHA256 {digest}")
PY
rm -f "$APK.idsig" "$APK_FINAL.idsig"
