# Phone Dock 0.3.5 — TestFlight preflight

Phone Dock's iPhone/iPad target should enter Internal TestFlight only after the protected branch passes the Apple, Windows, and interoperability jobs.

## Automated gate

The Apple job validates the cross-platform version contract, regenerates the Xcode project reproducibly, tests the macOS core, and compiles Release builds for iOS Simulator, iPhoneOS, and macOS with warnings treated as errors.

The Windows and interoperability jobs must remain green because the mobile app and desktop companions share authenticated protocol v3.

## Physical acceptance

Use `docs/TESTING.md`: test Bonjour and manual connection, six-digit pairing, wrong PIN/lockout, replay protection, key rotation, persistent host identity, forget/revoke, Mac controls, Windows controls, portrait/landscape Quick Dock, localization, and revoked permissions.

## Export compliance

Phone Dock uses CryptoKit directly for P-256 key agreement, HKDF/SHA-256 and ChaChaPoly, and protocol v3 encrypts and authenticates application payloads. Do not automatically set `ITSAppUsesNonExemptEncryption = NO`.

Before the first App Store Connect upload, complete Apple's current export compliance questionnaire for this cryptographic use and determine whether an exemption applies. Keep the selected answer or supporting documentation with the release record. Add the plist key only after that determination is known.

## Archive / TestFlight

1. Merge only when `apple`, `windows`, and `interoperability` are green.
2. Open `PhoneDock.xcodeproj` and select the paid Developer Team for `PhoneDockMobile`.
3. Keep the existing mobile bundle identifier unless you intentionally create a new App ID and accept a migration.
4. Product > Archive for Generic iOS Device.
5. Organizer > Validate App.
6. Upload to App Store Connect and begin with Internal Testing.
7. Test against Mac and Windows companions built from the same revision.

The Mac DMG Developer ID/notarization path is a separate desktop-distribution gate and does not block iOS TestFlight.
