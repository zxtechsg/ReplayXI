import SwiftUI

struct ReplayDashboardView: View {
    @Environment(ReplayStore.self) private var store
    @Environment(LocalPitchAnchorCoordinator.self) private var sharedSpace
    @Environment(ReplayConversionPreviewSession.self) private var comparisonSession
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            ScenarioRail()
                .frame(width: 286)

            Divider().opacity(0.5)

            ScenarioWorkspace(openRoom: openRoom, openComparison: openComparison)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.5)

            RoomRail(openRoom: openRoom)
                .frame(width: 278)
        }
        .background {
            ZStack {
                Color.black.opacity(0.72)
                RadialGradient(
                    colors: [ReplayTheme.pitch.opacity(0.48), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 760
                )
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        // Keep a second gesture from starting while presentation is in flight.
        // An already-open room remains interactive if this window is reopened.
        .disabled(store.isOpeningImmersive || store.isClosingImmersive)
        .task {
            let clock = ContinuousClock()
            var previous = clock.now
            while !Task.isCancelled {
                let shouldAdvance = store.isActivelyPlaying && !store.isImmersiveOpen
                try? await Task.sleep(
                    for: ReplayPresentationClock.interval(shouldAdvance: shouldAdvance)
                )
                guard !Task.isCancelled else { return }
                let now = clock.now
                let duration = previous.duration(to: now)
                previous = now
                guard shouldAdvance else { continue }
                store.advance(by: ReplayPresentationClock.seconds(duration))
            }
        }
        .task {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            let scenarioArguments = [
                "--replayxi-eleven-eyes": "eleven-eyes",
                "--replayxi-coach-focus": "everyone-with-seven",
                "--replayxi-shape-lab": "triangle-lock",
                "--replayxi-lane-lens": "lane-lens",
                "--replayxi-four-minds": "four-minds",
                "--replayxi-world-replay": "real-world-match-replay",
                "--replayxi-final-counter": "final-36-counter-v2",
                "--replayxi-final-volley": "final-81-volley-v2",
                "--replayxi-final-rebound": "final-108-rebound-v2",
                "--replayxi-city-header": "city-45-overlap-header",
                "--replayxi-city-cutback": "city-57-underlap-cutback"
            ]
            if let scenarioID = scenarioArguments.first(where: { arguments.contains($0.key) })?.value {
                store.selectScenario(id: scenarioID, broadcast: false)
                if scenarioID == "triangle-lock" {
                    let stage: ShapeFocusStage = arguments.contains("--replayxi-shape-ideal")
                        ? .ideal
                        : .problem
                    store.setShapeFocusStage(stage, broadcast: false)
                } else {
                    let showcaseTimes: [String: TimeInterval] = [
                        "eleven-eyes": 13.6,
                        "everyone-with-seven": 9.8,
                        "lane-lens": 13.2,
                        "four-minds": 12.8,
                        "real-world-match-replay": 13.6
                    ]
                    store.seek(to: showcaseTimes[scenarioID] ?? 0, broadcast: false)
                }
            }
            if arguments.contains("--replayxi-player-pov") {
                store.openLocalPlayerPOV(store.localPerspectiveID)
            }
            if arguments.contains("--replayxi-impact") {
                store.seek(to: 14.1, broadcast: false)
            }
            if arguments.contains("--replayxi-annotation-draft") {
                store.beginDrawing(.pass)
                _ = store.registerPitchTap(PitchPoint(x: 20, z: 18))
            }
            if arguments.contains("--replayxi-coach-mark") {
                store.beginDrawing(.pass)
                _ = store.registerPitchTap(PitchPoint(x: 14, z: 9))
                _ = store.registerPitchTap(PitchPoint(x: 25, z: 22))
            }
            if arguments.contains("--replayxi-arc-review") {
                store.beginDrawing(.arc)
                _ = store.registerPitchTap(PitchPoint(x: 5, z: 5))
                if let mark = store.registerPitchTap(PitchPoint(x: 24, z: 20)) {
                    _ = store.updateCoachMarkGeometry(id: mark.id, start: mark.start, end: mark.end,
                                                       curve: .init(bend: 4, lift: 1))
                }
            }
            if arguments.contains("--replayxi-comparison") {
                openComparison()
            }
            if arguments.contains("--replayxi-autostart") {
                try? await Task.sleep(for: .milliseconds(750))
                openRoom()
            }
            #endif
        }
    }

    private func openRoom() {
        ReplayRoomLauncher.open(store: store, openImmersiveSpace: openImmersiveSpace,
                                dismissWindow: dismissWindow)
    }

    private func openComparison() {
        guard FootballReferenceScenarios.contains(store.selectedScenario),
              !store.hasActiveTimelineScrub, !store.hasActiveCoachMarkGeometryPreview,
              !store.isRoomPresentationBusy else { return }
        comparisonSession.capture(scenario: store.selectedScenario, marks: store.marks,
                                  playhead: store.playhead, perspectiveID: store.activePerspectiveID)
        // A fixed typed window identity reuses the comparison instead of
        // starting another renderer and playback clock on repeated taps.
        openWindow(id: "ReplayVideoComparison", value: "reference-comparison")
    }
}

private struct ScenarioRail: View {
    @Environment(ReplayStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsSavedReviews = false
    @State private var showsExercises = true
    @State private var lastScenarioByMode: [ReplayAppMode: String] = [:]

    private var activeMode: ReplayAppMode { ReplayAppMode(scenario: store.selectedScenario) }
    private var modeScenarios: [ReplayScenario] { activeMode.featuredScenarios(in: store.scenarios) }
    private var navigationIsDisabled: Bool {
        store.hasActiveTimelineScrub || store.hasActiveCoachMarkGeometryPreview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(ReplayTheme.signal)
                            .frame(width: 38, height: 38)
                        Text("XI")
                            .font(.headline.monospaced().weight(.black))
                            .foregroundStyle(.black)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("REPLAY XI")
                            .font(.headline.monospaced().weight(.black))
                        Text("SPATIAL FILM ROOM")
                            .font(.caption2.monospaced().weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("See the play they saw.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
            .padding(22)

            Rectangle().fill(ReplayTheme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ReplayAppMode.allCases) { mode in
                        modeButton(mode)
                    }

                    Divider().padding(.vertical, 4)

                    Button {
                        showsExercises.toggle()
                    } label: {
                        HStack {
                            Text(activeMode == .situationRoleplay ? "Exercises" : "Match studies")
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            Text("\(modeScenarios.count)")
                                .foregroundStyle(.secondary).monospacedDigit()
                            Image(systemName: showsExercises ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.bold))
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsExercises ? "Collapse exercises" : "Show exercises")
                    .accessibilityValue(showsExercises ? "Expanded" : "Collapsed")

                    if showsExercises {
                        VStack(spacing: 6) {
                            ForEach(modeScenarios) { scenario in
                                ScenarioRailRow(
                                    scenario: scenario,
                                    selected: scenario.id == store.selectedScenarioID
                                ) {
                                    store.selectScenario(id: scenario.id)
                                }
                                .disabled(navigationIsDisabled)
                            }
                            if !modeScenarios.contains(where: { $0.id == store.selectedScenarioID }) {
                                Text("Previous review").font(.caption).foregroundStyle(.secondary)
                                ScenarioRailRow(scenario: store.selectedScenario, selected: true) {}
                            }
                        }
                    }
                }
                .padding(14)
            }
            Divider()
            Button {
                showsSavedReviews = true
            } label: {
                HStack {
                    Label("Saved reviews", systemImage: "bookmark")
                        .font(.headline)
                    Spacer(minLength: 4)
                    Text("\(store.savedReviews.count)")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .padding(14)
            .sheet(isPresented: $showsSavedReviews) {
                let libraryLayout = ReplayReviewLibraryLayout.resolve(
                    usesAccessibilityText: dynamicTypeSize.isAccessibilitySize)
                ReplayReviewLibraryView { showsSavedReviews = false }
                    .padding(16)
                    .frame(width: libraryLayout.sheetWidth, height: libraryLayout.sheetHeight, alignment: .topLeading)
                    .environment(store)
            }
        }
        .onChange(of: store.selectedScenarioID) { _, id in
            lastScenarioByMode[activeMode] = id
        }
        .task {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--replayxi-saved-reviews") {
                if store.savedReviews.isEmpty { store.saveReview(named: "Right-wing return") }
                showsSavedReviews = !arguments.contains("--replayxi-autostart")
            }
            #endif
        }
    }

    private func modeButton(_ mode: ReplayAppMode) -> some View {
        let isSelected = activeMode == mode
        return Button {
            lastScenarioByMode[activeMode] = store.selectedScenarioID
            showsExercises = true
            guard let id = mode.scenarioID(
                in: store.scenarios,
                preferredID: lastScenarioByMode[mode]
            ) else { return }
            store.selectScenario(id: id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mode.systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 30)
                    .foregroundStyle(isSelected ? ReplayTheme.signal : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title)
                        .font(.headline).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(mode.subtitle)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(12)
            .background(isSelected ? ReplayTheme.signal.opacity(0.09) : .white.opacity(0.025),
                        in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(isSelected ? ReplayTheme.signal.opacity(0.4) : ReplayTheme.hairline,
                            lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(navigationIsDisabled)
        .accessibilityLabel("\(mode.title), \(mode.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ScenarioRailRow: View {
    let scenario: ReplayScenario
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: scenario.kind.systemImage)
                    .font(.subheadline)
                    .frame(width: 24)
                    .foregroundStyle(selected ? ReplayTheme.signal : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ReplayAppMode.exerciseTitle(for: scenario))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if let reference = ReplayReferenceLibrary.reference(for: scenario.id) {
                        Label(reference.shortLabel, systemImage: "play.rectangle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ReplayTheme.signal)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(selected ? Color.white.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(selected ? ReplayTheme.signal.opacity(0.36) : Color.white.opacity(0.055), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ReplayAppMode.exerciseTitle(for: scenario))
        .accessibilityValue(ReplayReferenceLibrary.reference(for: scenario.id)?.shortLabel ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ScenarioWorkspace: View {
    @Environment(ReplayStore.self) private var store

    let openRoom: () -> Void
    let openComparison: () -> Void

    var scenario: ReplayScenario { store.selectedScenario }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 9) {
                        Eyebrow(text: FootballReferenceScenarios.contains(scenario)
                            ? "RECONSTRUCTION  /  \(scenario.matchContext)"
                            : "DEMO \(scenario.kind.number)  /  \(scenario.matchContext)")
                        Text(scenario.title)
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .tracking(-1.0)
                        if let reference = ReplayReferenceLibrary.reference(for: scenario.id) {
                            ReplayVideoReferenceButton(reference: reference)
                        }
                        Text(scenario.objective)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 20)
                    StatusPill(text: store.viewMode.title, systemImage: store.viewMode.systemImage)
                }

                if FootballReferenceScenarios.contains(scenario) {
                    Button(action: openComparison) {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.split.2x1")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Video → Replay").font(.headline)
                                Text("Concept demo · compare video with 3D")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.forward")
                        }
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.hasActiveTimelineScrub || store.hasActiveCoachMarkGeometryPreview
                              || store.isRoomPresentationBusy)
                    .accessibilityHint("Opens source video beside an authored 3D replay, not automatic conversion")
                }

                if scenario.kind == .shapeLab {
                    HStack(spacing: 10) {
                        MetricTile(value: "3", label: "Role stations")
                        MetricTile(value: "2", label: "Passing lanes")
                        MetricTile(value: "1", label: "Local origin")
                        MetricTile(value: "0", label: "Running required")
                    }
                }

                if scenario.kind == .realWorldReplay && ReplayReferenceLibrary.reference(for: scenario.id) == nil {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "cube.transparent")
                            .font(.title2).foregroundStyle(ReplayTheme.cyan)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Demo match · no video loaded").font(.headline)
                            Text("Replay authored player paths, switch POVs and add 3D marks. These movements are simulated, not measured from footage.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ReplayTheme.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }

                TacticalPreview(
                    scenario: scenario,
                    time: store.playhead,
                    marks: store.marks,
                    highlightedPlayerID: store.activePerspectiveID,
                    showsSightCones: store.viewMode == .firstPerson
                        || scenario.kind == .perspectiveMatrix
                        || scenario.kind == .squadReplay,
                    shapeFocusStage: scenario.kind == .shapeLab ? store.shapeFocusStage : nil
                )
                .frame(height: scenario.kind == .shapeLab ? 310 : 290)

                if scenario.kind == .shapeLab {
                    ShapeFocusDashboard(openRoom: openRoom)
                } else {
                    DashboardTransport()
                    PlaybackConsole()
                }
            }
            .padding(26)
        }
    }
}

private enum ShapeFocusStep: Int, CaseIterable, Identifiable {
    case problem = 1
    case ideal = 2
    case physical = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .problem: "Problem"
        case .ideal: "Ideal"
        case .physical: "Physical"
        }
    }

    var detail: String {
        switch self {
        case .problem: "See the blocked angle"
        case .ideal: "Open two lanes"
        case .physical: "Place room stations"
        }
    }

    var systemImage: String {
        switch self {
        case .problem: "exclamationmark.triangle.fill"
        case .ideal: "arrow.triangle.branch"
        case .physical: "figure.stand"
        }
    }
}

private struct ShapeFocusDashboard: View {
    @Environment(ReplayStore.self) private var store

    let openRoom: () -> Void

    private var stage: ShapeFocusStep {
        if store.triangleLockMode == .place { return .physical }
        return store.shapeFocusStage == .ideal ? .ideal : .problem
    }

    private var canEnterSpatialSetup: Bool {
        store.localRole == .coach && !store.isRoomPresentationBusy
            && !store.hasActiveTimelineScrub && !store.hasActiveCoachMarkGeometryPreview
    }

    private var canCompareShapes: Bool {
        store.triangleLockMode != .place && store.canChangePlaybackView
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(text: "Shape Focus", color: stageColor)
                    Text("One clear progression: diagnose, correct, then place.")
                        .font(.headline.weight(.black))
                }
                Spacer()
                StatusPill(
                    text: "STEP \(stage.rawValue) OF 3 • \(stage.title.uppercased())",
                    systemImage: stage.systemImage,
                    color: stageColor
                )
            }

            HStack(spacing: 10) {
                ForEach(ShapeFocusStep.allCases) { item in
                    ShapeFocusStepButton(
                        stage: item,
                        currentStage: stage,
                        enabled: item == .physical ? canEnterSpatialSetup : canCompareShapes,
                        action: { select(item) }
                    )
                }
            }

            if let hint = roomEntryGestureHint(for: store) {
                Label(hint, systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(ReplayTheme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(stageHeadline, systemImage: stage.systemImage)
                        .font(.title3.weight(.black))
                        .foregroundStyle(stageColor)

                    Text(stageExplanation)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)

                    Label(
                        stage == .problem
                            ? "One cover shadow screens both forward options."
                            : "The source keeps a wide return and an outside overlap.",
                        systemImage: stage == .problem ? "nosign" : "arrow.triangle.branch"
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(stage == .problem ? ReplayTheme.orange : ReplayTheme.signal)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 166, alignment: .topLeading)
                .background(stageColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(stageColor.opacity(0.24), lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Eyebrow(text: stage == .problem ? "Correction to teach" : "Three distinct roles")
                    ForEach(store.selectedScenario.formationTargets) { target in
                        shapeRoleRow(target)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 166, alignment: .topLeading)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            }

            HStack(spacing: 10) {
                if stage == .problem {
                    Button {
                        showIdeal()
                    } label: {
                        Label("Reveal the corrected shape", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ReplayTheme.signal)
                    .foregroundStyle(.black)
                    .disabled(!canCompareShapes)
                } else {
                    Button {
                        showProblem()
                    } label: {
                        Label("Compare problem", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canCompareShapes)

                    if store.localRole == .coach {
                        Button {
                            enterSpatialSetup()
                        } label: {
                            Label("Open physical setup", systemImage: "visionpro")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ReplayTheme.signal)
                        .foregroundStyle(.black)
                        .disabled(!canEnterSpatialSetup)
                    } else {
                        Label("The coach starts physical setup", systemImage: "person.badge.key")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 4)

                StatusPill(
                    text: "LOCAL POSITIONING",
                    systemImage: "person.crop.circle",
                    color: ReplayTheme.cyan
                )
            }

            Label(
                "Station markers stay on this device. Use a clear 5 m × 3 m area, confirm it is safe, and never run in the headset.",
                systemImage: "checkmark.shield.fill"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(ReplayTheme.panel, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(stageColor.opacity(0.22), lineWidth: 1)
        }
    }

    private var stageColor: Color {
        switch stage {
        case .problem: ReplayTheme.orange
        case .ideal: ReplayTheme.signal
        case .physical: ReplayTheme.cyan
        }
    }

    private var stageHeadline: String {
        switch stage {
        case .problem: "Problem: the unit collapses into one line"
        case .ideal: "Ideal: the triangle creates two exits"
        case .physical: "Physical: learn the spacing at room scale"
        }
    }

    private var stageExplanation: String {
        switch stage {
        case .problem:
            "#8 starts on the ball. #7 and #2 sit on one passing angle, so the cover shadow removes both forward options."
        case .ideal:
            "#8 stays inside and beneath the play, #7 holds the wide return, and #2 goes outside and beyond."
        case .physical:
            "Choose a role station and compare your headset position with the local triangle."
        }
    }

    @ViewBuilder
    private func shapeRoleRow(_ target: FormationTarget) -> some View {
        if let player = store.selectedScenario.player(id: target.playerID) {
            HStack(spacing: 9) {
                Text("#\(player.shirtNumber)")
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 26)
                    .background(ReplayTheme.signal, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.role)
                        .font(.caption.weight(.black))
                    Text(target.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func select(_ nextStage: ShapeFocusStep) {
        switch nextStage {
        case .problem: showProblem()
        case .ideal: showIdeal()
        case .physical: enterSpatialSetup()
        }
    }

    private func showProblem() {
        store.setShapeFocusStage(.problem)
    }

    private func showIdeal() {
        store.setShapeFocusStage(.ideal)
    }

    private func enterSpatialSetup() {
        guard canEnterSpatialSetup else { return }
        showIdeal()
        openRoom()
    }
}

private struct ShapeFocusStepButton: View {
    let stage: ShapeFocusStep
    let currentStage: ShapeFocusStep
    let enabled: Bool
    let action: () -> Void

    private var isCurrent: Bool { stage == currentStage }
    private var isComplete: Bool { stage.rawValue < currentStage.rawValue }
    private var color: Color {
        switch stage {
        case .problem: ReplayTheme.orange
        case .ideal: ReplayTheme.signal
        case .physical: ReplayTheme.cyan
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isCurrent || isComplete ? color : Color.white.opacity(0.08))
                        .frame(width: 34, height: 34)
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.black)
                    } else {
                        Text("\(stage.rawValue)")
                            .font(.caption.monospacedDigit().weight(.black))
                            .foregroundStyle(isCurrent ? .black : .secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(stage.title)
                        .font(.caption.weight(.black))
                    Text(stage.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: stage.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isCurrent ? color : .secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? color.opacity(0.09) : Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(isCurrent ? color.opacity(0.40) : Color.white.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .accessibilityLabel("Step \(stage.rawValue), \(stage.title). \(stage.detail)")
    }
}

private struct DashboardTransport: View {
    @Environment(ReplayStore.self) private var store
    @State private var scrubController = DashboardTimelineScrubController()

    private var scenario: ReplayScenario { store.selectedScenario }

    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Match timeline")
                    Text("\(formatTime(store.playhead)) / \(formatTime(scenario.duration))")
                        .font(.title3.monospacedDigit().weight(.black))
                }

                Spacer(minLength: 12)

                if let player = store.activePerspective {
                    StatusPill(
                        text: "\(store.viewMode == .firstPerson ? "POV" : "Selected") • \(player.team.compactTitle) • #\(player.shirtNumber) \(player.role)",
                        systemImage: "viewfinder",
                        color: player.team == .home ? ReplayTheme.cyan : ReplayTheme.danger
                    )
                }
            }

            HStack(spacing: 12) {
                Button {
                    store.skip(by: -1)
                } label: {
                    Text("−1s")
                        .font(.caption.monospacedDigit().weight(.black))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Back one second")
                .disabled(!store.canChangePlaybackView)

                Button {
                    store.togglePlayback()
                } label: {
                    Image(systemName: playbackIcon)
                        .frame(width: 26)
                }
                .buttonStyle(.borderedProminent)
                .tint(ReplayTheme.signal)
                .foregroundStyle(.black)
                .accessibilityLabel(playbackLabel)
                .disabled(!store.canChangePlaybackView)

                Button {
                    store.skip(by: 1)
                } label: {
                    Text("+1s")
                        .font(.caption.monospacedDigit().weight(.black))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Forward one second")
                .disabled(!store.canChangePlaybackView)

                Slider(
                    value: Binding(
                        get: { store.playhead },
                        set: { previewScrub(to: $0) }
                    ),
                    in: 0...max(scenario.duration, 0.1),
                    step: DashboardTimelineScrubController.step,
                    onEditingChanged: handleScrubbing
                )
                .tint(ReplayTheme.signal)
                .controlSize(.large)
                .accessibilityLabel("Replay position")
                .accessibilityValue(
                    "\(formatTime(store.playhead)) of \(formatTime(scenario.duration)) seconds"
                )
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: _ = scrubController.adjustDiscrete(direction: 1, in: store)
                    case .decrement: _ = scrubController.adjustDiscrete(direction: -1, in: store)
                    @unknown default: break
                    }
                }
                .disabled(playbackControlsAreDisabled)

                Menu {
                    ForEach(ReplayStore.availablePlaybackRates, id: \.self) { rate in
                        Button {
                            store.setPlaybackRate(rate)
                        } label: {
                            if rate == store.playbackRate {
                                Label(rateLabel(rate), systemImage: "checkmark")
                            } else {
                                Text(rateLabel(rate))
                            }
                        }
                    }
                } label: {
                    Label(rateLabel(store.playbackRate), systemImage: "speedometer")
                        .font(.caption.monospacedDigit().weight(.black))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Playback speed, \(rateLabel(store.playbackRate))")
                .disabled(!store.canChangePlaybackView)
            }

            if let editingHint {
                Label(editingHint, systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(ReplayTheme.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(ReplayTheme.panel, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(ReplayTheme.signal.opacity(0.20), lineWidth: 1)
        }
        .onAppear { scrubController.appear() }
        .onDisappear { scrubController.disappear(in: store) }
    }

    private var playbackControlsAreDisabled: Bool {
        // Keep this slider enabled for its own drag, never for another rail's.
        store.isDrawing || store.hasActiveCoachMarkGeometryPreview || !scrubController.isEnabled(in: store)
    }

    private var editingHint: String? {
        if store.isDrawing { return "Finish or cancel your annotation to use playback and POV controls." }
        if store.hasActiveCoachMarkGeometryPreview { return "Release the annotation handle to use playback and POV controls." }
        if store.hasActiveTimelineScrub, !scrubController.ownsScrub(in: store) { return "Finish the other timeline gesture first." }
        return nil
    }

    private var playbackIcon: String { store.isActivelyPlaying ? "pause.fill" : "play.fill" }

    private var playbackLabel: String { store.isActivelyPlaying ? "Pause replay" : "Play replay" }

    private func handleScrubbing(_ editing: Bool) {
        if editing {
            _ = scrubController.begin(in: store)
            return
        }
        guard scrubController.finish(in: store) else { return }
        store.flushReviewAutosave()
    }

    private func previewScrub(to time: TimeInterval) {
        _ = scrubController.valueChanged(to: time, in: store)
    }

    private func formatTime(_ value: TimeInterval) -> String {
        String(format: "%05.2f", max(value, 0))
    }

    private func rateLabel(_ rate: Double) -> String {
        rate == rate.rounded()
            ? "\(Int(rate))×"
            : "\(rate.formatted(.number.precision(.fractionLength(2))))×"
    }
}

struct PlaybackConsole: View {
    @Environment(ReplayStore.self) private var store
    @State private var rosterTeam: FootballTeam = .home
    @State private var rosterScrollID: String?

    var scenario: ReplayScenario { store.selectedScenario }

    var body: some View {
        VStack(spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(text: "Player & view")
                }
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    Text("CUES")
                        .font(.caption2.monospaced().weight(.black))
                        .foregroundStyle(.secondary)
                    ForEach(scenario.moments) { moment in
                        Button {
                            store.setPlaying(false, broadcast: false)
                            store.seek(to: moment.time)
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(moment.id == store.activeMoment?.id ? ReplayTheme.orange : ReplayTheme.signal)
                                    .frame(width: 6, height: 6)
                                Text("\(formatTime(moment.time))  \(moment.headline)")
                                    .lineLimit(1)
                            }
                            .font(.caption2.weight(.bold))
                        }
                        .buttonStyle(.bordered)
                        .tint(moment.id == store.activeMoment?.id ? ReplayTheme.orange : .white.opacity(0.45))
                        .disabled(!store.canChangePlaybackView)
                    }
                }
            }

            Rectangle().fill(ReplayTheme.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Eyebrow(text: "Players")
                    Picker("Team", selection: $rosterTeam) {
                        ForEach(FootballTeam.allCases) { team in
                            Text(FootballReferenceScenarios.teamTitle(team, in: store.selectedScenario)).tag(team)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 330)

                    Spacer()

                    Button {
                        openAdjacentPlayerPOV(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Previous player POV")
                    .disabled(!store.canChangePlaybackView)

                    Button {
                        openAdjacentPlayerPOV(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Next player POV")
                    .disabled(!store.canChangePlaybackView)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(playersForRoster) { player in
                            let isSelected = store.viewMode == .firstPerson && store.activePerspectiveID == player.id
                            Button {
                                store.openLocalPlayerPOV(player.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("#\(player.shirtNumber)  \(player.positionCode)")
                                        .font(.caption.weight(.black))
                                    Text(player.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(isSelected ? Color.black.opacity(0.72) : Color.secondary)
                                }
                                .frame(minWidth: 112, alignment: .leading)
                                .foregroundStyle(isSelected ? Color.black : Color.white)
                            }
                            .buttonStyle(.bordered)
                            .tint(isSelected ? ReplayTheme.signal : .white.opacity(0.10))
                            .disabled(!store.canChangePlaybackView)
                            .accessibilityLabel("\(FootballReferenceScenarios.teamTitle(player.team, in: store.selectedScenario)), number \(player.shirtNumber), \(player.role), \(player.displayName)")
                            .accessibilityHint("Open this player's first-person view")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                            .id(player.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $rosterScrollID, anchor: .center)
                .accessibilityIdentifier("dashboard-player-roster")
            }

            HStack(alignment: .center, spacing: 14) {
                Label(
                    store.viewMode == .firstPerson
                        ? "Free look · position follows player · brackets show facing"
                        : "Switch views without changing the synchronized match clock.",
                    systemImage: store.viewMode == .firstPerson ? "move.3d" : "clock.arrow.2.circlepath"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(store.viewMode == .firstPerson ? ReplayTheme.signal : .secondary)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 7) {
                    Eyebrow(text: "View")
                    HStack(spacing: 7) {
                        ForEach(availableViewModes, id: \.self) { mode in
                            Button {
                                store.setViewMode(mode)
                            } label: {
                                Label(mode.title, systemImage: mode.systemImage)
                                    .labelStyle(.iconOnly)
                                    .font(.body.weight(.semibold))
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .tint(store.viewMode == mode ? ReplayTheme.signal : .white.opacity(0.10))
                            .foregroundStyle(store.viewMode == mode ? Color.black : Color.white)
                            .disabled(!store.canChangePlaybackView)
                            .help(mode.title)
                            .accessibilityLabel(mode.title)
                            .accessibilityAddTraits(store.viewMode == mode ? .isSelected : [])
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(ReplayTheme.panel, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).stroke(ReplayTheme.hairline, lineWidth: 1)
        }
        .onAppear { revealCurrentRosterPlayer() }
        .onChange(of: store.activePerspectiveID) { _, _ in revealCurrentRosterPlayer() }
        .onChange(of: store.selectedScenarioID) { _, _ in revealCurrentRosterPlayer() }
        .onChange(of: store.viewMode) { _, mode in
            if mode == .firstPerson { revealCurrentRosterPlayer() }
        }
        .onChange(of: rosterTeam) { _, _ in
            // Browsing another team never changes the camera or playhead.
            rosterScrollID = playersForRoster.first { $0.id == store.activePerspectiveID }?.id
                ?? playersForRoster.first?.id
        }
    }

    private var availableViewModes: [ReplayViewMode] {
        scenario.kind == .shapeLab
            ? [.positional, .tacticalTable, .firstPerson]
            : [.firstPerson, .tacticalTable, .touchline]
    }

    private func formatTime(_ value: TimeInterval) -> String {
        String(format: "%05.2f", max(value, 0))
    }

    private var playersForRoster: [PlayerTrack] {
        rosterTeam == .home ? scenario.homePlayers : scenario.awayPlayers
    }

    private func revealCurrentRosterPlayer() {
        guard let player = scenario.player(id: store.activePerspectiveID) else { return }
        rosterTeam = player.team
        rosterScrollID = player.id
    }

    private func openAdjacentPlayerPOV(by offset: Int) {
        guard let playerID = PlaybackPerspectiveNavigation.adjacentPlayerID(
            in: store.selectedScenario.players,
            activeID: store.activePerspectiveID,
            localFallbackID: store.localPerspectiveID,
            offset: offset
        ) else { return }
        store.openLocalPlayerPOV(playerID)
    }

}

/// Keeps a room role distinct from a camera choice. Only real formation
/// targets may be offered as stations; ordinary replay rows enter player POV.
struct DashboardPlayerRailContent {
    let scenario: ReplayScenario

    var isSelectingStation: Bool { scenario.kind == .shapeLab }
    var title: String { isSelectingStation ? "Role stations" : "Home XI · quick POV" }
    var instruction: String { isSelectingStation ? "Choose your room role." : "Select a player to enter POV." }

    var players: [PlayerTrack] {
        if isSelectingStation {
            return scenario.formationTargets.compactMap {
                scenario.player(id: $0.playerID)
            }
        }
        return scenario.homePlayers
    }

    func isSelected(playerID: String, perspectiveID: String, viewMode: ReplayViewMode) -> Bool {
        playerID == perspectiveID && (isSelectingStation || viewMode == .firstPerson)
    }

    @MainActor
    func select(playerID: String, in store: ReplayStore) {
        guard store.selectedScenarioID == scenario.id,
              let player = players.first(where: { $0.id == playerID }) else { return }
        if isSelectingStation {
            // The store returns no success flag. Capture the same input gate
            // before the synchronous call: an already-selected ID alone does
            // not prove success when drawing or another gesture blocks it.
            let acceptsSelection = store.canChangePlaybackView
            store.setLocalPerspective(playerID, entersLocalReview: false)
            if acceptsSelection,
               store.localPerspectiveID == playerID,
               let target = scenario.formationTargets.first(where: { $0.playerID == playerID }) {
                store.statusMessage = "Role station: #\(player.shirtNumber) · \(target.label)"
            }
        } else {
            store.openLocalPlayerPOV(playerID)
        }
    }
}

@MainActor
private func roomEntryGestureHint(for store: ReplayStore) -> String? {
    if store.hasActiveTimelineScrub { return "Finish the timeline drag before entering." }
    if store.hasActiveCoachMarkGeometryPreview { return "Finish the annotation adjustment before entering." }
    return nil
}

private struct RoomRail: View {
    @Environment(ReplayStore.self) private var store

    let openRoom: () -> Void

    private var playerRail: DashboardPlayerRailContent {
        DashboardPlayerRailContent(scenario: store.selectedScenario)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Your review")
                Label("Local experience", systemImage: "visionpro")
                    .font(.title3.weight(.bold))
                Text("Replay, switch players and annotate. Reviews stay on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)

            Rectangle().fill(ReplayTheme.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: playerRail.title)
                Text(playerRail.instruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(playerRail.players) { player in
                            DashboardPlayerRow(
                                player: player,
                                selected: isSelected(playerID: player.id),
                                isStation: playerRail.isSelectingStation
                            ) {
                                playerRail.select(playerID: player.id, in: store)
                            }
                            .disabled(!store.canChangePlaybackView)
                        }
                    }
                }
                .frame(maxHeight: 256)
            }
            .padding(18)

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 10) {
                Label("Stationary experience", systemImage: "figure.stand")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ReplayTheme.signal)
                Text("Stay seated or planted. Never run, tackle, or kick while wearing Vision Pro. Positioning uses headset location—not foot tracking.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: openRoom) {
                    Label(roomEntryTitle, systemImage: "visionpro")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(ReplayTheme.signal)
                .foregroundStyle(.black)
                .disabled(store.isRoomPresentationBusy)
                .disabled(store.hasActiveTimelineScrub || store.hasActiveCoachMarkGeometryPreview)

                if let roomEntryHint {
                    Text(roomEntryHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(Color.black.opacity(0.22))
        }
    }



    private var roomEntryTitle: String {
        switch store.roomPresentation.phase {
        case .closed: "Enter spatial replay"
        case .opening: "Opening room…"
        case .open: "Room open"
        case .closing: "Closing room…"
        }
    }

    private var roomEntryHint: String? {
        switch store.roomPresentation.phase {
        case .closed:
            return roomEntryGestureHint(for: store)
        case .opening: return "Preparing your spatial view."
        case .open: return "Use Exit in the room to return here."
        case .closing: return "Wait for the room to close before reopening."
        }
    }

    private func isSelected(playerID: String) -> Bool {
        playerRail.isSelected(
            playerID: playerID,
            perspectiveID: playerRail.isSelectingStation ? store.localPerspectiveID : store.activePerspectiveID,
            viewMode: store.viewMode
        )
    }
}

private struct DashboardPlayerRow: View {
    @Environment(ReplayStore.self) private var store

    let player: PlayerTrack
    let selected: Bool
    let isStation: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text("\(player.shirtNumber)")
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(selected ? .black : .white)
                    .frame(width: 30, height: 30)
                    .background(selected ? ReplayTheme.signal : Color.white.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.role)
                        .font(.subheadline.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(player.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? (isStation ? "checkmark.circle.fill" : "viewfinder") : "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selected ? ReplayTheme.signal : .secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(selected ? Color.white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(FootballReferenceScenarios.teamTitle(player.team, in: store.selectedScenario)), number \(player.shirtNumber), \(player.role), \(player.displayName)")
        .accessibilityHint(isStation ? "Choose this role station" : "Open this player's first-person view")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
