import SwiftUI

/// Semantic tokens shared by all tabs. Appearance preferences stay on each device.
struct DockStyle {
    var palette: DockPalette = .aurora
    var isDark = false
    var iconSize: DockIconSize = .extraLarge
    var cardShape: DockCardShape = .soft
    var showSubtitles = true
    var originalColors = false

    var accent: Color { Color(hex: isDark ? palette.darkAccent : palette.lightAccent) }
    var companion: Color { Color(hex: palette.companion) }
    var ink: Color { Color(hex: isDark ? "F1F2F7" : "232737") }
    var secondary: Color { Color(hex: isDark ? "AFB4C6" : "626879") }
    var surface: Color { Color(hex: isDark ? "222532" : "FFFFFF") }
    var base: Color { Color(hex: isDark ? "151823" : "F3F4F8") }
    var border: Color { accent.opacity(isDark ? 0.24 : 0.13) }
    var radius: CGFloat { cardShape.radius }
    var background: LinearGradient {
        LinearGradient(colors: [accent.opacity(isDark ? 0.08 : 0.07), base], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    func tileColor(_ tile: RemoteTile) -> Color {
        // Artwork needs a saturated background even when the surrounding UI uses light accents.
        Color(hex: originalColors ? tile.tintHex : palette.lightAccent)
    }
}

private struct DockStyleKey: EnvironmentKey {
    static let defaultValue = DockStyle()
}

extension EnvironmentValues {
    var dockStyle: DockStyle {
        get { self[DockStyleKey.self] }
        set { self[DockStyleKey.self] = newValue }
    }
}

private struct DockAppearanceModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage(DockPreferenceKey.palette) private var palette: DockPalette = .aurora
    @AppStorage(DockPreferenceKey.iconSize) private var iconSize: DockIconSize = .extraLarge
    @AppStorage(DockPreferenceKey.cardShape) private var cardShape: DockCardShape = .soft
    @AppStorage(DockPreferenceKey.colorMode) private var colorMode: DockColorMode = .system
    @AppStorage(DockPreferenceKey.showSubtitles) private var showSubtitles = true
    @AppStorage(DockPreferenceKey.originalColors) private var originalColors = false

    private var preferredScheme: ColorScheme? {
        switch colorMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func body(content: Content) -> some View {
        let style = DockStyle(palette: palette, isDark: (preferredScheme ?? systemScheme) == .dark,
                              iconSize: iconSize, cardShape: cardShape,
                              showSubtitles: showSubtitles, originalColors: originalColors)
        content.environment(\.dockStyle, style)
            .tint(style.accent).foregroundStyle(style.ink)
            .preferredColorScheme(preferredScheme)
    }
}

extension View {
    func dockAppearance() -> some View { modifier(DockAppearanceModifier()) }
    func dockPanel() -> some View { modifier(DockPanelModifier()) }
    func dockBackground() -> some View { modifier(DockBackgroundModifier()) }
}

private struct DockPanelModifier: ViewModifier {
    @Environment(\.dockStyle) private var style
    func body(content: Content) -> some View {
        content.background(style.surface, in: RoundedRectangle(cornerRadius: style.radius))
            .overlay(RoundedRectangle(cornerRadius: style.radius).strokeBorder(style.border))
    }
}

private struct DockBackgroundModifier: ViewModifier {
    @Environment(\.dockStyle) private var style
    func body(content: Content) -> some View {
        content.background { style.base.overlay(style.background).ignoresSafeArea() }
    }
}

struct DockHeader: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        let _ = appLocale
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3).fill(style.accent).frame(width: 22, height: 7)
                Circle().fill(style.companion).frame(width: 7, height: 7)
                Text(eyebrow).font(.caption2.weight(.bold)).tracking(2)
            }
            .foregroundStyle(style.accent)
            Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(style.ink)
            Text(subtitle).font(.subheadline).foregroundStyle(style.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }
}

struct ConnectionPill: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    let connected: Bool
    let text: String

    var body: some View {
        let _ = appLocale
        Label(text, systemImage: connected ? "checkmark.circle.fill" : "wifi.slash")
            .font(.caption.weight(.semibold))
            .foregroundStyle(connected ? style.accent : style.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(style.accent.opacity(connected ? 0.12 : 0.06), in: Capsule())
            .accessibilityLabel(text)
    }
}
