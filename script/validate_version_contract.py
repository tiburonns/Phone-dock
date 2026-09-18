#!/usr/bin/env python3
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

print(f"PASS: Phone Dock version contract {version} (build {build}) across Apple, Windows, and README")
