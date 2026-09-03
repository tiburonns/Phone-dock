#!/usr/bin/env bash
# Universal preview distribution. Ad-hoc signed, NOT Developer ID / notarized.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/PhoneDockDMG.XXXXXX")"
ARTIFACT_DIR="$ROOT_DIR/dist/macos"
mkdir -p "$ARTIFACT_DIR" "$WORK_DIR/stage"

xcodebuild -project "$ROOT_DIR/PhoneDock.xcodeproj" -scheme PhoneDockMac \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$WORK_DIR/DerivedData" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= build

BUILT_APP="$WORK_DIR/DerivedData/Build/Products/Release/Phone Dock.app"
APP="$WORK_DIR/stage/Phone Dock.app"
ditto "$BUILT_APP" "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP/Contents/Info.plist")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid version' >&2; exit 1; }
[[ "$EXECUTABLE" == 'PhoneDock' ]] || { echo 'Unexpected executable' >&2; exit 1; }
test ! -e "$APP/Contents/embedded.provisionprofile"
/usr/bin/lipo "$APP/Contents/MacOS/$EXECUTABLE" -verify_arch arm64 x86_64
/usr/bin/codesign --force --sign - --options runtime --timestamp=none "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
ln -s /Applications "$WORK_DIR/stage/Applications"
cp "$ROOT_DIR/docs/MAC-INSTALL.txt" "$WORK_DIR/stage/LEEME - README.txt"
cp "$ROOT_DIR/LICENSE" "$WORK_DIR/stage/LICENSE.txt"
/usr/bin/hdiutil create -volname 'Phone Dock' -srcfolder "$WORK_DIR/stage" \
  -format UDZO "$WORK_DIR/PhoneDock-$VERSION-universal.dmg"
/usr/bin/hdiutil verify "$WORK_DIR/PhoneDock-$VERSION-universal.dmg"
install -m 644 "$WORK_DIR/PhoneDock-$VERSION-universal.dmg" "$ARTIFACT_DIR/PhoneDock-$VERSION-universal.dmg"
echo "DMG: $ARTIFACT_DIR/PhoneDock-$VERSION-universal.dmg"
echo "Ad-hoc signed preview; no Developer ID signature or notarization."
echo "Build directory retained for inspection: $WORK_DIR"
