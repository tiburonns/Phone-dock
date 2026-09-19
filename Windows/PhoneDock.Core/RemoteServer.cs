using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.Json.Nodes;

namespace PhoneDock.Core;

public static class SecretStorageNames
{
    public const string PreviousPrefix = "__previous__:";
    public const string HostIdentity = "__host_identity__";

    public static string Previous(string identity) => PreviousPrefix + identity;

    public static bool IsAuxiliary(string name) =>
        name == HostIdentity
        || name.StartsWith(PreviousPrefix, StringComparison.Ordinal);
}

public interface ISecretStore
{
    byte[]? Get(string name);
    void Save(string name, byte[] secret);
    void Remove(string name);
    IReadOnlyList<string> Names { get; }
    string DisplayName(string identity) => identity;
    void SetDisplayName(string identity, string displayName) { }
}
public interface IRemoteHost
{
    Task<JsonObject> StateAsync();
    Task<JsonObject> CatalogAsync();
    Task ExecuteAsync(JsonObject command);
}

public sealed class RemoteServer(IRemoteHost host, ISecretStore secrets) : IDisposable
{
    private sealed class Client(TcpClient tcp)
    {
        public TcpClient Tcp { get; } = tcp;
        public SemaphoreSlim Writer { get; } = new(1);
        public string? Name { get; set; }
    }
    private readonly ConcurrentDictionary<Guid, Client> clients = new();
    private readonly SemaphoreSlim gate = new(1);
    private readonly Dictionary<string, Queue<(Guid Id, DateTimeOffset AcceptedAt)>> replay = new();
    private CancellationTokenSource? stop;
    private TcpListener? listener;
    private string pin = "";
    private DateTime pinExpires;
    private readonly Queue<DateTime> failures = new();
    private DateTime lockedUntil;
    public event Action? Changed;
    public int Port { get; private set; }
    public string ServerID { get; } = LoadOrCreateServerID(secrets);
    public int ConnectedCount => clients.Values.Where(c => c.Name != null).Select(c => c.Name).Distinct().Count();
    public string PairingCode { get { lock (failures) { if (DateTime.UtcNow >= pinExpires) RotatePin(); return pin; } } }

    public void RotatePin()
    {
        lock (failures) {
            pin = RandomNumberGenerator.GetInt32(1_000_000).ToString("D6");
            pinExpires = DateTime.UtcNow.AddMinutes(5);
        }
        Changed?.Invoke();
    }
    public void Start(int port = 49832, IPAddress? address = null)
    {
        if (listener != null) return;
        stop = new(); listener = new TcpListener(address ?? IPAddress.Any, port);
        try { listener.Start(32); }
        catch { listener = null; stop.Dispose(); stop = null; throw; }
        Port = ((IPEndPoint)listener.LocalEndpoint).Port; RotatePin();
        _ = AcceptAsync(stop.Token);
    }
    private async Task AcceptAsync(CancellationToken token)
    {
        try {
            while (!token.IsCancellationRequested) {
                var tcp = await listener!.AcceptTcpClientAsync(token);
                if (clients.Count >= 32) { tcp.Dispose(); continue; }
                tcp.NoDelay = true;
                var id = Guid.NewGuid(); var client = new Client(tcp); clients[id] = client;
                _ = ReceiveAsync(id, client, token);
            }
        } catch (Exception e) when (e is OperationCanceledException or SocketException or ObjectDisposedException) { }
    }
    private async Task ReceiveAsync(Guid id, Client client, CancellationToken token)
    {
        try {
            while (!token.IsCancellationRequested) {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
                timeout.CancelAfter(TimeSpan.FromSeconds(client.Name == null ? 30 : 90));
                var message = await Wire.ReadAsync(client.Tcp.GetStream(), timeout.Token);
                await gate.WaitAsync(token);
                try { await HandleAsync(client, message, token); }
                finally { gate.Release(); }
            }
        } catch (Exception e) when (e is IOException or SocketException or OperationCanceledException
                                    or ObjectDisposedException or System.Text.Json.JsonException or InvalidOperationException) { }
        finally { clients.TryRemove(id, out _); client.Tcp.Dispose(); Changed?.Invoke(); }
    }
    private async Task HandleAsync(Client client, JsonObject request, CancellationToken token)
    {
        byte[]? secret = null;
        try
        {
            if (request["version"]?.GetValue<int>() != 3)
            {
                var mismatch = Wire.Message("error");
                mismatch["error"] = AppLanguage.T("Versión de protocolo no compatible.");
                mismatch["supportedProtocolVersion"] = 3;
                await SendAsync(client, mismatch, token);
                return;
            }

            if (request["type"]?.GetValue<string>() == "pairRequest")
            {
                await PairAsync(client, request, token);
                return;
            }

            if (request["type"]?.GetValue<string>() == "identityRequest")
            {
                var identity = Wire.Message("identityResponse");
                identity["serverID"] = ServerID;
                identity["supportedProtocolVersion"] = 3;
                await SendAsync(client, identity, token);
                return;
            }

            var displayName = request["deviceName"]?.GetValue<string>() ?? "";
            var identity = StableIdentity(request["deviceID"]?.GetValue<string>(), displayName);

            var directSecret = secrets.Get(identity);
            var legacySecret = identity == displayName ? null : secrets.Get(displayName);
            secret = directSecret ?? legacySecret;
            if (secret == null)
            {
                client.Tcp.Close();
                return;
            }

            var usedLegacyIdentity = directSecret == null && legacySecret != null;
            var usedPreviousSecret = false;

            try
            {
                request = Wire.Open(request, secret);
            }
            catch (InvalidDataException)
            {
                var previous =
                    secrets.Get(SecretStorageNames.Previous(identity))
                    ?? (usedLegacyIdentity
                        ? secrets.Get(SecretStorageNames.Previous(displayName))
                        : null);

                if (previous == null)
                    throw;

                request = Wire.Open(request, previous);
                secret = previous;
                usedPreviousSecret = true;
            }

            if (usedLegacyIdentity)
            {
                var current = directSecret ?? legacySecret!;
                secrets.Save(identity, current);
                secrets.SetDisplayName(identity, displayName);
                secrets.Remove(displayName);

                var legacyPrevious =
                    secrets.Get(SecretStorageNames.Previous(displayName));
                if (legacyPrevious != null)
                {
                    secrets.Save(
                        SecretStorageNames.Previous(identity),
                        legacyPrevious
                    );
                }
                secrets.Remove(SecretStorageNames.Previous(displayName));

                replay.Remove(displayName);
            }
            else
            {
                secrets.SetDisplayName(identity, displayName);
            }

            var now = DateTimeOffset.UtcNow;
            var sentAt = DateTimeOffset.FromUnixTimeSeconds(request["sentAt"]!.GetValue<long>());
            if ((now - sentAt).Duration() > TimeSpan.FromMinutes(2))
                throw new InvalidDataException(AppLanguage.T("Solicitud caducada rechazada."));

            var messageID = Guid.Parse(request["id"]!.GetValue<string>());
            if (!replay.TryGetValue(identity, out var ids))
                replay[identity] = ids = new();

            while (ids.TryPeek(out var oldest) && now - oldest.AcceptedAt > TimeSpan.FromMinutes(2))
                ids.Dequeue();

            if (ids.Any(entry => entry.Id == messageID) || ids.Count >= 4_096)
                throw new InvalidDataException(AppLanguage.T("Solicitud duplicada rechazada."));

            ids.Enqueue((messageID, now));
            client.Name = identity;
            Changed?.Invoke();

            if (usedPreviousSecret)
            {
                var recovery = Wire.Message("rotateSecretResponse");
                recovery["encryptedSecret"] = Convert.ToBase64String(secrets.Get(identity)!);
                await SendAsync(client, SealForClient(recovery, secret), token);
                return;
            }

            JsonObject response;
            switch (request["type"]?.GetValue<string>())
            {
                case "catalogRequest":
                    response = await host.CatalogAsync();
                    break;
                case "stateRequest":
                case "ping":
                    response = await host.StateAsync();
                    break;
                case "command":
                    await host.ExecuteAsync(
                        request["command"] as JsonObject
                        ?? throw new InvalidDataException(AppLanguage.T("Acción inválida."))
                    );
                    response = await host.StateAsync();
                    break;
                case "rotateSecret":
                    var replacementSecret = RandomNumberGenerator.GetBytes(32);
                    secrets.Save(
                        SecretStorageNames.Previous(identity),
                        secret
                    );
                    secrets.Save(identity, replacementSecret);
                    response = Wire.Message("rotateSecretResponse");
                    response["encryptedSecret"] = Convert.ToBase64String(replacementSecret);
                    await SendAsync(client, SealForClient(response, secret), token);
                    return;
                case "rotateSecretAcknowledgement":
                    secrets.Remove(
                        SecretStorageNames.Previous(identity)
                    );
                    response = await host.StateAsync();
                    break;
                case "unpair":
                    response = Wire.Message("unpair");
                    response["deviceName"] = displayName;
                    response["deviceID"] = identity;
                    await SendAsync(client, SealForClient(response, secret), token);
                    Forget(identity);
                    return;
                default:
                    throw new InvalidDataException(AppLanguage.T("Mensaje no compatible."));
            }

            await SendAsync(client, SealForClient(response, secret), token);
        }
        catch (Exception e) when (
            e is not OperationCanceledException and
            not IOException and
            not SocketException
        )
        {
            var error = Wire.Message("error");
            error["error"] = e.Message;
            await SendAsync(client, secret == null ? error : SealForClient(error, secret), token);
        }
    }

    private async Task PairAsync(Client client, JsonObject request, CancellationToken token)
    {
        var displayName = request["deviceName"]?.GetValue<string>();
        var identity = StableIdentity(request["deviceID"]?.GetValue<string>(), displayName ?? "");

        lock (failures)
        {
            var now = DateTime.UtcNow;
            if (now < lockedUntil)
                throw new InvalidDataException(AppLanguage.T("Demasiados intentos. Espera 30 segundos."));

            if (string.IsNullOrWhiteSpace(displayName) ||
                displayName.Length > 128 ||
                identity.Length > 128 ||
                request["pin"]?.GetValue<string>() != PairingCode)
            {
                while (failures.TryPeek(out var oldest) && now - oldest > TimeSpan.FromMinutes(1))
                    failures.Dequeue();

                failures.Enqueue(now);
                if (failures.Count >= 5)
                {
                    lockedUntil = now.AddSeconds(30);
                    RotatePin();
                    failures.Clear();
                }

                throw new InvalidDataException(AppLanguage.T("El código es incorrecto o ha caducado."));
            }
        }

        if (secrets.Names.Count >= 20 && !secrets.Names.Contains(identity))
            throw new InvalidDataException(AppLanguage.T("Elimina un dispositivo antes de enlazar otro."));

        var newSecret = RandomNumberGenerator.GetBytes(32);
        var sealedKey = Pairing.Seal(
            Convert.FromBase64String(request["publicKey"]!.GetValue<string>()),
            request["pin"]!.GetValue<string>(),
            newSecret
        );

        var response = Wire.Message("pairResponse");
        response["serverID"] = ServerID;
        response["publicKey"] = Convert.ToBase64String(sealedKey.PublicKey);
        response["encryptedSecret"] = Convert.ToBase64String(sealedKey.SealedSecret);

        // Validate frame size before saving a credential or changing session state.
        _ = Wire.Frame(response);

        secrets.Save(identity, newSecret);
        secrets.SetDisplayName(identity, displayName!);
        replay.Remove(identity);
        client.Name = identity;
        secrets.Remove(SecretStorageNames.Previous(identity));

        await SendAsync(client, Wire.Sign(response, newSecret), token);
        RotatePin();
        Changed?.Invoke();
    }

    private JsonObject SealForClient(JsonObject message, byte[] secret)
    {
        var identified = (JsonObject)message.DeepClone();
        identified["serverID"] ??= ServerID;
        return Wire.Seal(identified, secret);
    }

    private static string LoadOrCreateServerID(ISecretStore secrets)
    {
        if (secrets.Get(SecretStorageNames.HostIdentity) is { Length: 16 } existing)
            return Convert.ToHexString(existing);

        var created = RandomNumberGenerator.GetBytes(16);
        secrets.Save(SecretStorageNames.HostIdentity, created);
        return Convert.ToHexString(created);
    }

    private static string StableIdentity(string? deviceID, string fallbackName)
    {
        var clean = deviceID?.Trim() ?? "";
        return string.IsNullOrWhiteSpace(clean) ? fallbackName : clean;
    }

    private static async Task SendAsync(Client client, JsonObject message, CancellationToken token)
    {
        var frame = Wire.Frame(message);
        await client.Writer.WaitAsync(token);
        try { await client.Tcp.GetStream().WriteAsync(frame, token); }
        finally { client.Writer.Release(); }
    }
    public async Task BroadcastAsync()
    {
        if (stop == null) return;
        var catalog = await host.CatalogAsync();
        foreach (var client in clients.Values) {
            if (client.Name == null || secrets.Get(client.Name) is not { } secret) continue;
            try { await SendAsync(client, SealForClient(catalog, secret), stop.Token); }
            catch (Exception e) when (e is IOException or SocketException or ObjectDisposedException or OperationCanceledException) { client.Tcp.Close(); }
        }
    }
    public void Forget(string name)
    {
        secrets.Remove(name);
        secrets.Remove(SecretStorageNames.Previous(name));
        foreach (var client in clients.Values.Where(c => c.Name == name)) client.Tcp.Close();
        Changed?.Invoke();
    }
    public void Dispose()
    {
        stop?.Cancel(); listener?.Stop(); listener = null;
        foreach (var client in clients.Values) client.Tcp.Close();
        clients.Clear(); stop?.Dispose(); stop = null;
    }
}
