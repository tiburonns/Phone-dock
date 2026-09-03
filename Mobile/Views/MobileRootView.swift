import SwiftUI

enum MobileTab: Hashable {
    case bar
    case controls
    case devices
    case settings
}

struct MobileRootView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    @EnvironmentObject private var connection: MobileConnectionStore
    @State private var selectedTab: MobileTab = .bar

    var body: some View {
        let _ = appLocale
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                LandscapeQuickDockView()
            } else {
                portraitTabs
            }
        }
        .tint(style.accent)
        .overlay(alignment: .top) {
            if let error = connection.lastError {
                HStack(spacing: 8) {
                    Text(error).lineLimit(2)
                    Button { connection.clearError() } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss error")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.red, in: Capsule())
                .padding(.horizontal)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: connection.isConnected) {
            guard connection.isConnected else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                connection.refreshState()
            }
        }
    }

    private var portraitTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { DeckView() }
                .tabItem { Label("Dock", systemImage: "square.grid.2x2.fill") }
                .tag(MobileTab.bar)
            NavigationStack { ControlCenterView() }
                .tabItem { Label("Controls", systemImage: "slider.horizontal.3") }
                .tag(MobileTab.controls)
            NavigationStack { MobileDevicesView() }
                .tabItem { Label("Devices", systemImage: "laptopcomputer.and.iphone") }
                .tag(MobileTab.devices)
            NavigationStack { MobileSettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(MobileTab.settings)
        }
        .tint(style.accent)
        .toolbarBackground(style.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
