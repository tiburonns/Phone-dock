import CryptoKit
import Foundation

let cocoaLiftBonjourType = "_cocoalift._tcp"

enum WireMessageType: String, Codable, Sendable {
    case secure
    case pairRequest
    case pairResponse
    case command
    case stateRequest
    case stateResponse
    case catalogRequest
    case catalogResponse
    case rotateSecret
    case rotateSecretResponse
    case rotateSecretAcknowledgement
    case unpair
    case ping
    case error
}

struct WireMessage: Codable, Equatable, Sendable {
    static let protocolVersion = 2
    private static let authenticationContext = Data("Phone Dock authentication v2".utf8)
    private static let encryptionContext = Data("Phone Dock encryption v2".utf8)

    var version = protocolVersion
    var id = UUID()
    var sentAt = Int64(Date().timeIntervalSince1970)
    var type: WireMessageType
    var deviceName: String?
    var pin: String?
    var publicKey: String?
    var encryptedSecret: String?
    var command: RemoteCommand?
    var catalog: [RemoteTile]?
    var recentApplications: [RecentApplication]?
    var state: MacState?
    var error: String?
    var encryptedPayload: String?
    var authentication: String?
    var supportedProtocolVersion: Int?

    init(
        type: WireMessageType,
        deviceName: String? = nil,
        pin: String? = nil,
        publicKey: String? = nil,
        encryptedSecret: String? = nil,
        command: RemoteCommand? = nil,
        catalog: [RemoteTile]? = nil,
        recentApplications: [RecentApplication]? = nil,
        state: MacState? = nil,
        error: String? = nil,
        supportedProtocolVersion: Int? = nil
    ) {
        self.type = type
        self.deviceName = deviceName
        self.pin = pin
        self.publicKey = publicKey
        self.encryptedSecret = encryptedSecret
        self.command = command
        self.catalog = catalog
        self.recentApplications = recentApplications
        self.state = state
        self.error = error
        self.supportedProtocolVersion = supportedProtocolVersion
    }

    func signed(with secret: Data) throws -> WireMessage {
        var result = self
        result.authentication = nil
        let bytes = try Self.encoder.encode(result)
        let key = Self.derivedKey(from: secret, context: Self.authenticationContext)
        result.authentication = Data(HMAC<SHA256>.authenticationCode(for: bytes, using: key)).base64EncodedString()
        return result
    }

    func isAuthenticated(with secret: Data) -> Bool {
        guard let authentication, let received = Data(base64Encoded: authentication) else { return false }
        var unsigned = self
        unsigned.authentication = nil
        guard let bytes = try? Self.encoder.encode(unsigned) else { return false }
        let key = Self.derivedKey(from: secret, context: Self.authenticationContext)
        return HMAC<SHA256>.isValidAuthenticationCode(received, authenticating: bytes, using: key)
    }

    /// Encrypts every application-level field inside an authenticated envelope.
    /// Pairing messages remain outside this envelope because they establish the
    /// secret used by this operation.
    func sealed(with secret: Data) throws -> WireMessage {
        precondition(type != .secure, "A secure envelope cannot contain another envelope")
        var inner = self
        inner.authentication = nil
        inner.encryptedPayload = nil

        let plaintext = try Self.encoder.encode(inner)
        let key = Self.derivedKey(from: secret, context: Self.encryptionContext)
        let box = try ChaChaPoly.seal(plaintext, using: key)

        var envelope = WireMessage(type: .secure, deviceName: deviceName)
        envelope.id = id
        envelope.sentAt = sentAt
        envelope.encryptedPayload = box.combined.base64EncodedString()
        return try envelope.signed(with: secret)
    }

    func opened(with secret: Data) throws -> WireMessage {
        guard type == .secure, isAuthenticated(with: secret) else {
            throw WireSecurityError.authenticationFailed
        }
        guard let encryptedPayload,
              let combined = Data(base64Encoded: encryptedPayload) else {
            throw WireSecurityError.invalidEnvelope
        }

        let key = Self.derivedKey(from: secret, context: Self.encryptionContext)
        let box = try ChaChaPoly.SealedBox(combined: combined)
        let plaintext = try ChaChaPoly.open(box, using: key)
        let inner = try Self.decoder.decode(WireMessage.self, from: plaintext)
        guard inner.type != .secure,
              inner.version == version,
              inner.id == id,
              inner.sentAt == sentAt,
              inner.deviceName == deviceName else {
            throw WireSecurityError.invalidEnvelope
        }
        return inner
    }

    private static func derivedKey(from secret: Data, context: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            salt: Data(),
            info: context,
            outputByteCount: 32
        )
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()
}

enum WireSecurityError: Error {
    case authenticationFailed
    case invalidEnvelope
}
