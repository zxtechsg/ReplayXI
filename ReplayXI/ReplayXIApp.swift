import GroupActivities
import SwiftUI

@main
struct ReplayXIApp: App {
    @State private var store: ReplayStore
    @State private var squadSession: SquadSessionCoordinator
    @State private var sharedSpace: SharedSpaceAnchorCoordinator

    init() {
        let store = ReplayStore()
        let sharedSpace = SharedSpaceAnchorCoordinator()
        sharedSpace.onSelectedAnchorRemoved = { [weak store] anchorID in
            store?.handleSharedPitchAnchorRemoval(anchorID)
        }
        store.onRetirePitchAnchor = { [weak sharedSpace] _ in
            Task { await sharedSpace?.removeLocallyPlacedPitchAnchor() }
        }
        _store = State(initialValue: store)
        _squadSession = State(initialValue: SquadSessionCoordinator(store: store))
        _sharedSpace = State(initialValue: sharedSpace)
    }

    var body: some Scene {
        WindowGroup(id: "ReplayDashboard") {
            ReplayDashboardView()
                .environment(store)
                .environment(squadSession)
                .environment(sharedSpace)
                .groupActivityAssociation(
                    store.isImmersiveOpen ? nil : .primary("ReplayXIReviewRoom")
                )
        }
        .defaultSize(width: 1_380, height: 820)
        .handlesExternalEvents(matching: ["ReplayXIReviewRoom"])

        ImmersiveSpace(id: "ReplayRoom") {
            FootballImmersiveView()
                .environment(store)
                .environment(squadSession)
                .environment(sharedSpace)
                .groupActivityAssociation(.primary("ReplayXIReviewRoom"))
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
