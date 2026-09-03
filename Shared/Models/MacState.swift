import Foundation

struct MacState: Codable, Equatable, Sendable {
    var volume: Double
    var isMuted: Bool
    var brightness: Double?
    var frontmostApplication: String?

    static let placeholder = MacState(volume: 0.5, isMuted: false, brightness: 0.7, frontmostApplication: nil)
}

struct RecentApplication: Identifiable, Codable, Hashable, Sendable {
    var id: String { bundleIdentifier }
    let name: String
    let bundleIdentifier: String
    let lastOpenedAt: Date
    let isPinned: Bool
    var iconPNGData: Data?

    init(name: String, bundleIdentifier: String, lastOpenedAt: Date, isPinned: Bool = false, iconPNGData: Data? = nil) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.lastOpenedAt = lastOpenedAt
        self.isPinned = isPinned
        self.iconPNGData = iconPNGData
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case bundleIdentifier
        case lastOpenedAt
        case isPinned
        case iconPNGData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        lastOpenedAt = try container.decode(Date.self, forKey: .lastOpenedAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        iconPNGData = try container.decodeIfPresent(Data.self, forKey: .iconPNGData)
    }
}
