using System.Diagnostics;
using System.IO;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;
using NAudio.CoreAudioApi;
using PhoneDock.Core;

namespace PhoneDock.Services;

public sealed class SystemController(LocalStore store)
{
    public JsonObject State() {
        double volume = 0; bool muted = false;
        try { using var enumerator = new MMDeviceEnumerator(); using var device = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            volume = Math.Round(device.AudioEndpointVolume.MasterVolumeLevelScalar, 4); muted = device.AudioEndpointVolume.Mute;
        } catch (COMException) { }
        var state = new JsonObject { ["volume"] = volume, ["isMuted"] = muted };
        if (Brightness() is { } brightness) state["brightness"] = brightness;
        var title = new StringBuilder(512); GetWindowText(GetForegroundWindow(), title, title.Capacity);
        if (title.Length > 0) state["frontmostApplication"] = title.ToString();
        return state;
    }
    private static double? Brightness() {
        try {
            using var query = new ManagementObjectSearcher("root\\WMI", "SELECT CurrentBrightness FROM WmiMonitorBrightness WHERE Active = True");
            using var values = query.Get();
            foreach (ManagementObject value in values) using (value) return Convert.ToDouble(value["CurrentBrightness"]) / 100;
        } catch (Exception e) when (e is ManagementException or COMException or UnauthorizedAccessException) { }
        return null;
    }
    public void Execute(JsonObject command) {
        if (command.Count != 1) throw new InvalidDataException(AppLanguage.T("Acción inválida."));
        var pair = command.First(); var args = pair.Value as JsonObject ?? throw new InvalidDataException(AppLanguage.T("Parámetros inválidos."));
        switch (pair.Key) {
            case "launchApp":
                var id = args["bundleIdentifier"]!.GetValue<string>();
                var tile = store.Tiles.FirstOrDefault(t => t.Id == id && t.Kind == "app") ?? throw new InvalidDataException(AppLanguage.T("La aplicación ya no está en tu Dock."));
                if (!File.Exists(tile.Target)) throw new FileNotFoundException(AppLanguage.T("No se encuentra la aplicación seleccionada."));
                Process.Start(new ProcessStartInfo(tile.Target) { UseShellExecute = true }); break;
            case "openURL":
                var url = args["_0"]!.GetValue<string>();
                if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https")) throw new InvalidDataException(AppLanguage.T("Solo se permiten enlaces HTTP o HTTPS."));
                Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true }); break;
            case "setVolume": case "setMuted":
                using (var enumerator = new MMDeviceEnumerator())
                using (var device = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia)) {
                    if (pair.Key == "setMuted") device.AudioEndpointVolume.Mute = args["_0"]!.GetValue<bool>();
                    else device.AudioEndpointVolume.MasterVolumeLevelScalar = (float)UnitValue(args["_0"]!);
                } break;
            case "setBrightness":
                var level = (byte)Math.Round(UnitValue(args["_0"]!) * 100); bool changed = false;
                using (var query = new ManagementObjectSearcher("root\\WMI", "SELECT * FROM WmiMonitorBrightnessMethods WHERE Active = True"))
                using (var values = query.Get())
                    foreach (ManagementObject monitor in values) using (monitor) { monitor.InvokeMethod("WmiSetBrightness", new object[] { 0u, level }); changed = true; }
                if (!changed) throw new InvalidOperationException(AppLanguage.T("Este monitor no permite ajustar el brillo por WMI."));
                break;
            case "window":
                var window = GetForegroundWindow();
                if (window == IntPtr.Zero) throw new InvalidOperationException(AppLanguage.T("No hay una ventana activa."));
                // 'hide' maps to minimize so a window cannot become unreachable.
                var action = args["_0"]!.GetValue<string>();
                if (action is not ("maximize" or "minimize" or "hide")) throw new InvalidDataException(AppLanguage.T("Control de ventana inválido."));
                ShowWindowAsync(window, action == "maximize" ? 3 : 6); break;
            case "clipboard":
                var operation = args["_0"]!.GetValue<string>();
                if (operation is not ("copy" or "paste")) throw new InvalidDataException(AppLanguage.T("Acción de portapapeles inválida."));
                SendKeys([Key(0x11), Key(operation == "copy" ? (ushort)0x43 : (ushort)0x56), Key(operation == "copy" ? (ushort)0x43 : (ushort)0x56, 2), Key(0x11, 2)]); break;
            case "insertText":
                var text = args["_0"]!.GetValue<string>();
                if (text.Length > 4096) throw new InvalidDataException(AppLanguage.T("El texto es demasiado largo."));
                SendKeys(text.SelectMany(c => new[] { Key(0, 4, c), Key(0, 6, c) }).ToArray()); break;
            case "runShortcut": throw new InvalidOperationException(AppLanguage.T("Atajos de Apple no está disponible en Windows. Agrega una aplicación o un acceso directo .lnk."));
            case "setRecentAppPinned": throw new InvalidOperationException(AppLanguage.T("Recientes todavía no está disponible en Windows; agrega la app a tu Dock."));
            default: throw new InvalidDataException(AppLanguage.T("Acción no compatible."));
        }
    }
    private static double UnitValue(JsonNode value) {
        var number = value.GetValue<double>();
        if (!double.IsFinite(number) || number < 0 || number > 1) throw new InvalidDataException(AppLanguage.T("Valor fuera de rango."));
        return number;
    }
    private static INPUT Key(ushort key, uint flags = 0, char scan = '\0') => new() { Type = 1, Data = new InputUnion { Keyboard = new() { Key = key, Scan = scan, Flags = flags } } };
    private static void SendKeys(INPUT[] keys) {
        if (keys.Length > 0 && SendInput((uint)keys.Length, keys, Marshal.SizeOf<INPUT>()) != keys.Length)
            throw new InvalidOperationException(AppLanguage.T("Windows bloqueó la entrada. No se pueden controlar ventanas elevadas o de seguridad."));
    }
    [StructLayout(LayoutKind.Sequential)] private struct INPUT { public uint Type; public InputUnion Data; }
    [StructLayout(LayoutKind.Explicit)] private struct InputUnion { [FieldOffset(0)] public KEYBDINPUT Keyboard; [FieldOffset(0)] public MOUSEINPUT Mouse; }
    [StructLayout(LayoutKind.Sequential)] private struct KEYBDINPUT { public ushort Key; public ushort Scan; public uint Flags; public uint Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] private struct MOUSEINPUT { public int X; public int Y; public uint Data; public uint Flags; public uint Time; public UIntPtr Extra; }
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll")] private static extern bool ShowWindowAsync(IntPtr window, int command);
}
