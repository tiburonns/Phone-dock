import SwiftUI

@main
struct CocoaLiftMobileApp: App {
    @StateObject private var connection = MobileConnectionStore()

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environmentObject(connection)
                .dockAppearance()
                .dockLanguage()
                .task { connection.startBrowsing() }
        }
    }
}
