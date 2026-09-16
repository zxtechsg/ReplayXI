import SwiftUI

struct ReplayDashboardView: View {
    @Environment(ReplayStore.self) private var store
    @Environment(LocalPitchAnchorCoordinator.self) private var sharedSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HStack(spacing: 0) {
            ScenarioRail()
                .frame(width: 286)

            Divider().opacity(0.5)

            ScenarioWorkspace(openRoom: openRoom)
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
                "--replayxi-world-replay": "real-world-match-replay"
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
            if arguments.contains("--replayxi-autostart") {
                try? await Task.sleep(for: .milliseconds(750))
                openRoom()
            }
            #endif
        }
    }

    private func openRoom() {
        guard let requestID = store.beginImmersiveOpen() else { return }
        Task {
            do {
                // Meshes and geometric shirt digits are finite and shared.
                // Warm them before RealityView starts its frame loop so the
                // first close player or impact cue cannot hitch playback.
                try ReplayAthleteFactory.prewarm(
                    for: store.scenarios.flatMap(\.players),
                    lods: [.near, .far]
                )
                // An explicit developer opt-in may admit one hash-locked CC0
                // skinned athlete for profiling. The pilot is fail-soft and
                // never blocks the room. It remains separate from the licensed
                // Rocketbox body and the procedural football-action fallback.
                _ = try? ReplayImportedAthleteProvider.prewarm()
                // The licensed single-skeleton body is prepared once before
                // presentation. Failed admission keeps the working fallback.
                do {
                    try ReplaySkinnedAthleteProvider.prewarm()
                } catch {
                    #if DEBUG
                    print("Replay XI skinned-player preparation failed; using standard rig: \(error)")
                    #endif
                }
                // Optional visual admission; a missing/corrupt asset retains the
                // procedural ball without blocking playback or loading per frame.
                do {
                    try ReplayStrategyBallProvider.prewarm()
                } catch {
                    #if DEBUG
                    print("Replay XI Blender ball unavailable; using standard ball: \(error)")
                    #endif
                }
                do {
                    try ReplayStrategyPitchProvider.prewarm()
                } catch {
                    #if DEBUG
                    print("Replay XI Blender pitch unavailable; using standard pitch: \(error)")
                    #endif
                }
            } catch {
                guard store.completeImmersiveOpen(requestID, opened: false) else { return }
                store.statusMessage = "Player renderer could not prepare. Try opening the room again."
                return
            }
            await Task.yield()
            guard store.roomPresentation.isOpeningRequest(requestID) else { return }
            store.statusMessage = "Opening spatial replay…"
            let result = await openImmersiveSpace(id: "ReplayRoom", value: requestID)
            guard store.completeImmersiveOpen(requestID, opened: result == .opened) else { return }
            if result == .opened {
                dismissWindow(id: "ReplayDashboard")
            } else {
                store.statusMessage = "The immersive room did not open. Try again."
            }
        }
    }
}

private struct ScenarioRail: View {
    @Environment(ReplayStore.self) private var store
    @State private var showsSavedReviews = false
    @State private var showsExercises = true
    @State private var lastScenarioByMode: [ReplayAppMode: String] = [:]

    private var activeMode: ReplayAppMode { ReplayAppMode(scenario: store.selectedScenario) }
    private var modeScenarios: [ReplayScenario] { activeMode.scenarios(in: store.scenarios) }
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
                            Text(activeMode == .situationRoleplay ? "Exercises" : "Replay demo")
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
                ReplayReviewLibraryView { showsSavedReviews = false }
                    .padding(16)
                    .frame(width: 820, height: 390)
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
                Text(ReplayAppMode.exerciseTitle(for: scenario))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ScenarioWorkspace: View {
    @Environment(ReplayStore.self) private var store

    let openRoom: () -> Void

    var scenario: ReplayScenario { store.selectedScenario }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 9) {
                        Eyebrow(text: "DEMO \(scenario.kind.number)  /  \(scenario.matchContext)")
                        Text(scenario.title)
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .tracking(-1.0)
                        Text(scenario.objective)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 20)
                    StatusPill(text: store.viewMode.title, systemImage: store.viewMode.systemImage)
                }

                if scenario.kind == .shapeLab {
                    HStack(spacing: 10) {
                        MetricTile(value: "3", label: "Role stations")
                        MetricTile(value: "2", label: "Passing lanes")
                        MetricTile(value: "1", label: "Local origin")
                        MetricTile(value: "0", label: "Running required")
                    }
                }

                if scenario.kind == .realWorldReplay {
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
                        enabled: item != .physical || store.localRole == .coach,
                        action: { select(item) }
                    )
                }
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
                } else {
                    Button {
                        showProblem()
                    } label: {
                        Label("Compare problem", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)

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
        guard store.localRole == .coach else { return }
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
                        text: "Viewing • \(player.team.compactTitle) • #\(player.shirtNumber) \(player.role)",
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
                .disabled(playbackControlsAreDisabled)

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

                Button {
                    store.skip(by: 1)
                } label: {
                    Text("+1s")
                        .font(.caption.monospacedDigit().weight(.black))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Forward one second")
                .disabled(playbackControlsAreDisabled)

                Slider(
                    value: Binding(
                        get: { store.playhead },
                        set: { previewScrub(to: $0) }
                    ),
                    in: 0...max(scenario.duration, 0.1),
                    step: 0.1,
                    onEditingChanged: handleScrubbing
                )
                .tint(ReplayTheme.signal)
                .controlSize(.large)
                .accessibilityLabel("Replay position")
                .accessibilityValue(
                    "\(formatTime(store.playhead)) of \(formatTime(scenario.duration)) seconds"
                )
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
                .disabled(playbackControlsAreDisabled)
            }
        }
        .padding(16)
        .background(ReplayTheme.panel, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(ReplayTheme.signal.opacity(0.20), lineWidth: 1)
        }
        .onDisappear {
            store.cancelTimelineScrub()
        }
    }

    private var playbackControlsAreDisabled: Bool {
        store.hasActiveCoachMarkGeometryPreview
    }



    private var playbackIcon: String { store.isActivelyPlaying ? "pause.fill" : "play.fill" }

    private var playbackLabel: String { store.isActivelyPlaying ? "Pause replay" : "Play replay" }

    private func handleScrubbing(_ editing: Bool) {
        if editing {
            _ = store.beginTimelineScrub()
            return
        }

        let finalPlayhead = store.playhead
        guard store.commitTimelineScrub(to: finalPlayhead) else { return }
        store.flushReviewAutosave()
    }

    private func previewScrub(to time: TimeInterval) {
        if store.hasActiveTimelineScrub {
            _ = store.previewTimelineScrub(to: time)
        } else {
            // Accessibility adjustments can update a Slider without opening a
            // continuous drag. Keep that discrete route bounded and local.
            store.seek(to: time, broadcast: false)
        }
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

private struct PlaybackConsole: View {
    @Environment(ReplayStore.self) private var store
    @State private var rosterTeam: FootballTeam = .home

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
                        .disabled(store.hasActiveCoachMarkGeometryPreview)
                    }
                }
            }

            Rectangle().fill(ReplayTheme.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Eyebrow(text: "Players")
                    Picker("Team", selection: $rosterTeam) {
                        ForEach(FootballTeam.allCases) { team in
                            Text(team.shortTitle).tag(team)
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
                    .accessibilityLabel("Previous player lens")

                    Button {
                        openAdjacentPlayerPOV(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Next player lens")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(playersForRoster) { player in
                            Button {
                                store.openLocalPlayerPOV(player.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("#\(player.shirtNumber)  \(player.positionCode)")
                                        .font(.caption.weight(.black))
                                    Text(player.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(minWidth: 112, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .tint(store.activePerspectiveID == player.id ? ReplayTheme.signal : .white.opacity(0.5))
                        }
                    }
                }
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
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.bordered)
                            .tint(store.viewMode == mode ? ReplayTheme.signal : .white.opacity(0.5))
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

private struct RoomRail: View {
    @Environment(ReplayStore.self) private var store
    @Environment(LocalPitchAnchorCoordinator.self) private var sharedSpace

    let openRoom: () -> Void

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
                HStack {
                    Eyebrow(text: "Home XI perspectives")
                    Spacer()
                    Text("11 SIMULATED")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(store.selectedScenario.homePlayers) { player in
                            SeatRow(
                                player: player,
                                state: seatState(playerID: player.id),
                                selected: store.localPerspectiveID == player.id
                            ) {
                                store.setLocalPerspective(player.id)
                            }
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
                    Label(
                        store.isClosingImmersive ? "Closing room…"
                            : store.isOpeningImmersive ? "Opening room…" : "Enter spatial replay",
                        systemImage: "visionpro"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(ReplayTheme.signal)
                .foregroundStyle(.black)
                .disabled(store.isRoomPresentationBusy)

                Text(store.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(18)
            .background(Color.black.opacity(0.22))
        }
    }



    private func seatState(playerID: String) -> String {
        store.localPerspectiveID == playerID ? "VIEWING" : "SIM"
    }
}

private struct SeatRow: View {
    let player: PlayerTrack
    let state: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text("\(player.shirtNumber)")
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(selected ? .black : .white)
                    .frame(width: 27, height: 27)
                    .background(selected ? ReplayTheme.signal : Color.white.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.role)
                        .font(.caption.weight(.bold))
                    Text(selected ? "PLAYER POV" : player.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(state)
                    .font(.caption2.monospaced().weight(.black))
                    .foregroundStyle(
                        state == "LIVE" ? ReplayTheme.signal
                            : (state == "VIEWING" ? ReplayTheme.cyan : .secondary)
                    )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(selected ? Color.white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
