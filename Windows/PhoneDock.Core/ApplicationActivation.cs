namespace PhoneDock.Core;

public interface IApplicationActivationBackend
{
    string ResolveExecutable(string target);
    nint FindWindow(string executable);
    bool Activate(nint window);
    void Start(string target);
}

/// Launch only when no window exists. A denied foreground request must never spawn a duplicate.
public sealed class ApplicationActivation(IApplicationActivationBackend backend, Func<DateTimeOffset>? clock = null)
{
    private readonly Dictionary<string, DateTimeOffset> starting = new(StringComparer.OrdinalIgnoreCase);
    public void OpenNew(string target) {
        _ = backend.ResolveExecutable(target);
        backend.Start(target); // Explicit long press bypasses reuse; single-instance apps may still reuse themselves.
    }
    public void Open(string target) {
        var executable = backend.ResolveExecutable(target);
        var window = backend.FindWindow(executable);
        if (window != 0) {
            starting.Remove(executable);
            if (!backend.Activate(window)) throw new InvalidOperationException(AppLanguage.T("La aplicación ya está abierta, pero Windows bloqueó el cambio de ventana. Selecciónala en la barra de tareas; no se abrió otra instancia."));
            return;
        }
        var now = (clock ?? (() => DateTimeOffset.UtcNow))();
        foreach (var key in starting.Where(p => now - p.Value >= TimeSpan.FromSeconds(15)).Select(p => p.Key).ToArray()) starting.Remove(key);
        if (starting.ContainsKey(executable)) return;
        backend.Start(target);
        starting[executable] = now;
    }
}
