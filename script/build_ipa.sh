#!/usr/bin/env bash
# Produce an unsigned device build for AltStore Classic to re-sign.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/PhoneDockIPA.XXXXXX")"
ARTIFACT_DIR="$ROOT_DIR/dist/ios"
mkdir -p "$ARTIFACT_DIR" "$WORK_DIR/package/Payload"

xcodebuild -project "$ROOT_DIR/PhoneDock.xcodeproj" -scheme PhoneDockMobile \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$WORK_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= build

APP="$WORK_DIR/DerivedData/Build/Products/Release-iphoneos/Phone Dock.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist")
# Avoid interpreting an arbitrary Info.plist value as an artifact path.
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid version' >&2; exit 1; }
test ! -e "$APP/embedded.mobileprovision"
test ! -e "$APP/_CodeSignature"
ditto "$APP" "$WORK_DIR/package/Payload/Phone Dock.app"
(
  cd "$WORK_DIR/package"
  COPYFILE_DISABLE=1 /usr/bin/zip -q -r -y "$WORK_DIR/PhoneDock-$VERSION.ipa" Payload
)
/usr/bin/unzip -tq "$WORK_DIR/PhoneDock-$VERSION.ipa"
install -m 644 "$WORK_DIR/PhoneDock-$VERSION.ipa" "$ARTIFACT_DIR/PhoneDock-$VERSION.ipa"
echo "IPA: $ARTIFACT_DIR/PhoneDock-$VERSION.ipa"
echo "Build directory retained for inspection: $WORK_DIR"
