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

                Text("Tap to switch apps. Hold to open a new instance in compatible apps.")
                    .font(.caption).foregroundStyle(.secondary)

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
                            DeckTile(tile: tile, newInstance: {
                                if let command = tile.command.newInstanceCommand {
                                    connection.perform(command)
                                    if haptics { hapticTrigger += 1 }
                                }
                            }) {
                                connection.perform(tile.command)
                                if haptics { hapticTrigger += 1 }
                            }
                            .disabled(!connection.isConnected)
                            .allowsHitTesting(connection.isConnected)
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
                            ), isPinned: app.isPinned, newInstance: {
                                connection.perform(.launchNewInstance(bundleIdentifier: app.bundleIdentifier))
                                if haptics { hapticTrigger += 1 }
                            }, togglePin: {
                                connection.perform(.setRecentAppPinned(
                                    bundleIdentifier: app.bundleIdentifier,
                                    pinned: !app.isPinned
                                ))
                            }) {
                                connection.perform(.launchApp(bundleIdentifier: app.bundleIdentifier))
                                if haptics { hapticTrigger += 1 }
                            }
                            .disabled(!connection.isConnected)
                            .allowsHitTesting(connection.isConnected)
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
    var newInstance: (() -> Void)?
    var togglePin: (() -> Void)?
    let action: () -> Void

    init(
        tile: RemoteTile,
        isPinned: Bool? = nil,
        newInstance: (() -> Void)? = nil,
        togglePin: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.tile = tile
        self.isPinned = isPinned
        self.newInstance = newInstance
        self.togglePin = togglePin
        self.action = action
    }

    var body: some View {
        let _ = appLocale
        ZStack(alignment: .topTrailing) {
            if tile.command.newInstanceCommand != nil, let newInstance {
                DockTileFace(tile: tile, accessory: "plus.square")
                    .contentShape(Rectangle())
                    .gesture(LongPressGesture(minimumDuration: 0.6, maximumDistance: 16)
                        .exclusively(before: TapGesture())
                        .onEnded { gesture in
                            switch gesture {
                            case .first(true): newInstance()
                            case .second: action()
                            default: break
                            }
                        })
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { action() }
                    .accessibilityAction(named: Text("Open new instance"), newInstance)
                    .accessibilityHint("Tap to switch apps. Hold to open a new instance in compatible apps.")
            } else {
                Button(action: action) { DockTileFace(tile: tile, accessory: "arrow.up.right") }
                    .buttonStyle(.plain)
            }
            if let isPinned, let togglePin {
                Button(action: togglePin) { Image(systemName: isPinned ? "pin.fill" : "pin") }
                    .buttonStyle(.bordered).padding(8)
                    .accessibilityLabel(isPinned ? localized("Unpin") : localized("Pin to Front"))
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
