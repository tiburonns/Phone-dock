import SwiftUI

struct AddTileSheet: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var catalog: CatalogStore
    let page: Int
    @State private var kind: RemoteTile.Kind = .app
    @State private var title = ""
    @State private var value = ""
    @State private var emoji = "✨"
    @State private var bundleIdentifier = ""
    @State private var iconPNGData: Data?
    @State private var isAdding = false
    @State private var tintHex = "6650D8"

    var body: some View {
        let _ = appLocale
        VStack(alignment: .leading, spacing: 20) {
            Text("Add an action").font(.title.bold())
            Picker("Type", selection: $kind) {
                ForEach(RemoteTile.Kind.allCases.filter { $0 != .system }, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Form {
                TextField("Name", text: $title)
                switch kind {
                case .app:
                    HStack {
                        TextField("Bundle identifier", text: $bundleIdentifier)
                        Button("Choose App…") {
                            if let app = catalog.selectApplication() {
                                title = app.name
                                bundleIdentifier = app.bundleIdentifier
                                iconPNGData = app.iconPNGData
                            }
                        }
                    }
                case .shortcut:
                    shortcutPicker
                    TextField("Icon emoji", text: $emoji)
                case .website:
                    TextField("https://example.com", text: $value)
                case .emoji:
                    TextField("Emoji or text", text: $emoji)
                case .system:
                    EmptyView()
                }
                TileColorPicker(selection: $tintHex)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { add() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid || isAdding)
            }
        }
        .padding(28)
        .frame(width: 570)
        .task(id: kind) {
            guard kind == .shortcut else { return }
            await catalog.loadShortcuts()
        }
        .onChange(of: value) { _, selected in
            if kind == .shortcut, title.isEmpty { title = selected }
        }
    }

    private var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return switch kind {
        case .app: !bundleIdentifier.isEmpty
        case .shortcut, .website: !value.isEmpty
        case .emoji: !emoji.isEmpty
        case .system: false
        }
    }

    private func add() {
        isAdding = true
        Task { @MainActor in
            let websiteIcon: Data?
            if kind == .website {
                websiteIcon = await catalog.faviconData(for: value)
            } else {
                websiteIcon = nil
            }
            createTile(iconPNGData: kind == .app ? iconPNGData : websiteIcon)
            dismiss()
        }
    }

    private func createTile(iconPNGData: Data?) {
        let command: RemoteCommand
        let image: String
        switch kind {
        case .app:
            command = .launchApp(bundleIdentifier: bundleIdentifier)
            image = "app.fill"
        case .shortcut:
            command = .runShortcut(value)
            image = "square.stack.3d.up.fill"
        case .website:
            let normalized = value.contains("://") ? value : "https://\(value)"
            command = .openURL(normalized)
            image = "globe"
        case .emoji:
            command = .insertText(emoji)
            image = "face.smiling.fill"
        case .system:
            return
        }
        let displayEmoji: String? = switch kind {
        case .shortcut, .emoji: emoji.isEmpty ? nil : String(emoji.prefix(2))
        default: nil
        }
        catalog.add(.init(
            title: title,
            subtitle: kind.title,
            systemImage: image,
            displayEmoji: displayEmoji,
            iconPNGData: iconPNGData,
            tintHex: tintHex,
            kind: kind,
            command: command,
            page: page
        ))
    }

    @ViewBuilder
    private var shortcutPicker: some View {
        switch catalog.shortcutLoadState {
        case .idle, .loading:
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading Shortcuts…").foregroundStyle(.secondary)
            }
        case .loaded(let shortcuts):
            if shortcuts.isEmpty {
                TextField("Shortcut name", text: $value)
            } else {
                HStack {
                    Picker("Shortcut", selection: $value) {
                        Text("Choose a Shortcut").tag("")
                        ForEach(shortcuts, id: \.self) { shortcut in
                            Text(shortcut).tag(shortcut)
                        }
                    }
                    Button { Task { await catalog.loadShortcuts(force: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reload Shortcuts")
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                TextField("Shortcut name", text: $value)
                Text(message).font(.caption).foregroundStyle(.red)
                Button("Try Again") { Task { await catalog.loadShortcuts(force: true) } }
            }
        }
    }
}
