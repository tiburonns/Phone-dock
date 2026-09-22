# Phone Dock for Windows

**English · [Español](README.md)**

Native **Windows 11 x64** companion for Phone Dock. The PC acts as the desktop host controlled by the iPhone/iPad application.

## Run and connect

1. Extract the complete `PhoneDock-Windows-x64.zip` folder.
2. Launch `PhoneDock.exe`. It is self-contained and does not require a separate .NET installation.
3. If Windows Firewall asks, allow access only on trusted private networks.
4. Keep iPhone and PC on the same LAN. In Phone Dock mobile, open Devices and select the Windows host.
5. If discovery fails, use the IPv4 address shown by Windows and port **49832**, then enter the rotating six-digit code.

The test executable is not distribution-signed, so Windows reputation warnings may appear. Verify its source before running it.

## Current capabilities

- Protocol v3 pairing/authentication shared with the Apple clients.
- Persistent host identity so credentials follow the computer rather than a temporary IP.
- Application activation/launch controls.
- Default audio-output volume/mute.
- Integrated display brightness through WMI or primary external-monitor DDC/CI when supported.
- Customizable action tiles, palettes, and language selection.
- Local-network operation without a cloud relay.

## Limitations

Windows remains a preview. Protocol interoperability is tested, but full WPF UI/hardware acceptance is still a physical release gate. DDC/CI depends on the monitor, GPU/driver, cable, and monitor settings. Unsupported controls are disabled rather than simulated.

Use [the physical acceptance plan](../docs/TESTING.md) before treating a build as release-ready.
