import Combine
import Foundation
import Network
import SystemConfiguration

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
    @Published private(set) var pairedDevices: [String]
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
    private let deviceDefaultsKey = "cocoalift.pairedDevices.v1"

    init(catalog: CatalogStore, controller: SystemController) {
        self.catalog = catalog
        self.controller = controller
        pairedDevices = UserDefaults.standard.stringArray(forKey: deviceDefaultsKey) ?? []
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

    func forgetDevice(_ name: String) {
        KeychainStore.delete(account: name)
        replayProtector.reset(device: name)
        pairedDevices.removeAll { $0 == name }
        UserDefaults.standard.set(pairedDevices, forKey: deviceDefaultsKey)
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
            send(.init(type: .error, error: localized("Unsupported protocol version.")), on: connection)
            return
        }
        if message.type == .pairRequest {
            pair(message, on: connection)
            return
        }
        guard let deviceName = message.deviceName,
              let secret = KeychainStore.load(account: deviceName),
              message.isAuthenticated(with: secret) else {
            send(.init(type: .error, error: localized("This device is not paired.")), on: connection)
            return
        }
        guard replayProtector.accept(message.id, from: deviceName) else {
            sendAuthenticated(.init(type: .error, error: localized("Duplicate request rejected.")), secret: secret, on: connection)
            return
        }
        connectionDevices[ObjectIdentifier(connection)] = deviceName
        updateConnectedDeviceCount()

        switch message.type {
        case .command:
            guard let command = message.command else { return }
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
        case .unpair:
            sendAuthenticated(.init(type: .unpair, deviceName: deviceName), secret: secret, on: connection)
            Task { @MainActor [weak self, weak connection] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.forgetDevice(deviceName)
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
        pairingLimiter.recordSuccess()
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            send(.init(type: .error, error: localized("Could not create pairing credentials.")), on: connection)
            return
        }
        let secret = Data(bytes)
        do {
            let sealed = try PairingCrypto.seal(secret: secret, for: clientKey, pin: pin)
            try KeychainStore.save(secret, account: name)
            if !pairedDevices.contains(name) {
                pairedDevices.append(name)
                UserDefaults.standard.set(pairedDevices, forKey: deviceDefaultsKey)
            }
            send(.init(
                type: .pairResponse,
                publicKey: sealed.serverPublicKey.base64EncodedString(),
                encryptedSecret: sealed.ciphertext.base64EncodedString(),
                catalog: catalog.tiles,
                recentApplications: catalog.recentApplications,
                state: controller.currentState()
            ), on: connection)
            connectionDevices[ObjectIdentifier(connection)] = name
            updateConnectedDeviceCount()
            if debugPairingCode == nil { rotatePairingCode() }
        } catch {
            send(.init(type: .error, error: localized("Could not save pairing credentials.")), on: connection)
        }
    }

    private func sendAuthenticated(_ message: WireMessage, secret: Data, on connection: NWConnection) {
        guard let signed = try? message.signed(with: secret) else { return }
        send(signed, on: connection)
    }

    private func send(_ message: WireMessage, on connection: NWConnection) {
        guard let data = try? MessageFramer.frame(message) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func updateConnectedDeviceCount() {
        connectedDeviceCount = Set(connectionDevices.values).count
    }

    private func broadcastCatalog() {
        for (id, deviceName) in connectionDevices {
            guard let connection = connections[id],
                  let secret = KeychainStore.load(account: deviceName) else { continue }
            sendAuthenticated(.init(
                type: .catalogResponse,
                catalog: catalog.tiles,
                recentApplications: catalog.recentApplications
            ), secret: secret, on: connection)
        }
    }
}
