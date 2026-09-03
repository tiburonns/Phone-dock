import SwiftUI

struct MacOverviewView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    @EnvironmentObject private var server: MacRemoteServer
    @EnvironmentObject private var catalog: CatalogStore
    var openDock: () -> Void = {}
    var openDevices: () -> Void = {}

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 16)]

    var body: some View {
        let _ = appLocale
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 24) {
                    Image("BrandIcon").resizable().frame(width: 116, height: 116)
                        .clipShape(RoundedRectangle(cornerRadius: 30))
                    DockHeader(eyebrow: "PHONE DOCK / STUDIO", title: localized("Your Mac, within reach."),
                               subtitle: localized("A personal space for your everyday actions."))
                }
                HStack(spacing: 12) {
                    Button(action: openDock) { Label("Customize my Dock", systemImage: "square.grid.2x2") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    Button(action: openDevices) { Label("Devices", systemImage: "iphone") }
                        .buttonStyle(.bordered).controlSize(.large)
                    Spacer(minLength: 0)
                    ConnectionPill(
                        connected: server.connectedDeviceCount > 0,
                        text: localizedFormat("%d connected", server.connectedDeviceCount)
                    )
                }

                PairingCard()

                LazyVGrid(columns: columns, spacing: 16) {
                    FeatureCard(title: localized("My Dock"), value: localizedFormat("%d actions", catalog.tiles.count), symbol: "square.grid.3x3.fill", tint: style.accent)
                    FeatureCard(title: localized("Private by design"), value: localized("Local network only"), symbol: "lock.shield.fill", tint: style.accent)
                    FeatureCard(title: localized("Always free"), value: localized("No subscriptions"), symbol: "heart.fill", tint: style.accent)
                }

                if !catalog.recentApplications.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recently opened").font(.title2.bold())
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(catalog.recentApplications) { app in
                                    VStack(spacing: 10) {
                                        TileArtwork(tile: .init(title: app.name, systemImage: "app.fill", iconPNGData: app.iconPNGData,
                                            tintHex: "6650D8", kind: .app, command: .launchApp(bundleIdentifier: app.bundleIdentifier)), size: 64)
                                        Text(app.name).font(.caption.weight(.medium)).lineLimit(1)
                                    }
                                    .frame(width: 110).padding(14).dockPanel()
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .dockBackground()
        .navigationTitle("Overview")
    }
}

private struct PairingCard: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    @EnvironmentObject private var server: MacRemoteServer

    var body: some View {
        let _ = appLocale
        VStack(alignment: .leading, spacing: 22) {
          HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(style.accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(style.accent)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Pair a device").font(.title2.bold())
                Text("Open Phone Dock on iPhone, choose this Mac, and enter the rotating code.")
                    .foregroundStyle(.secondary)
                Text(server.advertisedServiceName == nil && server.status.isReady ? localized("Waiting for Bonjour permission…") : server.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(server.advertisedServiceName != nil ? .green : .secondary)
                if let address = server.manualConnectionAddress {
                    Text(localizedFormat("Manual address: %@", address))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
          }
          Divider().overlay(style.border)
          HStack {
            Label("Pairing code", systemImage: "lock.rotation").font(.headline)
            Spacer()
            Text(server.pairingCode)
                .font(.system(size: 35, weight: .bold, design: .rounded))
                .monospacedDigit()
                .tracking(5)
                .foregroundStyle(style.accent)
                .accessibilityLabel(localizedFormat("Pairing code %@", server.pairingCode))
            Button { server.rotatePairingCode() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Rotate pairing code")
          }
        }
        .padding(24)
        .dockPanel()
    }
}

private extension MacRemoteServer.Status {
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

private struct FeatureCard: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        let _ = appLocale
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(style.isDark ? style.base : .white)
                .frame(width: 46, height: 46)
                .background(tint, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(value).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .dockPanel()
    }
}
