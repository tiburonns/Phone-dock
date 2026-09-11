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
        case connected(String)
        case disconnected
        case failed(String)

        var title: String {
            switch self {
            case .searching: localized("Searching for Macs…")
            case .connecting(let name): localizedFormat("Connecting to %@…", name)
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
    private let deviceName = UIDevice.current.name

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
        pendingPairCode = nil
        pendingPairKey = nil
        currentSecret = KeychainStore.load(account: mac.id)
        openConnection(to: mac)
    }

    func pair(with mac: DiscoveredMac, code: String) {
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
        connection?.cancel()
        connection = nil
        selectedMac = nil
        currentSecret = nil
        status = .disconnected
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

    private func openConnection(to mac: DiscoveredMac) {
        connection?.cancel()
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
                lastError = nil
                updateIdleTimer()
                refresh()
            } else {
                lastError = localized("This Mac must be paired again.")
                status = .failed(lastError ?? localized("Pairing required"))
            }
        case .failed(let error):
            lastError = error.localizedDescription
            status = .failed(error.localizedDescription)
            updateIdleTimer()
        case .cancelled:
            if self.connection === connection {
                status = .disconnected
                updateIdleTimer()
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
                lastError = nil
                updateIdleTimer()
                refresh()
            } catch {
                status = .failed(localized("Could not save the pairing credential."))
            }
        case .error:
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
            let outgoing: WireMessage
            if authenticated {
                guard let currentSecret else { return }
                outgoing = try message.sealed(with: currentSecret)
            } else {
                outgoing = message
            }
            connection.send(content: try MessageFramer.frame(outgoing), completion: .contentProcessed { _ in })
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = isQuickDockVisible && isConnected
    }
}
