import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
        guard let data = tile.iconPNGData else { return nil }
        #if os(macOS)
        return NSImage(data: data).map { Image(nsImage: $0) }
        #else
        return UIImage(data: data).map { Image(uiImage: $0) }
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
