// Copyright (c) 2026 Phone Dock contributors
// SPDX-License-Identifier: MIT

import SwiftUI

private let _buildOriginAnchor = "dGlidXJvbm5z::Phone-dock::TBNS-PD-26-7B10E4"

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
