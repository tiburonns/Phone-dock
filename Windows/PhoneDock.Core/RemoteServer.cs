using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.Json.Nodes;

namespace PhoneDock.Core;

public interface ISecretStore
{
    byte[]? Get(string name);
    void Save(string name, byte[] secret);
    void Remove(string name);
    IReadOnlyList<string> Names { get; }
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
    private readonly Dictionary<string, byte[]> previousSecrets = new(StringComparer.Ordinal);
    private CancellationTokenSource? stop;
    private TcpListener? listener;
    private string pin = "";
    private DateTime pinExpires;
    private readonly Queue<DateTime> failures = new();
    private DateTime lockedUntil;
    public event Action? Changed;
    public int Port { get; private set; }
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
        try {
            if (request["version"]?.GetValue<int>() != 2) {
                var mismatch = Wire.Message("error");
                mismatch["error"] = AppLanguage.T("Versión de protocolo no compatible.");
                mismatch["supportedProtocolVersion"] = 2;
                await SendAsync(client, mismatch, token);
                return;
            }
            if (request["type"]?.GetValue<string>() == "pairRequest") { await PairAsync(client, request, token); return; }
            var name = request["deviceName"]?.GetValue<string>() ?? "";
            secret = secrets.Get(name);
            if (secret == null) { client.Tcp.Close(); return; }
            var usedPreviousSecret = false;
            try { request = Wire.Open(request, secret); }
            catch (InvalidDataException) when (previousSecrets.TryGetValue(name, out var previous)) {
                request = Wire.Open(request, previous);
                secret = previous;
                usedPreviousSecret = true;
            }
            var now = DateTimeOffset.UtcNow;
            var sentAt = DateTimeOffset.FromUnixTimeSeconds(request["sentAt"]!.GetValue<long>());
            if ((now - sentAt).Duration() > TimeSpan.FromMinutes(2))
                throw new InvalidDataException(AppLanguage.T("Solicitud caducada rechazada."));
            var id = Guid.Parse(request["id"]!.GetValue<string>());
            if (!replay.TryGetValue(name, out var ids)) replay[name] = ids = new();
            while (ids.TryPeek(out var oldest) && now - oldest.AcceptedAt > TimeSpan.FromMinutes(2)) ids.Dequeue();
            if (ids.Any(entry => entry.Id == id) || ids.Count >= 4_096)
                throw new InvalidDataException(AppLanguage.T("Solicitud duplicada rechazada."));
            ids.Enqueue((id, now));
            client.Name = name; Changed?.Invoke();

            if (usedPreviousSecret) {
                var recovery = Wire.Message("rotateSecretResponse");
                recovery["encryptedSecret"] = Convert.ToBase64String(secrets.Get(name)!);
                await SendAsync(client, Wire.Seal(recovery, secret), token);
                return;
            }

            JsonObject response;
            switch (request["type"]?.GetValue<string>()) {
                case "catalogRequest": response = await host.CatalogAsync(); break;
                case "stateRequest": case "ping": response = await host.StateAsync(); break;
                case "command":
                    await host.ExecuteAsync(request["command"] as JsonObject ?? throw new InvalidDataException(AppLanguage.T("Acción inválida.")));
                    response = await host.StateAsync(); break;
                case "rotateSecret":
                    var replacement = RandomNumberGenerator.GetBytes(32);
                    previousSecrets[name] = secret;
                    secrets.Save(name, replacement);
                    response = Wire.Message("rotateSecretResponse");
                    response["encryptedSecret"] = Convert.ToBase64String(replacement);
                    await SendAsync(client, Wire.Seal(response, secret), token);
                    return;
                case "rotateSecretAcknowledgement":
                    previousSecrets.Remove(name);
                    response = await host.StateAsync();
                    break;
                case "unpair":
                    response = Wire.Message("unpair"); response["deviceName"] = name;
                    await SendAsync(client, Wire.Seal(response, secret), token);
                    Forget(name); return;
                default: throw new InvalidDataException(AppLanguage.T("Mensaje no compatible."));
            }
            await SendAsync(client, Wire.Seal(response, secret), token);
        } catch (Exception e) when (e is not OperationCanceledException and not IOException and not SocketException) {
            var error = Wire.Message("error"); error["error"] = e.Message;
            await SendAsync(client, secret == null ? error : Wire.Seal(error, secret), token);
        } catch (InvalidDataException e) {
            var error = Wire.Message("error"); error["error"] = e.Message;
            await SendAsync(client, secret == null ? error : Wire.Seal(error, secret), token);
        }
    }
    private async Task PairAsync(Client client, JsonObject request, CancellationToken token)
    {
        var name = request["deviceName"]?.GetValue<string>();
        lock (failures) {
            var now = DateTime.UtcNow;
            if (now < lockedUntil) throw new InvalidDataException(AppLanguage.T("Demasiados intentos. Espera 30 segundos."));
            if (string.IsNullOrWhiteSpace(name) || name.Length > 128 || request["pin"]?.GetValue<string>() != PairingCode) {
                while (failures.TryPeek(out var oldest) && now - oldest > TimeSpan.FromMinutes(1)) failures.Dequeue();
                failures.Enqueue(now);
                if (failures.Count >= 5) { lockedUntil = now.AddSeconds(30); RotatePin(); failures.Clear(); }
                throw new InvalidDataException(AppLanguage.T("El código es incorrecto o ha caducado."));
            }
        }
        if (secrets.Names.Count >= 20 && !secrets.Names.Contains(name!)) throw new InvalidDataException(AppLanguage.T("Elimina un dispositivo antes de enlazar otro."));
        var secret = RandomNumberGenerator.GetBytes(32);
        var sealedKey = Pairing.Seal(Convert.FromBase64String(request["publicKey"]!.GetValue<string>()), request["pin"]!.GetValue<string>(), secret);
        var response = Wire.Message("pairResponse");
        response["publicKey"] = Convert.ToBase64String(sealedKey.PublicKey);
        response["encryptedSecret"] = Convert.ToBase64String(sealedKey.SealedSecret);
        // Validate frame size before saving a credential or changing session state.
        _ = Wire.Frame(response);
        secrets.Save(name!, secret); replay.Remove(name!); client.Name = name;
        previousSecrets.Remove(name!);
        await SendAsync(client, response, token); RotatePin(); Changed?.Invoke();
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
            try { await SendAsync(client, Wire.Seal(catalog, secret), stop.Token); }
            catch (Exception e) when (e is IOException or SocketException or ObjectDisposedException or OperationCanceledException) { client.Tcp.Close(); }
        }
    }
    public void Forget(string name)
    {
        secrets.Remove(name);
        previousSecrets.Remove(name);
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
