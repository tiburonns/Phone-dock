import SwiftUI

struct BarEditorView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    @EnvironmentObject private var catalog: CatalogStore
    @State private var isAdding = false
    @State private var isEditing = false
    @State private var currentPage = 0
    @State private var customizingTile: RemoteTile?

    private let columns = [GridItem(.adaptive(minimum: 174, maximum: 240), spacing: 16)]

    var body: some View {
        let _ = appLocale
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DockHeader(eyebrow: "PHONE DOCK / YOUR SPACE", title: localized("My Dock"),
                           subtitle: localized("Your favorite actions, with your own signature."))
                HStack {
                    Text("Click an action to personalize it.").foregroundStyle(style.secondary)
                    Spacer()
                    SettingsLink { Label("Appearance", systemImage: "paintpalette") }
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(catalog.sortedTiles(page: currentPage)) { tile in
                        VStack(spacing: 10) {
                            Button { customizingTile = tile } label: {
                                DockTileFace(tile: tile, accessory: "pencil")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(localizedFormat("Customize %@", tile.title))
                            if isEditing {
                                HStack {
                                    Button { catalog.move(tile, offset: -1) } label: { Image(systemName: "arrow.left") }
                                        .help("Move left")
                                    Button { catalog.move(tile, offset: 1) } label: { Image(systemName: "arrow.right") }
                                        .help("Move right")
                                    Spacer()
                                    Button(role: .destructive) { catalog.remove(tile) } label: {
                                        Image(systemName: "trash")
                                    }
                                    .help("Remove action")
                                }
                                .buttonStyle(.borderless).padding(.horizontal, 12)
                            }
                        }
                    }
                    Button { isAdding = true } label: {
                        VStack(spacing: 14) {
                            Image(systemName: "plus").font(.system(size: 32, weight: .light))
                                .frame(width: 76, height: 76)
                                .background(style.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))
                            Text("Add action").font(.system(.headline, design: .rounded))
                        }
                        .foregroundStyle(style.accent)
                        .frame(maxWidth: .infinity, minHeight: style.iconSize == .extraLarge ? 226 : 202)
                        .overlay(RoundedRectangle(cornerRadius: style.radius)
                            .stroke(style.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
        }
        .dockBackground()
        .navigationTitle("My Dock")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Page", selection: $currentPage) {
                    ForEach(0..<8, id: \.self) { page in Text("Page \(page + 1)").tag(page) }
                }
                .frame(width: 130)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? localized("Done") : localized("Reorder")) { isEditing.toggle() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: { Label("Add", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $isAdding) { AddTileSheet(page: currentPage) }
        .sheet(item: $customizingTile) { TileCustomizationSheet(tile: $0) }
    }
}
