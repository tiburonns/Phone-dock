import Foundation

enum RemoteCommand: Codable, Equatable, Hashable, Sendable {
    case launchApp(bundleIdentifier: String)
    case openURL(String)
    case runShortcut(String)
    case insertText(String)
    case setVolume(Double)
    case setMuted(Bool)
    case setBrightness(Double)
    case setRecentAppPinned(bundleIdentifier: String, pinned: Bool)
    case window(WindowCommand)
    case clipboard(ClipboardCommand)
}

enum WindowCommand: String, Codable, CaseIterable, Hashable, Sendable {
    case minimize
    case maximize
    case hide
}

enum ClipboardCommand: String, Codable, CaseIterable, Hashable, Sendable {
    case copy
    case paste
}
