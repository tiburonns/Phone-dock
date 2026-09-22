# Phone Dock physical acceptance plan

This checklist is the release gate for behavior that CI cannot prove on simulators, loopback networking, or hosted runners.

## Environment

- One physical iPhone or iPad on iOS/iPadOS 17 or newer.
- One Mac on macOS 14 or newer.
- One Windows 11 x64 PC for the Windows companion.
- A trusted private LAN with Wi-Fi available; keep the router closed to inbound Internet traffic.
- A second SSID or hotspot available to test disconnect/reconnect behavior.
- At least one Mac with an internal display if possible, plus an external DDC/CI-capable monitor for optional brightness validation.
- AltStore Classic configured on the iPhone/iPad for the unsigned IPA acceptance test.

## 1. Installation and first launch

1. Install the current iPhone/iPad build from Xcode and launch it.
2. Accept Local Network access.
3. Launch the current Mac build.
4. Confirm Bonjour discovery shows the Mac without entering an address.
5. Repeat using the current AltStore IPA and confirm it installs, launches, and requests only the expected permissions.

Pass: both installation paths launch successfully and Bonjour discovery works without router changes.

## 2. Pairing, identity, reconnect, and revocation

1. Pair with the six-digit code.
2. Enter an incorrect code repeatedly and confirm temporary lockout occurs.
3. Pair correctly and verify Dock/state data load.
4. Close and reopen both apps; confirm reconnect uses the saved stable host identity.
5. Change the Mac host name or move between DHCP addresses; confirm the pairing still follows the same host identity.
6. Rotate the pairing key and confirm control continues.
7. Forget the phone from the Mac and verify subsequent commands fail.
8. Pair again, then forget the computer from the phone and verify the desktop credential is revoked.
9. Disconnect Wi-Fi, restore it, and verify automatic reconnect does not duplicate credentials or actions.

Pass: credentials survive benign endpoint changes, reject unexpected identity changes, rotate cleanly, and are revoked bidirectionally.

## 3. macOS command surface

Test every action with Accessibility denied first, then granted where required.

- Launch an installed application.
- Long-press an application tile and verify a new instance is requested for a multi-instance app.
- Open an HTTPS URL.
- Run an Apple Shortcut.
- Insert Unicode text.
- Copy and paste.
- Minimize, maximize/full-screen behavior, and hide/window actions.
- Change volume and mute state.
- Change internal-display brightness when available.
- Exercise the external-display fallback and document whether the monitor/connection supports it.

Pass: supported commands change only the intended state, unsupported hardware returns a clear error, and denied Accessibility never causes a crash.

## 4. Mobile interaction and synchronization

1. Use portrait navigation and all action pages.
2. Rotate to landscape and swipe through the three controller pages.
3. Tap several emojis and confirm ranking changes without losing defaults.
4. Drag volume and brightness for more than three seconds, then release at 25%, 50%, and 75%.
5. Edit an action on Mac and confirm name, icon/artwork, detail, color, page, and ordering update on the phone.
6. Pin and unpin recent applications and relaunch both apps.
7. Background and foreground the phone while connected.

Pass: gestures do not accidentally launch actions, sliders are not overwritten during a drag, and catalog/recent-app changes persist and synchronize.

## 5. Windows 11 companion

1. Launch the self-contained Windows package without administrator privileges.
2. Allow the firewall prompt only on the private network.
3. Pair by discovery, then repeat by manual IPv4 address and port 49832.
4. Exercise applications, URLs, text, volume, mute, copy/paste, minimize/maximize, and brightness.
5. Test integrated WMI brightness where available.
6. Test a DDC/CI-capable external monitor and repeat with DDC/CI disabled.
7. Change default audio output while connected and repeat slider tests.
8. Revoke the phone and confirm DPAPI-backed credentials no longer authorize commands.
9. Verify 100%, 150%, and 200% display scaling and keyboard navigation.

Pass: the WPF UI remains usable at each scale, hardware capabilities are detected rather than assumed, and Swift/.NET protocol behavior matches the Apple companion.

## 6. Failure modes

- Launch a second desktop instance.
- Remove the default audio device.
- Disconnect an external display during a command.
- Block mDNS and connect manually.
- Send commands while disconnected.
- Restart the router while paired.
- Reboot the Mac/PC and reconnect.
- Verify no command path requires exposing the service port to the public Internet.

Pass: failures are recoverable, surfaced to the user, and do not corrupt pairing or action data.

## Release gate

Phone Dock can be called physically validated only after the applicable Mac, iPhone/iPad, AltStore, and Windows sections above pass on real hardware. CI success, simulator builds, the macOS loopback integration test, and Swift/.NET interoperability tests are necessary but do not replace this gate.
