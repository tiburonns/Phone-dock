import SwiftUI

enum MacSection: String, CaseIterable, Identifiable {
    case overview
    case bar
    case devices
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: localized("Overview")
        case .bar: localized("My Dock")
        case .devices: localized("Devices")
        case .about: localized("About")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "sparkles"
        case .bar: "square.grid.3x3.fill"
        case .devices: "iphone.and.arrow.forward"
        case .about: "info.circle"
        }
    }
}

struct MacRootView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    @EnvironmentObject private var server: MacRemoteServer
    @State private var selection: MacSection? = .overview
    let controller: SystemController

    var body: some View {
        let _ = appLocale
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image("BrandIcon").resizable().frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Phone Dock").font(.system(.headline, design: .rounded))
                        Text("Your personal studio").font(.caption).foregroundStyle(style.secondary)
                    }
                }.padding(.horizontal, 16).padding(.top, 18)
                List(MacSection.allCases, selection: $selection) { section in
                    Label(section.title, systemImage: section.symbol)
                        .font(.system(.body, design: .rounded)).padding(.vertical, 5)
                        .tag(section)
                }
                .listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 12) {
                    ConnectionPill(connected: server.connectedDeviceCount > 0,
                        text: server.connectedDeviceCount > 0 ? localized("Live") : localized("Ready to connect"))
                    SettingsLink { Label("Make it yours", systemImage: "paintpalette") }
                        .buttonStyle(.plain).foregroundStyle(style.accent)
                }.padding(18)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
            .navigationTitle("Phone Dock")
        } detail: {
            switch selection ?? .overview {
            case .overview:
                MacOverviewView(openDock: { selection = .bar }, openDevices: { selection = .devices })
            case .bar:
                BarEditorView()
            case .devices:
                DevicesView()
            case .about:
                AboutView()
            }
        }
        .tint(style.accent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}
