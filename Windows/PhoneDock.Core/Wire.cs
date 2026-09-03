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
    public static JsonObject Message(string type) => new()
    {
        ["version"] = 1, ["id"] = Guid.NewGuid().ToString().ToUpperInvariant(), ["type"] = type
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
        copy["authentication"] = Convert.ToBase64String(HMACSHA256.HashData(secret, Canonical(copy)));
        return copy;
    }
    public static bool Verify(JsonObject message, byte[] secret)
    {
        try
        {
            var signature = Convert.FromBase64String(message["authentication"]!.GetValue<string>());
            var copy = (JsonObject)message.DeepClone(); copy.Remove("authentication");
            return CryptographicOperations.FixedTimeEquals(signature, HMACSHA256.HashData(secret, Canonical(copy)));
        }
        catch (Exception e) when (e is FormatException or InvalidOperationException or NullReferenceException) { return false; }
    }
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
