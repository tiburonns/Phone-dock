import CryptoKit
import XCTest
import SwiftUI

final class WireProtocolTests: XCTestCase {
    func testSwipePadDirectionsAndAccidentalTouchThreshold() {
        XCTAssertEqual(RemoteCommand.swipe(horizontal: 0, vertical: -80), .window(.maximize))
        XCTAssertEqual(RemoteCommand.swipe(horizontal: 3, vertical: 80), .window(.minimize))
        XCTAssertEqual(RemoteCommand.swipe(horizontal: -80, vertical: 3), .clipboard(.copy))
        XCTAssertEqual(RemoteCommand.swipe(horizontal: 80, vertical: 3), .clipboard(.paste))
        XCTAssertEqual(RemoteCommand.swipe(horizontal: 28, vertical: 0), .clipboard(.paste))
        XCTAssertNil(RemoteCommand.swipe(horizontal: 20, vertical: 20))
        XCTAssertNil(RemoteCommand.swipe(horizontal: 0, vertical: 0))
        XCTAssertNil(RemoteCommand.swipe(horizontal: .nan, vertical: 40))
    }
    func testLanguageChoicePersistsAndResolvesRegionalFallbacks() throws {
        let suite = "PhoneDock.LanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let choice = AppStorage(wrappedValue: AppLanguage.system, AppLanguage.preferenceKey, store: defaults)
        XCTAssertEqual(choice.wrappedValue, .system)
        choice.wrappedValue = .spanish
        XCTAssertEqual(AppStorage(wrappedValue: AppLanguage.system, AppLanguage.preferenceKey, store: defaults).wrappedValue, .spanish)
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["es-MX", "en-US"]), "es")
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["fr-FR", "en-GB"]), "en")
        XCTAssertEqual(AppLanguage.system.resolvedCode(preferredLanguages: ["ja-JP"]), "en")
        XCTAssertEqual(AppLanguage.english.resolvedCode(preferredLanguages: ["es-MX"]), "en")
        XCTAssertEqual(AppLanguage.spanish.resolvedCode(preferredLanguages: ["en-US"]), "es")
        defaults.set("removed-language", forKey: AppLanguage.preferenceKey)
        XCTAssertEqual(AppStorage(wrappedValue: AppLanguage.system, AppLanguage.preferenceKey, store: defaults).wrappedValue, .system)
    }

    func testBothLanguageResourcesAndMissingKeyFallback() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resources = try XCTUnwrap(Bundle(url: root.appendingPathComponent("Shared")))
        XCTAssertEqual(AppLanguage.spanish.translate("Language", bundle: resources), "Idioma")
        XCTAssertEqual(AppLanguage.english.translate("Language", bundle: resources), "Language")
        XCTAssertEqual(AppLanguage.spanish.translate("Unknown test key", bundle: resources), "Unknown test key")
    }

    func testAppearancePreferencesPersistAndUseSafeDefaults() throws {
        let suite = "PhoneDock.AppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let palette = AppStorage(wrappedValue: DockPalette.aurora, DockPreferenceKey.palette, store: defaults)
        let size = AppStorage(wrappedValue: DockIconSize.extraLarge, DockPreferenceKey.iconSize, store: defaults)
        XCTAssertEqual(palette.wrappedValue, .aurora)
        XCTAssertEqual(size.wrappedValue, .extraLarge)
        palette.wrappedValue = .ocean
        size.wrappedValue = .large
        let restored = AppStorage(wrappedValue: DockPalette.aurora, DockPreferenceKey.palette, store: defaults)
        XCTAssertEqual(restored.wrappedValue, .ocean)
        XCTAssertEqual(defaults.string(forKey: DockPreferenceKey.iconSize), "large")
        defaults.set("removed-palette", forKey: DockPreferenceKey.palette)
        let fallback = AppStorage(wrappedValue: DockPalette.aurora, DockPreferenceKey.palette, store: defaults)
        XCTAssertEqual(fallback.wrappedValue, .aurora)
    }

    func testEveryPaletteHasValidDistinctTokens() {
        XCTAssertEqual(DockPalette.allCases.count, 5)
        XCTAssertEqual(Set(DockPalette.allCases.map(\.lightAccent)).count, 5)
        for palette in DockPalette.allCases {
            for hex in [palette.lightAccent, palette.darkAccent, palette.companion] {
                XCTAssertEqual(hex.count, 6)
                XCTAssertNotNil(UInt32(hex, radix: 16))
            }
        }
        XCTAssertGreaterThanOrEqual(DockIconSize.large.points, 76)
        XCTAssertEqual(DockIconSize.extraLarge.points, 100)
    }

    @MainActor
    func testCustomizationPersistsWithoutChangingActionOrPosition() throws {
        let suite = "PhoneDock.CustomizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CatalogStore(defaults: defaults)
        let original = try XCTUnwrap(store.tiles.first)
        var edited = original
        edited.title = "My personal action"
        edited.subtitle = "Custom detail"
        edited.displayEmoji = "🌊"
        edited.tintHex = "096B97"
        edited.iconPNGData = Data([1, 2, 3])
        edited.command = .setVolume(0)
        edited.page = 7
        store.update(edited)
        let restored = CatalogStore(defaults: defaults)
        let result = try XCTUnwrap(restored.tiles.first { $0.id == original.id })
        XCTAssertEqual(result.title, "My personal action")
        XCTAssertEqual(result.displayEmoji, "🌊")
        XCTAssertEqual(result.iconPNGData, Data([1, 2, 3]))
        XCTAssertEqual(result.tintHex, "096B97")
        XCTAssertEqual(result.command, original.command)
        XCTAssertEqual(result.page, original.page)
        XCTAssertEqual(result.sortOrder, original.sortOrder)
    }

    func testRecentArtworkRoundTripsAndLegacyStillDecodes() throws {
        let app = RecentApplication(name: "Preview", bundleIdentifier: "test.preview", lastOpenedAt: Date(),
                                    isPinned: true, iconPNGData: Data([0, 1, 2]))
        let message = WireMessage(type: .catalogResponse, recentApplications: [app])
        var framer = MessageFramer()
        XCTAssertEqual(try framer.append(MessageFramer.frame(message)), [message])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(app)) as? [String: Any])
        legacy.removeValue(forKey: "iconPNGData")
        let decoded = try JSONDecoder().decode(RecentApplication.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.iconPNGData)
        XCTAssertTrue(decoded.isPinned)
    }

    func testFramerHandlesFragmentedAndMultipleMessages() throws {
        let first = WireMessage(type: .ping, deviceName: "Phone")
        let second = WireMessage(type: .stateResponse, state: .placeholder)
        let joined = try MessageFramer.frame(first) + MessageFramer.frame(second)

        var framer = MessageFramer()
        XCTAssertTrue(try framer.append(joined.prefix(7)).isEmpty)
        let decoded = try framer.append(joined.dropFirst(7))

        XCTAssertEqual(decoded, [first, second])
    }

    func testAuthenticationDetectsTampering() throws {
        let secret = Data(SHA256.hash(data: Data("secret".utf8)))
        let original = WireMessage(type: .command, deviceName: "Phone", command: .setVolume(0.42))
        let signed = try original.signed(with: secret)
        XCTAssertTrue(signed.isAuthenticated(with: secret))

        var tampered = signed
        tampered.command = .setVolume(1)
        XCTAssertFalse(tampered.isAuthenticated(with: secret))
    }

    func testStarterDeckHasStableOrder() {
        let deck = RemoteTile.starterDeck
        XCTAssertFalse(deck.isEmpty)
        XCTAssertEqual(deck.map(\.sortOrder), Array(0..<deck.count))
        XCTAssertEqual(Set(deck.map(\.id)).count, deck.count)
    }

    func testRemoteTileDecodesCatalogSavedBeforeCustomEmojiSupport() throws {
        let tile = RemoteTile.starterDeck[0]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(tile)) as? [String: Any])
        object.removeValue(forKey: "displayEmoji")
        object.removeValue(forKey: "iconPNGData")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(RemoteTile.self, from: legacyData)
        XCTAssertNil(decoded.displayEmoji)
        XCTAssertNil(decoded.iconPNGData)
    }

    func testPairingSecretIsEncryptedForClientKey() throws {
        let client = PairingCrypto.makePrivateKey()
        let secret = Data("persistent-secret".utf8)
        let sealed = try PairingCrypto.seal(
            secret: secret,
            for: client.publicKey.rawRepresentation,
            pin: "142857"
        )

        XCTAssertFalse(sealed.ciphertext.contains(secret))
        XCTAssertEqual(
            try PairingCrypto.open(
                ciphertext: sealed.ciphertext,
                serverPublicKey: sealed.serverPublicKey,
                clientPrivateKey: client,
                pin: "142857"
            ),
            secret
        )
        XCTAssertThrowsError(try PairingCrypto.open(
            ciphertext: sealed.ciphertext,
            serverPublicKey: sealed.serverPublicKey,
            clientPrivateKey: client,
            pin: "000000"
        ))
    }

    func testReplayProtectorRejectsDuplicateAndEvictsOldIDs() {
        var protector = MessageReplayProtector(capacityPerDevice: 2)
        let first = UUID()
        let second = UUID()
        let third = UUID()

        XCTAssertTrue(protector.accept(first, from: "iPhone"))
        XCTAssertFalse(protector.accept(first, from: "iPhone"))
        XCTAssertTrue(protector.accept(first, from: "iPad"))
        XCTAssertTrue(protector.accept(second, from: "iPhone"))
        XCTAssertTrue(protector.accept(third, from: "iPhone"))
        XCTAssertTrue(protector.accept(first, from: "iPhone"))
    }

    func testPairingLimiterLocksAndRecovers() {
        let start = Date(timeIntervalSince1970: 1_000)
        var limiter = PairingAttemptLimiter(maximumFailures: 3, failureWindow: 60, lockoutDuration: 30)

        XCTAssertNil(limiter.recordFailure(at: start))
        XCTAssertNil(limiter.recordFailure(at: start.addingTimeInterval(1)))
        XCTAssertEqual(limiter.recordFailure(at: start.addingTimeInterval(2)), 30)
        XCTAssertNotNil(limiter.remainingLockout(at: start.addingTimeInterval(20)))
        XCTAssertNil(limiter.remainingLockout(at: start.addingTimeInterval(33)))
    }

    @MainActor
    func testRecentApplicationsPersistAndPinnedAppsStayAtFront() throws {
        let suiteName = "io.cocoalift.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CatalogStore(defaults: defaults)
        store.recordRecent(name: "Safari", bundleIdentifier: "com.apple.Safari")
        store.recordRecent(name: "Mail", bundleIdentifier: "com.apple.mail")
        store.setRecentApplicationPinned(bundleIdentifier: "com.apple.Safari", pinned: true)

        XCTAssertEqual(store.recentApplications.map(\.bundleIdentifier), ["com.apple.Safari", "com.apple.mail"])
        XCTAssertTrue(try XCTUnwrap(store.recentApplications.first).isPinned)

        let restored = CatalogStore(defaults: defaults)
        XCTAssertEqual(restored.recentApplications, store.recentApplications)
    }

    func testRecentApplicationDecodesLegacyPayloadAsUnpinned() throws {
        let payload = #"{"name":"Safari","bundleIdentifier":"com.apple.Safari","lastOpenedAt":0}"#.data(using: .utf8)!
        let application = try JSONDecoder().decode(RecentApplication.self, from: payload)
        XCTAssertFalse(application.isPinned)
    }

    func testPinnedRecentCommandRoundTripsAndAuthenticates() throws {
        let secret = Data(SHA256.hash(data: Data("pin-command-secret".utf8)))
        let message = WireMessage(
            type: .command,
            deviceName: "iPhone",
            command: .setRecentAppPinned(bundleIdentifier: "com.apple.Safari", pinned: true)
        )
        let signed = try message.signed(with: secret)
        let decoded = try WireMessage.decoder.decode(
            WireMessage.self,
            from: WireMessage.encoder.encode(signed)
        )

        XCTAssertEqual(decoded.command, .setRecentAppPinned(bundleIdentifier: "com.apple.Safari", pinned: true))
        XCTAssertTrue(decoded.isAuthenticated(with: secret))
    }
}
