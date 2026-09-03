import CryptoKit
import Foundation
import Network

@main
struct PhoneDockIntegrationClient {
    static func main() {
        guard CommandLine.arguments.count == 3,
              let rawPort = UInt16(CommandLine.arguments[1]),
              let port = NWEndpoint.Port(rawValue: rawPort) else {
            fputs("usage: PhoneDockIntegrationClient <port> <pairing-code>\n", stderr)
            exit(2)
        }

        let client = Client(port: port, pin: CommandLine.arguments[2])
        client.start()
        guard client.finished.wait(timeout: .now() + 12) == .success, client.succeeded else {
            fputs("Phone Dock loopback integration failed: \(client.failure ?? "timeout")\n", stderr)
            exit(1)
        }
        print("Phone Dock loopback pairing, authentication, state and unpair succeeded.")
    }
}

private final class Client {
    private enum Phase {
        case pairing
        case readingState
        case settingVolume
        case settingBrightness
        case unpairing
    }

    let finished = DispatchSemaphore(value: 0)
    private(set) var succeeded = false
    private(set) var failure: String?

    private let queue = DispatchQueue(label: "io.cocoalift.integration-client")
    private let pin: String
    private let pairKey = PairingCrypto.makePrivateKey()
    private let connection: NWConnection
    private var framer = MessageFramer()
    private var secret: Data?
    private var phase: Phase = .pairing
    private var initialState: MacState?

    init(port: NWEndpoint.Port, pin: String) {
        self.pin = pin
        connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.send(.init(
                    type: .pairRequest,
                    deviceName: "Phone Dock Integration Test",
                    pin: self.pin,
                    publicKey: self.pairKey.publicKey.rawRepresentation.base64EncodedString()
                ))
                self.receive()
            case .failed(let error):
                self.finish(error.localizedDescription)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    for message in try self.framer.append(data) { self.handle(message) }
                } catch {
                    self.finish(error.localizedDescription)
                    return
                }
            }
            if let error { self.finish(error.localizedDescription); return }
            if complete { self.finish("connection closed before completion"); return }
            if !self.succeeded { self.receive() }
        }
    }

    private func handle(_ message: WireMessage) {
        switch message.type {
        case .pairResponse:
            guard let serverKeyValue = message.publicKey,
                  let serverKey = Data(base64Encoded: serverKeyValue),
                  let ciphertextValue = message.encryptedSecret,
                  let ciphertext = Data(base64Encoded: ciphertextValue),
                  let secret = try? PairingCrypto.open(
                    ciphertext: ciphertext,
                    serverPublicKey: serverKey,
                    clientPrivateKey: pairKey,
                    pin: pin
                  ) else {
                finish("invalid encrypted pairing response")
                return
            }
            self.secret = secret
            phase = .readingState
            sendAuthenticated(.init(type: .stateRequest, deviceName: "Phone Dock Integration Test"))
        case .stateResponse:
            guard let secret, message.isAuthenticated(with: secret), let state = message.state else {
                finish("invalid authenticated state response")
                return
            }
            switch phase {
            case .readingState:
                initialState = state
                phase = .settingVolume
                sendAuthenticated(.init(
                    type: .command,
                    deviceName: "Phone Dock Integration Test",
                    command: .setVolume(state.volume)
                ))
            case .settingVolume:
                guard let brightness = initialState?.brightness else {
                    phase = .unpairing
                    sendAuthenticated(.init(type: .unpair, deviceName: "Phone Dock Integration Test"))
                    return
                }
                phase = .settingBrightness
                sendAuthenticated(.init(
                    type: .command,
                    deviceName: "Phone Dock Integration Test",
                    command: .setBrightness(brightness)
                ))
            case .settingBrightness:
                phase = .unpairing
                sendAuthenticated(.init(type: .unpair, deviceName: "Phone Dock Integration Test"))
            default:
                finish("unexpected state response")
            }
        case .unpair:
            guard phase == .unpairing, let secret, message.isAuthenticated(with: secret) else {
                finish("invalid unpair acknowledgement")
                return
            }
            succeeded = true
            connection.cancel()
            finished.signal()
        case .error:
            finish("server rejected \(String(describing: phase)): \(message.error ?? "unknown error")")
        default:
            break
        }
    }

    private func sendAuthenticated(_ message: WireMessage) {
        guard let secret, let signed = try? message.signed(with: secret) else {
            finish("could not sign request")
            return
        }
        send(signed)
    }

    private func send(_ message: WireMessage) {
        do {
            connection.send(content: try MessageFramer.frame(message), completion: .contentProcessed { [weak self] error in
                if let error { self?.finish(error.localizedDescription) }
            })
        } catch {
            finish(error.localizedDescription)
        }
    }

    private func finish(_ message: String) {
        guard !succeeded, failure == nil else { return }
        failure = message
        connection.cancel()
        finished.signal()
    }
}
