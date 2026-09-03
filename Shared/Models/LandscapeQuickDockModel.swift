import Foundation

enum LandscapePanel: Int, CaseIterable {
    case emojis
    case dock
    case actions

    var title: String {
        switch self {
        case .emojis: localized("Frequently used")
        case .dock: localized("Quick Dock")
        case .actions: localized("Quick actions")
        }
    }
}

enum LandscapeEmojiRanking {
    static let defaults = [
        "😂", "❤️", "🤣", "👍", "😭", "🙏", "😘", "🥰",
        "😍", "😊", "🔥", "✨", "🎉", "😁", "💕", "👌",
        "🤗", "😎", "🤔", "👏", "🙌", "💯", "🎂", "✅"
    ]

    static func ranked(counts: [String: Int]) -> [String] {
        defaults.enumerated().sorted { lhs, rhs in
            let leftCount = counts[lhs.element, default: 0]
            let rightCount = counts[rhs.element, default: 0]
            return leftCount == rightCount ? lhs.offset < rhs.offset : leftCount > rightCount
        }.map(\.element)
    }
}
