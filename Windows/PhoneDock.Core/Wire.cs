using System.Buffers.Binary;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace PhoneDock.Core;

public static class Wire
{
    public const int MaximumMessageSize = 1_048_576;
    private static readonly byte[] AuthenticationContext = Encoding.UTF8.GetBytes("Phone Dock authentication v3");
    private static readonly byte[] EncryptionContext = Encoding.UTF8.GetBytes("Phone Dock encryption v3");
    public static JsonObject Message(string type) => new()
    {
        ["version"] = 3,
        ["id"] = Guid.NewGuid().ToString().ToUpperInvariant(),
        ["sentAt"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
        ["type"] = type
    };

    // JSONEncoder(.sortedKeys) uses unescaped Unicode and escaped forward slashes.
    // Do not replace with the default System.Text.Json serializer: that breaks the iOS HMAC.
    public static byte[] Canonical(JsonNode node) => Encoding.UTF8.GetBytes(CanonicalText(node));
    public static string CanonicalText(JsonNode? node) => node switch
    {
        null => "null",
        JsonObject obj => "{" + string.Join(",", obj.OrderBy(p => p.Key, StringComparer.Ordinal)
            .Select(p => Quote(p.Key) + ":" + CanonicalText(p.Value))) + "}",
        JsonArray array => "[" + string.Join(",", array.Select(CanonicalText)) + "]",
        _ => Scalar(node)
    };
    private static string Scalar(JsonNode node)
    {
        using var document = JsonDocument.Parse(node.ToJsonString());
        var e = document.RootElement;
        return e.ValueKind == JsonValueKind.String ? Quote(e.GetString()!) : e.GetRawText();
    }
    private static string Quote(string value)
    {
        var result = new StringBuilder("\"");
        foreach (var c in value)
            result.Append(c switch
            {
                '"' => "\\\"", '\\' => "\\\\", '/' => "\\/", '\n' => "\\n", '\r' => "\\r",
                '\t' => "\\t", '\b' => "\\b", '\f' => "\\f",
                < ' ' => "\\u" + ((int)c).ToString("x4", CultureInfo.InvariantCulture), _ => c.ToString()
            });
        return result.Append('"').ToString();
    }
    public static JsonObject Sign(JsonObject message, byte[] secret)
    {
        var copy = (JsonObject)message.DeepClone();
        copy.Remove("authentication");
        copy["authentication"] = Convert.ToBase64String(HMACSHA256.HashData(DerivedKey(secret, AuthenticationContext), Canonical(copy)));
        return copy;
    }
    public static bool Verify(JsonObject message, byte[] secret)
    {
        try
        {
            var signature = Convert.FromBase64String(message["authentication"]!.GetValue<string>());
            var copy = (JsonObject)message.DeepClone(); copy.Remove("authentication");
            return CryptographicOperations.FixedTimeEquals(signature, HMACSHA256.HashData(DerivedKey(secret, AuthenticationContext), Canonical(copy)));
        }
        catch (Exception e) when (e is FormatException or InvalidOperationException or NullReferenceException) { return false; }
    }

    public static JsonObject Seal(JsonObject message, byte[] secret)
    {
        if (message["type"]?.GetValue<string>() == "secure") throw new InvalidDataException("Nested secure envelope.");
        var inner = (JsonObject)message.DeepClone();
        inner.Remove("authentication"); inner.Remove("encryptedPayload");
        var plaintext = Canonical(inner);
        var nonce = RandomNumberGenerator.GetBytes(12);
        var ciphertext = new byte[plaintext.Length];
        var tag = new byte[16];
        using (var cipher = new ChaCha20Poly1305(DerivedKey(secret, EncryptionContext)))
            cipher.Encrypt(nonce, plaintext, ciphertext, tag);

        var combined = new byte[nonce.Length + ciphertext.Length + tag.Length];
        nonce.CopyTo(combined, 0); ciphertext.CopyTo(combined, nonce.Length); tag.CopyTo(combined, nonce.Length + ciphertext.Length);
        var envelope = Message("secure");
        envelope["id"] = inner["id"]!.DeepClone();
        envelope["sentAt"] = inner["sentAt"]!.DeepClone();
        if (inner["deviceName"] is { } deviceName) envelope["deviceName"] = deviceName.DeepClone();
        if (inner["deviceID"] is { } deviceID) envelope["deviceID"] = deviceID.DeepClone();
        envelope["encryptedPayload"] = Convert.ToBase64String(combined);
        return Sign(envelope, secret);
    }

    public static JsonObject Open(JsonObject envelope, byte[] secret)
    {
        if (envelope["type"]?.GetValue<string>() != "secure" || !Verify(envelope, secret))
            throw new InvalidDataException("Secure message authentication failed.");
        var combined = Convert.FromBase64String(envelope["encryptedPayload"]!.GetValue<string>());
        if (combined.Length < 28) throw new InvalidDataException("Invalid secure envelope.");
        var nonce = combined[..12]; var ciphertext = combined[12..^16]; var tag = combined[^16..];
        var plaintext = new byte[ciphertext.Length];
        try {
            using var cipher = new ChaCha20Poly1305(DerivedKey(secret, EncryptionContext));
            cipher.Decrypt(nonce, ciphertext, tag, plaintext);
        } catch (AuthenticationTagMismatchException) { throw new InvalidDataException("Secure message authentication failed."); }
        var inner = JsonNode.Parse(plaintext) as JsonObject ?? throw new InvalidDataException("Invalid secure payload.");
        if (inner["type"]?.GetValue<string>() == "secure"
            || inner["version"]?.GetValue<int>() != envelope["version"]?.GetValue<int>()
            || inner["id"]?.GetValue<string>() != envelope["id"]?.GetValue<string>()
            || inner["sentAt"]?.GetValue<long>() != envelope["sentAt"]?.GetValue<long>()
            || inner["deviceName"]?.GetValue<string>() != envelope["deviceName"]?.GetValue<string>()
            || inner["deviceID"]?.GetValue<string>() != envelope["deviceID"]?.GetValue<string>())
            throw new InvalidDataException("Secure envelope metadata mismatch.");
        return inner;
    }

    private static byte[] DerivedKey(byte[] secret, byte[] context) =>
        HKDF.DeriveKey(HashAlgorithmName.SHA256, secret, 32, Array.Empty<byte>(), context);
    public static byte[] Frame(JsonObject message)
    {
        var json = Canonical(message);
        if (json.Length > MaximumMessageSize) throw new InvalidDataException(AppLanguage.T("El catálogo supera el tamaño permitido."));
        var frame = new byte[4 + json.Length];
        BinaryPrimitives.WriteInt32BigEndian(frame, json.Length); json.CopyTo(frame, 4); return frame;
    }
    public static async Task<JsonObject> ReadAsync(Stream stream, CancellationToken token)
    {
        var header = new byte[4]; await stream.ReadExactlyAsync(header, token);
        var size = BinaryPrimitives.ReadInt32BigEndian(header);
        if (size is <= 0 or > MaximumMessageSize) throw new InvalidDataException(AppLanguage.T("Tamaño de mensaje inválido."));
        var bytes = new byte[size]; await stream.ReadExactlyAsync(bytes, token);
        return JsonNode.Parse(bytes, documentOptions: new JsonDocumentOptions { MaxDepth = 24 }) as JsonObject
            ?? throw new InvalidDataException(AppLanguage.T("Mensaje inválido."));
    }
    public static JsonObject Command(string name, JsonObject? arguments = null) => new() { [name] = arguments ?? new() };
    public static JsonObject ValueCommand(string name, JsonNode value) => Command(name, new() { ["_0"] = value });
}
