import SwiftUI

struct MobileSettingsView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @EnvironmentObject private var connection: MobileConnectionStore
    @State private var showingFeedback = false

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
                    Label(localized("Support & Feedback"), systemImage: "bubble.left.and.bubble.right").font(.headline)
                    Text(localized("Questions, suggestions, bug reports, and general feedback can be prepared here and reviewed in GitHub before publishing."))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button {
                        showingFeedback = true
                    } label: {
                        Label(localized("Contact / Send feedback"), systemImage: "paperplane")
                    }
                    Link(
                        localized("Open GitHub Issues"),
                        destination: URL(string: "https://github.com/tiburonns/Phone-dock/issues")!
                    )
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
            }
            .padding(18)
        }
        .dockBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingFeedback) {
            NavigationStack {
                PhoneDockMobileFeedbackView()
            }
        }
    }
}


private struct PhoneDockMobileFeedbackView: View {
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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var category = Category.question
    @State private var message = ""

    var body: some View {
        Form {
            Section(localized("Type")) {
                Picker(localized("Category"), selection: $category) {
                    ForEach(Category.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }

            Section(localized("Message")) {
                TextEditor(text: $message)
                    .frame(minHeight: 160)

                Text(localized("Do not include passwords, pairing codes, private addresses, or other sensitive information."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    submit()
                } label: {
                    Label(localized("Open in GitHub"), systemImage: "paperplane.fill")
                }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text(localized("GitHub will open so you can review and publish the report yourself."))
            }
        }
        .navigationTitle(localized("Feedback"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(localized("Cancel")) { dismiss() }
            }
        }
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
            URLQueryItem(name: "title", value: "[iPhone/iPad][\(category.issuePrefix)] "),
            URLQueryItem(
                name: "body",
                value: """
                \(message)

                ---
                App: Phone Dock
                Platform: iPhone/iPad
                Version: \(appVersion)
                """
            )
        ]
        if let url = components.url { openURL(url) }
    }
}
