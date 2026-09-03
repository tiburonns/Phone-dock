import Foundation

struct RemoteTile: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case app
        case shortcut
        case website
        case emoji
        case system

        var title: String {
            switch self {
            case .app: localized("App")
            case .shortcut: localized("Shortcut")
            case .website: localized("Website")
            case .emoji: localized("Emoji")
            case .system: localized("System")
            }
        }
    }

    var id: UUID
    var title: String
    var subtitle: String?
    var systemImage: String
    var displayEmoji: String?
    var iconPNGData: Data?
    var tintHex: String
    var kind: Kind
    var command: RemoteCommand
    var page: Int
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        displayEmoji: String? = nil,
        iconPNGData: Data? = nil,
        tintHex: String,
        kind: Kind,
        command: RemoteCommand,
        page: Int = 0,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.displayEmoji = displayEmoji
        self.iconPNGData = iconPNGData
        self.tintHex = tintHex
        self.kind = kind
        self.command = command
        self.page = page
        self.sortOrder = sortOrder
    }
}

extension RemoteTile {
    static let starterDeck: [RemoteTile] = [
        .init(title: "Finder", subtitle: localized("Files"), systemImage: "folder.fill", tintHex: "5B8DEF", kind: .app, command: .launchApp(bundleIdentifier: "com.apple.finder"), sortOrder: 0),
        .init(title: "Safari", subtitle: localized("Browser"), systemImage: "safari.fill", tintHex: "3EA6FF", kind: .app, command: .launchApp(bundleIdentifier: "com.apple.Safari"), sortOrder: 1),
        .init(title: localized("Mail"), subtitle: localized("Inbox"), systemImage: "envelope.fill", tintHex: "587CF7", kind: .app, command: .launchApp(bundleIdentifier: "com.apple.mail"), sortOrder: 2),
        .init(title: localized("Calendar"), subtitle: localized("Today"), systemImage: "calendar", tintHex: "EC5B54", kind: .app, command: .launchApp(bundleIdentifier: "com.apple.iCal"), sortOrder: 3),
        .init(title: localized("Shortcuts"), subtitle: localized("Automations"), systemImage: "square.stack.3d.up.fill", tintHex: "9A5BF6", kind: .app, command: .launchApp(bundleIdentifier: "com.apple.shortcuts"), sortOrder: 4),
        .init(title: "OpenAI", subtitle: localized("Website"), systemImage: "globe", tintHex: "2DA77A", kind: .website, command: .openURL("https://openai.com"), sortOrder: 5),
        .init(title: localized("Clipboard"), subtitle: localized("Paste"), systemImage: "doc.on.clipboard.fill", tintHex: "E98B3A", kind: .system, command: .clipboard(.paste), sortOrder: 6),
        .init(title: "✨", subtitle: localized("Insert"), systemImage: "sparkles", tintHex: "D4A72C", kind: .emoji, command: .insertText("✨"), sortOrder: 7)
    ]
}
