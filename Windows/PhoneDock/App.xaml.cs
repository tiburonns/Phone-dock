using System.Windows;
using System.Security.Cryptography;
using PhoneDock.Core;

namespace PhoneDock;
public partial class App : Application
{
    private Mutex? instance;
    protected override void OnStartup(StartupEventArgs e) {
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22000) || !ChaCha20Poly1305.IsSupported) {
            MessageBox.Show(AppLanguage.T("Esta versión de Phone Dock requiere Windows 11 para el emparejamiento seguro."), "Phone Dock"); Shutdown(); return;
        }
        DispatcherUnhandledException += (_, args) => {
            MessageBox.Show(AppLanguage.T(args.Exception.Message), "Phone Dock", MessageBoxButton.OK, MessageBoxImage.Warning);
            args.Handled = true;
        };
        base.OnStartup(e);
        instance = new Mutex(true, @"Local\PhoneDock-" + Environment.UserName, out var first);
        if (!first) { MessageBox.Show(AppLanguage.T("Phone Dock ya está abierto. Busca su ventana en la barra de tareas."), "Phone Dock"); Shutdown(); return; }
        try { new MainWindow().Show(); }
        catch (Exception error) { MessageBox.Show(AppLanguage.F("No se pudo iniciar Phone Dock. Tus archivos se conservaron.\n\n{0}", error.Message), "Phone Dock"); Shutdown(1); }
    }
    protected override void OnExit(ExitEventArgs e) { instance?.Dispose(); base.OnExit(e); }
}
