import AppKit
import SwiftUI

/// Offline visual regression harness: renders shared UI without launching a simulator or connecting to a Mac.
@main
struct AppearanceSnapshots {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/PhoneDockAppearanceQA")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for palette in DockPalette.allCases {
            for dark in [false, true] {
                let style = DockStyle(palette: palette, isDark: dark)
                try render(DockSnapshot().environment(\.dockStyle, style)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.locale, Locale(identifier: "es")),
                    width: 393, path: directory.appendingPathComponent("\(palette.rawValue)-\(dark ? "dark" : "light").png"))
            }
        }
        try render(DockSnapshot().environment(\.dockStyle, DockStyle(iconSize: .large, cardShape: .crisp, showSubtitles: false)),
                   width: 320, path: directory.appendingPathComponent("small-screen.png"))
        try renderHosted(AppearanceControls().padding(18).dockBackground()
            .environment(\.dockStyle, DockStyle()).environment(\.locale, Locale(identifier: "es"))
            .environment(\.colorScheme, .light).foregroundStyle(DockStyle().ink).tint(DockStyle().accent),
                   width: 393, path: directory.appendingPathComponent("appearance-controls.png"))
        print("Rendered 12 offline appearance snapshots in \(directory.path)")
    }

    @MainActor static func render<Content: View>(_ content: Content, width: CGFloat, path: URL) throws {
        let renderer = ImageRenderer(content: content.frame(width: width))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PhoneDock.Snapshots", code: 1)
        }
        try data.write(to: path)
    }

    /// AppKit-backed controls cannot be drawn by ImageRenderer; cache the hosting view instead.
    @MainActor static func renderHosted<Content: View>(_ content: Content, width: CGFloat, path: URL) throws {
        let host = NSHostingView(rootView: content.frame(width: width))
        host.appearance = NSAppearance(named: .aqua)
        host.setFrameSize(NSSize(width: width, height: host.fittingSize.height))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "PhoneDock.Snapshots", code: 2)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PhoneDock.Snapshots", code: 3)
        }
        try data.write(to: path)
    }
}

private struct DockSnapshot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DockHeader(eyebrow: "01 / PHONE DOCK", title: "Tu espacio. Tus atajos.", subtitle: "Lo mejor de tu Mac, a un toque.")
            HStack {
                Text("Mi Dock").font(.headline)
                Spacer()
                ConnectionPill(connected: true, text: "En vivo")
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(RemoteTile.starterDeck.prefix(4))) { tile in
                    DockTileFace(tile: tile)
                }
            }
        }
        .padding(18).dockBackground()
    }
}
