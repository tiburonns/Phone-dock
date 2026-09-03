import CryptoKit
import Foundation

enum PairingCryptoError: Error {
    case invalidCiphertext
}

enum PairingCrypto {
    static func makePrivateKey() -> P256.KeyAgreement.PrivateKey {
        P256.KeyAgreement.PrivateKey()
    }

    static func seal(
        secret: Data,
        for clientPublicKey: Data,
        pin: String
    ) throws -> (serverPublicKey: Data, ciphertext: Data) {
        let clientKey = try P256.KeyAgreement.PublicKey(rawRepresentation: clientPublicKey)
        let serverKey = P256.KeyAgreement.PrivateKey()
        let sharedSecret = try serverKey.sharedSecretFromKeyAgreement(with: clientKey)
        let key = deriveKey(sharedSecret: sharedSecret, pin: pin)
        let sealed = try ChaChaPoly.seal(secret, using: key)
        return (serverKey.publicKey.rawRepresentation, sealed.combined)
    }

    static func open(
        ciphertext: Data,
        serverPublicKey: Data,
        clientPrivateKey: P256.KeyAgreement.PrivateKey,
        pin: String
    ) throws -> Data {
        let serverKey = try P256.KeyAgreement.PublicKey(rawRepresentation: serverPublicKey)
        let sharedSecret = try clientPrivateKey.sharedSecretFromKeyAgreement(with: serverKey)
        let key = deriveKey(sharedSecret: sharedSecret, pin: pin)
        return try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: ciphertext), using: key)
    }

    private static func deriveKey(sharedSecret: SharedSecret, pin: String) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(pin.utf8),
            sharedInfo: Data("CocoaLift pairing v1".utf8),
            outputByteCount: 32
        )
    }
}
