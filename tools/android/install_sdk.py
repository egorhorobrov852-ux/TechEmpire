"""Install the native Godot APK toolchain without modifying the user's HOME."""
import os
from pathlib import Path
import subprocess
from urllib.parse import urlparse

sdk = Path(os.environ["ANDROID_HOME"])
manager = sdk / "cmdline-tools/latest/bin/sdkmanager"
args = [str(manager), f"--sdk_root={sdk}"]
proxy = urlparse(os.environ.get("HTTPS_PROXY", os.environ.get("HTTP_PROXY", "")))
if proxy.hostname:
    args += ["--proxy=http", f"--proxy_host={proxy.hostname}", f"--proxy_port={proxy.port or 8080}"]

subprocess.run(args + ["--licenses"], input="y\n" * 100, text=True, check=True)
subprocess.run(
    args + ["platform-tools", "build-tools;36.0.0", "platforms;android-36"],
    input="y\n" * 100,
    text=True,
    check=True,
)
for required in ("platform-tools/adb", "build-tools/36.0.0/apksigner", "platforms/android-36/android.jar"):
    if not (sdk / required).is_file():
        raise SystemExit(f"SDK installation did not produce {required}")
