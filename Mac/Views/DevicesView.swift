import SwiftUI

struct DevicesView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    @EnvironmentObject private var server: MacRemoteServer

    var body: some View {
        let _ = appLocale
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DockHeader(eyebrow: "PHONE DOCK / CONNECT", title: localized("Better together."),
                           subtitle: localized("Your Mac and your phone. A direct connection."))
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Label("Pairing code", systemImage: "lock.rotation").font(.headline)
                        Spacer()
                        Button { server.rotatePairingCode() } label: { Image(systemName: "arrow.clockwise") }
                            .help("Rotate pairing code")
                    }
                    Text(server.pairingCode)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .tracking(8).monospacedDigit().foregroundStyle(style.accent)
                        .textSelection(.enabled)
                    Text("Rotates after each pairing and every five minutes.")
                        .font(.subheadline).foregroundStyle(style.secondary)
                    if let address = server.manualConnectionAddress {
                        Divider()
                        LabeledContent("Manual address", value: address)
                            .font(.callout.monospaced()).textSelection(.enabled)
                    }
                }
                .padding(24).dockPanel()

                VStack(alignment: .leading, spacing: 18) {
                    Label("Remembered devices", systemImage: "laptopcomputer.and.iphone")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    if server.pairedDevices.isEmpty {
                        ContentUnavailableView("No paired devices", systemImage: "iphone.slash",
                            description: Text("Pair from Phone Dock on your iPhone or iPad."))
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        ForEach(server.pairedDevices, id: \.self) { device in
                            HStack(spacing: 16) {
                                Image(systemName: "iphone")
                                    .font(.system(size: 32, weight: .medium)).foregroundStyle(style.accent)
                                    .frame(width: 68, height: 68)
                                    .background(style.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(device).font(.headline)
                                    Text("Remembered").font(.caption).foregroundStyle(style.secondary)
                                }
                                Spacer()
                                Button("Forget", role: .destructive) { server.forgetDevice(device) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(24).dockPanel()
                Label("Commands stay on your local network", systemImage: "lock.shield.fill")
                    .font(.subheadline).foregroundStyle(style.secondary).padding(.horizontal, 6)
            }.padding(28)
        }
        .dockBackground().navigationTitle("Devices")
    }
}
