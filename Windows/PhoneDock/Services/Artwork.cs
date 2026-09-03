using PhoneDock.Core;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace PhoneDock.Services;
public static class Artwork
{
    public static string? AppIcon(string path) {
        var info = new SHFILEINFO();
        SHGetFileInfo(path, 0, ref info, (uint)Marshal.SizeOf<SHFILEINFO>(), 0x100);
        if (info.Icon == IntPtr.Zero) return null;
        try { return Encode(Imaging.CreateBitmapSourceFromHIcon(info.Icon, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions())); }
        finally { DestroyIcon(info.Icon); }
    }
    public static string Encode(BitmapSource source) {
        var size = 128d; var scale = Math.Min(size / source.PixelWidth, size / source.PixelHeight);
        var drawing = new DrawingVisual();
        using (var context = drawing.RenderOpen()) context.DrawImage(source, new Rect((size - source.PixelWidth * scale) / 2, (size - source.PixelHeight * scale) / 2, source.PixelWidth * scale, source.PixelHeight * scale));
        var target = new RenderTargetBitmap(128, 128, 96, 96, PixelFormats.Pbgra32); target.Render(drawing);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(target));
        using var data = new MemoryStream(); encoder.Save(data);
        if (data.Length > 24_000) throw new InvalidDataException(AppLanguage.T("La imagen es demasiado compleja. Elige un icono más sencillo."));
        return Convert.ToBase64String(data.ToArray());
    }
    public static BitmapSource? Decode(string? data) {
        if (data == null) return null;
        try { using var stream = new MemoryStream(Convert.FromBase64String(data));
            var image = BitmapFrame.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad); image.Freeze(); return image;
        } catch { return null; }
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct SHFILEINFO {
        public IntPtr Icon; public int Index; public uint Attributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string DisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string TypeName;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr SHGetFileInfo(string path, uint attributes, ref SHFILEINFO info, uint size, uint flags);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr icon);
}
