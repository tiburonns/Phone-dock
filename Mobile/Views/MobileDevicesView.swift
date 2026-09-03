import SwiftUI

struct MobileDevicesView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    @EnvironmentObject private var connection: MobileConnectionStore
    @State private var pairingMac: DiscoveredMac?
    @State private var isShowingManualConnection = false

    var body: some View {
        let _ = appLocale
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            DockHeader(eyebrow: "03 / PHONE DOCK", title: localized("Better together."),
                       subtitle: localized("Your Mac and your phone. A direct connection."))
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ConnectionPill(connected: connection.isConnected, text: connection.status.title)
                    Spacer()
                    if connection.isConnected { Button("Disconnect") { connection.disconnect() } }
                }
            }
            .padding(20).dockPanel()
            VStack(alignment: .leading, spacing: 16) {
                Label("Nearby Macs", systemImage: "dot.radiowaves.left.and.right").font(.headline)
                if connection.discoveredMacs.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Searching on the local network…").foregroundStyle(.secondary)
                    }
                }
                ForEach(connection.discoveredMacs) { mac in
                    Button {
                        if connection.isRemembered(mac) { connection.connect(to: mac) }
                        else { pairingMac = mac }
                    } label: {
                        HStack {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundStyle(style.accent)
                                .frame(width: 64, height: 64)
                                .background(style.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                            VStack(alignment: .leading) {
                                Text(mac.name).foregroundStyle(.primary)
                                Text(connection.isRemembered(mac) ? localized("Remembered") : localized("Pair with code"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    if connection.isRemembered(mac) {
                        Button("Forget", role: .destructive) { connection.forget(mac) }
                            .font(.caption)
                    }
                }
            }
            .padding(20).dockPanel()
            VStack(alignment: .leading, spacing: 16) {
                Label("Local network only", systemImage: "lock.shield").font(.headline)
                Text("Both devices must be on the same Wi‑Fi or local network. Phone Dock does not use a cloud relay.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Connect with address…") { isShowingManualConnection = true }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding(20).dockPanel()
          }
          .padding(18)
        }
        .dockBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pairingMac) { mac in
            PairingSheet(mac: mac)
                .environmentObject(connection)
        }
        .sheet(isPresented: $isShowingManualConnection) {
            ManualConnectionSheet()
                .environmentObject(connection)
        }
    }
}

private struct ManualConnectionSheet: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connection: MobileConnectionStore
    @State private var host = ""
    @State private var port = ""
    @State private var code = ""

    var body: some View {
        let _ = appLocale
        NavigationStack {
            Form {
                Section("Mac address") {
                    TextField("MacBook.local", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                }
                Section("Pairing code") {
                    TextField("000000", text: $code)
                        .keyboardType(.numberPad)
                        .monospacedDigit()
                        .onChange(of: code) { _, newValue in
                            code = String(newValue.filter(\.isNumber).prefix(6))
                        }
                }
                Section {
                    Text("The Mac app shows its manual address directly below the pairing code.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Manual Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        guard let portValue = UInt16(port) else { return }
                        connection.pairManually(host: host, port: portValue, code: code)
                        dismiss()
                    }
                    .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || UInt16(port) == nil || code.count != 6)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct PairingSheet: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connection: MobileConnectionStore
    let mac: DiscoveredMac
    @State private var code = ""

    var body: some View {
        let _ = appLocale
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 54))
                    .foregroundStyle(style.accent)
                VStack(spacing: 7) {
                    Text(localizedFormat("Pair with %@", mac.name)).font(.title2.bold())
                    Text("Enter the six-digit code shown in Phone Dock on your Mac.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                TextField("000000", text: $code)
                    .keyboardType(.numberPad)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(8)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: code) { _, newValue in
                        code = String(newValue.filter(\.isNumber).prefix(6))
                    }
                Button("Connect") {
                    connection.pair(with: mac, code: code)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(style.accent)
                .controlSize(.large)
                .disabled(code.count != 6)
                Spacer()
            }
            .padding(28)
            .navigationTitle("Pairing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
