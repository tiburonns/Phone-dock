import AppKit
import SwiftUI

/// Run in a dedicated QA directory with en.lproj and es.lproj beside the executable.
/// The same hosting view stays alive while the persisted language changes.
@main struct LanguageSnapshots {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let original = UserDefaults.standard.object(forKey: AppLanguage.preferenceKey)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: AppLanguage.preferenceKey) }
            else { UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey) }
        }
        UserDefaults.standard.set("en", forKey: AppLanguage.preferenceKey)
        let host = NSHostingView(rootView: LanguagePreview().dockAppearance().dockLanguage().frame(width: 580))
        host.appearance = NSAppearance(named: .aqua)
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        for language in ["en", "es", "en"] {
            UserDefaults.standard.set(language, forKey: AppLanguage.preferenceKey)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            host.setFrameSize(NSSize(width: 580, height: host.fittingSize.height))
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("language-\(language).png"))
        }
        print("Rendered live English → Spanish → English language snapshots")
    }
}

private struct LanguagePreview: View {
    @Environment(\.locale) private var locale
    @State private var preservedText = "Mi acción / My action ✨"
    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: 18) {
            DockHeader(eyebrow: "PHONE DOCK", title: localized("Make yourself at home."), subtitle: localized("A little color. A lot more you."))
            LanguageControls()
            TextField("Name", text: $preservedText)
            Text(localized("Your actions and paired devices will not change."))
        }.padding(24).dockBackground()
    }
}
