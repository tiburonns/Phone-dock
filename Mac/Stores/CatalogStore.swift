import AppKit
import Foundation

@MainActor
final class CatalogStore: ObservableObject {
    enum ShortcutLoadState: Equatable {
        case idle
        case loading
        case loaded([String])
        case failed(String)
    }

    @Published private(set) var tiles: [RemoteTile] = []
    @Published private(set) var recentApplications: [RecentApplication] = []
    @Published private(set) var shortcutLoadState: ShortcutLoadState = .idle

    private let defaults: UserDefaults
    private let catalogKey = "cocoalift.catalog.v1"
    private let recentApplicationsKey = "cocoalift.recentApplications.v1"
    private var activationObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: catalogKey),
           let decoded = try? JSONDecoder().decode([RemoteTile].self, from: data) {
            tiles = decoded
        } else {
            tiles = RemoteTile.starterDeck
        }
        if let data = defaults.data(forKey: recentApplicationsKey),
           let decoded = try? JSONDecoder().decode([RecentApplication].self, from: data) {
            recentApplications = Self.sortedRecent(decoded)
        }
        // Enrich existing actions without replacing IDs, commands, or user artwork.
        for index in tiles.indices where tiles[index].iconPNGData == nil {
            if case .launchApp(let identifier) = tiles[index].command {
                tiles[index].iconPNGData = Self.applicationIcon(identifier)
            }
        }
        for index in recentApplications.indices where recentApplications[index].iconPNGData == nil {
            recentApplications[index].iconPNGData = Self.applicationIcon(recentApplications[index].bundleIdentifier)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let identifier = app.bundleIdentifier,
                  let name = app.localizedName else { return }
            Task { @MainActor in self?.recordRecent(name: name, bundleIdentifier: identifier) }
        }
    }

    deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    func add(_ tile: RemoteTile) {
        var tile = tile
        tile.sortOrder = tiles.filter { $0.page == tile.page }.count
        tiles.append(tile)
        save()
    }

    func remove(_ tile: RemoteTile) {
        tiles.removeAll { $0.id == tile.id }
        normalizeOrder(page: tile.page)
        save()
    }

    func update(_ tile: RemoteTile) {
        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        // Appearance editing must never move an action or alter what it executes.
        tiles[index].title = tile.title
        tiles[index].subtitle = tile.subtitle
        tiles[index].displayEmoji = tile.displayEmoji
        tiles[index].iconPNGData = tile.iconPNGData
        tiles[index].tintHex = tile.tintHex
        save()
    }

    func selectIconImage() -> Data? {
        let panel = NSOpenPanel()
        panel.title = localized("Choose icon image…")
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return nil }
        return Self.pngData(from: image)
    }

    func move(_ tile: RemoteTile, offset: Int) {
        var pageTiles = tiles.filter { $0.page == tile.page }.sorted { $0.sortOrder < $1.sortOrder }
        guard let source = pageTiles.firstIndex(where: { $0.id == tile.id }) else { return }
        let destination = min(max(source + offset, 0), pageTiles.count - 1)
        guard source != destination else { return }
        pageTiles.swapAt(source, destination)
        for (index, item) in pageTiles.enumerated() {
            if let globalIndex = tiles.firstIndex(where: { $0.id == item.id }) { tiles[globalIndex].sortOrder = index }
        }
        save()
    }

    func sortedTiles(page: Int = 0) -> [RemoteTile] {
        tiles.filter { $0.page == page }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func selectApplication() -> (name: String, bundleIdentifier: String, iconPNGData: Data?)? {
        let panel = NSOpenPanel()
        panel.title = localized("Choose a Mac app")
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        return (url.deletingPathExtension().lastPathComponent, identifier, Self.pngData(from: icon))
    }

    func faviconData(for website: String) async -> Data? {
        let normalized = website.contains("://") ? website : "https://\(website)"
        guard let pageURL = URL(string: normalized),
              var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false),
              components.host != nil else { return nil }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        guard let faviconURL = components.url else { return nil }

        var request = URLRequest(url: faviconURL)
        request.timeoutInterval = 3
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              data.count <= 512_000,
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let image = NSImage(data: data) else { return nil }
        return Self.pngData(from: image)
    }

    func loadShortcuts(force: Bool = false) async {
        if !force, case .loaded = shortcutLoadState { return }
        shortcutLoadState = .loading
        let result = await Task.detached(priority: .userInitiated) {
            Self.discoverShortcuts()
        }.value
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let shortcuts):
            shortcutLoadState = .loaded(shortcuts)
        case .failure(let error):
            shortcutLoadState = .failed(error.localizedDescription)
        }
    }

    func recordRecent(name: String, bundleIdentifier: String) {
        let previous = recentApplications.first { $0.bundleIdentifier == bundleIdentifier }
        let wasPinned = previous?.isPinned ?? false
        recentApplications.removeAll { $0.bundleIdentifier == bundleIdentifier }
        recentApplications.append(.init(
            name: name,
            bundleIdentifier: bundleIdentifier,
            lastOpenedAt: Date(),
            isPinned: wasPinned,
            iconPNGData: previous?.iconPNGData ?? Self.applicationIcon(bundleIdentifier)
        ))
        recentApplications = Array(Self.sortedRecent(recentApplications).prefix(12))
        saveRecentApplications()
    }

    func setRecentApplicationPinned(bundleIdentifier: String, pinned: Bool) {
        guard let index = recentApplications.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
        let application = recentApplications[index]
        recentApplications[index] = .init(
            name: application.name,
            bundleIdentifier: application.bundleIdentifier,
            lastOpenedAt: application.lastOpenedAt,
            isPinned: pinned,
            iconPNGData: application.iconPNGData
        )
        recentApplications = Self.sortedRecent(recentApplications)
        saveRecentApplications()
    }

    private func normalizeOrder(page: Int) {
        for (index, item) in sortedTiles(page: page).enumerated() {
            if let globalIndex = tiles.firstIndex(where: { $0.id == item.id }) { tiles[globalIndex].sortOrder = index }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tiles) else { return }
        defaults.set(data, forKey: catalogKey)
    }

    private func saveRecentApplications() {
        guard let data = try? JSONEncoder().encode(recentApplications) else { return }
        defaults.set(data, forKey: recentApplicationsKey)
    }

    private static func sortedRecent(_ applications: [RecentApplication]) -> [RecentApplication] {
        applications.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.lastOpenedAt > $1.lastOpenedAt
        }
    }

    private static func applicationIcon(_ identifier: String) -> Data? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return nil }
        return pngData(from: NSWorkspace.shared.icon(forFile: url.path))
    }

    private static func pngData(from image: NSImage) -> Data? {
        // Bound artwork size so larger on-screen icons don't bloat local messages.
        for pixels in [192, 128, 96, 64] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            let side = CGFloat(pixels)
            let source = image.size
            let scale = min(side / max(source.width, 1), side / max(source.height, 1))
            let size = NSSize(width: source.width * scale, height: source.height * scale)
            image.draw(in: NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                 width: size.width, height: size.height))
            NSGraphicsContext.restoreGraphicsState()
            if let data = bitmap.representation(using: .png, properties: [:]), data.count <= 24_000 { return data }
        }
        return nil
    }

    nonisolated private static func discoverShortcuts() -> Result<[String], Error> {
        do {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                let message = String(decoding: errorData, as: UTF8.self)
                throw NSError(
                    domain: "io.cocoalift.shortcuts",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? localized("Could not list Shortcuts.") : message]
                )
            }
            let names = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            return .success(names)
        } catch {
            return .failure(error)
        }
    }
}
