import SwiftUI

@main
struct ReplayXIApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: ReplayStore
    @State private var sharedSpace: LocalPitchAnchorCoordinator
    @State private var comparisonSession = ReplayConversionPreviewSession()
    @State private var annotationEntry = ReplayAnnotationEntrySession()
    @State private var macCoachService: ReplayXILocalCoachService
    @State private var launchSession: ReplayLaunchSession
    @AppStorage(ReplayEnvironmentMode.storageKey) private var environmentModeRawValue =
        ReplayEnvironmentMode.defaultSelection.rawValue

    private var immersionStyle: Binding<any ImmersionStyle> {
        Binding(get: {
            let mode = ReplayEnvironmentMode.effective(environmentModeRawValue,
                isPhysicalPractice: store.selectedScenario.kind == .shapeLab || store.triangleLockMode == .place)
            if mode == .stadium { return .full }
            return .mixed
        }, set: { style in
            // A safety override for physical practice never overwrites the
            // user's chosen replay environment.
            guard store.selectedScenario.kind != .shapeLab, store.triangleLockMode != .place else { return }
            environmentModeRawValue = style is FullImmersionStyle
                ? ReplayEnvironmentMode.stadium.rawValue : ReplayEnvironmentMode.room.rawValue
        })
    }

    init() {
        // Test hosts and scripted demos never touch production saves. A normal
        // launch restores the user's local session and enables durable saves.
        let launch = ReplayLaunchConfiguration.current
        let scenarios = DemoScenarios.catalogue
        let library = launch.usesTransientReviews
            ? ReplayReviewLibrary(scenarios: scenarios)
            : ReplayReviewLibrary.persistent(scenarios: scenarios)
        let store = ReplayStore(scenarios: scenarios, reviewLibrary: library)
        if !launch.usesTransientReviews { store.restoreAutosavedReview() }
        store.prepareForLocalExperience()
        let sharedSpace = LocalPitchAnchorCoordinator()
        sharedSpace.onSelectedAnchorRemoved = { [weak store] anchorID in
            store?.handleSharedPitchAnchorRemoval(anchorID)
        }
        store.onRetirePitchAnchor = { [weak sharedSpace] anchorID in
            sharedSpace?.retireLocallyPlacedPitchAnchor(ifMatching: anchorID)
        }
        _store = State(initialValue: store)
        _sharedSpace = State(initialValue: sharedSpace)
        _macCoachService = State(initialValue: ReplayXILocalCoachService(store: store))
        _launchSession = State(initialValue: ReplayLaunchSession(configuration: launch))
    }

    var body: some Scene {
        WindowGroup(id: "ReplayDashboard") {
            VStack(spacing: 0) {
                ReplayDashboardView()
                ReplayXIMacPairingBar(service: macCoachService)
            }
            .environment(store)
            .environment(sharedSpace)
            .environment(comparisonSession)
            .environment(annotationEntry)
            .environment(launchSession)
            // Outside the dashboard's transition lock, so Cancel remains
            // reachable while resource preparation disables navigation.
            .overlay {
                if store.isOpeningImmersive {
                    VStack(spacing: 16) {
                        ProgressView().controlSize(.large)
                        Text(store.statusMessage)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Cancel") { ReplayRoomLauncher.cancelPendingOpen(for: store) }
                            .buttonStyle(.bordered)
                            .disabled(!ReplayRoomLauncher.canCancelPendingOpen(for: store))
                            .accessibilityLabel("Cancel room preparation")
                    }
                    .padding(28)
                    .frame(width: 360)
                    .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 24))
                }
            }
        }
        .defaultSize(width: 1_380, height: 820)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flushReviewAutosave() }
            if phase == .background { ReplayRoomLauncher.cancelPendingOpen(for: store) }
        }

        WindowGroup(id: "ReplayVideoComparison", for: String.self) { _ in
            ReplayReferenceVideoWindow()
                .environment(store)
                .environment(comparisonSession)
                .environment(annotationEntry)
        }
        .defaultSize(width: 1_280, height: 760)
        .windowResizability(.contentMinSize)

        ImmersiveSpace(id: "ReplayRoom", for: UUID.self) { $requestID in
            if let requestID {
                FootballImmersiveView(roomPresentationID: requestID)
                    .id(requestID)
                    .environment(store)
                    .environment(sharedSpace)
                    .environment(annotationEntry)
            }
        }
        .immersionStyle(selection: immersionStyle, in: .mixed, .full)
    }
}
