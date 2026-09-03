using PhoneDock.Core;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using PhoneDock.Models;
using PhoneDock.Services;

namespace PhoneDock;

public sealed class TileEditor : Window
{
    public ActionTile Result { get; private set; }
    private readonly TextBox title = new(), target = new(), emoji = new(), tint = new();
    private readonly ComboBox kind = new(), page = new();
    public TileEditor(ActionTile original) {
        Result = original with { };
        Title = AppLanguage.T("Personalizar acción · Phone Dock"); Width = 530; Height = 700;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var body = new StackPanel { Margin = new Thickness(26) };
        Content = new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        body.Children.Add(MainWindow.Text("Un toque muy tuyo.", 26, true));
        void Field(string label, UIElement control) { body.Children.Add(MainWindow.Text(label, 13, true)); body.Children.Add(control); }
        title.Text = original.Title; title.MaxLength = 60; Field("Nombre", title);
        kind.ItemsSource = new[] { AppLanguage.T("Aplicación"), AppLanguage.T("Sitio web"), AppLanguage.T("Texto") };
        kind.SelectedIndex = original.Kind == "website" ? 1 : original.Kind == "text" ? 2 : 0; Field("Tipo de acción", kind);
        target.Text = original.Target; target.MaxLength = 4096; Field("Archivo .exe / .lnk, URL o texto", target);
        body.Children.Add(MainWindow.MakeButton("Elegir aplicación…", () => {
            var picker = new OpenFileDialog { Filter = AppLanguage.T("Aplicaciones y accesos directos|*.exe;*.lnk"), DereferenceLinks = false };
            if (picker.ShowDialog(this) != true) return;
            target.Text = picker.FileName; kind.SelectedIndex = 0;
            if (title.Text == AppLanguage.T("Nueva acción")) title.Text = Path.GetFileNameWithoutExtension(picker.FileName);
            try { Result.Icon = Artwork.AppIcon(picker.FileName); emoji.Text = ""; } catch (Exception e) { Notice(e.Message); }
        }));
        emoji.Text = original.Emoji; emoji.MaxLength = 16; Field("Emoji (vacío para mostrar la imagen)", emoji);
        body.Children.Add(MainWindow.MakeButton("Elegir imagen…", () => {
            var picker = new OpenFileDialog { Filter = AppLanguage.T("Imágenes|*.png;*.jpg;*.jpeg") };
            if (picker.ShowDialog(this) != true) return;
            try {
                if (new FileInfo(picker.FileName).Length > 10_000_000) throw new InvalidDataException(AppLanguage.T("Elige una imagen de menos de 10 MB."));
                using var stream = File.OpenRead(picker.FileName);
                var bitmap = new BitmapImage(); bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.DecodePixelWidth = 128; bitmap.StreamSource = stream; bitmap.EndInit();
                Result.Icon = Artwork.Encode(bitmap); emoji.Text = ""; Notice("Imagen preparada. Guarda para aplicarla.");
            } catch (Exception e) { Notice(e.Message); }
        }));
        tint.Text = original.Tint; tint.MaxLength = 7; Field("Color hexadecimal", tint);
        var colors = new WrapPanel();
        foreach (var color in new[] { "6650D8", "096B97", "AF4934", "3C714C", "515D72" }) {
            var button = MainWindow.MakeButton("●", () => tint.Text = color);
            button.Foreground = new System.Windows.Media.SolidColorBrush((System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString("#" + color));
            button.FontSize = 24; colors.Children.Add(button);
        }
        body.Children.Add(colors);
        page.ItemsSource = Enumerable.Range(1, 8); page.SelectedIndex = original.Page; Field("Página del Dock", page);
        var buttons = new WrapPanel(); buttons.Children.Add(MainWindow.MakeButton("Guardar acción", Save));
        buttons.Children.Add(MainWindow.MakeButton("Cancelar", () => DialogResult = false)); body.Children.Add(buttons);
    }
    private void Save() {
        var value = target.Text.Trim(); var color = tint.Text.Trim().TrimStart('#');
        if (string.IsNullOrWhiteSpace(title.Text) || value.Length == 0) { Notice("Escribe un nombre y un destino."); return; }
        if (color.Length != 6 || !color.All(Uri.IsHexDigit)) { Notice("Usa un color de seis dígitos, como 6650D8."); return; }
        if (kind.SelectedIndex == 0 && (!File.Exists(value) || !new[] { ".exe", ".lnk" }.Contains(Path.GetExtension(value).ToLowerInvariant()))) { Notice("Selecciona una aplicación .exe o un acceso directo .lnk existente."); return; }
        if (kind.SelectedIndex == 1 && (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme is not ("https" or "http"))) { Notice("Escribe una dirección que empiece por https:// o http://."); return; }
        Result.Title = title.Text.Trim(); Result.Target = kind.SelectedIndex == 2 ? target.Text : value;
        Result.Kind = kind.SelectedIndex == 1 ? "website" : kind.SelectedIndex == 2 ? "text" : "app";
        Result.Emoji = emoji.Text.Trim(); Result.Tint = color.ToUpperInvariant(); Result.Page = Math.Max(0, page.SelectedIndex);
        DialogResult = true;
    }
    private void Notice(string message) => MessageBox.Show(this, AppLanguage.T(message), "Phone Dock");
}
