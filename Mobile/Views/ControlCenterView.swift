import SwiftUI

struct ControlCenterView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    @EnvironmentObject private var connection: MobileConnectionStore
    @State private var volume = 0.5
    @State private var brightness = 0.7

    var body: some View {
        let _ = appLocale
        ScrollView {
            VStack(spacing: 16) {
                DockHeader(eyebrow: "02 / PHONE DOCK", title: localized("Find your flow."),
                           subtitle: localized("Lights, sound, and a little more control."))
                HStack {
                    Text(connection.macState.frontmostApplication ?? localized("Mac system controls"))
                        .font(.subheadline.weight(.medium)).lineLimit(1)
                    Spacer()
                    ConnectionPill(connected: connection.isConnected, text: connection.isConnected ? localized("Live") : localized("Offline"))
                }

                ControlSliderCard(
                    title: localized("Display"),
                    value: $brightness,
                    symbol: "sun.max.fill",
                    tint: style.accent,
                    isEnabled: connection.isConnected && connection.macState.brightness != nil
                ) { connection.perform(.setBrightness(brightness)) }

                ControlSliderCard(
                    title: localized("Volume"),
                    value: $volume,
                    symbol: connection.macState.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill",
                    tint: style.accent,
                    isEnabled: connection.isConnected
                ) { connection.perform(.setVolume(volume)) }

                HStack(spacing: 12) {
                    ControlButton(title: connection.macState.isMuted ? localized("Unmute") : localized("Mute"), symbol: connection.macState.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill") {
                        connection.perform(.setMuted(!connection.macState.isMuted))
                    }
                    ControlButton(title: localized("Minimize"), symbol: "minus.rectangle") { connection.perform(.window(.minimize)) }
                    ControlButton(title: localized("Full Screen"), symbol: "arrow.up.left.and.arrow.down.right") { connection.perform(.window(.maximize)) }
                }
                .disabled(!connection.isConnected)

                HStack(spacing: 12) {
                    ControlButton(title: localized("Copy"), symbol: "doc.on.doc") { connection.perform(.clipboard(.copy)) }
                    ControlButton(title: localized("Paste"), symbol: "doc.on.clipboard") { connection.perform(.clipboard(.paste)) }
                    ControlButton(title: localized("Hide App"), symbol: "eye.slash") { connection.perform(.window(.hide)) }
                }
                .disabled(!connection.isConnected)

                GesturePadView { command in connection.perform(command) }
                    .disabled(!connection.isConnected)
            }
            .padding(18)
        }
        .dockBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { syncFromMac() }
        .onChange(of: connection.macState) { _, _ in syncFromMac() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { connection.refresh() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
    }

    private func syncFromMac() {
        volume = connection.macState.volume
        if let value = connection.macState.brightness { brightness = value }
    }
}

private struct GesturePadView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    let perform: (RemoteCommand) -> Void
    @State private var lastAction = localized("Swipe to control")

    var body: some View {
        let _ = appLocale
        VStack(spacing: 12) {
            Image(systemName: "hand.draw.fill")
                .font(.title)
            Text(lastAction).font(.headline)
            Text("↑ full screen  ·  ↓ minimize  ·  ← copy  ·  → paste")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(style.accent)
        .frame(maxWidth: .infinity, minHeight: 120)
        .dockPanel()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 28).onEnded { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    if value.translation.width > 0 {
                        lastAction = localized("Paste")
                        perform(.clipboard(.paste))
                    } else {
                        lastAction = localized("Copy")
                        perform(.clipboard(.copy))
                    }
                } else if value.translation.height > 0 {
                    lastAction = localized("Minimize")
                    perform(.window(.minimize))
                } else {
                    lastAction = localized("Full Screen")
                    perform(.window(.maximize))
                }
            }
        )
        .accessibilityLabel("Gesture pad")
        .accessibilityHint("Swipe up for full screen, down to minimize, left to copy, or right to paste")
    }
}

private struct ControlSliderCard: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    let title: String
    @Binding var value: Double
    let symbol: String
    let tint: Color
    let isEnabled: Bool
    let commit: () -> Void

    var body: some View {
        let _ = appLocale
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(title, systemImage: symbol).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(style.ink)
                Spacer()
                Text("\(Int(value * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0...1) { editing in
                if !editing { commit() }
            }
            .tint(tint)
        }
        .padding(20)
        .dockPanel()
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
    }
}

private struct ControlButton: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        let _ = appLocale
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(style.accent)
            .frame(maxWidth: .infinity, minHeight: 92)
            .dockPanel()
        }
        .buttonStyle(.plain)
    }
}
