import SwiftUI
import UIKit

struct DeckView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dynamicTypeSize) private var dynamicType
    @AppStorage(DockPreferenceKey.haptics) private var haptics = true
    @EnvironmentObject private var connection: MobileConnectionStore
    @State private var hapticTrigger = 0
    @State private var mode: DeckMode = .bar
    @State private var currentPage = 0
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 280 : 150, maximum: 260), spacing: 12)]
    }

    var body: some View {
        let _ = appLocale
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DockHeader(eyebrow: "01 / PHONE DOCK", title: localized("Your space. Your shortcuts."),
                           subtitle: localized("Everything you love about your Mac, one tap away."))
                HStack {
                    Text(mode == .bar ? localized("My Dock") : localized("Recent apps"))
                        .font(.headline)
                    Spacer()
                    ConnectionPill(connected: connection.isConnected, text: connection.isConnected ? localized("Live") : localized("Offline"))
                }

                Picker("Content", selection: $mode) {
                    ForEach(DeckMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if mode == .bar && connection.catalog.isEmpty {
                    ContentUnavailableView(
                        connection.isConnected ? localized("Your bar is empty") : localized("Connect your Mac"),
                        systemImage: connection.isConnected ? "square.grid.2x2" : "laptopcomputer.and.iphone",
                        description: Text(connection.isConnected ? localized("Add actions from the Phone Dock Mac app.") : localized("Pair a nearby Mac in the Devices tab."))
                    )
                    .frame(minHeight: 360)
                } else if mode == .bar {
                    if availablePages.count > 1 {
                        Picker("Page", selection: $currentPage) {
                            ForEach(availablePages, id: \.self) { page in
                                Text("Page \(page + 1)").tag(page)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(pageTiles) { tile in
                            DeckTile(tile: tile) {
                                connection.perform(tile.command)
                                if haptics { hapticTrigger += 1 }
                            }
                            .disabled(!connection.isConnected)
                        }
                    }
                } else if connection.recentApplications.isEmpty {
                    ContentUnavailableView("No recent apps yet", systemImage: "clock.arrow.circlepath", description: Text("Open apps on your Mac, then refresh."))
                        .frame(minHeight: 360)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(connection.recentApplications) { app in
                            DeckTile(tile: .init(
                                title: app.name,
                                subtitle: localized("Recent app"),
                                systemImage: "app.fill",
                                iconPNGData: app.iconPNGData,
                                tintHex: "9A5BF6",
                                kind: .app,
                                command: .launchApp(bundleIdentifier: app.bundleIdentifier)
                            ), isPinned: app.isPinned, togglePin: {
                                connection.perform(.setRecentAppPinned(
                                    bundleIdentifier: app.bundleIdentifier,
                                    pinned: !app.isPinned
                                ))
                            }) {
                                connection.perform(.launchApp(bundleIdentifier: app.bundleIdentifier))
                                if haptics { hapticTrigger += 1 }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .dockBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { connection.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(!connection.isConnected)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
        .onChange(of: availablePages) { _, pages in
            if !pages.contains(currentPage) { currentPage = pages.first ?? 0 }
        }
    }

    private var availablePages: [Int] {
        let pages = Set(connection.catalog.map(\.page)).sorted()
        return pages.isEmpty ? [0] : pages
    }

    private var pageTiles: [RemoteTile] {
        connection.catalog
            .filter { $0.page == currentPage }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}

private enum DeckMode: CaseIterable {
    case bar
    case recent

    var title: String { self == .bar ? localized("My Dock") : localized("Recent apps") }
}

private struct DeckTile: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    let tile: RemoteTile
    var isPinned: Bool?
    var togglePin: (() -> Void)?
    let action: () -> Void

    init(
        tile: RemoteTile,
        isPinned: Bool? = nil,
        togglePin: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.tile = tile
        self.isPinned = isPinned
        self.togglePin = togglePin
        self.action = action
    }

    var body: some View {
        let _ = appLocale
        Button(action: action) {
            DockTileFace(tile: tile, accessory: isPinned == true ? "pin.fill" : "arrow.up.right")
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let isPinned, let togglePin {
                Button(isPinned ? localized("Unpin") : localized("Pin to Front"), action: togglePin)
            }
        }
        .accessibilityLabel("\(tile.title), \(tile.subtitle ?? tile.kind.title)")
        .modifier(RecentPinAccessibilityModifier(isPinned: isPinned, togglePin: togglePin))
    }
}

private struct RecentPinAccessibilityModifier: ViewModifier {
    let isPinned: Bool?
    let togglePin: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let isPinned, let togglePin {
            content.accessibilityAction(named: Text(isPinned ? localized("Unpin") : localized("Pin to Front"))) {
                togglePin()
            }
        } else {
            content
        }
    }
}
