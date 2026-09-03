import SwiftUI

struct LandscapeQuickDockView: View {
    @Environment(\.dockStyle) private var style
    @EnvironmentObject private var connection: MobileConnectionStore
    @State private var panel = LandscapePanel.dock

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(panel.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                Text("Swipe right for emojis and left for quick actions.")
                    .font(.caption).foregroundStyle(style.secondary).lineLimit(1)
                ConnectionPill(connected: connection.isConnected,
                               text: connection.isConnected ? localized("Live") : localized("Offline"))
            }
            .padding(.horizontal, 18).padding(.vertical, 8)

            TabView(selection: $panel) {
                LandscapeEmojiPage().tag(LandscapePanel.emojis)
                LandscapeDockPage().tag(LandscapePanel.dock)
                LandscapeActionsPage().tag(LandscapePanel.actions)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 7) {
                ForEach(LandscapePanel.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == panel ? style.accent : style.secondary.opacity(0.3))
                        .frame(width: item == panel ? 24 : 7, height: 7)
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: 0.18), value: panel)
            .padding(.vertical, 7)
        }
        .dockBackground()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(panel.title)
    }
}

private struct LandscapeDockPage: View {
    @Environment(\.dockStyle) private var style
    @EnvironmentObject private var connection: MobileConnectionStore
    @AppStorage(DockPreferenceKey.haptics) private var haptics = true
    @State private var hapticTrigger = 0
    private let columns = [GridItem(.adaptive(minimum: 82, maximum: 90), spacing: 14)]

    private var tiles: [RemoteTile] {
        connection.catalog.sorted {
            $0.page == $1.page ? $0.sortOrder < $1.sortOrder : $0.page < $1.page
        }
    }

    var body: some View {
        Group {
            if tiles.isEmpty {
                ContentUnavailableView(
                    connection.isConnected ? localized("Your bar is empty") : localized("Connect your Mac"),
                    systemImage: connection.isConnected ? "square.grid.2x2" : "laptopcomputer.and.iphone",
                    description: Text(connection.isConnected ? localized("Add actions from the Phone Dock Mac app.") : localized("Pair a nearby Mac in the Devices tab."))
                )
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(tiles) { tile in
                            LandscapeIconButton(tile: tile) {
                                connection.perform(tile.command)
                                if haptics { hapticTrigger += 1 }
                            } newInstance: {
                                guard let command = tile.command.newInstanceCommand else { return }
                                connection.perform(command)
                                if haptics { hapticTrigger += 1 }
                            }
                            .disabled(!connection.isConnected)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 10)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }
}

private struct LandscapeIconButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let tile: RemoteTile
    let action: () -> Void
    let newInstance: () -> Void

    var body: some View {
        if tile.command.newInstanceCommand != nil {
            TileArtwork(tile: tile, size: 72)
                .padding(5).contentShape(Rectangle())
                .gesture(LongPressGesture(minimumDuration: 0.6, maximumDistance: 16)
                    .exclusively(before: TapGesture())
                    .onEnded { result in
                        guard isEnabled else { return }
                        switch result {
                        case .first(true): newInstance()
                        case .second: action()
                        default: break
                        }
                    })
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { if isEnabled { action() } }
                .accessibilityAction(named: Text("Open new instance")) { if isEnabled { newInstance() } }
                .accessibilityHint("Tap to switch apps. Hold to open a new instance in compatible apps.")
                .accessibilityLabel(tile.title)
                .opacity(isEnabled ? 1 : 0.45)
        } else {
            Button(action: action) { TileArtwork(tile: tile, size: 72).padding(5) }
                .buttonStyle(.plain).accessibilityLabel(tile.title)
        }
    }
}

private struct LandscapeEmojiPage: View {
    @Environment(\.dockStyle) private var style
    @EnvironmentObject private var connection: MobileConnectionStore
    @AppStorage(DockPreferenceKey.landscapeEmojiCounts) private var storedCounts = Data()
    @AppStorage(DockPreferenceKey.haptics) private var haptics = true
    @State private var hapticTrigger = 0
    private let columns = [GridItem(.adaptive(minimum: 68, maximum: 76), spacing: 10)]

    private var counts: [String: Int] {
        (try? JSONDecoder().decode([String: Int].self, from: storedCounts)) ?? [:]
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(LandscapeEmojiRanking.ranked(counts: counts), id: \.self) { emoji in
                    Button {
                        connection.perform(.insertText(emoji))
                        record(emoji)
                        if haptics { hapticTrigger += 1 }
                    } label: {
                        Text(emoji).font(.system(size: 31))
                            .frame(width: 62, height: 62)
                            .background(style.surface, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(style.border))
                    }
                    .buttonStyle(.plain).disabled(!connection.isConnected)
                    .accessibilityLabel(localizedFormat("Insert %@", emoji))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: hapticTrigger)
    }

    private func record(_ emoji: String) {
        var updated = counts
        updated[emoji] = min(max(updated[emoji, default: 0], 0), 999_999) + 1
        if let data = try? JSONEncoder().encode(updated) { storedCounts = data }
    }
}

private struct LandscapeActionsPage: View {
    @Environment(\.dockStyle) private var style
    @EnvironmentObject private var connection: MobileConnectionStore
    @State private var volume = 0.5
    @State private var brightness = 0.7
    @State private var editingVolume = false
    @State private var editingBrightness = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        HStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 10) {
                action(localized("Copy"), "doc.on.doc") { connection.perform(.clipboard(.copy)) }
                action(localized("Paste"), "doc.on.clipboard") { connection.perform(.clipboard(.paste)) }
                action(localized("Full Screen"), "arrow.up.left.and.arrow.down.right") { connection.perform(.window(.maximize)) }
                action(localized("Minimize"), "minus.rectangle") { connection.perform(.window(.minimize)) }
                action(connection.macState.isMuted ? localized("Unmute") : localized("Mute"),
                       connection.macState.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill") {
                    connection.perform(.setMuted(!connection.macState.isMuted))
                }
                action(localized("Hide App"), "eye.slash") { connection.perform(.window(.hide)) }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 12) {
                LandscapeSlider(title: localized("Volume"), symbol: "speaker.wave.3.fill",
                                value: $volume, isEnabled: connection.isConnected,
                                editingChanged: { editingVolume = $0 }) {
                    connection.perform(.setVolume(volume))
                }
                LandscapeSlider(title: localized("Display"), symbol: "sun.max.fill",
                                value: $brightness,
                                isEnabled: connection.isConnected && connection.macState.brightness != nil,
                                editingChanged: { editingBrightness = $0 }) {
                    connection.perform(.setBrightness(brightness))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .disabled(!connection.isConnected)
        .onAppear { syncState() }
        .onChange(of: connection.macState) { _, _ in syncState() }
    }

    private func action(_ title: String, _ symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(style.accent).frame(maxWidth: .infinity, minHeight: 74).dockPanel()
        }
        .buttonStyle(.plain)
    }

    private func syncState() {
        if !editingVolume { volume = connection.macState.volume }
        if !editingBrightness, let current = connection.macState.brightness { brightness = current }
    }
}

private struct LandscapeSlider: View {
    @Environment(\.dockStyle) private var style
    let title: String
    let symbol: String
    @Binding var value: Double
    let isEnabled: Bool
    let editingChanged: (Bool) -> Void
    let commit: () -> Void
    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Label(title, systemImage: symbol).font(.caption.weight(.bold))
                Spacer()
                Text("\(Int(value * 100))%").font(.caption.monospacedDigit())
            }
            Slider(value: $value, in: 0...1, step: 0.01) { editing in
                isEditing = editing
                editingChanged(editing)
                if !editing { commit() }
            }
        }
        .padding(13).dockPanel().opacity(isEnabled ? 1 : 0.45).disabled(!isEnabled)
        .task(id: value) {
            guard isEditing, isEnabled else { return }
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard !Task.isCancelled, isEditing, isEnabled else { return }
            commit()
        }
    }
}
