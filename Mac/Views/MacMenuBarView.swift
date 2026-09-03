import AppKit
import SwiftUI

struct MacMenuBarView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    @EnvironmentObject private var server: MacRemoteServer
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = appLocale
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image("BrandIcon").resizable().frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phone Dock").font(.system(.headline, design: .rounded))
                    Text(server.status.title).font(.caption).foregroundStyle(style.secondary).lineLimit(2)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Pairing code").font(.caption.weight(.semibold))
                    Spacer()
                    Button { server.rotatePairingCode() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help("New pairing code")
                }
                Text(server.pairingCode).font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit().tracking(5).foregroundStyle(style.accent)
                ConnectionPill(connected: server.connectedDeviceCount > 0,
                               text: localizedFormat("%d connected", server.connectedDeviceCount))
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).dockPanel()
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Phone Dock", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            HStack {
                SettingsLink { Label("Appearance", systemImage: "paintpalette") }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.plain).font(.caption).foregroundStyle(style.secondary)
        }
        .padding(20).frame(width: 320).dockBackground()
    }
}
