using System.Management;
using System.Runtime.InteropServices;
using PhoneDock.Core;

namespace PhoneDock.Services;

/// Integrated panel via WMI; otherwise a brightness-capable primary display via DDC/CI.
public sealed class DisplayBrightness
{
    public double? Read() {
        if (ReadIntegrated() is { } integrated) return integrated;
        return WithPrimaryMonitor((handle, min, current, max) => (double)(current - min) / (max - min));
    }
    public void Set(double normalized) {
        if (ReadIntegrated() != null) {
            using var query = Query("SELECT * FROM WmiMonitorBrightnessMethods WHERE Active = True");
            using var values = query.Get();
            foreach (ManagementObject monitor in values) using (monitor) {
                using var args = monitor.GetMethodParameters("WmiSetBrightness");
                args["Timeout"] = 0u; args["Brightness"] = (byte)Math.Round(normalized * 100);
                using var result = monitor.InvokeMethod("WmiSetBrightness", args, null);
                if (result != null && Convert.ToUInt32(result["ReturnValue"]) == 0) return;
            }
            throw new InvalidOperationException(AppLanguage.T("Windows no pudo aplicar el brillo de la pantalla integrada."));
        }
        var changed = WithPrimaryMonitor((handle, min, current, max) => {
            var value = min + (uint)Math.Round(normalized * (max - min));
            return SetMonitorBrightness(handle, value) ? 1d : 0d;
        });
        if (changed != 1) throw new InvalidOperationException(AppLanguage.T("El monitor no permite ajustar el brillo. Revisa si admite DDC/CI y si está activado en su menú."));
    }
    private static ManagementObjectSearcher Query(string statement) => new("root\\WMI", statement) {
        Options = new EnumerationOptions { Timeout = TimeSpan.FromSeconds(2) }
    };
    private static double? ReadIntegrated() {
        try {
            using var query = Query("SELECT CurrentBrightness FROM WmiMonitorBrightness WHERE Active = True");
            using var values = query.Get();
            foreach (ManagementObject monitor in values) using (monitor) return Convert.ToDouble(monitor["CurrentBrightness"]) / 100;
        } catch (Exception e) when (e is ManagementException or COMException or UnauthorizedAccessException) { }
        return null;
    }
    private static double? WithPrimaryMonitor(Func<nint, uint, uint, uint, double> action) {
        var monitor = MonitorFromPoint(new Point(), 1);
        if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, out var count) || count == 0 || count > 16) return null;
        var physical = new PhysicalMonitor[count];
        if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, physical)) return null;
        try {
            foreach (var display in physical) {
                if (!GetMonitorCapabilities(display.Handle, out var capabilities, out _) || (capabilities & 2) == 0) continue;
                if (!GetMonitorBrightness(display.Handle, out var min, out var current, out var max) || max <= min || current < min || current > max) continue;
                return action(display.Handle, min, current, max);
            }
            return null;
        } finally { DestroyPhysicalMonitors(count, physical); }
    }
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct PhysicalMonitor {
        public nint Handle;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
    }
    [DllImport("user32.dll")] private static extern nint MonitorFromPoint(Point point, uint flags);
    [DllImport("dxva2.dll", SetLastError = true)] private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(nint monitor, out uint count);
    [DllImport("dxva2.dll", SetLastError = true)] private static extern bool GetPhysicalMonitorsFromHMONITOR(nint monitor, uint count, [Out] PhysicalMonitor[] monitors);
    [DllImport("dxva2.dll")] private static extern bool DestroyPhysicalMonitors(uint count, PhysicalMonitor[] monitors);
    [DllImport("dxva2.dll")] private static extern bool GetMonitorCapabilities(nint monitor, out uint capabilities, out uint temperatures);
    [DllImport("dxva2.dll", SetLastError = true)] private static extern bool GetMonitorBrightness(nint monitor, out uint min, out uint current, out uint max);
    [DllImport("dxva2.dll", SetLastError = true)] private static extern bool SetMonitorBrightness(nint monitor, uint value);
}
