import SwiftUI

struct AppearanceControls: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    @AppStorage(DockPreferenceKey.palette) private var palette: DockPalette = .aurora
    @AppStorage(DockPreferenceKey.iconSize) private var iconSize: DockIconSize = .extraLarge
    @AppStorage(DockPreferenceKey.cardShape) private var cardShape: DockCardShape = .soft
    @AppStorage(DockPreferenceKey.colorMode) private var colorMode: DockColorMode = .system
    @AppStorage(DockPreferenceKey.showSubtitles) private var showSubtitles = true
    @AppStorage(DockPreferenceKey.originalColors) private var originalColors = false
    @AppStorage(DockPreferenceKey.haptics) private var haptics = true
    @State private var confirmReset = false

    var body: some View {
        let _ = appLocale
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("Color palette", symbol: "paintpalette.fill")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
                    ForEach(DockPalette.allCases) { option in
                        Button { palette = option } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 0) {
                                    Color(hex: option.lightAccent)
                                    Color(hex: option.darkAccent)
                                    Color(hex: option.companion)
                                }
                                .frame(height: 38).clipShape(RoundedRectangle(cornerRadius: 10))
                                HStack(spacing: 4) {
                                    Text(option.title).font(.caption.weight(.semibold)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if palette == option { Image(systemName: "checkmark.circle.fill").font(.caption) }
                                }
                            }
                            .foregroundStyle(style.ink).padding(10)
                            .background(style.accent.opacity(palette == option ? 0.10 : 0.03), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette == option ? style.accent : style.border, lineWidth: palette == option ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(palette == option ? .isSelected : [])
                    }
                }
                Text("One palette, every tab. Changes are saved on this device.")
                    .font(.caption).foregroundStyle(style.secondary)
            }
            .padding(20).dockPanel()

            VStack(alignment: .leading, spacing: 16) {
                sectionLabel("Make it yours", symbol: "slider.horizontal.3")
                preferencePicker("Appearance", selection: $colorMode) {
                    ForEach(DockColorMode.allCases) { Text($0.title).tag($0) }
                }
                Divider()
                preferencePicker("Icon size", selection: $iconSize) {
                    ForEach(DockIconSize.allCases) { Text($0.title).tag($0) }
                }
                preferencePicker("Card corners", selection: $cardShape) {
                    ForEach(DockCardShape.allCases) { Text($0.title).tag($0) }
                }
                Divider()
                Toggle("Show action details", isOn: $showSubtitles)
                Toggle("Individual icon colors", isOn: $originalColors)
                Text("Turn this on to use the colors assigned to each action on your Mac.")
                    .font(.caption).foregroundStyle(style.secondary)
                #if os(iOS)
                Divider()
                Toggle("Haptic feedback", isOn: $haptics)
                #endif
            }
            .toggleStyle(.switch).padding(20).dockPanel()

            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Live preview", symbol: "eye")
                HStack(alignment: .top, spacing: 12) {
                    DockTileFace(tile: Self.previewTile)
                    DockTileFace(tile: Self.secondPreviewTile)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Live preview")
                Button("Reset appearance") { confirmReset = true }
                    .font(.subheadline).padding(.top, 6)
            }
        }
        .confirmationDialog("Reset appearance?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset appearance", role: .destructive) {
                palette = .aurora; iconSize = .extraLarge; cardShape = .soft
                colorMode = .system; showSubtitles = true; originalColors = false; haptics = true
            }
        } message: {
            Text("Your actions and paired devices will not change.")
        }
    }

    private func sectionLabel(_ title: LocalizedStringKey, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(.headline, design: .rounded)).foregroundStyle(style.accent)
    }

    private func preferencePicker<Selection: Hashable, Content: View>(
        _ title: LocalizedStringKey, selection: Binding<Selection>, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.subheadline.weight(.medium))
            Picker(title, selection: selection, content: content).pickerStyle(.segmented).labelsHidden()
        }
    }

    private static var previewTile: RemoteTile { RemoteTile(title: localized("Focus"), subtitle: localized("Your next good idea"),
        systemImage: "sparkles", tintHex: "6650D8", kind: .shortcut, command: .runShortcut("Focus")) }
    private static var secondPreviewTile: RemoteTile { RemoteTile(title: localized("Music"), subtitle: localized("Set the mood"),
        systemImage: "music.note", tintHex: "AF4934", kind: .app, command: .launchApp(bundleIdentifier: "com.apple.Music")) }
}

struct LanguageControls: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @AppStorage(AppLanguage.preferenceKey) private var language: AppLanguage = .system
    var body: some View {
        let _ = appLocale
        VStack(alignment: .leading, spacing: 14) {
            Label("Language", systemImage: "globe").font(.headline)
            Picker("App language", selection: $language) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            Text("Applies immediately on this device. Your actions and paired devices stay unchanged.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20).dockPanel()
    }
}

private struct DockLanguageModifier: ViewModifier {
    @AppStorage(AppLanguage.preferenceKey) private var language: AppLanguage = .system
    @Environment(\.locale) private var systemLocale
    func body(content: Content) -> some View {
        let _ = systemLocale
        content.environment(\.locale, language.locale)
    }
}

extension View {
    func dockLanguage() -> some View { modifier(DockLanguageModifier()) }
}

#Preview("Appearance") {
    ScrollView { AppearanceControls().padding(18) }.frame(width: 390).dockBackground().dockAppearance()
}
