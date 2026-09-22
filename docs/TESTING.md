# Phone Dock physical acceptance plan

**English · [Español](TESTING.es.md)**

CI is necessary but not sufficient for Phone Dock because several features depend on physical devices, operating-system permissions, local-network discovery, audio/display hardware, and AltStore signing.

## iPhone/iPad + Mac

- Install the same `main` revision on mobile and Mac.
- Verify Bonjour discovery and manual host/port fallback.
- Pair with the six-digit code and confirm reconnect survives IP/service-name changes while host identity remains stable.
- Verify wrong-PIN lockout, replay rejection, key rotation, forget/revocation, and protocol mismatch messaging.
- Exercise app/Shortcut/web/text/clipboard actions.
- Validate volume, mute, brightness where supported, window actions, copy/paste, Quick Dock gestures, landscape pages, customization, and EN/ES/System language behavior.
- Revoke Accessibility and confirm only dependent actions degrade.

## Windows 11 x64

- Run the self-contained package as a standard user.
- Validate discovery/manual IP pairing and persistent host identity.
- Exercise app activation/launch, window restoration, volume/mute, and brightness.
- Test integrated-display WMI and external DDC/CI separately where hardware is available.
- Confirm unsupported brightness paths are disabled and do not report false success.
- Validate WPF UI, palettes, customization, EN/ES/System language, and restart persistence.

## AltStore Classic

- Install the release IPA through the repository source on a physical iPhone/iPad.
- Confirm the IPA is re-signed by the user's account and launches normally.
- Verify local-network permission and pairing.
- Confirm renewal behavior appropriate to the selected Apple account.

## Release evidence

Record device/OS/build revision and pass/fail results for each hardware-dependent path. Do not call a release hardware-validated based only on simulator or CI results.
