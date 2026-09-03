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

    static func swipe(horizontal: Double, vertical: Double) -> RemoteCommand? {
        guard horizontal.isFinite, vertical.isFinite, max(abs(horizontal), abs(vertical)) >= 28 else { return nil }
        if abs(horizontal) > abs(vertical) { return .clipboard(horizontal > 0 ? .paste : .copy) }
        return .window(vertical > 0 ? .minimize : .maximize)
    }
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
