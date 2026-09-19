import Combine
import Foundation
import Network
import SystemConfiguration

struct PairedDeviceInfo: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
}

@MainActor
final class MacRemoteServer: ObservableObject {
    enum Status: Equatable {
        case stopped
        case starting
        case ready(port: UInt16)
        case failed(String)

        var title: String {
            switch self {
            case .stopped: localized("Stopped")
            case .starting: localized("Starting…")
            case .ready: localized("Ready")
            case .failed: localized("Unavailable")
            }
        }
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var pairingCode = "------"
    @Published private(set) var pairedDevices: [PairedDeviceInfo]
    @Published private(set) var lastError: String?
    @Published private(set) var connectedDeviceCount = 0
    @Published private(set) var advertisedServiceName: String?

    var manualConnectionAddress: String? {
        guard case .ready(let port) = status else { return nil }
        let localName = (SCDynamicStoreCopyLocalHostName(nil) as String?) ?? "Mac"
        return "\(localName).local:\(port)"
    }

    private let catalog: CatalogStore
    private let controller: SystemController
    private let queue = DispatchQueue(label: "io.cocoalift.server", qos: .userInitiated)
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var connectionDevices: [ObjectIdentifier: String] = [:]
    private var pinTimer: Timer?
    private var catalogObservers: Set<AnyCancellable> = []
    private var replayProtector = MessageReplayProtector()
    private var pairingLimiter = PairingAttemptLimiter()
    private var debugPairingCode: String?
    private let legacyDeviceDefaultsKey = "cocoalift.pairedDevices.v1"
    private let deviceDefaultsKey = "cocoalift.pairedDevices.v2"
    private let previousSecretSuffix = ".previous"
    private let serverID = MacServerIdentity.id

    init(catalog: CatalogStore, controller: SystemController) {
        self.catalog = catalog
        self.controller = controller
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: deviceDefaultsKey),
           let decoded = try? JSONDecoder().decode([PairedDeviceInfo].self, from: data) {
            pairedDevices = decoded
        } else {
            pairedDevices = (defaults.stringArray(forKey: legacyDeviceDefaultsKey) ?? [])
                .map { PairedDeviceInfo(id: $0, name: $0) }
        }
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "--pairing-code"), arguments.indices.contains(flag + 1) {
            let candidate = arguments[flag + 1]
            if candidate.count == 6, candidate.allSatisfy(\.isNumber) { debugPairingCode = candidate }
        }
#endif
        catalog.$tiles
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.broadcastCatalog() }
            }
            .store(in: &catalogObservers)
        catalog.$recentApplications
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.broadcastCatalog() }
            }
            .store(in: &catalogObservers)
    }

    func start() {
        guard listener == nil else { return }
        status = .starting
        rotatePairingCode()
        do {
            let listener = try NWListener(using: .tcp, on: .any)
            listener.service = .init(name: Host.current().localizedName ?? "Mac", type: cocoaLiftBonjourType)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.handleListenerState(state) }
            }
            listener.serviceRegistrationUpdateHandler = { [weak self] change in
                Task { @MainActor in self?.handleServiceRegistrationChange(change) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: queue)
            self.listener = listener
            pinTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.rotatePairingCode() }
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        connectionDevices.removeAll()
        pinTimer?.invalidate()
        pinTimer = nil
        connectedDeviceCount = 0
        advertisedServiceName = nil
        status = .stopped
    }

    func rotatePairingCode() {
        if let debugPairingCode {
            pairingCode = debugPairingCode
            return
        }
        pairingCode = String(format: "%06d", Int.random(in: 0...999_999))
    }

    func forgetDevice(_ device: PairedDeviceInfo) {
        forgetDevice(identity: device.id)
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port?.rawValue { status = .ready(port: port) }
        case .failed(let error):
            status = .failed(error.localizedDescription)
            listener = nil
        case .cancelled:
            status = .stopped
        default:
            break
        }
    }

    private func handleServiceRegistrationChange(_ change: NWListener.ServiceRegistrationChange) {
        switch change {
        case .add(let endpoint):
            if case .service(let name, _, _, _) = endpoint {
                advertisedServiceName = name
            } else {
                advertisedServiceName = endpoint.debugDescription
            }
        case .remove:
            advertisedServiceName = nil
        @unknown default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            if case .failed = state { Task { @MainActor in self?.remove(connection) } }
            if case .cancelled = state { Task { @MainActor in self?.remove(connection) } }
        }
        connection.start(queue: queue)
        receive(on: connection, framer: MessageFramer())
    }

    private func remove(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
        connectionDevices.removeValue(forKey: ObjectIdentifier(connection))
        updateConnectedDeviceCount()
    }

    nonisolated private func receive(on connection: NWConnection, framer: MessageFramer) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            var nextFramer = framer
            if let data, !data.isEmpty {
                do {
                    let messages = try nextFramer.append(data)
                    for message in messages {
                        Task { @MainActor in self?.handle(message, on: connection) }
                    }
                } catch {
                    connection.cancel()
                    return
                }
            }
            if complete || error != nil {
                connection.cancel()
                return
            }
            self?.receive(on: connection, framer: nextFramer)
        }
    }

    private func handle(_ message: WireMessage, on connection: NWConnection) {
        guard message.version == WireMessage.protocolVersion else {
            send(.init(
                type: .error,
                error: localized("Unsupported protocol version."),
                supportedProtocolVersion: WireMessage.protocolVersion
            ), on: connection)
            return
        }
        if message.type == .pairRequest {
            pair(message, on: connection)
            return
        }

        if message.type == .identityRequest {
            send(.init(
                type: .identityResponse,
                serverID: serverID,
                supportedProtocolVersion: WireMessage.protocolVersion
            ), on: connection)
            return
        }

        guard let displayName = message.deviceName, !displayName.isEmpty else {
            send(.init(type: .error, error: localized("This device is not paired.")), on: connection)
            return
        }

        let identity = stableIdentity(deviceID: message.deviceID, fallbackName: displayName)
        let directSecret = KeychainStore.load(account: identity)
        let legacySecret = identity == displayName ? nil : KeychainStore.load(account: displayName)

        guard let currentSecret = directSecret ?? legacySecret else {
            send(.init(type: .error, error: localized("This device is not paired.")), on: connection)
            return
        }

        let usedLegacyIdentity = directSecret == nil && legacySecret != nil
        let previousSecret = KeychainStore.load(account: previousSecretAccount(for: identity))
            ?? (usedLegacyIdentity ? KeychainStore.load(account: previousSecretAccount(for: displayName)) : nil)

        let openedWithCurrent = (try? message.opened(with: currentSecret)).map { ($0, currentSecret, false) }
        let openedWithPrevious = previousSecret.flatMap { previous in
            (try? message.opened(with: previous)).map { ($0, previous, true) }
        }
        guard let (openedMessage, secret, usedPreviousSecret) = openedWithCurrent ?? openedWithPrevious else {
            send(.init(type: .error, error: localized("This device is not paired.")), on: connection)
            return
        }

        if usedLegacyIdentity {
            migrateLegacyIdentity(
                from: displayName,
                to: identity,
                displayName: displayName,
                secret: currentSecret
            )
        } else {
            rememberDevice(identity: identity, displayName: displayName)
        }

        guard replayProtector.accept(
            openedMessage.id,
            sentAt: openedMessage.sentAt,
            from: identity
        ) else {
            sendAuthenticated(.init(type: .error, error: localized("Duplicate request rejected.")), secret: secret, on: connection)
            return
        }
        connectionDevices[ObjectIdentifier(connection)] = identity
        updateConnectedDeviceCount()

        if usedPreviousSecret {
            sendAuthenticated(.init(
                type: .rotateSecretResponse,
                encryptedSecret: currentSecret.base64EncodedString()
            ), secret: secret, on: connection)
            return
        }

        switch openedMessage.type {
        case .command:
            guard let command = openedMessage.command else { return }
            if case .setRecentAppPinned(let bundleIdentifier, let pinned) = command {
                catalog.setRecentApplicationPinned(bundleIdentifier: bundleIdentifier, pinned: pinned)
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await controller.execute(command)
                    sendAuthenticated(.init(type: .stateResponse, state: controller.currentState()), secret: secret, on: connection)
                } catch {
                    lastError = error.localizedDescription
                    sendAuthenticated(.init(type: .error, error: error.localizedDescription), secret: secret, on: connection)
                }
            }
        case .stateRequest, .ping:
            sendAuthenticated(.init(type: .stateResponse, state: controller.currentState()), secret: secret, on: connection)
        case .catalogRequest:
            sendAuthenticated(.init(
                type: .catalogResponse,
                catalog: catalog.tiles,
                recentApplications: catalog.recentApplications
            ), secret: secret, on: connection)
        case .rotateSecret:
            rotateSecret(for: identity, currentSecret: secret, on: connection)
        case .rotateSecretAcknowledgement:
            KeychainStore.delete(account: previousSecretAccount(for: identity))
        case .unpair:
            sendAuthenticated(.init(type: .unpair, deviceName: displayName, deviceID: identity), secret: secret, on: connection)
            Task { @MainActor [weak self, weak connection] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.forgetDevice(identity: identity)
                connection?.cancel()
            }
        default:
            break
        }
    }

    private func pair(_ message: WireMessage, on connection: NWConnection) {
        if let remaining = pairingLimiter.remainingLockout() {
            send(.init(type: .error, error: localizedFormat("Pairing is temporarily locked. Try again in %d seconds.", Int(ceil(remaining)))), on: connection)
            return
        }
        guard let name = message.deviceName,
              !name.isEmpty,
              let pin = message.pin,
              pin == pairingCode,
              let encodedClientKey = message.publicKey,
              let clientKey = Data(base64Encoded: encodedClientKey) else {
            if pairingLimiter.recordFailure() != nil { rotatePairingCode() }
            send(.init(type: .error, error: localized("The pairing code is incorrect or expired.")), on: connection)
            return
        }

        let identity = stableIdentity(deviceID: message.deviceID, fallbackName: name)
        pairingLimiter.recordSuccess()
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            send(.init(type: .error, error: localized("Could not create pairing credentials.")), on: connection)
            return
        }

        let secret = Data(bytes)
        do {
            let sealed = try PairingCrypto.seal(secret: secret, for: clientKey, pin: pin)
            try KeychainStore.save(secret, account: identity)
            KeychainStore.delete(account: previousSecretAccount(for: identity))
            rememberDevice(identity: identity, displayName: name)

            send(.init(
                type: .pairResponse,
                serverID: serverID,
                publicKey: sealed.serverPublicKey.base64EncodedString(),
                encryptedSecret: sealed.ciphertext.base64EncodedString()
            ), on: connection)
            connectionDevices[ObjectIdentifier(connection)] = identity
            updateConnectedDeviceCount()
            if debugPairingCode == nil { rotatePairingCode() }
        } catch {
            send(.init(type: .error, error: localized("Could not save pairing credentials.")), on: connection)
        }
    }

    private func sendAuthenticated(_ message: WireMessage, secret: Data, on connection: NWConnection) {
        var identified = message
        if identified.serverID == nil {
            identified.serverID = serverID
        }
        guard let sealed = try? identified.sealed(with: secret) else { return }
        send(sealed, on: connection)
    }

    private func send(_ message: WireMessage, on connection: NWConnection) {
        guard let data = try? MessageFramer.frame(message) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func updateConnectedDeviceCount() {
        connectedDeviceCount = Set(connectionDevices.values).count
    }

    private func rotateSecret(for identity: String, currentSecret: Data, on connection: NWConnection) {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            sendAuthenticated(.init(type: .error, error: localized("Could not rotate pairing credentials.")), secret: currentSecret, on: connection)
            return
        }
        let replacement = Data(bytes)
        do {
            try KeychainStore.save(currentSecret, account: previousSecretAccount(for: identity))
            try KeychainStore.save(replacement, account: identity)
            sendAuthenticated(.init(
                type: .rotateSecretResponse,
                encryptedSecret: replacement.base64EncodedString()
            ), secret: currentSecret, on: connection)
        } catch {
            try? KeychainStore.save(currentSecret, account: identity)
            KeychainStore.delete(account: previousSecretAccount(for: identity))
            sendAuthenticated(.init(type: .error, error: localized("Could not rotate pairing credentials.")), secret: currentSecret, on: connection)
        }
    }

    private func previousSecretAccount(for identity: String) -> String {
        identity + previousSecretSuffix
    }

    private func stableIdentity(deviceID: String?, fallbackName: String) -> String {
        let clean = deviceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty ? fallbackName : clean
    }

    private func rememberDevice(identity: String, displayName: String) {
        if let index = pairedDevices.firstIndex(where: { $0.id == identity }) {
            if pairedDevices[index].name != displayName {
                pairedDevices[index].name = displayName
                savePairedDevices()
            }
            return
        }
        pairedDevices.append(PairedDeviceInfo(id: identity, name: displayName))
        pairedDevices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        savePairedDevices()
    }

    private func migrateLegacyIdentity(
        from legacyName: String,
        to identity: String,
        displayName: String,
        secret: Data
    ) {
        guard identity != legacyName else {
            rememberDevice(
                identity: identity,
                displayName: displayName
            )
            return
        }

        do {
            try KeychainStore.save(
                secret,
                account: identity
            )

            if let previous = KeychainStore.load(
                account: previousSecretAccount(
                    for: legacyName
                )
            ) {
                try KeychainStore.save(
                    previous,
                    account: previousSecretAccount(
                        for: identity
                    )
                )
            }

            KeychainStore.delete(account: legacyName)
            KeychainStore.delete(
                account: previousSecretAccount(
                    for: legacyName
                )
            )
            replayProtector.reset(device: legacyName)
            pairedDevices.removeAll {
                $0.id == legacyName
            }
            rememberDevice(
                identity: identity,
                displayName: displayName
            )
        } catch {
            // Keep the legacy credential intact. A failed migration must never
            // turn a previously paired device into an unrecoverable one.
            lastError = localized(
                "Could not migrate the pairing credential."
            )
            rememberDevice(
                identity: legacyName,
                displayName: displayName
            )
        }
    }

    private func forgetDevice(identity: String) {
        KeychainStore.delete(account: identity)
        KeychainStore.delete(account: previousSecretAccount(for: identity))
        replayProtector.reset(device: identity)
        pairedDevices.removeAll { $0.id == identity }
        savePairedDevices()
    }

    private func savePairedDevices() {
        guard let data = try? JSONEncoder().encode(pairedDevices) else { return }
        UserDefaults.standard.set(data, forKey: deviceDefaultsKey)
    }

    private func broadcastCatalog() {
        for (id, identity) in connectionDevices {
            guard let connection = connections[id],
                  let secret = KeychainStore.load(account: identity) else { continue }
            sendAuthenticated(.init(
                type: .catalogResponse,
                catalog: catalog.tiles,
                recentApplications: catalog.recentApplications
            ), secret: secret, on: connection)
        }
    }
}


private enum MacServerIdentity {
    private static let service = "io.cocoalift.server.identity"
    private static let account = "server-id"
    private static let fallbackKey = "phoneDock.macServerIDFallback"

    static var id: String {
        if let data = KeychainStore.load(account: account, service: service),
           let existing = String(data: data, encoding: .utf8),
           !existing.isEmpty {
            UserDefaults.standard.removeObject(forKey: fallbackKey)
            return existing
        }

        if let fallback = UserDefaults.standard.string(forKey: fallbackKey),
           !fallback.isEmpty {
            persistIfPossible(fallback)
            return fallback
        }

        let created = UUID().uuidString
        if !persistIfPossible(created) {
            UserDefaults.standard.set(created, forKey: fallbackKey)
        }
        return created
    }

    @discardableResult
    private static func persistIfPossible(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        do {
            try KeychainStore.save(data, account: account, service: service)
            UserDefaults.standard.removeObject(forKey: fallbackKey)
            return true
        } catch {
            return false
        }
    }
}
