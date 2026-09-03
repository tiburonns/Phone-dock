import CryptoKit
import Foundation

let cocoaLiftBonjourType = "_cocoalift._tcp"

enum WireMessageType: String, Codable, Sendable {
    case pairRequest
    case pairResponse
    case command
    case stateRequest
    case stateResponse
    case catalogRequest
    case catalogResponse
    case unpair
    case ping
    case error
}

struct WireMessage: Codable, Equatable, Sendable {
    static let protocolVersion = 1

    var version = protocolVersion
    var id = UUID()
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
    var authentication: String?

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
        error: String? = nil
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
    }

    func signed(with secret: Data) throws -> WireMessage {
        var result = self
        result.authentication = nil
        let bytes = try Self.encoder.encode(result)
        let key = SymmetricKey(data: secret)
        result.authentication = Data(HMAC<SHA256>.authenticationCode(for: bytes, using: key)).base64EncodedString()
        return result
    }

    func isAuthenticated(with secret: Data) -> Bool {
        guard let authentication, let received = Data(base64Encoded: authentication) else { return false }
        var unsigned = self
        unsigned.authentication = nil
        guard let bytes = try? Self.encoder.encode(unsigned) else { return false }
        let key = SymmetricKey(data: secret)
        return HMAC<SHA256>.isValidAuthenticationCode(received, authenticating: bytes, using: key)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()
}
