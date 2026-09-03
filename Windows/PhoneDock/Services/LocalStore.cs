using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using PhoneDock.Core;
using PhoneDock.Models;

namespace PhoneDock.Services;

public sealed class LocalStore : ISecretStore
{
    private readonly object sync = new();
    public string DirectoryPath { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PhoneDock");
    public List<ActionTile> Tiles { get; private set; } = [];
    public Preferences Preferences { get; private set; } = new();
    private Dictionary<string, string> devices = new();
    public IReadOnlyList<string> Names { get { lock (sync) return devices.Keys.ToArray(); } }
    public LocalStore() {
        Directory.CreateDirectory(DirectoryPath);
        Preferences = Load("appearance.json", new Preferences());
        AppLanguage.Selected = Preferences.Language;
        Tiles = Load("actions.json", new List<ActionTile> {
            new() { Title = "Explorador", Target = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe"), Emoji = "📁" },
            new() { Title = "Bloc de notas", Target = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "notepad.exe"), Emoji = "📝" },
            new() { Title = "OpenAI", Kind = "website", Target = "https://openai.com", Emoji = "🌐" },
            new() { Title = "Un poco de magia", Kind = "text", Target = "✨", Emoji = "✨" }
        });
        devices = Load("devices.json", new Dictionary<string, string>());
    }
    private T Load<T>(string file, T fallback) {
        var path = Path.Combine(DirectoryPath, file);
        if (!File.Exists(path)) return fallback;
        // Preserve corrupt files and report them rather than silently overwriting user data.
        return JsonSerializer.Deserialize<T>(File.ReadAllText(path)) ?? throw new InvalidDataException(AppLanguage.F("No se pudo leer {0}.", file));
    }
    private void Save<T>(string file, T value) {
        var path = Path.Combine(DirectoryPath, file); var temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(value)); File.Move(temp, path, true);
    }
    public void SaveActions() => Save("actions.json", Tiles);
    public void SavePreferences() => Save("appearance.json", Preferences);
    public byte[]? Get(string name) {
        lock (sync) {
            if (!devices.TryGetValue(name, out var data)) return null;
            return ProtectedData.Unprotect(Convert.FromBase64String(data), Encoding.UTF8.GetBytes("PhoneDock pairing"), DataProtectionScope.CurrentUser);
        }
    }
    public void Save(string name, byte[] secret) {
        lock (sync) {
            devices[name] = Convert.ToBase64String(ProtectedData.Protect(secret, Encoding.UTF8.GetBytes("PhoneDock pairing"), DataProtectionScope.CurrentUser));
            Save("devices.json", devices);
        }
    }
    public void Remove(string name) { lock (sync) { devices.Remove(name); Save("devices.json", devices); } }
}
