using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;
using PhoneDock.Core;

namespace PhoneDock.Services;

public sealed class ApplicationWindows : IApplicationActivationBackend
{
    public string ResolveExecutable(string target) {
        if (!Path.GetExtension(target).Equals(".lnk", StringComparison.OrdinalIgnoreCase)) return Path.GetFullPath(target);
        var link = (IShellLinkW)new ShellLink();
        try {
            ((IPersistFile)link).Load(target, 0);
            var path = new StringBuilder(32768);
            link.GetPath(path, path.Capacity, IntPtr.Zero, 0);
            if (path.Length == 0 || !Path.GetExtension(path.ToString()).Equals(".exe", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException(AppLanguage.T("Este acceso directo no apunta a un ejecutable. Selecciona el archivo .exe de la aplicación para poder cambiar a su ventana."));
            return Path.GetFullPath(Environment.ExpandEnvironmentVariables(path.ToString()));
        } finally { Marshal.FinalReleaseComObject(link); }
    }

    public nint FindWindow(string executable) {
        var candidates = new List<(nint Handle, string Path)>();
        var processes = new Dictionary<uint, string?>();
        EnumWindows((window, _) => {
            if (!IsWindowVisible(window) || GetWindow(window, 4) != 0 || GetWindowTextLength(window) == 0 || (GetWindowLongPtr(window, -20).ToInt64() & 0x80) != 0) return true;
            GetWindowThreadProcessId(window, out var pid);
            if (!processes.TryGetValue(pid, out var path)) processes[pid] = path = ExecutablePath(pid);
            if (path == null) return true;
            if (Path.GetFileName(path).Equals("explorer.exe", StringComparison.OrdinalIgnoreCase)) {
                var className = new StringBuilder(256); GetClassName(window, className, className.Capacity);
                if (className.ToString() is not ("CabinetWClass" or "ExploreWClass")) return true;
            }
            candidates.Add((window, path)); return true;
        }, 0);
        // EnumWindows returns top-level windows in Z order: prefer the most recently foregrounded.
        var exact = candidates.FirstOrDefault(w => string.Equals(w.Path, executable, StringComparison.OrdinalIgnoreCase));
        if (exact.Handle != 0) return exact.Handle;
        // Windows 11 redirects the built-in Notepad launcher into its Store package.
        var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        if (string.Equals(executable, Path.Combine(windows, "notepad.exe"), StringComparison.OrdinalIgnoreCase)
            || string.Equals(executable, Path.Combine(Environment.SystemDirectory, "notepad.exe"), StringComparison.OrdinalIgnoreCase)) {
            return candidates.FirstOrDefault(w => Path.GetFileName(w.Path).Equals("Notepad.exe", StringComparison.OrdinalIgnoreCase)
                && w.Path.Contains(@"\WindowsApps\Microsoft.WindowsNotepad_", StringComparison.OrdinalIgnoreCase)).Handle;
        }
        return 0;
    }

    public bool Activate(nint window) {
        var popup = GetLastActivePopup(window);
        if (popup != 0 && IsWindowVisible(popup)) window = popup;
        if (IsIconic(window)) ShowWindowAsync(window, 9); // SW_RESTORE preserves normal/maximized placement.
        if (GetForegroundWindow() == window || SetForegroundWindow(window)) return true;
        var current = GetCurrentThreadId();
        var foreground = GetWindowThreadProcessId(GetForegroundWindow(), out _);
        var attached = foreground != 0 && foreground != current && AttachThreadInput(current, foreground, true);
        try { return SetForegroundWindow(window); }
        finally { if (attached) AttachThreadInput(current, foreground, false); }
    }

    public void Start(string target) { using var process = Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); }

    private static string? ExecutablePath(uint pid) {
        var process = OpenProcess(0x1000, false, pid); // Query limited information, no debug privilege.
        if (process == 0) return null;
        try { var path = new StringBuilder(32768); var size = path.Capacity; return QueryFullProcessImageName(process, 0, path, ref size) ? path.ToString() : null; }
        finally { CloseHandle(process); }
    }

    [ComImport, Guid("00021401-0000-0000-C000-000000000046")] private class ShellLink { }
    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int maxPath, nint data, uint flags);
    }
    private delegate bool EnumWindowsCallback(nint window, nint parameter);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsCallback callback, nint parameter);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(nint window);
    [DllImport("user32.dll")] private static extern nint GetWindow(nint window, uint command);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern nint GetWindowLongPtr(nint window, int index);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLength(nint window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(nint window, StringBuilder text, int count);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint window, out uint pid);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(nint window);
    [DllImport("user32.dll")] private static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] private static extern nint GetLastActivePopup(nint window);
    [DllImport("user32.dll")] private static extern bool IsIconic(nint window);
    [DllImport("user32.dll")] private static extern bool ShowWindowAsync(nint window, int command);
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint current, uint target, bool attach);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll")] private static extern nint OpenProcess(uint access, bool inherit, uint pid);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern bool QueryFullProcessImageName(nint process, uint flags, StringBuilder path, ref int size);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(nint handle);
}
