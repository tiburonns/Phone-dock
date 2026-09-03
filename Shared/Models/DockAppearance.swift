import Foundation

enum DockPalette: String, CaseIterable, Identifiable, Codable {
    case aurora, ocean, sunset, forest, graphite
    var id: String { rawValue }
    var title: String { localized(rawValue.capitalized) }
    var lightAccent: String {
        switch self {
        case .aurora: "6650D8"
        case .ocean: "096B97"
        case .sunset: "AF4934"
        case .forest: "3C714C"
        case .graphite: "515D72"
        }
    }
    var darkAccent: String {
        switch self {
        case .aurora: "B6A7FF"
        case .ocean: "75CFF5"
        case .sunset: "FFB19A"
        case .forest: "9CD4AE"
        case .graphite: "C0CBDD"
        }
    }
    var companion: String {
        switch self {
        case .aurora: "56BDA8"
        case .ocean: "D9AE66"
        case .sunset: "BF97DC"
        case .forest: "C5B372"
        case .graphite: "A69ABB"
        }
    }
}

enum DockIconSize: String, CaseIterable, Identifiable {
    case large, extraLarge
    var id: String { rawValue }
    var points: Double { self == .large ? 76 : 100 }
    var title: String { localized(self == .large ? "Large" : "Extra large") }
}

enum DockCardShape: String, CaseIterable, Identifiable {
    case soft, crisp
    var id: String { rawValue }
    var radius: Double { self == .soft ? 28 : 14 }
    var title: String { localized(self == .soft ? "Soft" : "Crisp") }
}

enum DockColorMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { localized(rawValue.capitalized) }
}

enum DockPreferenceKey {
    static let palette = "phonedock.appearance.palette"
    static let iconSize = "phonedock.appearance.iconSize"
    static let cardShape = "phonedock.appearance.cardShape"
    static let colorMode = "phonedock.appearance.colorMode"
    static let showSubtitles = "phonedock.appearance.showSubtitles"
    static let originalColors = "phonedock.appearance.originalColors"
    static let haptics = "phonedock.appearance.haptics"
    static let landscapeEmojiCounts = "phonedock.landscape.emojiCounts"
}
