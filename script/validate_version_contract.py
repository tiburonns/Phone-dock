#!/usr/bin/env python3
import plistlib
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

project_yml = (ROOT / "project.yml").read_text(encoding="utf-8")
pbxproj = (ROOT / "PhoneDock.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
readme = (ROOT / "README.md").read_text(encoding="utf-8")
main_window = (ROOT / "Windows/PhoneDock/MainWindow.xaml.cs").read_text(encoding="utf-8")

version_match = re.search(r"MARKETING_VERSION:\s*([0-9.]+)", project_yml)
build_match = re.search(r"CURRENT_PROJECT_VERSION:\s*([0-9]+)", project_yml)
if not version_match or not build_match:
    raise SystemExit("version contract failed: project.yml version/build missing")

version = version_match.group(1)
build = build_match.group(1)

pbx_versions = set(re.findall(r"MARKETING_VERSION = ([0-9.]+);", pbxproj))
pbx_builds = set(re.findall(r"CURRENT_PROJECT_VERSION = ([0-9]+);", pbxproj))
if pbx_versions != {version}:
    raise SystemExit(f"version contract failed: Xcode project versions {sorted(pbx_versions)} != {version}")
if pbx_builds != {build}:
    raise SystemExit(f"version contract failed: Xcode project builds {sorted(pbx_builds)} != {build}")

windows_project = ET.parse(ROOT / "Windows/PhoneDock/PhoneDock.csproj").getroot()
windows_version = windows_project.findtext(".//Version")
if windows_version != version:
    raise SystemExit(f"version contract failed: Windows {windows_version} != Apple {version}")

expected_readme = f"The current `main` branch is **{version} (build {build})**"
if expected_readme not in readme:
    raise SystemExit("version contract failed: README development version is stale")

if re.search(r'Windows 11 · versión 0\.\d+\.\d+', main_window):
    raise SystemExit("version contract failed: Windows About screen hardcodes a version")

mobile_info = plistlib.loads((ROOT / "Mobile/Info.plist").read_bytes())
mac_info = plistlib.loads((ROOT / "Mac/Info.plist").read_bytes())
bonjour_type = "_cocoalift._tcp"

for name, info in [("Mobile", mobile_info), ("Mac", mac_info)]:
    if bonjour_type not in set(info.get("NSBonjourServices", [])):
        raise SystemExit(
            f"local-network contract failed: {name} Info.plist is missing {bonjour_type}"
        )
    if not str(info.get("NSLocalNetworkUsageDescription", "")).strip():
        raise SystemExit(
            f"local-network contract failed: {name} usage description is missing"
        )

privacy_manifest = plistlib.loads((ROOT / "Shared/PrivacyInfo.xcprivacy").read_bytes())
if privacy_manifest.get("NSPrivacyTracking") is not False:
    raise SystemExit("privacy contract failed: tracking must be false")
privacy_reasons = {
    item.get("NSPrivacyAccessedAPIType"): set(item.get("NSPrivacyAccessedAPITypeReasons", []))
    for item in privacy_manifest.get("NSPrivacyAccessedAPITypes", [])
}
if "CA92.1" not in privacy_reasons.get("NSPrivacyAccessedAPICategoryUserDefaults", set()):
    raise SystemExit("privacy contract failed: UserDefaults CA92.1 reason is missing")
if "PrivacyInfo.xcprivacy in Resources" not in pbxproj:
    raise SystemExit("privacy contract failed: PrivacyInfo.xcprivacy is not embedded in Apple resources")

spanish_info = (ROOT / "Shared/es.lproj/InfoPlist.strings").read_text(
    encoding="utf-8"
)
if '"NSLocalNetworkUsageDescription"' not in spanish_info:
    raise SystemExit(
        "local-network contract failed: Spanish permission localization is missing"
    )

wire = (ROOT / "Shared/Networking/WireProtocol.swift").read_text(encoding="utf-8")
mobile = (ROOT / "Mobile/Services/MobileConnectionStore.swift").read_text(encoding="utf-8")
mac_server = (ROOT / "Mac/Services/MacRemoteServer.swift").read_text(encoding="utf-8")
windows_wire = (ROOT / "Windows/PhoneDock.Core/Wire.cs").read_text(encoding="utf-8")
windows_server = (ROOT / "Windows/PhoneDock.Core/RemoteServer.cs").read_text(encoding="utf-8")
integration = (ROOT / "script/IntegrationClient.swift").read_text(encoding="utf-8")

if 'let cocoaLiftBonjourType = "_cocoalift._tcp"' not in wire:
    raise SystemExit(
        "local-network contract failed: Swift Bonjour type diverged from Info.plist"
    )

required_swift = [
    "case identityRequest",
    "case identityResponse",
    "var serverID: String?",
]
for token in required_swift:
    if token not in wire:
        raise SystemExit(f"host identity contract failed: Swift wire missing {token}")

for token in [
    "ServerIdentityStore",
    "message.isAuthenticated(with: secret)",
    "pendingIdentityLookup",
]:
    if token not in mobile:
        raise SystemExit(f"host identity contract failed: mobile missing {token}")

for token in ["MacServerIdentity", "serverID: serverID", ".identityRequest"]:
    if token not in mac_server:
        raise SystemExit(f"host identity contract failed: Mac server missing {token}")

for token in ['envelope["serverID"]', 'inner["serverID"]']:
    if token not in windows_wire:
        raise SystemExit(f"host identity contract failed: Windows wire missing {token}")

for token in ["HostIdentity", "identityRequest", "Wire.Sign(response, newSecret)"]:
    if token not in windows_server:
        raise SystemExit(f"host identity contract failed: Windows server missing {token}")

for token in ["identityRequest", "message.isAuthenticated(with: secret)"]:
    if token not in integration:
        raise SystemExit(f"host identity integration contract failed: missing {token}")

testflight_en = ROOT / "docs/TESTFLIGHT.md"
testflight_es = ROOT / "docs/TESTFLIGHT.es.md"
for path in [testflight_en, testflight_es]:
    if not path.exists():
        raise SystemExit(f"release contract failed: missing {path.relative_to(ROOT)}")
    content = path.read_text(encoding="utf-8").lower()
    for token in ["cryptokit", "export compliance"]:
        if token not in content:
            raise SystemExit(
                f"release contract failed: {path.relative_to(ROOT)} must document {token}"
            )

workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
for token in [
    "Build Release iOS Simulator",
    "Build Release iPhoneOS",
    "Build Release macOS",
    "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES",
]:
    if token not in workflow:
        raise SystemExit(f"release CI contract failed: missing {token}")

print(f"PASS: Phone Dock version contract {version} (build {build}) across Apple, Windows, README, stable host identity, and TestFlight preflight")
