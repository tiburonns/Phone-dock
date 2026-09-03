using System.Security.Cryptography;
using System.Text;

namespace PhoneDock.Core;

public static class Pairing
{
    public static (byte[] PublicKey, byte[] SealedSecret) Seal(byte[] clientKey, string pin, byte[] secret)
    {
        if (clientKey.Length != 64) throw new CryptographicException(AppLanguage.T("Clave P-256 inválida."));
        using var remote = ECDiffieHellman.Create(new ECParameters {
            Curve = ECCurve.NamedCurves.nistP256, Q = new ECPoint { X = clientKey[..32], Y = clientKey[32..] }
        });
        using var local = ECDiffieHellman.Create(ECCurve.NamedCurves.nistP256);
        var raw = local.DeriveRawSecretAgreement(remote.PublicKey);
        var key = HKDF.DeriveKey(HashAlgorithmName.SHA256, raw, 32, Encoding.UTF8.GetBytes(pin),
                                Encoding.UTF8.GetBytes("CocoaLift pairing v1"));
        try
        {
            var nonce = RandomNumberGenerator.GetBytes(12);
            var ciphertext = new byte[secret.Length]; var tag = new byte[16];
            using var cipher = new ChaCha20Poly1305(key);
            cipher.Encrypt(nonce, secret, ciphertext, tag);
            var publicKey = local.ExportParameters(false).Q;
            return ([.. publicKey.X!, .. publicKey.Y!], [.. nonce, .. ciphertext, .. tag]);
        }
        finally { CryptographicOperations.ZeroMemory(raw); CryptographicOperations.ZeroMemory(key); }
    }
}
