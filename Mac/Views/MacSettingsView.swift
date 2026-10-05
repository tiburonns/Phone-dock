import SwiftUI

struct MacSettingsView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @EnvironmentObject private var server: MacRemoteServer
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
            supportSettings
                .tabItem { Label(localized("Support"), systemImage: "bubble.left.and.bubble.right") }
        }
        .frame(width: 620, height: 700)
    }

    private var supportSettings: some View {
        PhoneDockMacFeedbackView()
            .padding()
            .dockBackground()
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
        }
        .formStyle(.grouped)
        .padding()
        .scrollContentBackground(.hidden)
        .dockBackground()
    }
}


private struct PhoneDockMacFeedbackView: View {
    private enum Category: String, CaseIterable, Identifiable {
        case question, suggestion, bug, feedback
        var id: String { rawValue }

        var title: String {
            switch self {
            case .question: localized("Question")
            case .suggestion: localized("Suggestion")
            case .bug: localized("Bug / Error")
            case .feedback: localized("General feedback")
            }
        }

        var issuePrefix: String {
            switch self {
            case .question: "Question"
            case .suggestion: "Suggestion"
            case .bug: "Bug"
            case .feedback: "Feedback"
            }
        }
    }

    @Environment(\.openURL) private var openURL
    @State private var category = Category.question
    @State private var message = ""

    var body: some View {
        Form {
            Section(localized("Support & Feedback")) {
                Picker(localized("Category"), selection: $category) {
                    ForEach(Category.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                TextEditor(text: $message)
                    .frame(minHeight: 180)

                Text(localized("Do not include passwords, pairing codes, private addresses, or other sensitive information."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    submit()
                } label: {
                    Label(localized("Open in GitHub"), systemImage: "paperplane.fill")
                }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Link(
                    localized("Open GitHub Issues"),
                    destination: URL(string: "https://github.com/tiburonns/Phone-dock/issues")!
                )
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func submit() {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/tiburonns/Phone-dock/issues/new"
        components.queryItems = [
            URLQueryItem(name: "title", value: "[macOS][\(category.issuePrefix)] "),
            URLQueryItem(
                name: "body",
                value: """
                \(message)

                ---
                App: Phone Dock
                Platform: macOS
                Version: \(appVersion)
                """
            )
        ]
        if let url = components.url { openURL(url) }
    }
}
