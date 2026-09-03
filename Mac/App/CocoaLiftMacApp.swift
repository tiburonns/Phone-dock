import AppKit
import SwiftUI

final class CocoaLiftAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct CocoaLiftMacApp: App {
    @NSApplicationDelegateAdaptor(CocoaLiftAppDelegate.self) private var appDelegate
    @StateObject private var catalog: CatalogStore
    @StateObject private var server: MacRemoteServer
    @AppStorage(AppLanguage.preferenceKey) private var language: AppLanguage = .system
    private let controller: SystemController

    init() {
        let catalog = CatalogStore()
        let controller = SystemController()
        _catalog = StateObject(wrappedValue: catalog)
        _server = StateObject(wrappedValue: MacRemoteServer(catalog: catalog, controller: controller))
        self.controller = controller
    }

    var body: some Scene {
        WindowGroup("Phone Dock", id: "main") {
            MacRootView(controller: controller)
                .environmentObject(catalog)
                .environmentObject(server)
                .dockAppearance()
                .dockLanguage()
                .frame(minWidth: 860, minHeight: 600)
                .task { server.start() }
        }
        .defaultSize(width: 1120, height: 780)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(language.translate("Rotate Pairing Code")) { server.rotatePairingCode() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("Phone Dock", systemImage: "square.grid.3x3.square") {
            MacMenuBarView()
                .environmentObject(server)
                .dockAppearance()
                .dockLanguage()
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView(controller: controller)
                .environmentObject(server)
                .dockAppearance()
                .dockLanguage()
        }
    }
}
