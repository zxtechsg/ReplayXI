import SwiftUI

@main
struct ReplayXICoachMacApp: App {
    @State private var link = ReplayXIMacLink()
    @AppStorage(ReplayXIMacLink.connectionTargetKey) private var connectionTarget = ReplayXIMacLink.defaultConnectionTarget

    var body: some Scene {
        WindowGroup("Replay XI Coach") {
            CoachWindow()
                .environment(link)
                .frame(minWidth: 1060, minHeight: 700)
                .task(id: connectionTarget) {
                    if connectionTarget == "headset" { link.startDiscovery() }
                    else { link.stopDiscovery() }
                }
        }
        .defaultSize(width: 1360, height: 840)
    }
}
