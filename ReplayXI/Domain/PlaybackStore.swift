import Foundation
import Observation

/// Identifies the independently adjustable handle of a two-point spatial
/// annotation. Keeping this domain-level avoids coupling accessibility actions
/// to RealityKit entities or a particular control surface.
enum CoachMarkEndpoint: Sendable {
    case start
    case end
}

@MainActor
@Observable
final class ReplayStore {
    static let availablePlaybackRates: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 4]
    static let coachAnnotationDisplayDuration: TimeInterval = 8
    static let maximumCoachAnnotationDuration: TimeInterval = 30
    /// Bounds independently rendered annotation hierarchies in shared state.
    static let maximumSharedCoachMarks = 128
    static let maximumCoachMarkLabelLength = 96
    /// Match-review annotations are pitch data, not arbitrary world-space
    /// content. Keeping the shared payload inside the actual 68 x 105 metre
    /// surface prevents a stray drag or malformed peer packet from creating a
    /// giant line, collision volume, or off-screen label.
    static let pitchHalfWidth: Float = 34
    static let pitchHalfLength: Float = 52.5

    let scenarios: [ReplayScenario]

    var selectedScenarioID: String
    var playhead: TimeInterval = 0
    var isPlaying = false
    var playbackRate: Double = 1
    var viewMode: ReplayViewMode
    var localPerspectiveID: String
    var coachFocusPerspectiveID: String?
    var coachLockEnabled = false
    var followsCoach = true
    var isLocallyPaused = false
    var localRole: SquadRole = .coach
    private(set) var isCollaborationActive = false
    /// A coach may inspect a tapped player locally before deliberately sharing
    /// that POV. Shared snapshots preserve the last published squad view while
    /// this flag is active.
    private(set) var isCoachLocalReview = false
    /// Scalar UI invalidation token for the event shelf. Geometry-only handle
    /// previews deliberately leave it unchanged, while timing, identity, kind,
    /// label, insertion, deletion, and remote replacement advance it.
    private(set) var reviewIndexVersion = PlaybackReviewIndexVersion()
    var marks: [CoachMark] {
        didSet {
            guard reviewIndexVersionCache.refresh(marks: marks) else { return }
            reviewIndexVersion = reviewIndexVersionCache.version
        }
    }
    var participantSeatAssignments: [UUID: String] = [:]
    private(set) var sharedPitchAnchorID: UUID?
    private(set) var triangleLockMode: TriangleLockMode = .visualise
    /// True only for a device-local solo rehearsal. Local anchor identifiers
    /// are deliberately excluded from shared playback snapshots.
    private(set) var isLocalTrianglePreview = false
    /// Per-headset safety consent. This is intentionally never serialized.
    private(set) var hasLocallyAcknowledgedTrianglePlacement = false
    var selectedTool: CoachMarkKind = .run
    var isDrawing = false
    var pendingDrawStart: PitchPoint?
    private(set) var shapeFocusStage: ShapeFocusStage = .problem
    var showsIdealBranch: Bool { shapeFocusStage == .ideal }
    var showsLaneLens = false
    var isImmersiveOpen = false
    var isOpeningImmersive = false
    var statusMessage = "Choose a scenario, then enter the review room."

    @ObservationIgnored
    var onBroadcastSnapshot: (@MainActor (SharedPlaybackSnapshot) -> Void)?

    /// Signals that shared playback no longer owns an anchor. The spatial
    /// coordinator removes it only when this headset created it.
    @ObservationIgnored
    var onRetirePitchAnchor: (@MainActor (UUID) -> Void)?

    @ObservationIgnored
    private var latestCoachSnapshot: SharedPlaybackSnapshot?

    @ObservationIgnored
    private var reviewIndexVersionCache = PlaybackReviewIndexVersionCache()

    /// Geometry handle drags are rendered immediately on the coach's headset,
    /// but remain transactional until the gesture ends. Keeping only the
    /// original endpoints lets unrelated shared actions publish safely without
    /// leaking a half-finished drag into late-join or heartbeat snapshots.
    @ObservationIgnored
    private var pendingCoachMarkGeometryBaselines: [UUID: CoachMarkGeometry] = [:]

    private struct CoachMarkGeometry {
        let start: PitchPoint
        let end: PitchPoint
    }

    convenience init() {
        self.init(scenarios: DemoScenarios.all)
    }

    init(scenarios: [ReplayScenario]) {
        precondition(!scenarios.isEmpty, "Replay XI requires at least one scenario")
        self.scenarios = scenarios
        let first = scenarios[0]
        selectedScenarioID = first.id
        viewMode = first.defaultViewMode
        localPerspectiveID = first.defaultPerspectiveID
        marks = first.coachMarks
        reviewIndexVersionCache.seed(marks: marks)
    }

    var selectedScenario: ReplayScenario {
        scenarios.first { $0.id == selectedScenarioID } ?? scenarios[0]
    }

    var selectedScenarioIndex: Int {
        scenarios.firstIndex { $0.id == selectedScenarioID } ?? 0
    }

    var activePerspectiveID: String {
        if localRole == .coach {
            return localPerspectiveID
        }
        if isCollaborationActive,
           followsCoach,
           coachLockEnabled,
           let coachFocusPerspectiveID {
            return coachFocusPerspectiveID
        }
        return localPerspectiveID
    }

    var activePerspective: PlayerTrack? {
        selectedScenario.player(id: activePerspectiveID)
    }

    var activePerspectiveIndex: Int {
        selectedScenario.players.firstIndex { $0.id == activePerspectiveID } ?? 0
    }

    var activeMoment: CueMoment? {
        selectedScenario.activeMoment(at: playhead)
    }

    var progress: Double {
        guard playhead.isFinite,
              selectedScenario.duration.isFinite,
              selectedScenario.duration > 0 else { return 0 }
        return min(max(playhead / selectedScenario.duration, 0), 1)
    }

    var isActivelyPlaying: Bool {
        isPlaying && !isLocallyPaused
    }

    func selectScenario(id: String, broadcast: Bool = true) {
        guard !isCollaborationActive || localRole == .coach || !broadcast else { return }
        guard let scenario = scenarios.first(where: { $0.id == id }) else { return }
        guard triangleLockMode != .place else {
            statusMessage = "End physical placement before changing scenarios."
            return
        }
        let retiredAnchorID = sharedPitchAnchorID
        selectedScenarioID = scenario.id
        shapeFocusStage = .problem
        playhead = scenario.kind == .shapeLab
            ? min(ShapeFocusStage.problem.referenceTime, scenario.duration)
            : 0
        isPlaying = false
        viewMode = scenario.defaultViewMode
        localPerspectiveID = scenario.defaultPerspectiveID
        coachFocusPerspectiveID = nil
        coachLockEnabled = false
        isCoachLocalReview = false
        isLocallyPaused = false
        marks = scenario.coachMarks
        pendingCoachMarkGeometryBaselines.removeAll(keepingCapacity: true)
        sharedPitchAnchorID = nil
        triangleLockMode = .visualise
        isLocalTrianglePreview = false
        hasLocallyAcknowledgedTrianglePlacement = false
        selectedTool = .run
        pendingDrawStart = nil
        isDrawing = false
        showsLaneLens = scenario.kind == .passingChannels
        statusMessage = scenario.coachPrompt
        if let retiredAnchorID { onRetirePitchAnchor?(retiredAnchorID) }
        if broadcast { emitSnapshot() }
    }

    func selectAdjacentScenario(by offset: Int) {
        guard (!isCollaborationActive || localRole == .coach), !scenarios.isEmpty else { return }
        let count = scenarios.count
        let wrappedIndex = (selectedScenarioIndex + offset % count + count) % count
        selectScenario(id: scenarios[wrappedIndex].id)
    }

    func togglePlayback(broadcast: Bool = true) {
        guard !isCollaborationActive || localRole == .coach || !broadcast else {
            setFollowingCoach(isLocallyPaused)
            return
        }
        if !isPlaying, playhead >= selectedScenario.duration - 0.05 {
            playhead = 0
        }
        isLocallyPaused = false
        isPlaying.toggle()
        statusMessage = isPlaying ? "Synchronized replay running" : "Replay paused for analysis"
        if broadcast { emitSnapshot() }
    }

    func setPlaying(_ value: Bool, broadcast: Bool = true) {
        if broadcast, isCollaborationActive, localRole != .coach {
            setFollowingCoach(value)
            return
        }
        let canPlay = playhead.isFinite
            && selectedScenario.duration.isFinite
            && playhead < selectedScenario.duration
        isPlaying = value && canPlay
        if isPlaying { isLocallyPaused = false }
        if broadcast { emitSnapshot() }
    }

    func seek(to time: TimeInterval, broadcast: Bool = true) {
        guard !isCollaborationActive || localRole == .coach || !broadcast else { return }
        guard time.isFinite, selectedScenario.duration.isFinite else { return }
        playhead = min(max(time, 0), selectedScenario.duration)
        if playhead >= selectedScenario.duration {
            isPlaying = false
        }
        if broadcast { emitSnapshot() }
    }

    /// Opens a device-local review instant without claiming transport
    /// authority. In a joined player session this atomically leaves coach
    /// follow before moving the playhead, preventing the next heartbeat from
    /// looking like an unexpected snap-back.
    @discardableResult
    func beginLocalReview(at time: TimeInterval) -> Bool {
        guard time.isFinite, selectedScenario.duration.isFinite else { return false }
        let entersComfortPause = isCollaborationActive && localRole == .player
        if entersComfortPause {
            followsCoach = false
            isLocallyPaused = true
        }
        isPlaying = false
        playhead = min(max(time, 0), selectedScenario.duration)
        statusMessage = entersComfortPause
            ? "Local comfort review — rejoin when ready"
            : "Local review paused"
        return true
    }

    func skip(by delta: TimeInterval, broadcast: Bool = true) {
        seek(to: playhead + delta, broadcast: broadcast)
    }

    func setPlaybackRate(_ rate: Double, broadcast: Bool = true) {
        guard !isCollaborationActive || localRole == .coach || !broadcast else { return }
        guard rate.isFinite else { return }
        playbackRate = min(max(rate, 0.25), 4)
        if broadcast { emitSnapshot() }
    }

    func setViewMode(_ mode: ReplayViewMode, broadcast: Bool = true) {
        guard triangleLockMode != .place || mode == .positional else {
            statusMessage = "End physical placement before changing views."
            return
        }
        if broadcast, isCollaborationActive, localRole == .player {
            followsCoach = false
            isLocallyPaused = true
        }
        viewMode = mode
        statusMessage = mode == .firstPerson
            ? "Player POV ready. Position follows the run; your head controls free look. Green brackets show recorded facing."
            : "\(mode.title) view ready"
        if broadcast, localRole == .coach {
            emitSnapshot()
        }
    }

    func openLocalPlayerPOV(_ id: String) {
        guard selectedScenario.player(id: id) != nil else { return }
        // Selecting the POV already being rendered is navigation-only. In a
        // shared room it must not turn a following player into a local review,
        // or pause a coach merely because a card/pitch hit resolved to the
        // current player again.
        guard viewMode != .firstPerson || activePerspectiveID != id else { return }
        if isCollaborationActive, localRole == .player {
            followsCoach = false
            isLocallyPaused = true
        }
        isPlaying = false
        localPerspectiveID = id
        viewMode = .firstPerson
        isCoachLocalReview = localRole == .coach && isCollaborationActive
        statusMessage = "Player POV: \(selectedScenario.player(id: id)?.role ?? id). Free look is active."
        if isCoachLocalReview {
            // Player selection remains private, but the review clock is shared.
            // The collaboration coordinator preserves the previously published
            // squad perspective while immediately delivering this pause.
            emitSnapshot()
        }
    }

    func setLocalPerspective(_ id: String, entersLocalReview: Bool = true) {
        guard selectedScenario.player(id: id) != nil else { return }
        if entersLocalReview, isCollaborationActive, localRole == .player {
            followsCoach = false
            isLocallyPaused = true
        }
        localPerspectiveID = id
        if !coachLockEnabled || !followsCoach {
            statusMessage = "Player POV: \(selectedScenario.player(id: id)?.role ?? id)"
        }
    }

    func selectAdjacentPerspective(by offset: Int, entersLocalReview: Bool = true) {
        let players = selectedScenario.players
        guard !players.isEmpty else { return }
        let currentIndex = players.firstIndex { $0.id == activePerspectiveID }
            ?? players.firstIndex { $0.id == localPerspectiveID }
            ?? 0
        let count = players.count
        let wrappedIndex = (currentIndex + offset % count + count) % count
        setLocalPerspective(players[wrappedIndex].id, entersLocalReview: entersLocalReview)
    }

    func broadcastPerspective(_ id: String) {
        guard localRole == .coach, selectedScenario.player(id: id) != nil else { return }
        isPlaying = false
        localPerspectiveID = id
        coachFocusPerspectiveID = id
        coachLockEnabled = true
        isCoachLocalReview = false
        followsCoach = true
        viewMode = .firstPerson
        statusMessage = "Squad Player POV locked to \(selectedScenario.player(id: id)?.role ?? id)"
        emitSnapshot()
    }

    func releaseSquad() {
        guard localRole == .coach else { return }
        coachLockEnabled = false
        coachFocusPerspectiveID = nil
        isCoachLocalReview = false
        statusMessage = "Own perspectives restored"
        emitSnapshot()
    }

    /// Selects the authored Shape Focus comparison and returns the scene to the
    /// stable positional view. Joined players may inspect a stage locally; doing
    /// so enters comfort pause and never broadcasts over the coach.
    func setShapeFocusStage(_ stage: ShapeFocusStage, broadcast: Bool = true) {
        guard selectedScenario.kind == .shapeLab else { return }
        guard triangleLockMode == .visualise else {
            statusMessage = "End physical placement before changing the comparison."
            return
        }
        if isCollaborationActive, localRole == .player {
            followsCoach = false
            isLocallyPaused = true
        }

        shapeFocusStage = stage
        playhead = min(stage.referenceTime, selectedScenario.duration)
        isPlaying = false
        viewMode = .positional
        statusMessage = stage == .problem
            ? "Problem: two support roles share one cover shadow."
            : "Ideal: three staggered heights preserve two passing lanes."

        if broadcast, !isCollaborationActive || localRole == .coach {
            emitSnapshot()
        }
    }

    func setFollowingCoach(_ follows: Bool) {
        guard isCollaborationActive, localRole == .player else { return }
        followsCoach = follows
        isLocallyPaused = !follows
        if follows, let latestCoachSnapshot {
            applyRemote(latestCoachSnapshot)
        } else {
            statusMessage = follows ? "Following coach" : "Local comfort pause — explore independently"
        }
    }

    func beginDrawing(_ kind: CoachMarkKind) {
        guard localRole == .coach else { return }
        guard marks.count < Self.maximumSharedCoachMarks else {
            isDrawing = false
            pendingDrawStart = nil
            statusMessage = "Annotation limit reached. Remove one before drawing."
            return
        }
        selectedTool = kind
        isDrawing = true
        pendingDrawStart = nil
        isPlaying = false
        statusMessage = kind.requiresTwoPitchPoints
            ? "Pinch-drag the \(kind.title.lowercased()), or tap two pitch points."
            : "Pinch one player to attach a label."
        // Annotation is a shared review action. Publish the pause immediately
        // so followers do not keep moving while the coach places the mark.
        emitSnapshot()
    }

    func cancelDrawing() {
        isDrawing = false
        pendingDrawStart = nil
        selectedTool = .run
        statusMessage = "Drawing cancelled"
    }

    @discardableResult
    func registerPitchTap(_ point: PitchPoint) -> CoachMark? {
        guard isDrawing, localRole == .coach else { return nil }
        guard Self.isPointOnPitch(point) else {
            statusMessage = "Choose a point on the pitch"
            return nil
        }
        guard selectedTool.requiresTwoPitchPoints else {
            pendingDrawStart = nil
            statusMessage = "Pinch a player to place this label."
            return nil
        }
        guard let start = pendingDrawStart else {
            pendingDrawStart = point
            statusMessage = "Start fixed. Pinch or tap the destination."
            return nil
        }
        guard CoachMarkGeometryPolicy.accepts(
            kind: selectedTool,
            start: start,
            end: point
        ) else {
            statusMessage = selectedTool == .space
                ? "Make the space at least 1.1 metres wide."
                : "Move at least 0.8 metres from the start point."
            return nil
        }
        guard marks.count < Self.maximumSharedCoachMarks else {
            pendingDrawStart = nil
            isDrawing = false
            statusMessage = "Annotation limit reached. Remove one before drawing."
            return nil
        }

        let label: String
        switch selectedTool {
        case .run: label = "Attack the space"
        case .pass: label = "Release the lane"
        case .danger: label = "Pressure arrives"
        case .space: label = "Useful space"
        case .playerLabel: return nil
        }

        let mark = CoachMark(
            kind: selectedTool,
            start: start,
            end: point,
            label: label,
            revealTime: playhead,
            hideTime: playhead + Self.coachAnnotationDisplayDuration
        )
        marks.append(mark)
        pendingDrawStart = nil
        isDrawing = false
        statusMessage = "\(selectedTool.title) annotation shared with the squad"
        emitSnapshot()
        return mark
    }

    /// Creates a complete player-attached annotation from one player tap. The
    /// target pose and reveal time are sampled atomically from the current
    /// playhead, so no second pitch tap or draft geometry is needed.
    @discardableResult
    func labelPlayer(_ playerID: String) -> CoachMark? {
        guard localRole == .coach else { return nil }
        guard marks.count < Self.maximumSharedCoachMarks else {
            statusMessage = "Annotation limit reached. Remove one before labelling."
            return nil
        }
        guard playhead.isFinite,
              let player = selectedScenario.player(id: playerID) else {
            statusMessage = "Player label unavailable"
            return nil
        }

        isPlaying = false
        selectedTool = .playerLabel
        let position = player.pose(at: playhead).position
        let mark = CoachMark(
            kind: .playerLabel,
            start: position,
            end: position,
            label: "#\(player.shirtNumber) \(player.displayName) · \(player.positionCode)",
            revealTime: playhead,
            hideTime: playhead + Self.coachAnnotationDisplayDuration,
            playerID: player.id
        )
        marks.append(mark)
        pendingDrawStart = nil
        isDrawing = false
        statusMessage = "Player label shared for #\(player.shirtNumber) \(player.displayName)"
        emitSnapshot()
        return mark
    }

    func addPresetMark() {
        guard localRole == .coach else { return }
        guard marks.count < Self.maximumSharedCoachMarks else {
            statusMessage = "Annotation limit reached. Remove one before adding."
            return
        }
        if selectedTool == .playerLabel {
            guard let playerID = activePerspective?.id else {
                statusMessage = "Choose a player before adding a label."
                return
            }
            labelPlayer(playerID)
            return
        }
        let focus = Self.clampedPitchPoint(
            activePerspective?.pose(at: playhead).position ?? .zero
        )
        let destination = Self.clampedPitchPoint(
            PitchPoint(x: focus.x + 7, z: focus.z + 10)
        )
        let mark = CoachMark(
            kind: selectedTool,
            start: focus,
            end: destination,
            label: selectedTool == .pass ? "Open channel" : "Next movement",
            revealTime: playhead,
            hideTime: playhead + Self.coachAnnotationDisplayDuration
        )
        marks.append(mark)
        statusMessage = "Coach annotation added"
        emitSnapshot()
    }

    func undoMark() {
        guard localRole == .coach else { return }
        let authoredIDs = Set(selectedScenario.coachMarks.map(\.id))
        guard let index = marks.lastIndex(where: { !authoredIDs.contains($0.id) }) else {
            statusMessage = "No new annotation to undo"
            return
        }
        pendingCoachMarkGeometryBaselines.removeValue(forKey: marks[index].id)
        marks.remove(at: index)
        statusMessage = "Last annotation removed"
        emitSnapshot()
    }

    /// Removes one coach-created annotation while preserving the scenario's
    /// authored teaching overlays. This supports mark-specific timeline menus.
    @discardableResult
    func removeCoachMark(id: UUID) -> Bool {
        guard localRole == .coach else { return false }
        let authoredIDs = Set(selectedScenario.coachMarks.map(\.id))
        guard !authoredIDs.contains(id),
              let index = marks.firstIndex(where: { $0.id == id }) else {
            statusMessage = authoredIDs.contains(id)
                ? "Authored match overlay kept"
                : "Annotation no longer exists"
            return false
        }
        pendingCoachMarkGeometryBaselines.removeValue(forKey: id)
        marks.remove(at: index)
        statusMessage = "Annotation removed"
        emitSnapshot()
        return true
    }

    /// Moves one coach-created annotation to a new match instant without
    /// changing its geometry or authored display duration. Fixture overlays
    /// remain immutable so a local edit cannot erase the teaching baseline.
    @discardableResult
    func retimeCoachMark(id: UUID, to revealTime: TimeInterval) -> Bool {
        guard localRole == .coach,
              revealTime.isFinite,
              selectedScenario.duration.isFinite,
              selectedScenario.duration >= 0,
              (0...selectedScenario.duration).contains(revealTime) else {
            statusMessage = "Choose a valid annotation time"
            return false
        }

        let authoredIDs = Set(selectedScenario.coachMarks.map(\.id))
        guard !authoredIDs.contains(id),
              let index = marks.firstIndex(where: { $0.id == id }) else {
            statusMessage = authoredIDs.contains(id)
                ? "Authored match overlay kept"
                : "Annotation no longer exists"
            return false
        }

        let mark = marks[index]
        let shiftedHideTime = mark.hideTime.map {
            revealTime + ($0 - mark.revealTime)
        }
        let replacement = CoachMark(
            id: mark.id,
            kind: mark.kind,
            start: mark.start,
            end: mark.end,
            label: mark.label,
            revealTime: revealTime,
            hideTime: shiftedHideTime,
            author: mark.author,
            playerID: mark.playerID
        )
        guard isValidSharedMark(replacement, for: selectedScenario) else {
            statusMessage = "That annotation window does not fit the replay"
            return false
        }

        marks[index] = replacement
        statusMessage = "Annotation moved to the current timestamp"
        emitSnapshot()
        return true
    }

    /// Resizes the visible lifetime of a coach-created mark without changing
    /// its timestamp or geometry. `nil` keeps the mark visible for the rest of
    /// the replay; a finite duration creates an explicit timeline window.
    @discardableResult
    func setCoachMarkDuration(id: UUID, duration: TimeInterval?) -> Bool {
        guard localRole == .coach else { return false }
        if let duration {
            guard duration.isFinite,
                  (0.5...Self.maximumCoachAnnotationDuration).contains(duration) else {
                statusMessage = "Choose a duration between half a second and 30 seconds"
                return false
            }
        }

        let authoredIDs = Set(selectedScenario.coachMarks.map(\.id))
        guard !authoredIDs.contains(id),
              let index = marks.firstIndex(where: { $0.id == id }) else {
            statusMessage = authoredIDs.contains(id)
                ? "Authored match overlay kept"
                : "Annotation no longer exists"
            return false
        }

        let mark = marks[index]
        let replacement = CoachMark(
            id: mark.id,
            kind: mark.kind,
            start: mark.start,
            end: mark.end,
            label: mark.label,
            revealTime: mark.revealTime,
            hideTime: duration.map { mark.revealTime + $0 },
            author: mark.author,
            playerID: mark.playerID
        )
        guard isValidSharedMark(replacement, for: selectedScenario) else {
            statusMessage = "That annotation window does not fit the replay"
            return false
        }

        marks[index] = replacement
        statusMessage = duration.map { "Annotation shown for \($0.formatted()) seconds" }
            ?? "Annotation shown until replay end"
        emitSnapshot()
        return true
    }

    /// Rewords one coach-created mark without changing its spatial geometry or
    /// timestamp. Keeping this as a full-state mutation means late joiners and
    /// locally paused players receive the same concise tactical instruction.
    @discardableResult
    func updateCoachMarkLabel(id: UUID, label: String) -> Bool {
        guard localRole == .coach else { return false }
        let normalizedLabel = label
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !normalizedLabel.isEmpty,
              normalizedLabel.count <= Self.maximumCoachMarkLabelLength,
              normalizedLabel.utf8.count <= Self.maximumCoachMarkLabelLength * 4 else {
            statusMessage = "Choose a shorter annotation label"
            return false
        }

        let authoredIDs = Set(selectedScenario.coachMarks.map(\.id))
        guard !authoredIDs.contains(id),
              let index = marks.firstIndex(where: { $0.id == id }) else {
            statusMessage = authoredIDs.contains(id)
                ? "Authored match overlay kept"
                : "Annotation no longer exists"
            return false
        }

        let mark = marks[index]
        guard mark.label != normalizedLabel else {
            statusMessage = "Annotation label already set"
            return false
        }
        let replacement = CoachMark(
            id: mark.id,
            kind: mark.kind,
            start: mark.start,
            end: mark.end,
            label: normalizedLabel,
            revealTime: mark.revealTime,
            hideTime: mark.hideTime,
            author: mark.author,
            playerID: mark.playerID
        )
        guard isValidSharedMark(replacement, for: selectedScenario) else {
            statusMessage = "Choose a valid annotation label"
            return false
        }

        marks[index] = replacement
        statusMessage = "Annotation label updated"
        emitSnapshot()
        return true
    }

    /// Moves the pitch-space endpoints of one coach-created spatial mark. The
    /// first non-broadcast update opens a local geometry transaction and pauses
    /// shared transport without exposing preview geometry. The final drag
    /// update publishes one authoritative geometry snapshot to the squad.
    @discardableResult
    func updateCoachMarkGeometry(
        id: UUID,
        start: PitchPoint,
        end: PitchPoint,
        broadcast: Bool = true
    ) -> Bool {
        guard localRole == .coach else { return false }
        let authoredIDs = Set(selectedScenario.coachMarks.map(\.id))
        guard !authoredIDs.contains(id),
              let index = marks.firstIndex(where: { $0.id == id }),
              marks[index].kind != .playerLabel else {
            statusMessage = authoredIDs.contains(id)
                ? "Authored match overlay kept"
                : "That annotation cannot be moved"
            return false
        }

        let mark = marks[index]
        let replacement = CoachMark(
            id: mark.id,
            kind: mark.kind,
            start: start,
            end: end,
            label: mark.label,
            revealTime: mark.revealTime,
            hideTime: mark.hideTime,
            author: mark.author,
            playerID: mark.playerID
        )
        guard isValidSharedMark(replacement, for: selectedScenario) else {
            if broadcast { rollbackCoachMarkGeometryPreview(id: id, index: index) }
            if broadcast { statusMessage = "Keep the annotation on the pitch" }
            return false
        }
        guard CoachMarkGeometryPolicy.accepts(
            kind: mark.kind,
            start: start,
            end: end
        ) else {
            if broadcast { rollbackCoachMarkGeometryPreview(id: id, index: index) }
            if broadcast {
                statusMessage = mark.kind == .space
                    ? "Keep the space at least 1.1 metres wide"
                    : "Keep the annotation at least 0.8 metres long"
            }
            return false
        }

        let beginsPreviewTransaction = !broadcast
            && pendingCoachMarkGeometryBaselines[id] == nil
        if broadcast {
            pendingCoachMarkGeometryBaselines.removeValue(forKey: id)
        } else if beginsPreviewTransaction {
            pendingCoachMarkGeometryBaselines[id] = CoachMarkGeometry(
                start: mark.start,
                end: mark.end
            )
        }
        marks[index] = replacement
        if beginsPreviewTransaction {
            // Geometry previews are intentionally masked by `makeSnapshot`.
            // Publishing here therefore synchronizes only the pause and the
            // committed baseline, preventing the coach from freezing locally
            // while followers continue through the moment being annotated.
            isPlaying = false
            if isCollaborationActive { emitSnapshot() }
        } else if broadcast {
            statusMessage = "Annotation position updated"
            emitSnapshot()
        }
        return true
    }

    /// Atomically nudges one handle of a coach-created spatial annotation.
    ///
    /// This is the store-level entry point for accessibility increment and
    /// decrement actions. The requested pitch-space delta is clamped at the
    /// touchlines, while malformed, no-op, and unreadably short results are
    /// rejected without mutating or publishing state. A successful nudge emits
    /// exactly one authoritative snapshot.
    @discardableResult
    func nudgeCoachMarkEndpoint(
        id: UUID,
        endpoint: CoachMarkEndpoint,
        by delta: PitchPoint
    ) -> Bool {
        guard localRole == .coach else { return false }
        guard delta.x.isFinite, delta.z.isFinite else {
            statusMessage = "Choose a valid annotation movement"
            return false
        }

        let authoredIDs = Set(selectedScenario.coachMarks.map(\.id))
        guard !authoredIDs.contains(id),
              let index = marks.firstIndex(where: { $0.id == id }),
              marks[index].kind.requiresTwoPitchPoints,
              marks[index].playerID == nil else {
            statusMessage = authoredIDs.contains(id)
                ? "Authored match overlay kept"
                : "That annotation cannot be moved"
            return false
        }
        guard pendingCoachMarkGeometryBaselines[id] == nil else {
            statusMessage = "Finish the current annotation move first"
            return false
        }

        let mark = marks[index]
        var start = mark.start
        var end = mark.end
        switch endpoint {
        case .start:
            let proposed = PitchPoint(x: start.x + delta.x, z: start.z + delta.z)
            guard proposed.x.isFinite, proposed.z.isFinite else {
                statusMessage = "Choose a valid annotation movement"
                return false
            }
            start = Self.clampedPitchPoint(proposed)
        case .end:
            let proposed = PitchPoint(x: end.x + delta.x, z: end.z + delta.z)
            guard proposed.x.isFinite, proposed.z.isFinite else {
                statusMessage = "Choose a valid annotation movement"
                return false
            }
            end = Self.clampedPitchPoint(proposed)
        }

        guard start != mark.start || end != mark.end else {
            statusMessage = "Annotation did not move"
            return false
        }
        guard CoachMarkGeometryPolicy.accepts(
            kind: mark.kind,
            start: start,
            end: end
        ) else {
            statusMessage = "Keep the annotation large enough to read"
            return false
        }

        let replacement = markReplacingGeometry(mark, start: start, end: end)
        guard isValidSharedMark(replacement, for: selectedScenario) else {
            statusMessage = "Keep the annotation on the pitch"
            return false
        }

        marks[index] = replacement
        // A precise endpoint adjustment is an atomic review action. Pause in
        // the same snapshot that publishes its geometry so a rejected nudge
        // leaves transport untouched and a successful one cannot split the
        // coach's clock from the squad's.
        isPlaying = false
        statusMessage = endpoint == .start
            ? "Annotation start adjusted"
            : "Annotation end adjusted"
        emitSnapshot()
        return true
    }

    /// Restores a local handle-drag preview when the system cancels its pinch
    /// sequence. The baseline was never published, so rollback is deliberately
    /// local and emits no collaboration snapshot.
    @discardableResult
    func cancelCoachMarkGeometryPreview(id: UUID) -> Bool {
        guard let baseline = pendingCoachMarkGeometryBaselines.removeValue(forKey: id),
              let index = marks.firstIndex(where: { $0.id == id }) else {
            return false
        }
        marks[index] = markReplacingGeometry(
            marks[index],
            start: baseline.start,
            end: baseline.end
        )
        statusMessage = "Annotation move cancelled"
        return true
    }

    private func rollbackCoachMarkGeometryPreview(id: UUID, index: Int) {
        guard let baseline = pendingCoachMarkGeometryBaselines.removeValue(forKey: id) else {
            return
        }
        marks[index] = markReplacingGeometry(
            marks[index],
            start: baseline.start,
            end: baseline.end
        )
    }

    /// Clears only the transient first point after an interrupted spatial
    /// stroke. The selected tool stays armed so the coach can pinch-draw again.
    func resetPendingAnnotationPointAfterInterruption() {
        guard isDrawing else { return }
        pendingDrawStart = nil
        statusMessage = "Gesture interrupted. Pinch-draw again or tap a start point."
    }

    func clearMarks() {
        guard localRole == .coach else { return }
        let authoredIDs = Set(selectedScenario.coachMarks.map(\.id))
        let previousCount = marks.count
        let removedIDs = Set(marks.lazy.filter { !authoredIDs.contains($0.id) }.map(\.id))
        marks.removeAll { removedIDs.contains($0.id) }
        for id in removedIDs {
            pendingCoachMarkGeometryBaselines.removeValue(forKey: id)
        }
        guard marks.count != previousCount else {
            statusMessage = "No new annotations to clear"
            return
        }
        statusMessage = "New annotations cleared"
        emitSnapshot()
    }

    /// Accepts the legacy incremental annotation command through the same
    /// validation path as a full sync. Keeping the cached coach snapshot in
    /// step prevents a locally paused player from losing the mark on Resume.
    @discardableResult
    func appendRemoteCoachMark(_ mark: CoachMark) -> Bool {
        let scenario = selectedScenario
        guard marks.count < Self.maximumSharedCoachMarks,
              !marks.contains(where: { $0.id == mark.id }),
              isValidSharedMark(mark, for: scenario) else { return false }
        marks.append(mark)
        if let snapshot = latestCoachSnapshot,
           snapshot.scenarioID == scenario.id,
           snapshot.marks.count < Self.maximumSharedCoachMarks,
           !snapshot.marks.contains(where: { $0.id == mark.id }) {
            latestCoachSnapshot = SharedPlaybackSnapshot(
                scenarioID: snapshot.scenarioID,
                playhead: snapshot.playhead,
                isPlaying: snapshot.isPlaying,
                playbackRate: snapshot.playbackRate,
                viewMode: snapshot.viewMode,
                coachFocusPerspectiveID: snapshot.coachFocusPerspectiveID,
                coachLockEnabled: snapshot.coachLockEnabled,
                marks: snapshot.marks + [mark],
                seatAssignments: snapshot.seatAssignments,
                showsLaneLens: snapshot.showsLaneLens,
                sharedPitchAnchorID: snapshot.sharedPitchAnchorID,
                triangleLockMode: snapshot.triangleLockMode,
                shapeFocusStage: snapshot.shapeFocusStage
            )
        }
        return true
    }

    /// Separates authenticated command validation from idempotent application.
    /// A duplicate valid annotation still advances transport ordering, while a
    /// malformed payload must never consume the coach's sequence namespace.
    func isValidRemoteCoachMarkPayload(_ mark: CoachMark) -> Bool {
        isValidSharedMark(mark, for: selectedScenario)
    }

    /// Resolves this headset's one physical station. Shared rehearsal is bound
    /// to the SharePlay participant identity; changing Player POV cannot change
    /// or steal another wearer's station.
    func physicalTriangleTarget(
        participantID: UUID?,
        sharedSession: Bool
    ) -> FormationTarget? {
        guard selectedScenario.kind == .shapeLab else { return nil }
        let targetPlayerID: String?
        if sharedSession {
            guard let participantID else { return nil }
            targetPlayerID = participantSeatAssignments[participantID]
        } else {
            targetPlayerID = localPerspectiveID
        }
        guard let targetPlayerID else { return nil }
        return selectedScenario.formationTargets.first { $0.playerID == targetPlayerID }
    }

    /// The coach sees an overview of all stations in a shared room but receives
    /// no personal movement correction. Every player must have a unique,
    /// identity-bound formation target before this headset reveals markers.
    func canRevealPhysicalTriangleMarkers(
        participantID: UUID?,
        sharedSession: Bool
    ) -> Bool {
        guard selectedScenario.kind == .shapeLab else { return false }
        if sharedSession, localRole == .coach { return true }
        return physicalTriangleTarget(
            participantID: participantID,
            sharedSession: sharedSession
        ) != nil
    }

    /// Keeps existing valid physical roles where possible, then assigns any
    /// remaining formation targets exactly once before filling ordinary seats.
    /// This is deterministic so every participant receives the same snapshot.
    func prioritizePhysicalTriangleAssignments() {
        guard selectedScenario.kind == .shapeLab,
              !participantSeatAssignments.isEmpty else { return }

        let participantIDs = participantSeatAssignments.keys.sorted {
            $0.uuidString < $1.uuidString
        }
        let targetPlayerIDs = selectedScenario.formationTargets.map(\.playerID)
        let validTargetIDs = Set(targetPlayerIDs)
        let validHomePlayerIDs = Set(selectedScenario.homePlayers.map(\.id))
        var result: [UUID: String] = [:]
        var claimedPlayerIDs = Set<String>()

        for participantID in participantIDs {
            guard let existing = participantSeatAssignments[participantID],
                  validTargetIDs.contains(existing),
                  claimedPlayerIDs.insert(existing).inserted else { continue }
            result[participantID] = existing
        }

        var remainingTargetIDs = targetPlayerIDs.filter { !claimedPlayerIDs.contains($0) }
        for participantID in participantIDs where result[participantID] == nil {
            guard !remainingTargetIDs.isEmpty else { break }
            let playerID = remainingTargetIDs.removeFirst()
            result[participantID] = playerID
            claimedPlayerIDs.insert(playerID)
        }

        for participantID in participantIDs where result[participantID] == nil {
            if let existing = participantSeatAssignments[participantID],
               validHomePlayerIDs.contains(existing),
               claimedPlayerIDs.insert(existing).inserted {
                result[participantID] = existing
                continue
            }
            guard let playerID = selectedScenario.homePlayers.map(\.id).first(where: {
                !claimedPlayerIDs.contains($0)
            }) else { break }
            result[participantID] = playerID
            claimedPlayerIDs.insert(playerID)
        }

        participantSeatAssignments = result
    }

    /// SharePlay startup invalidates a local-only origin immediately, before the
    /// session can enter preparing/waiting or publish a heartbeat.
    func discardLocalTrianglePreviewForSessionTransition() {
        guard isLocalTrianglePreview else { return }
        let retiredAnchorID = sharedPitchAnchorID
        isPlaying = false
        triangleLockMode = .visualise
        shapeFocusStage = .ideal
        isLocalTrianglePreview = false
        hasLocallyAcknowledgedTrianglePlacement = false
        sharedPitchAnchorID = nil
        statusMessage = "Local preview ended before SharePlay. Set a new shared origin after the room connects."
        if let retiredAnchorID { onRetirePitchAnchor?(retiredAnchorID) }
    }

    func setSharedPitchAnchor(_ id: UUID?) {
        guard localRole == .coach, selectedScenario.kind == .shapeLab else { return }
        let retiredAnchorID = sharedPitchAnchorID.flatMap { $0 == id ? nil : $0 }
        sharedPitchAnchorID = id
        isLocalTrianglePreview = false
        statusMessage = id == nil
            ? "Shared pitch origin cleared"
            : "Shared pitch origin synchronized"
        if let retiredAnchorID { onRetirePitchAnchor?(retiredAnchorID) }
        emitSnapshot()
    }

    func activateTrianglePlacement(anchorID: UUID) {
        guard localRole == .coach, selectedScenario.kind == .shapeLab else { return }
        prioritizePhysicalTriangleAssignments()
        isPlaying = false
        isLocallyPaused = false
        viewMode = .positional
        shapeFocusStage = .ideal
        playhead = min(ShapeFocusStage.ideal.referenceTime, selectedScenario.duration)
        sharedPitchAnchorID = anchorID
        triangleLockMode = .place
        isLocalTrianglePreview = false
        hasLocallyAcknowledgedTrianglePlacement = true
        statusMessage = "Physical Triangle Lock ready. Stay still and verify each shared station."
        emitSnapshot()
    }

    /// Starts a solo, device-local rehearsal. Its WorldAnchor identifier never
    /// appears in `makeSnapshot()`, even if SharePlay begins later.
    func activateLocalTrianglePreview(anchorID: UUID) {
        guard localRole == .coach,
              !isCollaborationActive,
              selectedScenario.kind == .shapeLab else { return }
        isPlaying = false
        isLocallyPaused = false
        viewMode = .positional
        shapeFocusStage = .ideal
        playhead = min(ShapeFocusStage.ideal.referenceTime, selectedScenario.duration)
        sharedPitchAnchorID = anchorID
        triangleLockMode = .place
        isLocalTrianglePreview = true
        hasLocallyAcknowledgedTrianglePlacement = true
        statusMessage = "Local station preview ready. Stay still and keep movements slow."
    }

    func acknowledgeTrianglePlacementLocally(
        participantID: UUID? = nil,
        sharedSession: Bool = false
    ) {
        guard triangleLockMode == .place, sharedPitchAnchorID != nil else { return }
        guard canRevealPhysicalTriangleMarkers(
            participantID: participantID,
            sharedSession: sharedSession
        ) else {
            statusMessage = "No unique role station is assigned to this headset. Stay still and ask the coach."
            return
        }
        hasLocallyAcknowledgedTrianglePlacement = true
        statusMessage = "Your station is visible. Look up and keep movements slow."
    }

    func revokeTrianglePlacementConsentLocally() {
        hasLocallyAcknowledgedTrianglePlacement = false
        if triangleLockMode == .place {
            statusMessage = "Physical station hidden on this headset until you confirm it again."
        }
    }

    func endTrianglePlacement() {
        guard localRole == .coach, triangleLockMode == .place else { return }
        let retiredAnchorID = sharedPitchAnchorID
        isPlaying = false
        triangleLockMode = .visualise
        shapeFocusStage = .ideal
        isLocalTrianglePreview = false
        hasLocallyAcknowledgedTrianglePlacement = false
        sharedPitchAnchorID = nil
        statusMessage = "Physical stations ended. Tabletop visualisation restored."
        if let retiredAnchorID { onRetirePitchAnchor?(retiredAnchorID) }
        emitSnapshot()
    }

    /// Reconciles shared state when ARKit reports that the selected world anchor
    /// disappeared unexpectedly. The coach republishes the safe tabletop state;
    /// players wait for that authoritative update without trying to recreate it.
    func handleSharedPitchAnchorRemoval(_ anchorID: UUID) {
        guard sharedPitchAnchorID == anchorID else { return }
        sharedPitchAnchorID = nil
        isLocalTrianglePreview = false
        hasLocallyAcknowledgedTrianglePlacement = false
        latestCoachSnapshot = nil
        isPlaying = false

        if triangleLockMode == .place {
            triangleLockMode = .visualise
            shapeFocusStage = .ideal
            viewMode = .positional
            statusMessage = "Shared origin lost. Tabletop Shape Focus restored safely."
        } else {
            statusMessage = "Shared pitch origin is no longer available."
        }

        if localRole == .coach {
            emitSnapshot()
        }
    }

    func resetCollaborationState() {
        let retiredAnchorID = sharedPitchAnchorID
        isCollaborationActive = false
        latestCoachSnapshot = nil
        rollbackAllCoachMarkGeometryPreviews()
        participantSeatAssignments.removeAll()
        sharedPitchAnchorID = nil
        triangleLockMode = .visualise
        isLocalTrianglePreview = false
        shapeFocusStage = .problem
        hasLocallyAcknowledgedTrianglePlacement = false
        coachFocusPerspectiveID = nil
        coachLockEnabled = false
        isCoachLocalReview = false
        followsCoach = true
        isLocallyPaused = false
        localRole = .coach
        isPlaying = false
        selectedTool = .run
        pendingDrawStart = nil
        isDrawing = false
        statusMessage = "Squad room closed. Solo review is ready."
        if let retiredAnchorID { onRetirePitchAnchor?(retiredAnchorID) }
    }

    func resetScenario() {
        if triangleLockMode == .place {
            endTrianglePlacement()
        }
        selectScenario(id: selectedScenarioID)
    }

    func advance(by delta: TimeInterval) {
        guard isActivelyPlaying,
              delta.isFinite,
              delta > 0,
              playhead.isFinite,
              playbackRate.isFinite,
              playbackRate > 0,
              selectedScenario.duration.isFinite,
              selectedScenario.duration >= 0 else { return }
        let duration = selectedScenario.duration
        let remaining = max(duration - playhead, 0)
        let requestedAdvance = delta >= remaining / playbackRate
            ? remaining
            : delta * playbackRate
        playhead = min(max(playhead + requestedAdvance, 0), duration)
        if playhead >= duration {
            isPlaying = false
            statusMessage = "Replay complete"
        }
    }

    func makeSnapshot() -> SharedPlaybackSnapshot {
        let publishesPhysicalPlacement = triangleLockMode == .place && !isLocalTrianglePreview
        let sharedMarks = marks.map { mark in
            guard let baseline = pendingCoachMarkGeometryBaselines[mark.id] else { return mark }
            return markReplacingGeometry(
                mark,
                start: baseline.start,
                end: baseline.end
            )
        }
        return SharedPlaybackSnapshot(
            scenarioID: selectedScenarioID,
            playhead: playhead,
            isPlaying: isPlaying && playhead < selectedScenario.duration,
            playbackRate: playbackRate,
            viewMode: viewMode,
            coachFocusPerspectiveID: coachFocusPerspectiveID,
            coachLockEnabled: coachLockEnabled,
            marks: sharedMarks,
            seatAssignments: participantSeatAssignments,
            showsLaneLens: showsLaneLens,
            sharedPitchAnchorID: publishesPhysicalPlacement ? sharedPitchAnchorID : nil,
            triangleLockMode: publishesPhysicalPlacement ? .place : .visualise,
            shapeFocusStage: shapeFocusStage
        )
    }

    @discardableResult
    func applyRemote(_ snapshot: SharedPlaybackSnapshot) -> Bool {
        guard let scenario = scenarios.first(where: { $0.id == snapshot.scenarioID }),
              scenario.duration.isFinite,
              scenario.duration >= 0 else { return false }

        let fallbackPlayhead = playhead.isFinite ? playhead : 0
        let fallbackPlaybackRate = playbackRate.isFinite ? playbackRate : 1
        let sanitizedPlayhead = min(
            max(snapshot.playhead.isFinite ? snapshot.playhead : fallbackPlayhead, 0),
            scenario.duration
        )
        let sanitizedPlaybackRate = min(
            max(snapshot.playbackRate.isFinite ? snapshot.playbackRate : fallbackPlaybackRate, 0.25),
            4
        )
        let sanitizedFocusID = snapshot.coachFocusPerspectiveID.flatMap { focusID in
            scenario.player(id: focusID) == nil ? nil : focusID
        }
        let sanitizedCoachLock = snapshot.coachLockEnabled && sanitizedFocusID != nil
        let validSeatIDs = Set(scenario.homePlayers.map(\.id))
        var claimedSeatIDs = Set<String>()
        var sanitizedSeatAssignments: [UUID: String] = [:]
        for (participantID, playerID) in snapshot.seatAssignments.sorted(by: {
            $0.key.uuidString < $1.key.uuidString
        }) {
            guard validSeatIDs.contains(playerID), !claimedSeatIDs.contains(playerID) else { continue }
            claimedSeatIDs.insert(playerID)
            sanitizedSeatAssignments[participantID] = playerID
        }
        var seenMarkIDs = Set<UUID>()
        var sanitizedMarks: [CoachMark] = []
        sanitizedMarks.reserveCapacity(min(snapshot.marks.count, Self.maximumSharedCoachMarks))
        for mark in snapshot.marks {
            guard sanitizedMarks.count < Self.maximumSharedCoachMarks else { break }
            guard seenMarkIDs.insert(mark.id).inserted,
                  isValidSharedMark(mark, for: scenario) else { continue }
            sanitizedMarks.append(mark)
        }

        let previousAnchorID = sharedPitchAnchorID
        isLocalTrianglePreview = false
        let sanitizedTriangleMode: TriangleLockMode =
            scenario.kind == .shapeLab
                && snapshot.triangleLockMode == .place
                && snapshot.sharedPitchAnchorID != nil
            ? .place
            : .visualise
        let sanitizedShapeFocusStage: ShapeFocusStage = scenario.kind == .shapeLab
            ? (sanitizedTriangleMode == .place ? .ideal : snapshot.shapeFocusStage)
            : .problem
        let sanitizedSharedPitchAnchorID = sanitizedTriangleMode == .place
            ? snapshot.sharedPitchAnchorID
            : nil
        let sanitizedSnapshot = SharedPlaybackSnapshot(
            scenarioID: scenario.id,
            playhead: sanitizedPlayhead,
            isPlaying: snapshot.isPlaying && sanitizedPlayhead < scenario.duration,
            playbackRate: sanitizedPlaybackRate,
            viewMode: sanitizedTriangleMode == .place ? .positional : snapshot.viewMode,
            coachFocusPerspectiveID: sanitizedFocusID,
            coachLockEnabled: sanitizedCoachLock,
            marks: sanitizedMarks,
            seatAssignments: sanitizedSeatAssignments,
            showsLaneLens: snapshot.showsLaneLens && scenario.kind == .passingChannels,
            sharedPitchAnchorID: sanitizedSharedPitchAnchorID,
            triangleLockMode: sanitizedTriangleMode,
            shapeFocusStage: sanitizedShapeFocusStage
        )
        selectedTool = .run
        pendingDrawStart = nil
        isDrawing = false
        pendingCoachMarkGeometryBaselines.removeAll(keepingCapacity: true)
        latestCoachSnapshot = sanitizedSnapshot
        participantSeatAssignments = sanitizedSeatAssignments
        if previousAnchorID != sanitizedSharedPitchAnchorID || triangleLockMode != sanitizedTriangleMode {
            hasLocallyAcknowledgedTrianglePlacement = false
        }
        sharedPitchAnchorID = sanitizedSharedPitchAnchorID
        triangleLockMode = sanitizedTriangleMode
        if sanitizedTriangleMode == .place {
            if selectedScenarioID != scenario.id {
                selectedScenarioID = scenario.id
                localPerspectiveID = scenario.defaultPerspectiveID
            }
            shapeFocusStage = .ideal
            isPlaying = false
            viewMode = .positional
        }
        guard !isLocallyPaused else {
            statusMessage = "Local comfort pause — coach state ready when you resume"
            return true
        }
        if selectedScenarioID != scenario.id {
            selectedScenarioID = scenario.id
            localPerspectiveID = scenario.defaultPerspectiveID
        }
        playhead = sanitizedSnapshot.playhead
        isPlaying = sanitizedTriangleMode == .place ? false : sanitizedSnapshot.isPlaying
        playbackRate = sanitizedSnapshot.playbackRate
        viewMode = sanitizedSnapshot.viewMode
        coachFocusPerspectiveID = sanitizedSnapshot.coachFocusPerspectiveID
        coachLockEnabled = sanitizedSnapshot.coachLockEnabled
        marks = sanitizedSnapshot.marks
        showsLaneLens = sanitizedSnapshot.showsLaneLens
        shapeFocusStage = sanitizedSnapshot.shapeFocusStage
        statusMessage = "Coach state synchronized"
        return true
    }

    /// Shared marks become RealityKit entity trees, so bound both geometry and
    /// presentation data before accepting them. Collection-level duplicate ID
    /// rejection happens in `applyRemote` to keep scene dictionary keys unique.
    private func isValidSharedMark(
        _ mark: CoachMark,
        for scenario: ReplayScenario
    ) -> Bool {
        let hasFiniteBoundedGeometry = Self.isPointOnPitch(mark.start)
            && Self.isPointOnPitch(mark.end)
        let hasValidRevealTime = mark.revealTime.isFinite
            && mark.revealTime >= 0
            && mark.revealTime <= scenario.duration
        let hasValidWindow = mark.hideTime.map {
            $0.isFinite
                && $0 > mark.revealTime
                && $0 - mark.revealTime <= Self.maximumCoachAnnotationDuration
        } ?? true
        let hasValidText = !mark.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && mark.label.count <= Self.maximumCoachMarkLabelLength
            && mark.label.utf8.count <= Self.maximumCoachMarkLabelLength * 4
            && mark.author.count <= Self.maximumCoachMarkLabelLength
            && mark.author.utf8.count <= Self.maximumCoachMarkLabelLength * 4
        guard hasFiniteBoundedGeometry,
              hasValidRevealTime,
              hasValidWindow,
              hasValidText else { return false }
        guard mark.kind == .playerLabel else { return mark.playerID == nil }
        guard let playerID = mark.playerID else { return false }
        return scenario.player(id: playerID) != nil
    }

    private func markReplacingGeometry(
        _ mark: CoachMark,
        start: PitchPoint,
        end: PitchPoint
    ) -> CoachMark {
        CoachMark(
            id: mark.id,
            kind: mark.kind,
            start: start,
            end: end,
            label: mark.label,
            revealTime: mark.revealTime,
            hideTime: mark.hideTime,
            author: mark.author,
            playerID: mark.playerID
        )
    }

    private static func isPointOnPitch(_ point: PitchPoint) -> Bool {
        point.x.isFinite
            && point.z.isFinite
            && abs(point.x) <= pitchHalfWidth
            && abs(point.z) <= pitchHalfLength
    }

    static func clampedPitchPoint(_ point: PitchPoint) -> PitchPoint {
        guard point.x.isFinite, point.z.isFinite else { return .zero }
        return PitchPoint(
            x: min(max(point.x, -pitchHalfWidth), pitchHalfWidth),
            z: min(max(point.z, -pitchHalfLength), pitchHalfLength)
        )
    }

    private func rollbackAllCoachMarkGeometryPreviews() {
        guard !pendingCoachMarkGeometryBaselines.isEmpty else { return }
        for index in marks.indices {
            let mark = marks[index]
            guard let baseline = pendingCoachMarkGeometryBaselines[mark.id] else { continue }
            marks[index] = markReplacingGeometry(
                mark,
                start: baseline.start,
                end: baseline.end
            )
        }
        pendingCoachMarkGeometryBaselines.removeAll(keepingCapacity: true)
    }

    func setCollaborationActive(_ isActive: Bool) {
        if isActive {
            discardLocalTrianglePreviewForSessionTransition()
        }
        isCollaborationActive = isActive
        guard !isActive else { return }
        rollbackAllCoachMarkGeometryPreviews()
        isCoachLocalReview = false
        followsCoach = true
        isLocallyPaused = false
    }

    private func emitSnapshot() {
        onBroadcastSnapshot?(makeSnapshot())
    }
}
