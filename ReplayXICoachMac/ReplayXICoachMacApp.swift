import SwiftUI

@main
struct ReplayXICoachMacApp: App {
    @State private var link = ReplayXIMacLink()

    var body: some Scene {
        WindowGroup("Replay XI Coach") {
            CoachWindow()
                .environment(link)
                .frame(minWidth: 1060, minHeight: 700)
                .task { link.startDiscovery() }
        }
        .defaultSize(width: 1360, height: 840)
    }
}
