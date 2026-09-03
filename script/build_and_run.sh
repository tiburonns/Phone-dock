#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PhoneDock"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/PhoneDock.xcodeproj"
DERIVED_DATA="/tmp/PhoneDockDerivedData-$UID"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/Phone Dock.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/PhoneDock"

cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
# Keep signing and other choices made in Xcode when the project already exists.
if [[ ! -d "$PROJECT_PATH" ]]; then
  xcodegen generate --spec project.yml
fi
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme PhoneDockMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "io.cocoalift.mac"'
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
