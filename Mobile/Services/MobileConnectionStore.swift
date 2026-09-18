import Foundation
import Network
import UIKit
import CryptoKit

struct DiscoveredMac: Identifiable, Hashable {
    let endpoint: NWEndpoint
    let name: String
    var id: String { endpoint.debugDescription }
}

@MainActor
final class MobileConnectionStore: ObservableObject {
    enum Status: Equatable {
        case searching
        case connecting(String)
        case reconnecting(String, Int)
        case connected(String)
        case disconnected
        case failed(String)

        var title: String {
            switch self {
            case .searching: localized("Searching for Macs…")
            case .connecting(let name): localizedFormat("Connecting to %@…", name)
            case .reconnecting(let name, let attempt): localizedFormat("Reconnecting to %@ (attempt %d)…", name, attempt)
            case .connected(let name): localizedFormat("Connected to %@", name)
            case .disconnected: localized("Not connected")
            case .failed(let message): message
            }
        }
    }

    @Published private(set) var discoveredMacs: [DiscoveredMac] = []
    @Published private(set) var status: Status = .searching
    @Published private(set) var catalog: [RemoteTile] = []
    @Published private(set) var recentApplications: [RecentApplication] = []
    @Published private(set) var macState = MacState.placeholder
    @Published private(set) var lastError: String?
    @Published private(set) var lastConnectedAt: Date?
    @Published private(set) var lastDisconnectedAt: Date?
    @Published private(set) var reconnectAttempt = 0
    @Published private(set) var negotiatedProtocolVersion: Int?
    @Published private(set) var lastKeyRotationAt: Date?

    private let queue = DispatchQueue(label: "io.cocoalift.mobile.connection", qos: .userInitiated)
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var selectedMac: DiscoveredMac?
    private var pendingPairCode: String?
    private var pendingPairKey: P256.KeyAgreement.PrivateKey?
    private var currentSecret: Data?
    private var framer = MessageFramer()
    private var replayProtector = MessageReplayProtector()
    private var isQuickDockVisible = false
    private var reconnectTask: Task<Void, Never>?
    private var allowsAutomaticReconnect = false
    private let deviceName = UIDevice.current.name
    private let deviceID = MobileClientIdentity.id

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    func startBrowsing() {
        guard browser == nil else { return }
        status = .searching
        let browser = NWBrowser(for: .bonjour(type: cocoaLiftBonjourType, domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Task { @MainActor in self?.status = .failed(error.localizedDescription) }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let macs = results.map { result -> DiscoveredMac in
                let name: String
                if case .service(let serviceName, _, _, _) = result.endpoint { name = serviceName }
                else { name = result.endpoint.debugDescription }
                return DiscoveredMac(endpoint: result.endpoint, name: name)
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            Task { @MainActor in self?.discoveredMacs = macs }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    func isRemembered(_ mac: DiscoveredMac) -> Bool {
        KeychainStore.load(account: mac.id) != nil
    }

    func connect(to mac: DiscoveredMac) {
        allowsAutomaticReconnect = true
        reconnectAttempt = 0
        pendingPairCode = nil
        pendingPairKey = nil
        currentSecret = KeychainStore.load(account: mac.id)
        openConnection(to: mac)
    }

    func pair(with mac: DiscoveredMac, code: String) {
        allowsAutomaticReconnect = true
        reconnectAttempt = 0
        pendingPairCode = code
        pendingPairKey = PairingCrypto.makePrivateKey()
        currentSecret = nil
        openConnection(to: mac)
    }

    func pairManually(host: String, port: UInt16, code: String) {
        guard let networkPort = NWEndpoint.Port(rawValue: port) else {
            lastError = localized("The port is invalid.")
            return
        }
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else {
            lastError = localized("Enter the Mac hostname or IP address.")
            return
        }
        let mac = DiscoveredMac(
            endpoint: .hostPort(host: NWEndpoint.Host(normalizedHost), port: networkPort),
            name: normalizedHost
        )
        pair(with: mac, code: code)
    }

    func disconnect() {
        allowsAutomaticReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.cancel()
        connection = nil
        selectedMac = nil
        currentSecret = nil
        status = .disconnected
        lastDisconnectedAt = .now
        negotiatedProtocolVersion = nil
        updateIdleTimer()
    }

    func clearError() {
        lastError = nil
    }

    func setQuickDockVisible(_ visible: Bool) {
        isQuickDockVisible = visible
        updateIdleTimer()
    }

    func forget(_ mac: DiscoveredMac) {
        if selectedMac?.id == mac.id, isConnected {
            send(.init(type: .unpair, deviceName: deviceName), authenticated: true)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                KeychainStore.delete(account: mac.id)
                self?.disconnect()
            }
        } else {
            KeychainStore.delete(account: mac.id)
        }
    }

    func perform(_ command: RemoteCommand) {
        guard isConnected else {
            lastError = localized("Connect to a Mac first.")
            return
        }
        send(.init(type: .command, deviceName: deviceName, command: command), authenticated: true)
    }

    func refresh() {
        send(.init(type: .catalogRequest, deviceName: deviceName), authenticated: true)
        refreshState()
    }

    func refreshState() {
        send(.init(type: .stateRequest, deviceName: deviceName), authenticated: true)
    }

    func rotatePairingKey() {
        guard isConnected else {
            lastError = localized("Connect to a Mac first.")
            return
        }
        send(.init(type: .rotateSecret, deviceName: deviceName), authenticated: true)
    }

    private func openConnection(to mac: DiscoveredMac) {
        reconnectTask?.cancel()
        reconnectTask = nil
        let previousConnection = connection
        connection = nil
        previousConnection?.cancel()
        selectedMac = mac
        status = .connecting(mac.name)
        framer = MessageFramer()
        let connection = NWConnection(to: mac.endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            Task { @MainActor in self.handleConnectionState(state, connection: connection) }
        }
        connection.start(queue: queue)
        self.connection = connection
        receive(on: connection)
    }

    private func handleConnectionState(_ state: NWConnection.State, connection: NWConnection) {
        switch state {
        case .ready:
            reconnectAttempt = 0
            if let code = pendingPairCode {
                guard let pendingPairKey else { return }
                send(.init(
                    type: .pairRequest,
                    deviceName: deviceName,
                    pin: code,
                    publicKey: pendingPairKey.publicKey.rawRepresentation.base64EncodedString()
                ), authenticated: false)
            } else if currentSecret != nil {
                status = .connected(selectedMac?.name ?? "Mac")
                lastConnectedAt = .now
                lastError = nil
                updateIdleTimer()
                refresh()
            } else {
                lastError = localized("This Mac must be paired again.")
                status = .failed(lastError ?? localized("Pairing required"))
            }
        case .failed(let error):
            guard self.connection === connection else { return }
            self.connection = nil
            lastError = error.localizedDescription
            status = .failed(error.localizedDescription)
            lastDisconnectedAt = .now
            updateIdleTimer()
            scheduleReconnect()
        case .cancelled:
            if self.connection === connection {
                self.connection = nil
                lastDisconnectedAt = .now
                updateIdleTimer()
                scheduleReconnect()
            }
        default:
            break
        }
    }

    nonisolated private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            if let data, !data.isEmpty {
                Task { @MainActor in self?.consume(data) }
            }
            if complete || error != nil {
                connection.cancel()
                return
            }
            self?.receive(on: connection)
        }
    }

    private func consume(_ data: Data) {
        do {
            for message in try framer.append(data) { handle(message) }
        } catch {
            lastError = localized("The Mac sent an unreadable response.")
            status = .failed(lastError ?? localized("Connection error"))
        }
    }

    private func handle(_ message: WireMessage) {
        if message.type == .secure {
            guard let openedMessage = open(message) else { return }
            handleAuthenticated(openedMessage)
            return
        }

        switch message.type {
        case .pairResponse:
            guard let selectedMac,
                  let pin = pendingPairCode,
                  let privateKey = pendingPairKey,
                  let encodedServerKey = message.publicKey,
                  let serverKey = Data(base64Encoded: encodedServerKey),
                  let encodedCiphertext = message.encryptedSecret,
                  let ciphertext = Data(base64Encoded: encodedCiphertext),
                  let secret = try? PairingCrypto.open(
                    ciphertext: ciphertext,
                    serverPublicKey: serverKey,
                    clientPrivateKey: privateKey,
                    pin: pin
                  ) else {
                status = .failed(localized("Pairing response was incomplete."))
                return
            }
            do {
                try KeychainStore.save(secret, account: selectedMac.id)
                currentSecret = secret
                pendingPairCode = nil
                pendingPairKey = nil
                catalog = message.catalog ?? []
                recentApplications = message.recentApplications ?? []
                if let state = message.state { macState = state }
                status = .connected(selectedMac.name)
                lastConnectedAt = .now
                negotiatedProtocolVersion = message.version
                lastError = nil
                updateIdleTimer()
                refresh()
            } catch {
                status = .failed(localized("Could not save the pairing credential."))
            }
        case .error:
            if let supportedVersion = message.supportedProtocolVersion {
                negotiatedProtocolVersion = supportedVersion
                lastError = localizedFormat(
                    "Protocol mismatch. This app uses version %d; the Mac supports version %d.",
                    WireMessage.protocolVersion,
                    supportedVersion
                )
                status = .failed(lastError ?? localized("Unsupported protocol version."))
                return
            }
            guard currentSecret == nil else { return }
            lastError = message.error ?? localized("The Mac rejected the request.")
            status = .failed(lastError ?? localized("Connection error"))
        default:
            break
        }
    }

    private func open(_ message: WireMessage) -> WireMessage? {
        guard let secret = currentSecret,
              let opened = try? message.opened(with: secret),
              replayProtector.accept(
                opened.id,
                sentAt: opened.sentAt,
                from: selectedMac?.id ?? "Mac"
              ) else {
            lastError = localized("A response failed authentication.")
            return nil
        }
        return opened
    }

    private func handleAuthenticated(_ message: WireMessage) {
        negotiatedProtocolVersion = message.version
        lastConnectedAt = .now
        switch message.type {
        case .catalogResponse:
            lastError = nil
            catalog = message.catalog ?? []
            recentApplications = message.recentApplications ?? []
        case .stateResponse:
            lastError = nil
            if let state = message.state { macState = state }
        case .error:
            lastError = message.error ?? localized("The Mac rejected the request.")
        case .rotateSecretResponse:
            guard let selectedMac,
                  let encodedSecret = message.encryptedSecret,
                  let newSecret = Data(base64Encoded: encodedSecret),
                  newSecret.count == 32 else {
                lastError = localized("The Mac returned an invalid replacement key.")
                return
            }
            do {
                try KeychainStore.save(newSecret, account: selectedMac.id)
                currentSecret = newSecret
                lastKeyRotationAt = .now
                lastError = nil
                send(.init(type: .rotateSecretAcknowledgement, deviceName: deviceName), authenticated: true)
            } catch {
                lastError = localized("Could not save the replacement pairing key.")
            }
        case .unpair:
            if let selectedMac {
                KeychainStore.delete(account: selectedMac.id)
                disconnect()
            }
        default:
            break
        }
    }

    private func send(_ message: WireMessage, authenticated: Bool) {
        guard let connection else { return }
        do {
            var identifiedMessage = message
            if identifiedMessage.deviceName == nil {
                identifiedMessage.deviceName = deviceName
            }
            if identifiedMessage.deviceID == nil {
                identifiedMessage.deviceID = deviceID
            }

            let outgoing: WireMessage
            if authenticated {
                guard let currentSecret else { return }
                outgoing = try identifiedMessage.sealed(with: currentSecret)
            } else {
                outgoing = identifiedMessage
            }
            connection.send(content: try MessageFramer.frame(outgoing), completion: .contentProcessed { _ in })
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = isQuickDockVisible && isConnected
    }

    private func scheduleReconnect() {
        guard allowsAutomaticReconnect,
              let selectedMac,
              currentSecret != nil,
              reconnectTask == nil else {
            if connection == nil { status = .disconnected }
            return
        }

        reconnectAttempt += 1
        let attempt = reconnectAttempt
        let delay = min(pow(2.0, Double(max(attempt - 1, 0))), 30)
        status = .reconnecting(selectedMac.name, attempt)
        reconnectTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, self.allowsAutomaticReconnect else { return }
            self.reconnectTask = nil
            self.openConnection(to: selectedMac)
        }
    }
}


private enum MobileClientIdentity {
    private static let service = "io.cocoalift.identity"
    private static let account = "mobile-device-id"

    static var id: String {
        if let data = KeychainStore.load(account: account, service: service),
           let existing = String(data: data, encoding: .utf8),
           !existing.isEmpty {
            return existing
        }

        let created = UUID().uuidString
        if let data = created.data(using: .utf8) {
            try? KeychainStore.save(data, account: account, service: service)
        }
        return created
    }
}
