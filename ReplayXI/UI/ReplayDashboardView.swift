import SwiftUI

struct ReplayDashboardView: View {
    @Environment(ReplayStore.self) private var store
    @Environment(SquadSessionCoordinator.self) private var squadSession
    @Environment(SharedSpaceAnchorCoordinator.self) private var sharedSpace
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
            squadSession.startObserving()
        }
        .task {
            let clock = ContinuousClock()
            var previous = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                let now = clock.now
                let duration = previous.duration(to: now)
                previous = now
                if !store.isImmersiveOpen {
                    let seconds = Double(duration.components.seconds)
                        + (Double(duration.components.attoseconds) / 1e18)
                    store.advance(by: seconds)
                }
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
                "--replayxi-four-minds": "four-minds"
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
                        "four-minds": 12.8
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
        guard !store.isOpeningImmersive, !store.isImmersiveOpen else { return }
        store.setPlaying(false)
        store.isOpeningImmersive = true
        store.statusMessage = "Preparing match players…"
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
                // never blocks the room; normal demos retain the cleaner,
                // deterministic procedural squad until a replacement passes
                // the close-range visual and physical-device gates.
                _ = try? ReplayImportedAthleteProvider.prewarm()
            } catch {
                store.isOpeningImmersive = false
                store.statusMessage = "Player renderer could not prepare. Try opening the room again."
                return
            }
            await Task.yield()
            store.statusMessage = "Opening the shared review room…"
            let result = await openImmersiveSpace(id: "ReplayRoom")
            store.isImmersiveOpen = result == .opened
            store.isOpeningImmersive = false
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
    @Environment(SquadSessionCoordinator.self) private var squadSession

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
                LazyVStack(spacing: 9) {
                    ForEach(store.scenarios) { scenario in
                        ScenarioRailRow(
                            scenario: scenario,
                            selected: scenario.id == store.selectedScenarioID
                        ) {
                            store.selectScenario(id: scenario.id)
                        }
                        .disabled(store.localRole == .player && squadSession.state == .joined)
                    }
                }
                .padding(14)
            }

        }
    }
}

private struct ScenarioRailRow: View {
    let scenario: ReplayScenario
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(scenario.kind.number)
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(selected ? .black : ReplayTheme.signal)
                    .frame(width: 34, height: 34)
                    .background(selected ? ReplayTheme.signal : ReplayTheme.signal.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 4) {
                    Text(scenario.kind.shortLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(scenario.strapline)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
                Image(systemName: scenario.kind.systemImage)
                    .font(.caption)
                    .foregroundStyle(selected ? ReplayTheme.signal : .secondary)
            }
            .padding(12)
            .background(selected ? Color.white.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(selected ? ReplayTheme.signal.opacity(0.36) : Color.white.opacity(0.055), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scenario \(scenario.kind.number), \(scenario.kind.shortLabel), \(scenario.title)")
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
                        MetricTile(value: "1", label: "Shared origin")
                        MetricTile(value: "0", label: "Running required")
                    }
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
    @Environment(SquadSessionCoordinator.self) private var squadSession

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
                    text: squadSession.state == .joined ? "SQUAD READY" : "SOLO PREVIEW",
                    systemImage: squadSession.state == .joined ? "shareplay" : "person.crop.circle",
                    color: squadSession.state == .joined ? ReplayTheme.signal : .secondary
                )
            }

            Label(
                "Squad stations use nearby SharePlay; solo mode provides a local-only preview. Both require a clear 5 m × 3 m area, explicit confirmation, and no running.",
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
            "Each wearer chooses one role station and receives a slow, local correction toward the shared triangle."
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
    @Environment(SquadSessionCoordinator.self) private var squadSession
    @State private var wasPlayingBeforeScrub = false

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
                    if isJoinedPlayer {
                        squadSession.setFollowingCoach(store.isLocallyPaused)
                    } else {
                        store.togglePlayback()
                    }
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
                        set: { store.seek(to: $0, broadcast: false) }
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
    }

    private var playbackControlsAreDisabled: Bool {
        store.localRole != .coach && squadSession.state == .joined
    }

    private var isJoinedPlayer: Bool {
        store.localRole == .player && squadSession.state == .joined
    }

    private var playbackIcon: String {
        if isJoinedPlayer {
            return store.isLocallyPaused ? "arrow.clockwise" : "pause.fill"
        }
        return store.isActivelyPlaying ? "pause.fill" : "play.fill"
    }

    private var playbackLabel: String {
        if isJoinedPlayer {
            return store.isLocallyPaused ? "Resume following coach" : "Pause locally"
        }
        return store.isActivelyPlaying ? "Pause replay" : "Play replay"
    }

    private func handleScrubbing(_ editing: Bool) {
        if editing {
            wasPlayingBeforeScrub = store.isActivelyPlaying
            store.setPlaying(false, broadcast: false)
        } else {
            if wasPlayingBeforeScrub {
                store.setPlaying(true, broadcast: false)
            }
            wasPlayingBeforeScrub = false
            squadSession.broadcastCurrentState()
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
    @Environment(SquadSessionCoordinator.self) private var squadSession
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
                        .disabled(store.localRole != .coach && squadSession.state == .joined)
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
    @Environment(SquadSessionCoordinator.self) private var squadSession
    @Environment(SharedSpaceAnchorCoordinator.self) private var sharedSpace

    let openRoom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: "Review room")
                    Spacer()
                    Circle()
                        .fill(squadSession.state == .joined ? ReplayTheme.signal : .secondary)
                        .frame(width: 8, height: 8)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(squadSession.state == .joined ? "\(squadSession.participantCount)" : "1")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                    Text(
                        squadSession.state == .joined
                            ? (squadSession.participantCount == 1 ? "player connected" : "players connected")
                            : "solo preview"
                    )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                StatusPill(
                    text: squadSession.state.label,
                    systemImage: squadSession.state == .joined ? "shareplay" : "person.crop.circle"
                )

                Picker("Local role", selection: Binding(
                    get: { store.localRole },
                    set: { store.localRole = $0 }
                )) {
                    ForEach(SquadRole.allCases, id: \.self) { role in
                        Text(role.title).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(squadSession.state != .offline)

                Button {
                    Task { await squadSession.startSharePlay() }
                } label: {
                    Label("Start squad SharePlay", systemImage: "shareplay")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(
                    squadSession.state == .preparing
                        || squadSession.state == .waiting
                        || squadSession.state == .joined
                )

                ShareLink(
                    item: ReplayXIActivity(
                        roomID: squadSession.localID,
                        scenarioID: store.selectedScenarioID,
                        coachInstanceID: squadSession.localID
                    ),
                    preview: SharePreview("Replay XI review room")
                ) {
                    Label("Invite via Share menu", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(squadSession.state == .preparing || squadSession.state == .waiting)
            }
            .padding(20)

            Rectangle().fill(ReplayTheme.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "Navy XI seats")
                    Spacer()
                    Text("\(liveSeatCount) LIVE • \(11 - min(liveSeatCount, 11)) SIM")
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
                        store.isOpeningImmersive ? "Opening room…" : "Enter spatial replay",
                        systemImage: "visionpro"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(ReplayTheme.signal)
                .foregroundStyle(.black)
                .disabled(store.isOpeningImmersive || store.isImmersiveOpen)

                Text(store.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(18)
            .background(Color.black.opacity(0.22))
        }
    }

    private var liveSeatCount: Int {
        if squadSession.state == .offline { return 0 }
        return min(store.participantSeatAssignments.count, 11)
    }

    private func seatState(playerID: String) -> String {
        if store.localRole == .coach, store.localPerspectiveID == playerID {
            return "VIEWING"
        }
        if let localParticipantID = squadSession.localParticipantID,
           store.participantSeatAssignments[localParticipantID] == playerID {
            return "YOU"
        }
        if store.participantSeatAssignments.values.contains(playerID) { return "LIVE" }
        if squadSession.state == .offline,
           store.localRole == .player,
           store.localPerspectiveID == playerID {
            return "YOU"
        }
        return "SIM"
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
                    Text(state == "VIEWING" ? "COACH POV" : (selected ? "OWN POV" : player.displayName))
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
