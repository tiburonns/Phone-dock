import SwiftUI

struct TileCustomizationSheet: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dockStyle) private var style
    @EnvironmentObject private var catalog: CatalogStore
    @State private var draft: RemoteTile

    init(tile: RemoteTile) { _draft = State(initialValue: tile) }

    var body: some View {
        let _ = appLocale
        VStack(alignment: .leading, spacing: 22) {
            Text("Personalize action").font(.system(.title, design: .rounded, weight: .bold))
            HStack(alignment: .top, spacing: 24) {
                DockTileFace(tile: draft, accessory: "pencil")
                    .environment(\.dockStyle, previewStyle)
                    .frame(width: 190)
                Form {
                    TextField("Name", text: $draft.title)
                    TextField("Action detail", text: Binding(
                        get: { draft.subtitle ?? "" }, set: { draft.subtitle = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Icon emoji", text: Binding(
                        get: { draft.displayEmoji ?? "" },
                        set: { draft.displayEmoji = $0.isEmpty ? nil : String($0.prefix(1)) }
                    ))
                    Text("Leave the emoji empty to use the original icon.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Choose icon image…") {
                        if let data = catalog.selectIconImage() {
                            draft.iconPNGData = data
                            draft.displayEmoji = nil
                        }
                    }
                    TileColorPicker(selection: $draft.tintHex)
                }
                .formStyle(.grouped)
            }
            Text("Names, images, and individual colors are shared with your iPhone. Enable Individual icon colors in Appearance to show these colors.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    catalog.update(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28).frame(width: 650).dockBackground()
    }

    private var previewStyle: DockStyle {
        var preview = style
        preview.originalColors = true
        return preview
    }
}

struct TileColorPicker: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Binding var selection: String
    private let colors = ["6650D8", "096B97", "AF4934", "3C714C", "515D72", "AC3970", "956522", "237D79"]

    var body: some View {
        let _ = appLocale
        VStack(alignment: .leading, spacing: 10) {
            Text("Icon color").font(.subheadline.weight(.medium))
            HStack(spacing: 8) {
                ForEach(colors, id: \.self) { hex in
                    Button { selection = hex } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 27, height: 27)
                            .overlay {
                                if selection.uppercased() == hex {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localizedFormat("Color %@", hex))
                    .accessibilityAddTraits(selection.uppercased() == hex ? .isSelected : [])
                }
            }
        }
    }
}
