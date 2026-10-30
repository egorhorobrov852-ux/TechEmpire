"""Verify packaged native resources against the checked-out TECH EMPIRE source."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("apk", type=Path)
parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
parser.add_argument("--report", type=Path)
args = parser.parse_args()

with zipfile.ZipFile(args.apk) as archive:
    names = set(archive.namelist())
    required = {
        "AndroidManifest.xml", "classes.dex", "assets/project.binary",
        "lib/arm64-v8a/libgodot_android.so", "lib/x86_64/libgodot_android.so",
        "assets/scenes/main_menu/main.tscn.remap", "assets/scenes/city/city.tscn.remap",
    }
    missing = sorted(required - names)
    if missing:
        raise SystemExit(f"Missing native project resources: {missing}")
    data_files = []
    for source in sorted((args.project / "data").rglob("*")):
        if source.suffix not in {".json", ".xml"}:
            continue
        relative = source.relative_to(args.project).as_posix()
        packaged = "assets/" + relative
        if packaged not in names:
            raise SystemExit(f"Data file was omitted by the export filter: {relative}")
        content = archive.read(packaged)
        if content != source.read_bytes():
            raise SystemExit(f"Packaged data does not match the source: {relative}")
        if source.suffix == ".json":
            json.loads(content)
        data_files.append(relative)
    script_files = sorted(n for n in names if n.startswith("assets/scripts/") and n.endswith((".gdc", ".gd", ".remap")))
    for script in ("economy/simulation", "ui/main", "world/city", "save_system/save_store", "data_sync/economic_feed"):
        if not any(f"assets/scripts/{script}." in name for name in script_files):
            raise SystemExit(f"Missing game system script in APK: {script}")
    forbidden = sorted(n for n in names if n.startswith(("assets/src/", "assets/tests/", "assets/tools/", "assets/docs/")))
    if forbidden:
        raise SystemExit(f"Non-game source should not be in the APK: {forbidden}")

report = {
    "apk": args.apk.name,
    "size_bytes": args.apk.stat().st_size,
    "sha256": hashlib.sha256(args.apk.read_bytes()).hexdigest(),
    "verified_native_architectures": ["arm64-v8a", "x86_64"],
    "source_matched_data_files": data_files,
    "game_script_files": script_files,
    "archive_entries": len(names),
    "android_device_launch_tested": False,
}
serialized = json.dumps(report, ensure_ascii=False, indent=2)
if args.report:
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(serialized + "\n")
print(serialized)
