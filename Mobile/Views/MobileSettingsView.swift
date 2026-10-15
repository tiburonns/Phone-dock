import SwiftUI

struct MobileSettingsView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @EnvironmentObject private var connection: MobileConnectionStore
    @State private var feedbackMessage = ""

    var body: some View {
        let _ = appLocale
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DockHeader(eyebrow: "04 / PHONE DOCK", title: localized("Make yourself at home."),
                           subtitle: localized("A little color. A lot more you."))
                LanguageControls()
                AppearanceControls()
                VStack(alignment: .leading, spacing: 14) {
                    Label("Connection", systemImage: "wifi").font(.headline)
                    LabeledContent("Status", value: connection.status.title)
                    LabeledContent("Protocol", value: "v\(connection.negotiatedProtocolVersion ?? WireMessage.protocolVersion)")
                    if let lastConnectedAt = connection.lastConnectedAt {
                        LabeledContent("Last connected", value: lastConnectedAt.formatted(date: .abbreviated, time: .standard))
                    }
                    if connection.reconnectAttempt > 0 {
                        LabeledContent("Reconnect attempt", value: "\(connection.reconnectAttempt)")
                    }
                    if let lastKeyRotationAt = connection.lastKeyRotationAt {
                        LabeledContent("Key rotated", value: lastKeyRotationAt.formatted(date: .abbreviated, time: .standard))
                    }
                    if let lastError = connection.lastError {
                        Text(lastError).font(.footnote).foregroundStyle(.red)
                    }
                    if connection.isConnected {
                        Button("Refresh Mac data") { connection.refresh() }
                        Button("Rotate pairing key", systemImage: "key.horizontal") { connection.rotatePairingKey() }
                        Button("Disconnect", role: .destructive) { connection.disconnect() }
                    }
                }
                .padding(20).dockPanel()
                VStack(alignment: .leading, spacing: 14) {
                    Label("Private by design", systemImage: "lock.shield.fill").font(.headline)
                    Text("No accounts. No analytics. No subscriptions. Commands travel directly between your Apple devices on the local network.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Divider()
                    Text("Phone Dock uses hardware brightness when macOS exposes it. On unsupported external displays it falls back to software dimming on the main display.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20).dockPanel()
                VStack(alignment: .leading, spacing: 12) {
                    Label(localized("Bugs, comments & suggestions"), systemImage: "bubble.left.and.bubble.right")
                        .font(.headline)
                    TextField(localized("Describe your report"), text: $feedbackMessage, axis: .vertical)
                        .lineLimit(4...8)
                    Button(localized("Continue in email"), action: sendFeedback)
                        .disabled(feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text(localized("Your email app opens a draft. Review and send it there."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20).dockPanel()
            }
            .padding(18)
        }
        .dockBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendFeedback() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "adrianbarcenasm37@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "[Phone Dock] Feedback"),
            URLQueryItem(name: "body", value: "\(feedbackMessage)\n\nPhone Dock \(version)")
        ]
        if let url = components.url { UIApplication.shared.open(url) }
    }
}
