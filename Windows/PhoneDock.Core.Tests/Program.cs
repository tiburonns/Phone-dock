using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using PhoneDock.Core;

var passed = 0;
void Check(bool condition, string label) { if (!condition) throw new Exception(label); Console.WriteLine("PASS " + label); passed++; }
var secret = Enumerable.Range(0, 32).Select(i => (byte)i).ToArray();
Check(AppLanguage.Resolve("system", "es-MX") == "es" && AppLanguage.Resolve("system", "fr-FR") == "en", "System language and unsupported fallback");
Check(AppLanguage.Resolve("en", "es-MX") == "en" && AppLanguage.Resolve("es", "en-US") == "es", "Explicit language overrides system");
AppLanguage.Selected = "en";
Check(AppLanguage.T("Idioma") == "Language" && AppLanguage.F("Página {0} · {1}/24 acciones", 2, 5) == "Page 2 · 5/24 actions", "English labels and formatted text");
var userTile = new PhoneDock.Models.ActionTile { Title = "Inicio", Kind = "website", Target = "https://example.com" };
Check(userTile.ToWire(0)["title"]!.GetValue<string>() == "Inicio" && userTile.Subtitle == "Website", "User content unchanged while labels translate");
var savedPreferences = System.Text.Json.JsonSerializer.Serialize(new PhoneDock.Models.Preferences { Language = "es" });
Check(System.Text.Json.JsonSerializer.Deserialize<PhoneDock.Models.Preferences>(savedPreferences)!.Language == "es", "Language preference persists");
Check(System.Text.Json.JsonSerializer.Deserialize<PhoneDock.Models.Preferences>("{\"Palette\":\"Aurora\"}")!.Language == "system", "Existing preferences migrate without losing appearance");
AppLanguage.Selected = "es";
Check(AppLanguage.T("Idioma") == "Idioma" && AppLanguage.T("Untranslated user text") == "Untranslated user text", "Spanish and missing-key fallback");
AppLanguage.Selected = "unsupported"; Check(AppLanguage.Selected == "system", "Unknown preference falls back safely");
var request = Wire.Message("command"); request["deviceName"] = "iPhone de José ✨";
request["command"] = Wire.ValueCommand("openURL", JsonValue.Create("https://example.com/a/b?q=🌈")!);
var signed = Wire.Sign(request, secret);
Check(Wire.Verify(signed, secret), "HMAC roundtrip Unicode/slashes");
signed["deviceName"] = "otro"; Check(!Wire.Verify(signed, secret), "Tampering rejected");
await using (var memory = new MemoryStream(Wire.Frame(request))) Check(Wire.CanonicalText(await Wire.ReadAsync(memory, default)) == Wire.CanonicalText(request), "Frame roundtrip");
try { await Wire.ReadAsync(new MemoryStream(new byte[] { 0, 32, 0, 0 }), default); throw new Exception("Oversized frame accepted"); }
catch (InvalidDataException) { Check(true, "Oversized frame rejected before allocation"); }
using var clientKey = ECDiffieHellman.Create(ECCurve.NamedCurves.nistP256);
var coordinates = clientKey.ExportParameters(false).Q;
byte[] publicKey = [.. coordinates.X!, .. coordinates.Y!];
byte[] Open(byte[] publicBytes, byte[] sealedBytes, string pin) {
    using var remote = ECDiffieHellman.Create(new ECParameters { Curve = ECCurve.NamedCurves.nistP256, Q = new ECPoint { X = publicBytes[..32], Y = publicBytes[32..] } });
    var shared = clientKey.DeriveRawSecretAgreement(remote.PublicKey);
    var key = HKDF.DeriveKey(HashAlgorithmName.SHA256, shared, 32, Encoding.UTF8.GetBytes(pin), Encoding.UTF8.GetBytes("CocoaLift pairing v1"));
    using var cipher = new ChaCha20Poly1305(key); var plain = new byte[sealedBytes.Length - 28];
    cipher.Decrypt(sealedBytes[..12], sealedBytes[12..^16], sealedBytes[^16..], plain); return plain;
}
var sealedKey = Pairing.Seal(publicKey, "123456", secret);
Check(Open(sealedKey.PublicKey, sealedKey.SealedSecret, "123456").SequenceEqual(secret), "P256/HKDF/ChaCha pairing");
try { Open(sealedKey.PublicKey, sealedKey.SealedSecret, "999999"); throw new Exception("Wrong PIN accepted"); }
catch (AuthenticationTagMismatchException) { Check(true, "Wrong PIN cannot decrypt"); }

var store = new MemorySecrets(); var host = new FakeHost();
using var server = new RemoteServer(host, store); server.Start(0, IPAddress.Loopback);
using var socket = new TcpClient(); await socket.ConnectAsync(IPAddress.Loopback, server.Port);
using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(15));
async Task<JsonObject> Exchange(JsonObject message) {
    await socket.GetStream().WriteAsync(Wire.Frame(message), deadline.Token);
    return await Wire.ReadAsync(socket.GetStream(), deadline.Token);
}
var pin = server.PairingCode;
var pair = Wire.Message("pairRequest"); pair["deviceName"] = "Test iPhone"; pair["pin"] = pin; pair["publicKey"] = Convert.ToBase64String(publicKey);
var response = await Exchange(pair);
Check(response["type"]!.GetValue<string>() == "pairResponse", "TCP pairing response");
var sessionKey = Open(Convert.FromBase64String(response["publicKey"]!.GetValue<string>()), Convert.FromBase64String(response["encryptedSecret"]!.GetValue<string>()), pin);
Check(sessionKey.SequenceEqual(store.Get("Test iPhone")!), "TCP secret matches persisted credential");
var command = Wire.Message("command"); command["deviceName"] = "Test iPhone"; command["command"] = Wire.ValueCommand("setVolume", JsonValue.Create(0.42)!);
var signedCommand = Wire.Sign(command, sessionKey);
response = await Exchange(signedCommand);
Check(Wire.Verify(response, sessionKey) && host.Executions == 1 && response["type"]!.GetValue<string>() == "stateResponse", "Authenticated command and signed state");
response = await Exchange(signedCommand);
Check(response["type"]!.GetValue<string>() == "error" && host.Executions == 1 && Wire.Verify(response, sessionKey), "Replay rejected without executing");
var unpair = Wire.Message("unpair"); unpair["deviceName"] = "Test iPhone";
response = await Exchange(Wire.Sign(unpair, sessionKey));
Check(Wire.Verify(response, sessionKey) && response["type"]!.GetValue<string>() == "unpair", "Signed unpair acknowledgement");
await Task.Delay(50); Check(store.Get("Test iPhone") == null, "Credential revoked");

using (var unauthenticated = new TcpClient()) {
    await unauthenticated.ConnectAsync(IPAddress.Loopback, server.Port);
    await unauthenticated.GetStream().WriteAsync(Wire.Frame(signedCommand), deadline.Token);
    var one = new byte[1]; var count = await unauthenticated.GetStream().ReadAsync(one, deadline.Token);
    Check(count == 0 && host.Executions == 1, "Revoked credential cannot execute on a new connection");
}
using (var guarded = new TcpClient()) {
    await guarded.ConnectAsync(IPAddress.Loopback, server.Port);
    for (int i = 0; i < 5; i++) {
        var attempt = Wire.Message("pairRequest"); attempt["deviceName"] = "Test iPhone"; attempt["pin"] = "invalid";
        await guarded.GetStream().WriteAsync(Wire.Frame(attempt), deadline.Token);
        var refusal = await Wire.ReadAsync(guarded.GetStream(), deadline.Token);
        Check(refusal["type"]!.GetValue<string>() == "error", "Wrong PIN rejected " + (i + 1));
    }
    pair["pin"] = server.PairingCode;
    await guarded.GetStream().WriteAsync(Wire.Frame(pair), deadline.Token);
    var blocked = await Wire.ReadAsync(guarded.GetStream(), deadline.Token);
    Check(blocked["type"]!.GetValue<string>() == "error" && store.Names.Count == 0, "PIN lockout blocks further pairing");
}

if (args.Length == 2) {
    var fixtures = JsonNode.Parse(await File.ReadAllTextAsync(args[0]))!.AsObject();
    foreach (var fixture in fixtures["messages"]!.AsArray()) Check(Wire.Verify(fixture!.AsObject(), secret), "Swift-generated HMAC: " + fixture["type"]);
    var swiftKey = Convert.FromBase64String(fixtures["publicKey"]!.GetValue<string>());
    var swiftSeal = Pairing.Seal(swiftKey, "123456", secret);
    var state = Wire.Message("stateResponse"); state["state"] = new JsonObject { ["volume"] = 0.42, ["isMuted"] = false, ["brightness"] = 1.0, ["frontmostApplication"] = "José / 🌈" };
    var catalog = Wire.Message("catalogResponse"); catalog["catalog"] = new JsonArray(
        new PhoneDock.Models.ActionTile { Title = "Aplicación", Target = "C:\\Windows\\explorer.exe", Icon = Convert.ToBase64String(new byte[] { 255, 255, 255 }) }.ToWire(0),
        new PhoneDock.Models.ActionTile { Title = "🌈 Web", Kind = "website", Target = "https://example.com/a/b", Emoji = "✨" }.ToWire(1),
        new PhoneDock.Models.ActionTile { Title = "Texto", Kind = "text", Target = "¡Hola! 👨‍👩‍👧‍👦" }.ToWire(2)); catalog["recentApplications"] = new JsonArray();
    var output = new JsonObject { ["publicKey"] = Convert.ToBase64String(swiftSeal.PublicKey), ["sealedSecret"] = Convert.ToBase64String(swiftSeal.SealedSecret), ["messages"] = new JsonArray(Wire.Sign(state, secret), Wire.Sign(catalog, secret)) };
    await File.WriteAllTextAsync(args[1], Wire.CanonicalText(output));
}
Console.WriteLine($"{passed} checks passed.");

sealed class MemorySecrets : ISecretStore {
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, byte[]> data = new();
    public byte[]? Get(string name) => data.GetValueOrDefault(name);
    public void Save(string name, byte[] secret) => data[name] = secret;
    public void Remove(string name) => data.TryRemove(name, out _);
    public IReadOnlyList<string> Names => data.Keys.ToArray();
}
sealed class FakeHost : IRemoteHost {
    public int Executions;
    public Task ExecuteAsync(JsonObject command) { Executions++; return Task.CompletedTask; }
    public Task<JsonObject> StateAsync() { var m = Wire.Message("stateResponse"); m["state"] = new JsonObject { ["volume"] = 0.42, ["isMuted"] = false }; return Task.FromResult(m); }
    public Task<JsonObject> CatalogAsync() { var m = Wire.Message("catalogResponse"); m["catalog"] = new JsonArray(); m["recentApplications"] = new JsonArray(); return Task.FromResult(m); }
}
