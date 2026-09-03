import Foundation
import CryptoKit

@main struct Interop {
    struct Fixtures: Encodable { let publicKey: String; let messages: [WireMessage] }
    static func main() throws {
        let secret = Data((0..<32).map(UInt8.init))
        let directory = URL(fileURLWithPath: CommandLine.arguments[2])
        if CommandLine.arguments[1] == "generate" {
            let key = PairingCrypto.makePrivateKey()
            try key.rawRepresentation.write(to: directory.appendingPathComponent("test-private-key.bin"))
            var messages: [WireMessage] = [
                WireMessage(type: .command, deviceName: "iPhone de José ✨", command: .openURL("https://example.com/a/b?q=🌈")),
                WireMessage(type: .command, deviceName: "Test iPhone", command: .insertText("línea\n\t👨‍👩‍👧‍👦 / prueba")),
                WireMessage(type: .stateRequest, deviceName: "Test iPhone")
            ]
            messages.append(WireMessage(type: .command, deviceName: "Test iPhone", command: .launchNewInstance(bundleIdentifier: "test.editor")))
            for value in (0...100).map({ Double($0) / 100 }) + [0.00001, 0.12345678901234567] {
                messages.append(WireMessage(type: .command, deviceName: "Test iPhone", command: .setVolume(value)))
                messages.append(WireMessage(type: .command, deviceName: "Test iPhone", command: .setBrightness(value)))
            }
            let fixtures = Fixtures(publicKey: key.publicKey.rawRepresentation.base64EncodedString(), messages: try messages.map { try $0.signed(with: secret) })
            let data = try WireMessage.encoder.encode(fixtures)
            try data.write(to: directory.appendingPathComponent("swift.json"))
        } else {
            let data = try Data(contentsOf: directory.appendingPathComponent("dotnet.json"))
            let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let key = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(contentsOf: directory.appendingPathComponent("test-private-key.bin")))
            let decrypted = try PairingCrypto.open(ciphertext: Data(base64Encoded: object["sealedSecret"] as! String)!, serverPublicKey: Data(base64Encoded: object["publicKey"] as! String)!, clientPrivateKey: key, pin: "123456")
            precondition(decrypted == secret, "Windows pairing rejected by Swift")
            for item in object["messages"] as! [[String: Any]] {
                let bytes = try JSONSerialization.data(withJSONObject: item)
                let message = try WireMessage.decoder.decode(WireMessage.self, from: bytes)
                precondition(message.isAuthenticated(with: secret), "Windows HMAC rejected by Swift: \(message.type)")
            }
            print("PASS Swift decrypts Windows pairing and authenticates Windows responses")
        }
    }
}
