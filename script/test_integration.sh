#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAIRING_CODE="246810"
APP_BUNDLE="/tmp/PhoneDockDerivedData-$UID/Build/Products/Debug/Phone Dock.app"
CLIENT_BINARY="/tmp/PhoneDockIntegrationClient-$UID"

cd "$ROOT_DIR"
./script/build_and_run.sh --verify >/tmp/phonedock-integration-build.log 2>&1
pkill -x PhoneDock >/dev/null 2>&1 || true
/usr/bin/open -n "$APP_BUNDLE" --args --pairing-code "$PAIRING_CODE"

app_pid=""
port=""
for _ in {1..20}; do
  app_pid="$(pgrep -x PhoneDock | head -1 || true)"
  if [[ -n "$app_pid" ]]; then
    port="$(lsof -nP -a -p "$app_pid" -iTCP -sTCP:LISTEN -Fn 2>/dev/null | sed -n 's/^n.*://p' | head -1 || true)"
  fi
  [[ -n "$port" ]] && break
  sleep 0.25
done

if [[ -z "$port" ]]; then
  echo "Phone Dock did not open a listening port." >&2
  exit 1
fi

swiftc -parse-as-library \
  Shared/Models/RemoteCommand.swift \
  Shared/Models/RemoteTile.swift \
  Shared/Models/MacState.swift \
  Shared/Networking/WireProtocol.swift \
  Shared/Networking/MessageFramer.swift \
  Shared/Networking/PairingCrypto.swift \
  script/IntegrationClient.swift \
  -o "$CLIENT_BINARY"

"$CLIENT_BINARY" "$port" "$PAIRING_CODE"
sleep 1

if /usr/bin/security find-generic-password \
  -s io.cocoalift.pairing \
  -a "Phone Dock Integration Test" >/dev/null 2>&1; then
  echo "The integration credential was not revoked." >&2
  exit 1
fi

echo "Verified Phone Dock on loopback port $port (PID $app_pid)."
