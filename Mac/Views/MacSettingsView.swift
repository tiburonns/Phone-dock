import SwiftUI

struct MacSettingsView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @EnvironmentObject private var server: MacRemoteServer
    @State private var feedbackMessage = ""
    @AppStorage("launchServerAutomatically") private var launchServerAutomatically = true
    let controller: SystemController

    var body: some View {
        let _ = appLocale
        TabView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DockHeader(eyebrow: "PHONE DOCK / PERSONALIZE", title: localized("Make yourself at home."),
                               subtitle: localized("A little color. A lot more you."))
                    LanguageControls()
                    AppearanceControls()
                }.padding(24)
            }
            .dockBackground()
            .tabItem { Label("Appearance", systemImage: "paintpalette") }
            connectionSettings
                .tabItem { Label("Connection", systemImage: "wifi") }
        }
        .frame(width: 620, height: 700)
    }

    private var connectionSettings: some View {
        Form {
            Section("Connection") {
                Toggle("Accept local connections", isOn: Binding(
                    get: { server.status != .stopped },
                    set: { $0 ? server.start() : server.stop() }
                ))
                Toggle("Start connection service at launch", isOn: $launchServerAutomatically)
                LabeledContent("Bonjour", value: server.advertisedServiceName ?? localized("Waiting for permission"))
                if let address = server.manualConnectionAddress {
                    LabeledContent("Manual address", value: address)
                        .textSelection(.enabled)
                }
            }
            Section("Mac permissions") {
                Text("Accessibility is only needed for copy, paste, text insertion and window controls.")
                    .foregroundStyle(.secondary)
                Button("Request Accessibility Access") { controller.requestAccessibilityPermission() }
            }
            Section("Privacy") {
                Label("Local network only", systemImage: "lock.shield")
                Text("Pairing secrets are stored in Keychain on both devices.")
                    .foregroundStyle(.secondary)
            }
            Section(localized("Bugs, comments & suggestions")) {
                TextField(localized("Describe your report"), text: $feedbackMessage, axis: .vertical)
                Button(localized("Continue in email"), action: sendFeedback)
                    .disabled(feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text(localized("Your email app opens a draft. Review and send it there."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .scrollContentBackground(.hidden)
        .dockBackground()
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
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
}
