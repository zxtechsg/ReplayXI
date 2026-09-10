import SwiftUI

@main
struct ReplayXIApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: ReplayStore
    @State private var sharedSpace: LocalPitchAnchorCoordinator

    init() {
        // Test hosts and scripted demos never touch production saves. A normal
        // launch restores the user's local session and enables durable saves.
        let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        let hasDemoRoute = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--replayxi-") }
        let scenarios = DemoScenarios.all
        let library = isTestHost || hasDemoRoute
            ? ReplayReviewLibrary(scenarios: scenarios)
            : ReplayReviewLibrary.persistent(scenarios: scenarios)
        let store = ReplayStore(scenarios: scenarios, reviewLibrary: library)
        if !isTestHost && !hasDemoRoute { store.restoreAutosavedReview() }
        store.prepareForLocalExperience()
        let sharedSpace = LocalPitchAnchorCoordinator()
        sharedSpace.onSelectedAnchorRemoved = { [weak store] anchorID in
            store?.handleSharedPitchAnchorRemoval(anchorID)
        }
        store.onRetirePitchAnchor = { [weak sharedSpace] _ in
            Task { await sharedSpace?.removeLocallyPlacedPitchAnchor() }
        }
        _store = State(initialValue: store)
        _sharedSpace = State(initialValue: sharedSpace)
    }

    var body: some Scene {
        WindowGroup(id: "ReplayDashboard") {
            ReplayDashboardView()
                .environment(store)
                .environment(sharedSpace)
        }
        .defaultSize(width: 1_380, height: 820)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flushReviewAutosave() }
        }

        ImmersiveSpace(id: "ReplayRoom") {
            FootballImmersiveView()
                .environment(store)
                .environment(sharedSpace)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
