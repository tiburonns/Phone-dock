using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Makaretu.Dns;
using PhoneDock.Core;
using PhoneDock.Models;
using PhoneDock.Services;

namespace PhoneDock;

public partial class MainWindow : Window, IRemoteHost
{
    private readonly LocalStore store;
    private readonly SystemController controller;
    private readonly RemoteServer server;
    private ServiceDiscovery? discovery;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(3) };
    private string selectedPage = "Inicio";
    private int dockPage;
    private TextBlock? pinLabel;
    private string serverError = "";
    private bool listening;
    private static readonly Dictionary<string, string> Palettes = new() {
        ["Aurora"] = "6650D8", ["Océano"] = "096B97", ["Atardecer"] = "AF4934", ["Bosque"] = "3C714C", ["Grafito"] = "515D72"
    };

    public MainWindow() {
        InitializeComponent();
        store = new LocalStore(); controller = new SystemController(store); server = new RemoteServer(this, store);
        server.Changed += () => Dispatcher.BeginInvoke(RefreshStatus);
        foreach (var name in new[] { "Inicio", "Mi Dock", "Dispositivos", "Apariencia", "Acerca de" }) {
            var button = MakeButton(name, () => { selectedPage = name; Render(); });
            button.Tag = name; button.HorizontalContentAlignment = HorizontalAlignment.Left; Navigation.Children.Add(button);
        }
        ApplyTheme(); Render();
        Loaded += (_, _) => StartServer();
        timer.Tick += (_, _) => RefreshStatus(); timer.Start();
        Closed += (_, _) => { timer.Stop(); discovery?.Dispose(); server.Dispose(); };
    }
    private void StartServer() {
        try {
            server.Start(); listening = true;
            try {
                discovery = new ServiceDiscovery();
                discovery.Advertise(new ServiceProfile($"Phone Dock · {Environment.MachineName}", "_cocoalift._tcp", (ushort)server.Port));
            } catch { Error("La detección automática no está disponible. Usa la dirección IP que aparece en Inicio."); }
        } catch (Exception e) { serverError = e.Message; Error(AppLanguage.F("No se pudo abrir la conexión: {0}", e.Message)); }
        Render(); RefreshStatus();
    }
    private void RefreshStatus() {
        ConnectionStatus.Text = !listening ? AppLanguage.T("Conexión detenida") : server.ConnectedCount == 0 ? AppLanguage.T("Listo para conectar") : AppLanguage.F("{0} dispositivo(s) conectado(s)", server.ConnectedCount);
        if (pinLabel != null) pinLabel.Text = server.PairingCode;
    }
    private void Render() {
        PageContent.Children.Clear(); pinLabel = null;
        StudioLabel.Text = AppLanguage.T("Tu estudio personal"); FooterLabel.Text = AppLanguage.T("WINDOWS · LOCAL · TUYO");
        DismissButton.Content = AppLanguage.T("Cerrar");
        RefreshStatus();
        foreach (Button button in Navigation.Children) {
            var key = (string)button.Tag; button.Content = AppLanguage.T(key);
            button.SetResourceReference(BackgroundProperty, key == selectedPage ? "Base" : "Surface");
            button.FontWeight = key == selectedPage ? FontWeights.Bold : FontWeights.Normal;
        }
        switch (selectedPage) {
            case "Inicio": Home(); break;
            case "Mi Dock": Dock(); break;
            case "Dispositivos": Devices(); break;
            case "Apariencia": Appearance(); break;
            default: About(); break;
        }
    }
    private void Header(string title, string detail) {
        var eyebrow = Text("●  PHONE DOCK / WINDOWS", 11); eyebrow.FontWeight = FontWeights.Bold;
        eyebrow.SetResourceReference(TextBlock.ForegroundProperty, "Accent"); PageContent.Children.Add(eyebrow);
        PageContent.Children.Add(Text(title, 32, true)); PageContent.Children.Add(Text(detail, 14, secondary: true));
    }
    private void Home() {
        Header("Tu PC, a un toque.", "Un espacio personal para tus acciones de cada día.");
        var hero = new StackPanel();
        hero.Children.Add(new Image { Source = Logo(), Width = 110, Height = 110, HorizontalAlignment = HorizontalAlignment.Left, Margin = new(0, 0, 0, 20) });
        hero.Children.Add(Text("Mejor juntos.", 24, true));
        hero.Children.Add(Text("Abre Phone Dock en tu iPhone, entra en Dispositivos y elige este PC. También puedes conectarte con su dirección IP.", 15, secondary: true));
        hero.Children.Add(MakeButton("Personalizar mi Dock", () => { selectedPage = "Mi Dock"; Render(); }));
        PageContent.Children.Add(Card(hero));
        var pairing = new StackPanel();
        pairing.Children.Add(Text("Código de enlace", 16, true));
        pinLabel = Text(server.PairingCode, 44, true); pinLabel.SetResourceReference(TextBlock.ForegroundProperty, "Accent");
        pairing.Children.Add(pinLabel); pairing.Children.Add(MakeButton("Nuevo código", server.RotatePin));
        pairing.Children.Add(Text("Caduca cada cinco minutos y después de enlazar.", 12, secondary: true));
        pairing.Children.Add(Text(AppLanguage.F("Puerto: {0}", server.Port), 14, true));
        foreach (var address in Addresses()) {
            var copy = MakeButton(AppLanguage.F("{0} · copiar", address), () => Clipboard.SetText(address)); pairing.Children.Add(copy);
        }
        if (!listening) pairing.Children.Add(Text(serverError, 14, secondary: true));
        pairing.Children.Add(Text("Al abrir por primera vez, permite Phone Dock en redes privadas en el Firewall de Windows. No abras puertos en el router.", 13, secondary: true));
        PageContent.Children.Add(Card(pairing));
    }
    private IEnumerable<string> Addresses() => NetworkInterface.GetAllNetworkInterfaces()
        .Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)
        .SelectMany(n => n.GetIPProperties().UnicastAddresses)
        .Where(a => a.Address.AddressFamily == AddressFamily.InterNetwork).Select(a => a.Address.ToString()).Distinct();
    private void Dock() {
        Header("Tu espacio. Tus acciones.", "Los cambios se comparten con tu iPhone. Haz clic en una tarjeta para personalizarla.");
        var controls = new WrapPanel();
        for (var i = 0; i < 8; i++) { var page = i; controls.Children.Add(MakeButton($"{i + 1}", () => { dockPage = page; Render(); })); }
        controls.Children.Add(MakeButton("+ Agregar acción", () => Edit(null))); PageContent.Children.Add(controls);
        PageContent.Children.Add(Text(AppLanguage.F("Página {0} · {1}/24 acciones", dockPage + 1, store.Tiles.Count), 12, secondary: true));
        var tiles = new WrapPanel();
        foreach (var tile in store.Tiles.Where(t => t.Page == dockPage)) {
            var body = new StackPanel();
            var iconSize = store.Preferences.LargeIcons ? 100 : 76;
            FrameworkElement art = !string.IsNullOrEmpty(tile.Emoji)
                ? new TextBlock { Text = tile.Emoji, FontSize = 44, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center }
                : Artwork.Decode(tile.Icon) is { } icon
                    ? new Image { Source = icon, Width = iconSize - 12, Height = iconSize - 12 }
                    : new TextBlock { Text = tile.Kind == "website" ? "↗" : "▦", FontSize = 46, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            body.Children.Add(new Border { Child = art, Width = iconSize, Height = iconSize, CornerRadius = new(24), Background = Brush("#" + tile.Tint), HorizontalAlignment = HorizontalAlignment.Center, Margin = new(0, 6, 0, 18) });
            body.Children.Add(Text(tile.Title, 16, true, translate: false)); body.Children.Add(Text(tile.Subtitle, 12, secondary: true));
            var edit = MakeButton("Personalizar", () => Edit(tile)); body.Children.Add(edit);
            var movement = new WrapPanel();
            movement.Children.Add(MakeButton("←", () => Move(tile, -1)));
            movement.Children.Add(MakeButton("→", () => Move(tile, 1)));
            movement.Children.Add(MakeButton("Quitar", () => {
                if (MessageBox.Show(AppLanguage.F("¿Quitar {0} del Dock?", tile.Title), "Phone Dock", MessageBoxButton.YesNo) != MessageBoxResult.Yes) return;
                store.Tiles.Remove(tile); SaveActions();
            })); body.Children.Add(movement);
            var card = Card(body); card.Width = 224; card.Margin = new(0, 8, 14, 8); tiles.Children.Add(card);
        }
        PageContent.Children.Add(tiles);
    }
    private void Move(ActionTile tile, int offset) {
        var page = store.Tiles.Where(t => t.Page == tile.Page).ToList(); var position = page.IndexOf(tile); var target = position + offset;
        if (target < 0 || target >= page.Count) return;
        var a = store.Tiles.IndexOf(tile); var b = store.Tiles.IndexOf(page[target]);
        (store.Tiles[a], store.Tiles[b]) = (store.Tiles[b], store.Tiles[a]); SaveActions();
    }
    private void Edit(ActionTile? tile) {
        if (tile == null && store.Tiles.Count >= 24) { Error("Esta primera versión admite hasta 24 acciones."); return; }
        var dialog = new TileEditor(tile ?? new ActionTile { Page = dockPage }) { Owner = this };
        if (dialog.ShowDialog() != true) return;
        if (tile != null) store.Tiles[store.Tiles.IndexOf(tile)] = dialog.Result;
        else store.Tiles.Add(dialog.Result);
        SaveActions();
    }
    private async void SaveActions() {
        try { store.SaveActions(); Render(); await server.BroadcastAsync(); }
        catch (Exception e) { Error(e.Message); }
    }
    private void Devices() {
        Header("Mejor juntos.", "Tus dispositivos autorizados para controlar este PC.");
        foreach (var name in store.Names) {
            var row = new StackPanel(); row.Children.Add(Text(name, 20, true, translate: false));
            row.Children.Add(Text("Credencial protegida por Windows", 13, secondary: true));
            row.Children.Add(MakeButton("Olvidar dispositivo", () => {
                if (MessageBox.Show(AppLanguage.F("¿Revocar el acceso de {0}?", name), "Phone Dock", MessageBoxButton.YesNo) == MessageBoxResult.Yes) { server.Forget(name); Render(); }
            })); PageContent.Children.Add(Card(row));
        }
        if (store.Names.Count == 0) PageContent.Children.Add(Card(Text("Todavía no hay dispositivos. Usa el código de Inicio para enlazar tu iPhone.", 16)));
        PageContent.Children.Add(MakeButton("Actualizar lista", Render));
    }
    private void Appearance() {
        Header("Hazlo tuyo.", "Un poco de color. Mucho más tú.");
        var language = new StackPanel(); language.Children.Add(Text("Idioma", 18, true));
        language.Children.Add(Text("Idioma de la app", 13, true));
        var selector = new ComboBox { ItemsSource = new[] { AppLanguage.T("Usar idioma del sistema"), "English", "Español" }, SelectedIndex = AppLanguage.Selected == "en" ? 1 : AppLanguage.Selected == "es" ? 2 : 0, Padding = new(10), MinWidth = 220, HorizontalAlignment = HorizontalAlignment.Left };
        System.Windows.Automation.AutomationProperties.SetName(selector, AppLanguage.T("Idioma de la app"));
        selector.SelectionChanged += async (_, _) => {
            var choice = selector.SelectedIndex == 1 ? "en" : selector.SelectedIndex == 2 ? "es" : "system";
            var previous = store.Preferences.Language;
            try { store.Preferences.Language = choice; store.SavePreferences(); }
            catch (Exception e) { store.Preferences.Language = previous; Error(e.Message); return; }
            AppLanguage.Selected = choice; Render();
            try { await server.BroadcastAsync(); } catch (Exception e) { Error(e.Message); }
        };
        language.Children.Add(selector);
        language.Children.Add(Text("Se aplica al instante en este PC. Tus acciones y dispositivos enlazados no cambian.", 13, secondary: true));
        PageContent.Children.Add(Card(language));
        var choices = new WrapPanel();
        foreach (var palette in Palettes) {
            var label = new StackPanel();
            label.Children.Add(new Border { Background = Brush("#" + palette.Value), Height = 42, Width = 92, CornerRadius = new(10), Margin = new(0, 0, 0, 10) });
            label.Children.Add(Text(AppLanguage.T(palette.Key) + (store.Preferences.Palette == palette.Key ? " ✓" : ""), 14, true));
            choices.Children.Add(new Button { Content = label, Command = new UIAction(() => { store.Preferences.Palette = palette.Key; SaveAppearance(); }) });
        }
        PageContent.Children.Add(Card(choices));
        var options = new StackPanel();
        options.Children.Add(Toggle("Modo oscuro", store.Preferences.Dark, v => store.Preferences.Dark = v));
        options.Children.Add(Toggle("Iconos extragrandes", store.Preferences.LargeIcons, v => store.Preferences.LargeIcons = v));
        options.Children.Add(Toggle("Esquinas suaves", store.Preferences.SoftCorners, v => store.Preferences.SoftCorners = v));
        options.Children.Add(Text("La apariencia se guarda en este PC. Tu iPhone conserva su propia paleta.", 13, secondary: true));
        PageContent.Children.Add(Card(options));
    }
    private CheckBox Toggle(string title, bool value, Action<bool> set) {
        var toggle = new CheckBox { Content = AppLanguage.T(title), IsChecked = value };
        toggle.Click += (_, _) => { set(toggle.IsChecked == true); SaveAppearance(); }; return toggle;
    }
    private void SaveAppearance() { store.SavePreferences(); ApplyTheme(); Render(); }
    private void ApplyTheme() {
        var dark = store.Preferences.Dark;
        Application.Current.Resources["Accent"] = Brush(dark ? store.Preferences.Palette switch {
            "Océano" => "#70CFFA", "Atardecer" => "#FFAE97", "Bosque" => "#9FDCAF", "Grafito" => "#B9C6E0", _ => "#B9A8FF"
        } : "#" + Palettes.GetValueOrDefault(store.Preferences.Palette, "6650D8"));
        Application.Current.Resources["Base"] = Brush(dark ? "#151823" : "#F3F4F8");
        Application.Current.Resources["Surface"] = Brush(dark ? "#222532" : "#FFFFFF");
        Application.Current.Resources["Ink"] = Brush(dark ? "#F1F2F7" : "#232737");
        Application.Current.Resources["Secondary"] = Brush(dark ? "#AFB4C6" : "#626879");
        Application.Current.Resources["Edge"] = Brush(dark ? "#45415F" : "#DFDCEF");
    }
    private void About() {
        Header("Phone Dock", "Tu PC y tu iPhone, conectados directamente.");
        var content = new StackPanel(); content.Children.Add(new Image { Source = Logo(), Width = 140, Height = 140, HorizontalAlignment = HorizontalAlignment.Left });
        content.Children.Add(Text("Local. Personal. Sin suscripciones.", 24, true));
        content.Children.Add(Text("Windows 11 · versión 0.3.1 · primera versión para pruebas", 14, secondary: true));
        content.Children.Add(Text("Brillo: pantallas compatibles con WMI, normalmente las integradas. Maximizar no equivale al modo de pantalla completa de todas las apps. Ocultar minimiza la ventana. Atajos de Apple y Recientes no están disponibles en esta versión.", 14, secondary: true));
        content.Children.Add(Text("Usa una red privada de confianza. El código protege el enlace y las órdenes se autentican. No hay nube ni telemetría propia. No se pueden controlar ventanas del sistema o aplicaciones ejecutadas como administrador.", 14, secondary: true));
        PageContent.Children.Add(Card(content));
    }
    public Task<JsonObject> StateAsync() => Dispatcher.InvokeAsync(() => { var message = Wire.Message("stateResponse"); message["state"] = controller.State(); return message; }).Task;
    public Task<JsonObject> CatalogAsync() => Dispatcher.InvokeAsync(() => {
        var message = Wire.Message("catalogResponse");
        message["catalog"] = new JsonArray(store.Tiles.Select((t, i) => (JsonNode)t.ToWire(i)).ToArray());
        message["recentApplications"] = new JsonArray(); return message;
    }).Task;
    public Task ExecuteAsync(JsonObject command) => Dispatcher.InvokeAsync(() => controller.Execute(command)).Task;
    private void Error(string message) { ErrorText.Text = AppLanguage.T(message); ErrorPanel.Visibility = Visibility.Visible; }
    private void DismissError(object sender, RoutedEventArgs e) => ErrorPanel.Visibility = Visibility.Collapsed;
    private Border Card(UIElement content) {
        var card = new Border { Child = content, CornerRadius = new(store.Preferences.SoftCorners ? 24 : 12), Padding = new(22), Margin = new(0, 14, 0, 4), BorderThickness = new(1) };
        card.SetResourceReference(Border.BackgroundProperty, "Surface"); card.SetResourceReference(Border.BorderBrushProperty, "Edge"); return card;
    }
    internal static TextBlock Text(string text, double size = 14, bool bold = false, bool secondary = false, bool translate = true) {
        var block = new TextBlock { Text = translate ? AppLanguage.T(text) : text, FontSize = size, FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal, TextWrapping = TextWrapping.Wrap, Margin = new(0, 6, 0, 10) };
        block.SetResourceReference(TextBlock.ForegroundProperty, secondary ? "Secondary" : "Ink"); return block;
    }
    internal static Button MakeButton(string text, Action action) { var button = new Button { Content = AppLanguage.T(text) }; button.Click += (_, _) => action(); return button; }
    private static SolidColorBrush Brush(string color) => new((Color)ColorConverter.ConvertFromString(color));
    private static BitmapImage Logo() => new(new Uri("pack://application:,,,/Assets/BrandIcon.png"));
    private sealed class UIAction(Action action) : System.Windows.Input.ICommand {
        public event EventHandler? CanExecuteChanged { add { } remove { } }
        public bool CanExecute(object? parameter) => true;
        public void Execute(object? parameter) => action();
    }
}
