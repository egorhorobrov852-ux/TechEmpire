"""Set only Android export paths in a dedicated or selected Godot configuration."""
import json
import os
from pathlib import Path
import re

config = Path(os.environ["XDG_CONFIG_HOME"]) / "godot/editor_settings-4.6.tres"
config.parent.mkdir(parents=True, exist_ok=True)
body = config.read_text() if config.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
values = {
    "export/android/android_sdk_path": os.environ["ANDROID_HOME"],
    "export/android/java_sdk_path": os.environ["JAVA_HOME"],
    "export/android/debug_keystore": os.environ["GODOT_ANDROID_KEYSTORE_DEBUG_PATH"],
    "export/android/debug_keystore_user": "androiddebugkey",
    "export/android/debug_keystore_pass": "android",
}
for key, value in values.items():
    entry = f"{key} = {json.dumps(value)}"
    pattern = re.compile(r"^" + re.escape(key) + r"\s*=.*$", re.MULTILINE)
    if pattern.search(body):
        body = pattern.sub(lambda _: entry, body)
    else:
        body += entry + "\n"
config.write_text(body)
