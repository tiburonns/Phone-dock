import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
private typealias TilePlatformImage = NSImage
#else
private typealias TilePlatformImage = UIImage
#endif

@MainActor
private final class TileImageCache {
    static let shared = TileImageCache()
    private let images = NSCache<NSData, TilePlatformImage>()

    private init() {
        images.totalCostLimit = 24 * 1_024 * 1_024
    }

    func image(for data: Data) -> TilePlatformImage? {
        let key = data as NSData
        if let cached = images.object(forKey: key) { return cached }
        guard let decoded = TilePlatformImage(data: data) else { return nil }
        images.setObject(decoded, forKey: key, cost: data.count)
        return decoded
    }
}

struct TileArtwork: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    let tile: RemoteTile
    var size: CGFloat = 100

    var body: some View {
        let _ = appLocale
        artwork
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.27)
                    .fill(LinearGradient(colors: [style.tileColor(tile), style.tileColor(tile).opacity(0.72)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(RoundedRectangle(cornerRadius: size * 0.27).strokeBorder(.white.opacity(0.14)))
            .accessibilityHidden(true)
    }

    @ViewBuilder private var artwork: some View {
        if let emoji = tile.displayEmoji, !emoji.isEmpty {
            Text(emoji).font(.system(size: size * 0.50))
        } else if let image = decodedImage {
            image.resizable().scaledToFit().padding(size * 0.06)
        } else {
            Image(systemName: tile.systemImage)
                .font(.system(size: size * 0.44, weight: .medium))
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var decodedImage: Image? {
        guard let data = tile.iconPNGData,
              let image = TileImageCache.shared.image(for: data) else { return nil }
        #if os(macOS)
        return Image(nsImage: image)
        #else
        return Image(uiImage: image)
        #endif
    }
}

struct DockTileFace: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    let tile: RemoteTile
    var accessory = "arrow.up.right"

    var body: some View {
        let _ = appLocale
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer(minLength: 0)
                Image(systemName: accessory).font(.caption.weight(.semibold))
                    .foregroundStyle(style.secondary)
            }
            TileArtwork(tile: tile, size: style.iconSize.points)
                .frame(maxWidth: .infinity).padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(tile.title).font(.system(.headline, design: .rounded))
                    .foregroundStyle(style.ink).lineLimit(2)
                    .frame(minHeight: 22, alignment: .topLeading)
                if style.showSubtitles {
                    Text(tile.subtitle ?? tile.kind.title)
                        .font(.caption).foregroundStyle(style.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: style.iconSize == .extraLarge ? 226 : 202, alignment: .top)
        .dockPanel()
        .contentShape(RoundedRectangle(cornerRadius: style.radius))
    }
}

#Preview("Aurora · large artwork") {
    DockTileFace(tile: RemoteTile.starterDeck[0]).frame(width: 180).padding().dockAppearance()
}

#Preview("Graphite · dark · compact") {
    DockTileFace(tile: RemoteTile.starterDeck[4])
        .environment(\.dockStyle, DockStyle(palette: .graphite, isDark: true, iconSize: .large, cardShape: .crisp))
        .frame(width: 180).padding().preferredColorScheme(.dark)
}
