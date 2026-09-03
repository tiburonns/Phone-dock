import SwiftUI

struct AboutView: View {
    // Observe locale changes for computed, non-LocalizedStringKey labels as well.
    @Environment(\.locale) private var appLocale
    @Environment(\.dockStyle) private var style
    var body: some View {
        let _ = appLocale
        VStack(spacing: 16) {
            Image("BrandIcon").resizable().frame(width: 144, height: 144)
                .clipShape(RoundedRectangle(cornerRadius: 38))
                .padding(.bottom, 8)
            Text("Phone Dock").font(.system(size: 40, weight: .bold, design: .rounded))
            Text("A free, local-first Mac remote.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No accounts. No analytics. No subscriptions. Commands travel directly between your Apple devices on the local network.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            HStack(spacing: 8) {
                ForEach(DockPalette.allCases) { palette in
                    Circle().fill(Color(hex: palette.lightAccent)).frame(width: 16, height: 16)
                }
            }.padding(.vertical, 8).accessibilityHidden(true)
            Text("Your space. Your shortcuts.")
                .font(.caption)
                .foregroundStyle(style.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dockBackground()
        .navigationTitle("About")
    }
}
