#!/usr/bin/env python3
import json
import plistlib
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("usage: update_altstore_source.py <ipa> <source.json>")

ipa_path = Path(sys.argv[1])
source_path = Path(sys.argv[2])

with zipfile.ZipFile(ipa_path) as archive:
    info_path = next(
        name for name in archive.namelist()
        if name.startswith("Payload/") and name.endswith(".app/Info.plist")
    )
    info = plistlib.loads(archive.read(info_path))

version = str(info["CFBundleShortVersionString"])
build = str(info["CFBundleVersion"])
bundle_id = str(info["CFBundleIdentifier"])
min_os = str(info.get("MinimumOSVersion", "17.0"))
size = ipa_path.stat().st_size
date = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

if bundle_id != "io.cocoalift.mobile":
    raise SystemExit(f"unexpected bundle identifier: {bundle_id}")

source = json.loads(source_path.read_text(encoding="utf-8"))
app = source["apps"][0]
if app["bundleIdentifier"] != bundle_id:
    raise SystemExit("AltStore bundle identifier does not match the IPA")

versions = app.setdefault("versions", [])
existing = next((item for item in versions if item.get("version") == version), None)
description = (
    existing.get("localizedDescription")
    if existing else
    "Actualización conjunta de Phone Dock para iPhone/iPad, Mac y Windows. "
    "Consulta las notas de la release para ver los cambios y compatibilidad de esta versión."
)

entry = {
    "version": version,
    "buildVersion": build,
    "date": date,
    "localizedDescription": description,
    "downloadURL": (
        "https://github.com/tiburonns/Phone-dock/releases/download/"
        f"v{version}/PhoneDock-{version}.ipa"
    ),
    "size": size,
    "minOSVersion": min_os,
}

versions[:] = [item for item in versions if item.get("version") != version]
versions.insert(0, entry)

source_path.write_text(
    json.dumps(source, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

print(f"Updated Phone Dock AltStore source for {version} ({build})")
