import Foundation
import Observation

/// Identifies the independently adjustable handle of a two-point spatial
/// annotation. Keeping this domain-level avoids coupling accessibility actions
/// to RealityKit entities or a particular control surface.
enum CoachMarkEndpoint: Equatable, Sendable {
    case start
    case end
}

/// The vertical part of a selected spatial instruction that should move.
/// `both` lifts the complete stroke atomically, avoiding two SharePlay packets
/// and preserving a level run/pass when the coach wants a raised layer.
enum CoachMarkElevationTarget: Equatable, Sendable {
    case start
    case end
    case both
}

/// The exact cumulative movement accepted for a joystick preview. Returning
/// pitch metres instead of a Boolean keeps a clamped diagonal sample honest:
/// one axis may reach a boundary while the other still has room to move.
struct CoachMarkEndpointPreviewResult: Equatable, Sendable {
    let appliedDelta: PitchPoint
    let hasActiveTransaction: Bool
}

/// Identifies the one annotation handle currently owned by a local joystick
/// gesture. Controls use this only for presentation; the store remains the
/// authority that rejects competing mutations.
struct CoachMarkEndpointPreviewOwner: Equatable, Sendable {
    let markID: UUID
    let endpoint: CoachMarkEndpoint
}

@MainActor
@Observable
final class ReplayStore {
    static let availablePlaybackRates: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 4]
    static let coachAnnotationDisplayDuration = CoachMarkTimingPolicy.preferredDuration
    static let maximumCoachAnnotationDuration = CoachMarkTimingPolicy.maximumDuration
    /// A pitch pinch that begins close to a footballer is treated as authored
    /// from that track. The radius is deliberately tighter than the broad
    /// player-selection target so a coach can still draw a fixed-space mark
    /// beside a player without it unexpectedly moving through time.
    static let coachMarkTrackSnapDistance: Float = 1.65
    /// Bounds independently rendered annotation hierarchies in shared state.
    static let maximumSharedCoachMarks = 128
    static let maximumCoachMarkLabelLength = 96
    /// Match-review annotations are bounded pitch-relative spatial data, not
    /// arbitrary room content. X/Z stays inside the actual 68 x 105 metre
    /// surface and Y is separately capped by `CoachMarkGeometryPolicy`, so a
    /// stray drag or malformed peer packet cannot create giant scene geometry.
    static let pitchHalfWidth: Float = 34
    static let pitchHalfLength: Float = 52.5

    let scenarios: [ReplayScenario]
    let reviewLibrary: ReplayReviewLibrary

    var selectedScenarioID: String {
        didSet { if oldValue != selectedScenarioID { scheduleReviewAutosave() } }
    }
    var playhead: TimeInterval = 0 {
        didSet {
            // Passive frame advancement never encodes the library. Deliberate
            // seeks/pauses and lifecycle exits save the latest committed time.
            if !isPlaying, oldValue != playhead {
                scheduleReviewAutosave()
            }
        }
    }
    var isPlaying = false { didSet { if oldValue != isPlaying { scheduleReviewAutosave() } } }
    var playbackRate: Double = 1 { didSet { if oldValue != playbackRate { scheduleReviewAutosave() } } }
    var viewMode: ReplayViewMode { didSet { if oldValue != viewMode { scheduleReviewAutosave() } } }
    var localPerspectiveID: String {
        didSet { if oldValue != localPerspectiveID { scheduleReviewAutosave() } }
    }
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
            if oldValue != marks { scheduleReviewAutosave() }
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
    /// True only while a joystick owns a local endpoint preview transaction.
    /// Control surfaces may use this to disable conflicting actions, but the
    /// store also enforces the barrier so correctness never depends on UI state.
    private(set) var hasActiveCoachMarkEndpointPreview = false
    private(set) var activeCoachMarkEndpointPreviewOwner: CoachMarkEndpointPreviewOwner?
    /// A timeline pinch is an exclusive device-local preview transaction. The
    /// store owns this flag so a second hand, accessibility activation, or an
    /// external control cannot start annotation/POV work against a transient
    /// playhead while the control deck owns the scrub.
    private(set) var hasActiveTimelineScrub = false
    private(set) var shapeFocusStage: ShapeFocusStage = .problem {
        didSet { if oldValue != shapeFocusStage { scheduleReviewAutosave() } }
    }
    var showsIdealBranch: Bool { shapeFocusStage == .ideal }
    var showsLaneLens = false { didSet { if oldValue != showsLaneLens { scheduleReviewAutosave() } } }
    private(set) var roomPresentation = ReplayRoomPresentation()
    var isImmersiveOpen: Bool { roomPresentation.isOpen }
    var isOpeningImmersive: Bool { roomPresentation.isOpening }
    var isClosingImmersive: Bool { roomPresentation.isClosing }
    var isRoomPresentationBusy: Bool { roomPresentation.isBusy }
    var statusMessage = "Choose a scenario, then enter the review room."

    @ObservationIgnored private var reviewAutosaveTask: Task<Void, Never>?
    @ObservationIgnored private(set) var scheduledReviewAutosaveID: UUID?
    @ObservationIgnored private var reviewAutosaveDeadline: ContinuousClock.Instant?
    @ObservationIgnored private var isReviewAutosaveReady = false
    @ObservationIgnored private var isRestoringSavedReview = false
    @ObservationIgnored private var retainedScenarioMarks: [String: [CoachMark]] = [:]
    private var annotationEditHistory: ReplayAnnotationEditHistory

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

    @ObservationIgnored
    private var timelineScrubCheckpoint: TimelineScrubCheckpoint?

    /// Covers both the control-deck joystick transaction and a direct pinch on
    /// a glowing RealityKit endpoint. Transport, POV, and view mutations must
    /// treat either route as one exclusive spatial edit.
    var hasActiveCoachMarkGeometryPreview: Bool {
        hasActiveCoachMarkEndpointPreview || !pendingCoachMarkGeometryBaselines.isEmpty
    }

    /// Joystick drags use absolute movement from a stable gesture baseline.
    /// This avoids treating a partially clamped multi-notch request as though
    /// every requested notch had been applied. The preview stays local until
    /// gesture end, when one snapshot publishes the final geometry.
    @ObservationIgnored
    private var pendingCoachMarkEndpointPreviews: [UUID: CoachMarkEndpointPreview] = [:]

    /// A collaboration or immersive lifecycle transition may cancel the store
    /// transaction while the physical pinch is still down. Remember that
    /// gesture identity until its eventual end/cancel callback so a later drag
    /// sample from the same pinch cannot silently start a second transaction.
    @ObservationIgnored
    private var interruptedCoachMarkEndpointGestureIDs: Set<UUID> = []

    @ObservationIgnored private var pendingCoachMarkCurveGestures: [UUID: UUID] = [:]
    @ObservationIgnored private var finishedCoachMarkCurveGestures: [UUID] = []

    private struct CoachMarkGeometry {
        let keyframes: [CoachMarkKeyframe]?
        let start: PitchPoint
        let end: PitchPoint
        let startElevation: Float?
        let endElevation: Float?
        let curve: CoachMarkCurve?
        let startTrackAnchor: CoachMarkTrackAnchor?
        let endTrackAnchor: CoachMarkTrackAnchor?
    }

    private struct TimelineScrubCheckpoint {
        let scenarioID: String
        let playhead: TimeInterval
        let isPlaying: Bool
        let isLocallyPaused: Bool
    }

    private struct CoachMarkEndpointPreview {
        let gestureID: UUID
        let endpoint: CoachMarkEndpoint
        let resolvedStart: PitchPoint
        let resolvedEnd: PitchPoint
        let wasPlaying: Bool
        /// Once the squad has received the masked pause baseline, cancellation
        /// must keep this headset paused as well. Resuming only the coach would
        /// split transport authority and the next heartbeat would snap them back.
        let didPublishPause: Bool
        var latestSampleIsValid: Bool
        var appliedDelta: PitchPoint
    }

    private func setPendingCoachMarkEndpointPreview(
        _ preview: CoachMarkEndpointPreview,
        for id: UUID
    ) {
        pendingCoachMarkEndpointPreviews[id] = preview
        hasActiveCoachMarkEndpointPreview = true
        activeCoachMarkEndpointPreviewOwner = CoachMarkEndpointPreviewOwner(
            markID: id,
            endpoint: preview.endpoint
        )
    }

    @discardableResult
    private func removePendingCoachMarkEndpointPreview(
        for id: UUID
    ) -> CoachMarkEndpointPreview? {
        let preview = pendingCoachMarkEndpointPreviews.removeValue(forKey: id)
        hasActiveCoachMarkEndpointPreview = !pendingCoachMarkEndpointPreviews.isEmpty
        if let remaining = pendingCoachMarkEndpointPreviews.first {
            activeCoachMarkEndpointPreviewOwner = CoachMarkEndpointPreviewOwner(
                markID: remaining.key,
                endpoint: remaining.value.endpoint
            )
        } else {
            activeCoachMarkEndpointPreviewOwner = nil
        }
        return preview
    }

    private func removeAllPendingCoachMarkEndpointPreviews() {
        pendingCoachMarkEndpointPreviews.removeAll(keepingCapacity: true)
        hasActiveCoachMarkEndpointPreview = false
        activeCoachMarkEndpointPreviewOwner = nil
    }

    /// User-driven state changes are serialized behind spatial adjustment.
    /// Rejection is deliberately local and snapshot-free: the gesture may then
    /// commit once or cancel without a stale transport/annotation action having
    /// changed its baseline or collaboration history.
    private func allowsMutationOutsideEndpointPreview() -> Bool {
        guard !hasActiveTimelineScrub else {
            statusMessage = "Finish or cancel the timeline scrub first"
            return false
        }
        guard !hasActiveCoachMarkGeometryPreview else {
            statusMessage = "Finish or cancel the annotation adjustment first"
            return false
        }
        return true
    }

    /// Camera/transport changes must not move the pitch beneath an unfinished
    /// annotation or a hand that owns a timeline/geometry transaction.
    var canChangePlaybackView: Bool {
        !isDrawing && !hasActiveTimelineScrub && !hasActiveCoachMarkGeometryPreview
    }

    private func allowsPlaybackViewChange() -> Bool {
        guard allowsMutationOutsideEndpointPreview() else { return false }
        guard !isDrawing else {
            statusMessage = "Finish or cancel the annotation first"
            return false
        }
        return true
    }

    convenience init() {
        self.init(scenarios: DemoScenarios.all)
    }

    init(scenarios: [ReplayScenario], reviewLibrary: ReplayReviewLibrary? = nil) {
        precondition(!scenarios.isEmpty, "Replay XI requires at least one scenario")
        self.scenarios = scenarios
        self.reviewLibrary = reviewLibrary ?? ReplayReviewLibrary(scenarios: scenarios)
        let first = scenarios[0]
        selectedScenarioID = first.id
        viewMode = first.defaultViewMode
        localPerspectiveID = first.defaultPerspectiveID
        marks = first.coachMarks
        annotationEditHistory = ReplayAnnotationEditHistory(marks: first.coachMarks)
        reviewIndexVersionCache.seed(marks: marks)
        isReviewAutosaveReady = true
    }

    var savedReviews: [SavedReplayReview] { reviewLibrary.savedReviews }

    /// The app has one local editor. Keep saved timeline/marks/POV, but never
    /// restore a remote role, a coach lock or a transport callback on launch.
    func prepareForLocalExperience() {
        onBroadcastSnapshot = nil
        setCollaborationActive(false)
        localRole = .coach
        coachLockEnabled = false
        coachFocusPerspectiveID = nil
        isCoachLocalReview = false
        followsCoach = true
        isLocallyPaused = false
        participantSeatAssignments.removeAll()
        statusMessage = "Local replay ready"
    }

    var autosavedReview: SavedReplayReview? { reviewLibrary.autosavedReview }
    /// One current reason for both the drawer and its final submit callback.
    /// Keep the library's diagnostic intact; a blocked copy must not replace
    /// recovery guidance or leak an in-progress edit into persisted state.
    var reviewSaveBlockReason: String? {
        if reviewLibrary.isReadOnly { return reviewLibrary.status }
        if hasActiveTimelineScrub { return "Finish or cancel the timeline scrub before saving" }
        if hasActiveCoachMarkGeometryPreview { return "Finish or cancel the annotation adjustment before saving" }
        if isDrawing { return "Finish or cancel the annotation before saving" }
        if savedReviews.count >= ReplayReviewLibrary.maximumSavedReviews {
            return "\(ReplayReviewLibrary.maximumSavedReviews) saves reached. Delete a save first."
        }
        return nil
    }
    var reviewSaveStatus: String {
        if let reason = reviewSaveBlockReason { return reason }
        return reviewLibrary.usesDisk ? reviewLibrary.status : "\(reviewLibrary.status) · saves are temporary"
    }
    var canSaveReview: Bool {
        reviewSaveBlockReason == nil
    }
    var canRestoreSavedReview: Bool {
        !isCollaborationActive && triangleLockMode != .place
            && !hasActiveTimelineScrub && !hasActiveCoachMarkGeometryPreview && !isDrawing
    }

    func makeSavedReviewState() -> SavedReplayState {
        let committed = makeSnapshot()
        var scenarioMarks = retainedScenarioMarks
        scenarioMarks[selectedScenarioID] = committed.marks
        return SavedReplayState(
            scenarioID: selectedScenarioID,
            playhead: committed.playhead,
            playbackRate: playbackRate,
            viewMode: viewMode,
            perspectiveID: localPerspectiveID,
            showsLaneLens: showsLaneLens,
            shapeFocusStage: shapeFocusStage,
            marksByScenario: scenarioMarks
        )
    }

    @discardableResult
    func saveReview(named name: String, state: SavedReplayState? = nil) -> Bool {
        if let reason = reviewSaveBlockReason {
            statusMessage = reason
            return false
        }
        return reviewLibrary.save(named: name, state: state ?? makeSavedReviewState())
    }

    @discardableResult
    func renameSavedReview(id: UUID, name: String) -> Bool {
        reviewLibrary.rename(id: id, name: name)
    }

    @discardableResult
    func deleteSavedReview(id: UUID) -> Bool { reviewLibrary.delete(id: id) }

    @discardableResult
    func restoreSavedReview(id: UUID) -> Bool {
        guard let review = savedReviews.first(where: { $0.id == id }) else { return false }
        return restoreReview(review)
    }

    @discardableResult
    func restoreAutosavedReview() -> Bool {
        guard let review = autosavedReview else { return false }
        return restoreReview(review)
    }

    @discardableResult
    func restoreReview(_ review: SavedReplayReview) -> Bool {
        guard canRestoreSavedReview else {
            statusMessage = isCollaborationActive
                ? "Leave the squad room to open a saved review"
                : "Finish the current gesture or placement first"
            return false
        }
        guard reviewLibrary.accepts(review.state) else {
            statusMessage = "This review could not be opened"
            return false
        }
        cancelScheduledReviewAutosave()
        isRestoringSavedReview = true
        resetCollaborationState()
        let state = review.state
        selectedScenarioID = state.scenarioID
        playhead = state.playhead
        playbackRate = state.playbackRate
        viewMode = state.viewMode
        localPerspectiveID = state.perspectiveID
        retainedScenarioMarks = state.marksByScenario
        marks = state.marks
        annotationEditHistory.reset(to: marks)
        showsLaneLens = state.showsLaneLens
        shapeFocusStage = selectedScenario.kind == .shapeLab ? state.shapeFocusStage : .problem
        isPlaying = false
        isRestoringSavedReview = false
        statusMessage = "\(review.name) opened · paused"
        scheduleReviewAutosave()
        return true
    }

    /// Captures committed endpoints/time even during an interrupted gesture.
    /// It never persists the drawing tool or uncommitted first stroke point.
    @discardableResult
    func flushReviewAutosave() -> Bool {
        cancelScheduledReviewAutosave()
        return reviewLibrary.autosave(makeSavedReviewState())
    }

    private func scheduleReviewAutosave() {
        guard isReviewAutosaveReady, !isRestoringSavedReview,
              reviewLibrary.usesDisk, !reviewLibrary.isReadOnly else { return }
        reviewAutosaveDeadline = ContinuousClock().now.advanced(by: .milliseconds(600))
        // Scrubs and handle drags update at display rate. Extend the existing
        // deadline instead of allocating/cancelling a Task for every sample.
        guard reviewAutosaveTask == nil else { return }
        let workerID = UUID()
        scheduledReviewAutosaveID = workerID
        reviewAutosaveTask = Task { @MainActor [weak self] in
            // Hold only a deadline across sleep, not the Store. A closed test,
            // preview or scene must be releasable while its timer is pending.
            while let deadline = self?.deadlineForReviewAutosave(workerID) {
                do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
                guard !Task.isCancelled else { return }
                if self?.finishReviewAutosaveIfDue(workerID, now: ContinuousClock().now) != false { return }
            }
        }
    }

    private func deadlineForReviewAutosave(_ workerID: UUID) -> ContinuousClock.Instant? {
        scheduledReviewAutosaveID == workerID ? reviewAutosaveDeadline : nil
    }

    /// Returns false only when a newer edit extended this worker's deadline.
    private func finishReviewAutosaveIfDue(_ workerID: UUID, now: ContinuousClock.Instant) -> Bool {
        guard scheduledReviewAutosaveID == workerID, let deadline = reviewAutosaveDeadline else { return true }
        guard now >= deadline else { return false }
        scheduledReviewAutosaveID = nil
        reviewAutosaveDeadline = nil
        reviewAutosaveTask = nil
        _ = reviewLibrary.autosave(makeSavedReviewState())
        return true
    }

    private func cancelScheduledReviewAutosave() {
        // Retire ownership before cancellation so a late wake cannot clear a
        // replacement worker or write a pre-restore snapshot over a new review.
        scheduledReviewAutosaveID = nil
        reviewAutosaveDeadline = nil
        reviewAutosaveTask?.cancel()
        reviewAutosaveTask = nil
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

    /// Spatial authoring samples the same view-specific origin as the visible
    /// body. Raw telemetry would put labels and new run anchors ahead of a
    /// fallen player, or behind a role moved into the ideal formation.
    var playerPresentation: ReplayPlayerPresentation {
        ReplayPlayerPresentation(
            scenario: selectedScenario,
            viewMode: viewMode,
            showsIdealBranch: showsIdealBranch,
            triangleLockMode: triangleLockMode
        )
    }

    func presentedPlayerPose(for player: PlayerTrack, at time: TimeInterval) -> PlayerPose {
        playerPresentation.pose(for: player, at: time)
    }

    func presentedCoachMarkGeometry(
        _ mark: CoachMark,
        at time: TimeInterval
    ) -> ResolvedCoachMarkGeometry {
        let presentation = playerPresentation
        // A mark has at most two attached players. Avoid sampling the entire
        // squad for each joystick or direct-handle input sample.
        let poses = Dictionary(uniqueKeysWithValues: mark.anchoredPlayerIDs.compactMap { id in
            selectedScenario.player(id: id).map { (id, presentation.pose(for: $0, at: time)) }
        })
        return mark.resolvedGeometry(
            in: selectedScenario, at: time, presentedPlayerPoses: poses
        )
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
        selectScenario(id: id, broadcast: broadcast, resettingReview: false)
    }

    private func selectScenario(id: String, broadcast: Bool, resettingReview: Bool) {
        guard allowsMutationOutsideEndpointPreview() else { return }
        guard !isCollaborationActive || localRole == .coach || !broadcast else { return }
        guard let scenario = scenarios.first(where: { $0.id == id }) else { return }
        guard selectedScenarioID != id || resettingReview else { return }
        guard triangleLockMode != .place else {
            statusMessage = "End physical placement before changing scenarios."
            return
        }
        let retiredAnchorID = sharedPitchAnchorID
        let changesScenario = selectedScenarioID != id
        if changesScenario {
            retainedScenarioMarks[selectedScenarioID] = makeSnapshot().marks
        }
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
        marks = resettingReview ? scenario.coachMarks : (retainedScenarioMarks[id] ?? scenario.coachMarks)
        annotationEditHistory.reset(to: marks)
        pendingCoachMarkGeometryBaselines.removeAll(keepingCapacity: true)
        removeAllPendingCoachMarkEndpointPreviews()
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
        guard allowsPlaybackViewChange() else { return }
        guard !isCollaborationActive || localRole == .coach || !broadcast else {
            setFollowingCoach(isLocallyPaused)
            return
        }
        if !isPlaying, playhead >= selectedScenario.duration - 0.05 {
            playhead = 0
        }
        isLocallyPaused = false
        isPlaying.toggle()
        statusMessage = isPlaying ? "Replay playing" : "Replay paused"
        if broadcast { emitSnapshot() }
    }

    func setPlaying(_ value: Bool, broadcast: Bool = true) {
        guard allowsMutationOutsideEndpointPreview() else { return }
        guard !value || !isDrawing else {
            statusMessage = "Finish or cancel the annotation first"
            return
        }
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
        guard allowsPlaybackViewChange() else { return }
        guard !isCollaborationActive || localRole == .coach || !broadcast else { return }
        guard time.isFinite, selectedScenario.duration.isFinite else { return }
        playhead = min(max(time, 0), selectedScenario.duration)
        if playhead >= selectedScenario.duration {
            isPlaying = false
        }
        scheduleReviewAutosave()
        if broadcast { emitSnapshot() }
    }

    /// Begins a local scrub without publishing its temporary pause or playhead.
    /// The checkpoint stays in the store so every other input route observes
    /// the same exclusive transaction, including a second hand on the pitch.
    @discardableResult
    func beginTimelineScrub() -> Bool {
        guard !hasActiveTimelineScrub else { return true }
        guard !isDrawing else {
            statusMessage = "Finish or cancel the annotation first"
            return false
        }
        guard !hasActiveCoachMarkGeometryPreview else {
            statusMessage = "Finish or cancel the annotation adjustment first"
            return false
        }
        guard playhead.isFinite,
              selectedScenario.duration.isFinite,
              selectedScenario.duration >= 0 else { return false }
        timelineScrubCheckpoint = TimelineScrubCheckpoint(
            scenarioID: selectedScenarioID,
            playhead: min(max(playhead, 0), selectedScenario.duration),
            isPlaying: isPlaying && playhead < selectedScenario.duration,
            isLocallyPaused: isLocallyPaused
        )
        hasActiveTimelineScrub = true
        isPlaying = false
        return true
    }

    /// Applies an unpublished preview sample while preserving the checkpoint
    /// used by cancellation and by any defensive snapshot taken mid-gesture.
    @discardableResult
    func previewTimelineScrub(to time: TimeInterval) -> Bool {
        guard hasActiveTimelineScrub,
              timelineScrubCheckpoint?.scenarioID == selectedScenarioID,
              time.isFinite,
              selectedScenario.duration.isFinite else { return false }
        playhead = min(max(time, 0), selectedScenario.duration)
        isPlaying = false
        return true
    }

    /// Commits one bounded playhead and restores the exact pre-pinch playback
    /// and local-comfort flags. Callers may publish after this returns, when no
    /// transient scrub remains for `makeSnapshot()` to mask.
    @discardableResult
    func commitTimelineScrub(to time: TimeInterval) -> Bool {
        guard let checkpoint = timelineScrubCheckpoint,
              hasActiveTimelineScrub,
              checkpoint.scenarioID == selectedScenarioID,
              time.isFinite,
              selectedScenario.duration.isFinite else {
            cancelTimelineScrub()
            return false
        }
        let committedPlayhead = min(max(time, 0), selectedScenario.duration)
        playhead = committedPlayhead
        isPlaying = checkpoint.isPlaying && committedPlayhead < selectedScenario.duration
        isLocallyPaused = checkpoint.isLocallyPaused
        timelineScrubCheckpoint = nil
        hasActiveTimelineScrub = false
        scheduleReviewAutosave()
        return true
    }

    /// Rolls an interrupted pinch back atomically. Immersive exit invokes this
    /// before applying its definitive pause, eliminating callback-order races.
    func cancelTimelineScrub() {
        defer {
            timelineScrubCheckpoint = nil
            hasActiveTimelineScrub = false
        }
        guard let checkpoint = timelineScrubCheckpoint,
              checkpoint.scenarioID == selectedScenarioID else { return }
        playhead = checkpoint.playhead
        isPlaying = checkpoint.isPlaying && checkpoint.playhead < selectedScenario.duration
        isLocallyPaused = checkpoint.isLocallyPaused
    }

    /// Opens a device-local review instant without claiming transport
    /// authority. In a joined player session this atomically leaves coach
    /// follow before moving the playhead, preventing the next heartbeat from
    /// looking like an unexpected snap-back.
    @discardableResult
    func beginLocalReview(at time: TimeInterval) -> Bool {
        guard allowsMutationOutsideEndpointPreview() else { return false }
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
        guard allowsPlaybackViewChange() else { return }
        guard !isCollaborationActive || localRole == .coach || !broadcast else { return }
        guard rate.isFinite else { return }
        playbackRate = min(max(rate, 0.25), 4)
        if broadcast { emitSnapshot() }
    }

    func setViewMode(_ mode: ReplayViewMode, broadcast: Bool = true) {
        guard allowsPlaybackViewChange() else { return }
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
        guard allowsPlaybackViewChange() else { return }
        guard selectedScenario.player(id: id) != nil else { return }
        guard triangleLockMode != .place else {
            statusMessage = "End physical placement before changing views."
            return
        }
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
        guard allowsPlaybackViewChange() else { return }
        guard selectedScenario.player(id: id) != nil else { return }
        if entersLocalReview, isCollaborationActive, localRole == .player {
            followsCoach = false
            isLocallyPaused = true
        }
        localPerspectiveID = id
        if selectedScenario.kind == .shapeLab, viewMode == .positional,
           let target = selectedScenario.formationTargets.first(where: { $0.playerID == id }),
           let player = selectedScenario.player(id: id) {
            statusMessage = "Role station: #\(player.shirtNumber) · \(target.label)"
            return
        }
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
        guard allowsPlaybackViewChange() else { return }
        guard localRole == .coach, selectedScenario.player(id: id) != nil else { return }
        guard triangleLockMode != .place else {
            statusMessage = "End physical placement before changing views."
            return
        }
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
        guard allowsMutationOutsideEndpointPreview() else { return }
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
        // A comparison changes both time and presented player origins. Keep
        // them fixed until an unfinished mark has been committed or cancelled.
        guard allowsPlaybackViewChange() else { return }
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
        guard allowsMutationOutsideEndpointPreview() else { return }
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
        guard allowsAnnotationAuthoring() else { return }
        guard allowsMutationOutsideEndpointPreview() else { return }
        guard localRole == .coach else { return }
        guard allowsAnnotationAtCurrentTime() else { return }
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
        guard allowsMutationOutsideEndpointPreview() else { return }
        isDrawing = false
        pendingDrawStart = nil
        selectedTool = .run
        statusMessage = "Drawing cancelled"
    }

    @discardableResult
    func registerPitchTap(_ point: PitchPoint) -> CoachMark? {
        guard allowsAnnotationAuthoring() else { return nil }
        guard allowsMutationOutsideEndpointPreview() else { return nil }
        guard isDrawing, localRole == .coach else { return nil }
        guard allowsAnnotationAtCurrentTime() else { return nil }
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
        case .arc: label = "Curved run"
        case .danger: label = "Pressure arrives"
        case .space: label = "Useful space"
        case .playerLabel: return nil
        }

        let anchors = automaticTrackAnchors(
            for: selectedTool,
            start: start,
            end: point,
            at: playhead
        )
        let mark = CoachMark(
            kind: selectedTool,
            start: start,
            end: point,
            curve: selectedTool == .arc ? .initial(start: start, end: point) : nil,
            label: label,
            revealTime: playhead,
            hideTime: defaultCoachMarkHideTime,
            startTrackAnchor: anchors.start,
            endTrackAnchor: anchors.end
        )
        guard isValidSharedMark(mark, for: selectedScenario) else {
            statusMessage = "Keep the annotation on the pitch"
            return nil
        }
        marks.append(mark)
        pendingDrawStart = nil
        isDrawing = false
        statusMessage = "\(selectedTool.title) annotation added"
        emitSnapshot()
        return mark
    }

    /// Creates a complete player-attached annotation from one player tap. The
    /// target pose and reveal time are sampled atomically from the current
    /// playhead, so no second pitch tap or draft geometry is needed.
    @discardableResult
    func labelPlayer(_ playerID: String) -> CoachMark? {
        guard allowsAnnotationAuthoring() else { return nil }
        guard allowsMutationOutsideEndpointPreview() else { return nil }
        guard localRole == .coach else { return nil }
        guard marks.count < Self.maximumSharedCoachMarks else {
            statusMessage = "Annotation limit reached. Remove one before labelling."
            return nil
        }
        guard allowsAnnotationAtCurrentTime(),
              let player = selectedScenario.player(id: playerID) else {
            statusMessage = "Player label unavailable"
            return nil
        }

        isPlaying = false
        selectedTool = .playerLabel
        let position = presentedPlayerPose(for: player, at: playhead).position
        let mark = CoachMark(
            kind: .playerLabel,
            start: position,
            end: position,
            label: "#\(player.shirtNumber) \(player.displayName) · \(player.positionCode)",
            revealTime: playhead,
            hideTime: defaultCoachMarkHideTime,
            playerID: player.id
        )
        guard isValidSharedMark(mark, for: selectedScenario) else {
            statusMessage = "Player label unavailable"
            return nil
        }
        marks.append(mark)
        pendingDrawStart = nil
        isDrawing = false
        statusMessage = "Label added for #\(player.shirtNumber) \(player.displayName)"
        emitSnapshot()
        return mark
    }

    func addPresetMark() {
        guard allowsAnnotationAuthoring() else { return }
        guard allowsMutationOutsideEndpointPreview() else { return }
        guard localRole == .coach else { return }
        guard allowsAnnotationAtCurrentTime() else { return }
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
        let sampledFocus = activePerspective.map {
            presentedPlayerPose(for: $0, at: playhead).position
        } ?? .zero
        let focus = Self.clampedPitchPoint(sampledFocus)
        // Point back into the field near a boundary. Clamping an outward
        // arrow at a corner used to collapse its two endpoints into one.
        let destination = PitchPoint(
            x: focus.x + (focus.x + 7 <= Self.pitchHalfWidth ? 7 : -7),
            z: focus.z + (focus.z + 10 <= Self.pitchHalfLength ? 10 : -10)
        )
        let activePlayerAnchor = activePerspective.map {
            CoachMarkTrackAnchor(
                playerID: $0.id,
                offset: Self.authoredTrackOffset(from: sampledFocus, to: focus)
            )
        }
        let mark = CoachMark(
            kind: selectedTool,
            start: focus,
            end: destination,
            curve: selectedTool == .arc ? .initial(start: focus, end: destination) : nil,
            label: selectedTool == .pass ? "Open channel" : "Next movement",
            revealTime: playhead,
            hideTime: defaultCoachMarkHideTime,
            startTrackAnchor: selectedTool == .space ? nil : activePlayerAnchor,
            endTrackAnchor: (selectedTool == .run || selectedTool == .arc)
                ? activePlayerAnchor.map {
                    CoachMarkTrackAnchor(
                        playerID: $0.playerID,
                        offset: Self.authoredTrackOffset(from: sampledFocus, to: destination)
                    )
                }
                : nil
        )
        guard CoachMarkGeometryPolicy.accepts(kind: mark.kind, start: mark.start, end: mark.end),
              isValidSharedMark(mark, for: selectedScenario) else {
            statusMessage = "Choose a player inside the pitch"
            return
        }
        marks.append(mark)
        statusMessage = "Coach annotation added"
        emitSnapshot()
    }

    private func allowsAnnotationAuthoring() -> Bool {
        guard triangleLockMode != .place else {
            statusMessage = "End the physical drill before editing annotations"
            return false
        }
        return true
    }

    private func allowsAnnotationAtCurrentTime() -> Bool {
        let valid = CoachMarkTimingPolicy.windowFits(
            revealTime: playhead, displayDuration: nil, replayDuration: selectedScenario.duration
        )
        if !valid { statusMessage = "Choose a time inside this replay" }
        return valid
    }

    private var defaultCoachMarkHideTime: TimeInterval? {
        CoachMarkTimingPolicy.defaultHideTime(revealTime: playhead, replayDuration: selectedScenario.duration)
    }

    /// Compatibility entry point: all Undo routes use the same edit history.
    func undoMark() {
        _ = undoAnnotationEdit()
    }

    var hasAnnotationEditHistory: Bool { annotationEditHistory.canUndo || annotationEditHistory.canRedo }
    var annotationUndoTitle: String { annotationEditHistory.undoTitle }
    var annotationRedoTitle: String { annotationEditHistory.redoTitle }
    var canUndoAnnotationEdit: Bool {
        triangleLockMode != .place && localRole == .coach && !isCollaborationActive
            && canChangePlaybackView && annotationEditHistory.canUndo
    }
    var canRedoAnnotationEdit: Bool {
        triangleLockMode != .place && localRole == .coach && !isCollaborationActive
            && canChangePlaybackView && annotationEditHistory.canRedo
    }

    @discardableResult
    func undoAnnotationEdit() -> Bool {
        guard allowsAnnotationAuthoring() else { return false }
        guard allowsPlaybackViewChange(), localRole == .coach, !isCollaborationActive else { return false }
        let action = annotationEditHistory.undoTitle
        guard let restored = annotationEditHistory.undo(current: marks) else {
            statusMessage = "Nothing to undo"
            return false
        }
        marks = restored
        isPlaying = false
        statusMessage = "\(action) complete"
        emitSnapshot()
        return true
    }

    @discardableResult
    func redoAnnotationEdit() -> Bool {
        guard allowsAnnotationAuthoring() else { return false }
        guard allowsPlaybackViewChange(), localRole == .coach, !isCollaborationActive else { return false }
        let action = annotationEditHistory.redoTitle
        guard let restored = annotationEditHistory.redo(current: marks) else {
            statusMessage = "Nothing to redo"
            return false
        }
        marks = restored
        isPlaying = false
        statusMessage = "\(action) complete"
        emitSnapshot()
        return true
    }

    /// Removes one coach-created annotation while preserving the scenario's
    /// authored teaching overlays. This supports mark-specific timeline menus.
    @discardableResult
    func removeCoachMark(id: UUID) -> Bool {
        guard allowsAnnotationAuthoring() else { return false }
        guard allowsMutationOutsideEndpointPreview() else { return false }
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
        removePendingCoachMarkEndpointPreview(for: id)
        marks.remove(at: index)
        statusMessage = "Annotation removed"
        emitSnapshot()
        return true
    }

    /// Commit In/Out together: one undo step, no transient invalid window.
    @discardableResult
    func setCoachMarkWindow(id: UUID, start: TimeInterval, end: TimeInterval?) -> Bool {
        guard allowsAnnotationAuthoring(), allowsMutationOutsideEndpointPreview(),
              localRole == .coach, !hasActiveTimelineScrub, !isDrawing,
              !selectedScenario.coachMarks.contains(where: { $0.id == id }),
              let index = marks.firstIndex(where: { $0.id == id }),
              CoachMarkTimingPolicy.windowFits(revealTime: start, displayDuration: end.map { $0 - start },
                  replayDuration: selectedScenario.duration),
              end.map({ $0 - start >= 0.5 }) ?? true else { return false }
        let mark = marks[index]
        let replacement = CoachMark(id: mark.id, kind: mark.kind, start: mark.start, end: mark.end,
            startElevation: mark.startElevation, endElevation: mark.endElevation, curve: mark.curve,
            label: mark.label, revealTime: start, hideTime: end, author: mark.author,
            playerID: mark.playerID, startTrackAnchor: mark.startTrackAnchor,
            endTrackAnchor: mark.endTrackAnchor, keyframes: mark.keyframes)
        guard replacement != mark, isValidSharedMark(replacement, for: selectedScenario) else { return false }
        marks[index] = replacement
        isPlaying = false
        statusMessage = "Annotation In / Out updated"
        emitSnapshot()
        return true
    }

    @discardableResult
    func captureCoachMarkKeyframe(id: UUID) -> Bool {
        guard allowsAnnotationAuthoring(), allowsMutationOutsideEndpointPreview(), canChangePlaybackView,
              localRole == .coach, !selectedScenario.coachMarks.contains(where: { $0.id == id }),
              let index = marks.firstIndex(where: { $0.id == id }),
              marks[index].kind != .playerLabel, !marks[index].followsPlayerTracks else { return false }
        let replacement = marks[index].sampled(at: playhead).recordingPose(at: playhead)
        guard replacement != marks[index], isValidSharedMark(replacement, for: selectedScenario) else { return false }
        marks[index] = replacement
        isPlaying = false
        statusMessage = "Pose saved — seek, then adjust to add another keyframe"
        emitSnapshot()
        return true
    }

    @discardableResult
    func removeCoachMarkKeyframe(id: UUID, at time: TimeInterval) -> Bool {
        guard allowsAnnotationAuthoring(), allowsMutationOutsideEndpointPreview(), canChangePlaybackView,
              localRole == .coach, !selectedScenario.coachMarks.contains(where: { $0.id == id }),
              let index = marks.firstIndex(where: { $0.id == id }),
              let frames = marks[index].keyframes,
              let frameIndex = frames.firstIndex(where: { abs($0.time - time) < 0.000_001 }) else { return false }
        var replacement = marks[index].sampled(at: playhead)
        var remaining = frames; remaining.remove(at: frameIndex)
        replacement.keyframes = remaining.isEmpty ? nil : remaining
        marks[index] = replacement
        isPlaying = false
        statusMessage = "Keyframe removed"
        emitSnapshot()
        return true
    }

    /// Move a saved pose in time, not in space. The edit is atomic and undoable.
    @discardableResult
    func retimeCoachMarkKeyframe(id: UUID, from time: TimeInterval, to destination: TimeInterval) -> Bool {
        guard allowsAnnotationAuthoring(), allowsMutationOutsideEndpointPreview(), canChangePlaybackView,
              localRole == .coach, !selectedScenario.coachMarks.contains(where: { $0.id == id }),
              let index = marks.firstIndex(where: { $0.id == id }) else { return false }
        var replacement = marks[index]
        guard replacement.canRetimeKeyframe(from: time, to: destination, duration: selectedScenario.duration),
              var frames = replacement.keyframes,
              let frameIndex = frames.firstIndex(where: { abs($0.time - time) < CoachMark.keyframeTimeTolerance })
        else {
            statusMessage = "Choose an unoccupied key time inside the replay"
            return false
        }
        frames[frameIndex].time = destination
        replacement.keyframes = frames.sorted { $0.time < $1.time }
        guard isValidSharedMark(replacement, for: selectedScenario) else { return false }
        marks[index] = replacement
        isPlaying = false
        statusMessage = "Position key moved"
        emitSnapshot()
        return true
    }

    /// Moves one coach-created annotation to a new match instant without
    /// changing its geometry or authored display duration. Fixture overlays
    /// remain immutable so a local edit cannot erase the teaching baseline.
    @discardableResult
    func retimeCoachMark(id: UUID, to revealTime: TimeInterval) -> Bool {
        guard allowsAnnotationAuthoring() else { return false }
        guard allowsMutationOutsideEndpointPreview() else { return false }
        guard !isDrawing else { return false }
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
        guard abs(revealTime - mark.revealTime) >= CoachMark.keyframeTimeTolerance,
              mark.canShiftKeyframes(by: revealTime - mark.revealTime, duration: selectedScenario.duration)
        else { return false }
        guard CoachMarkTimingPolicy.windowFits(
            revealTime: revealTime, displayDuration: mark.hideTime.map { $0 - mark.revealTime },
            replayDuration: selectedScenario.duration
        ) else {
            statusMessage = "That annotation window does not fit the replay"
            return false
        }
        let shiftedHideTime = mark.hideTime.map {
            min(revealTime + ($0 - mark.revealTime), selectedScenario.duration)
        }
        var replacement = CoachMark(
            id: mark.id,
            kind: mark.kind,
            start: mark.start,
            end: mark.end,
            startElevation: mark.startElevation,
            endElevation: mark.endElevation,
            curve: mark.curve,
            label: mark.label,
            revealTime: revealTime,
            hideTime: shiftedHideTime,
            author: mark.author,
            playerID: mark.playerID,
            startTrackAnchor: mark.startTrackAnchor,
            endTrackAnchor: mark.endTrackAnchor,
            keyframes: mark.keyframes
        )
        replacement.keyframes = mark.keyframes?.map {
            var frame = $0; frame.time += revealTime - mark.revealTime; return frame
        }
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
        guard allowsAnnotationAuthoring() else { return false }
        guard allowsMutationOutsideEndpointPreview() else { return false }
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
        guard CoachMarkTimingPolicy.windowFits(
            revealTime: mark.revealTime, displayDuration: duration, replayDuration: selectedScenario.duration
        ) else {
            statusMessage = "That annotation window does not fit the replay"
            return false
        }
        let replacement = CoachMark(
            id: mark.id,
            kind: mark.kind,
            start: mark.start,
            end: mark.end,
            startElevation: mark.startElevation,
            endElevation: mark.endElevation,
            curve: mark.curve,
            label: mark.label,
            revealTime: mark.revealTime,
            hideTime: duration.map { min(mark.revealTime + $0, selectedScenario.duration) },
            author: mark.author,
            playerID: mark.playerID,
            startTrackAnchor: mark.startTrackAnchor,
            endTrackAnchor: mark.endTrackAnchor,
            keyframes: mark.keyframes
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
        guard allowsAnnotationAuthoring() else { return false }
        guard allowsMutationOutsideEndpointPreview() else { return false }
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
            startElevation: mark.startElevation,
            endElevation: mark.endElevation,
            curve: mark.curve,
            label: normalizedLabel,
            revealTime: mark.revealTime,
            hideTime: mark.hideTime,
            author: mark.author,
            playerID: mark.playerID,
            startTrackAnchor: mark.startTrackAnchor,
            endTrackAnchor: mark.endTrackAnchor,
            keyframes: mark.keyframes
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

    /// Links both endpoints of a coach-created mark to one player's telemetry,
    /// or freezes the currently resolved geometry back onto the pitch when
    /// `playerID` is nil. Offsets are sampled at the current replay instant, so
    /// toggling tracking never makes an annotation visibly jump.
    @discardableResult
    func setCoachMarkTracking(id: UUID, playerID: String?) -> Bool {
        guard allowsAnnotationAuthoring() else { return false }
        guard !hasActiveTimelineScrub else {
            statusMessage = "Finish or cancel the timeline scrub first"
            return false
        }
        if hasActiveCoachMarkEndpointPreview {
            statusMessage = "Finish or cancel the joystick adjustment first"
            return false
        }
        guard pendingCoachMarkGeometryBaselines.isEmpty else {
            statusMessage = "Finish the current annotation move first"
            return false
        }
        guard localRole == .coach else { return false }
        let authoredIDs = Set(selectedScenario.coachMarks.map(\.id))
        guard !authoredIDs.contains(id),
              let index = marks.firstIndex(where: { $0.id == id }),
              marks[index].kind.requiresTwoPitchPoints else {
            statusMessage = authoredIDs.contains(id)
                ? "Authored match overlay kept"
                : "That annotation cannot track a player"
            return false
        }
        if let playerID, selectedScenario.player(id: playerID) == nil {
            statusMessage = "Choose a player in this replay"
            return false
        }

        let mark = marks[index]
        let resolved = presentedCoachMarkGeometry(mark, at: playhead)
        guard !mark.hasKeyframes else {
            statusMessage = "Remove position keyframes before enabling player tracking"
            return false
        }
        let playerPosition = playerID.flatMap {
            selectedScenario.player(id: $0).map {
                presentedPlayerPose(for: $0, at: playhead).position
            }
        }
        let startTrackAnchor = playerID.flatMap { playerID in
            playerPosition.map {
                CoachMarkTrackAnchor(
                    playerID: playerID,
                    offset: Self.authoredTrackOffset(from: $0, to: resolved.start)
                )
            }
        }
        let endTrackAnchor = playerID.flatMap { playerID in
            playerPosition.map {
                CoachMarkTrackAnchor(
                    playerID: playerID,
                    offset: Self.authoredTrackOffset(from: $0, to: resolved.end)
                )
            }
        }
        let replacement = CoachMark(
            id: mark.id,
            kind: mark.kind,
            start: resolved.start,
            end: resolved.end,
            startElevation: mark.startElevation,
            endElevation: mark.endElevation,
            curve: mark.curve,
            label: mark.label,
            revealTime: mark.revealTime,
            hideTime: mark.hideTime,
            author: mark.author,
            playerID: mark.playerID,
            startTrackAnchor: startTrackAnchor,
            endTrackAnchor: endTrackAnchor
        )
        guard isValidSharedMark(replacement, for: selectedScenario) else {
            statusMessage = "Player tracking unavailable"
            return false
        }

        marks[index] = replacement
        isPlaying = false
        if let playerID,
           let player = selectedScenario.player(id: playerID) {
            statusMessage = "Annotation follows #\(player.shirtNumber)"
        } else {
            statusMessage = "Annotation fixed to the pitch"
        }
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
        curve: CoachMarkCurve? = nil,
        broadcast: Bool = true
    ) -> Bool {
        guard allowsAnnotationAuthoring() else { return false }
        guard !hasActiveTimelineScrub else {
            statusMessage = "Finish or cancel the timeline scrub first"
            return false
        }
        // A direct handle drag must be able to update and commit its own
        // baseline, while every other mutation—including a joystick gesture or
        // a second mark—stays serialized behind it.
        guard !hasActiveCoachMarkEndpointPreview else {
            statusMessage = "Finish or cancel the joystick adjustment first"
            return false
        }
        guard pendingCoachMarkCurveGestures[id] == nil || curve != nil else {
            statusMessage = "Finish the curve adjustment first"
            return false
        }
        guard pendingCoachMarkGeometryBaselines.isEmpty
                || pendingCoachMarkGeometryBaselines[id] != nil else {
            statusMessage = "Finish or cancel the annotation adjustment first"
            return false
        }
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
        let replacement = markReplacingGeometry(
            mark,
            start: start,
            end: end,
            curve: curve,
            resolvingTrackOffsetsAt: playhead
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
                keyframes: mark.keyframes,
                start: mark.start,
                end: mark.end,
                startElevation: mark.startElevation,
                endElevation: mark.endElevation,
                curve: mark.curve,
                startTrackAnchor: mark.startTrackAnchor,
                endTrackAnchor: mark.endTrackAnchor
            )
        }
        marks[index] = replacement
        if beginsPreviewTransaction {
            // Geometry previews are intentionally masked by `makeSnapshot`.
            // Publishing here therefore synchronizes only the pause and the
            // committed baseline, preventing the coach from freezing locally
            // while followers continue through the moment being annotated.
            isPlaying = false
            if isCollaborationActive { emitSnapshot(allowingGeometryPreview: true) }
        } else if broadcast {
            if curve != nil { isPlaying = false }
            statusMessage = "Annotation position updated"
            // The final sample may equal the preview already on screen. The
            // baseline mask changed even when marks.didSet observes no change.
            scheduleReviewAutosave()
            emitSnapshot()
        }
        return true
    }

    /// Curve dragging uses the same masked save/Undo baseline as endpoint
    /// editing, but a distinct gesture token prevents stale or competing pads
    /// from committing another input's preview.
    func isCoachMarkCurvePreviewOwner(id: UUID, gestureID: UUID) -> Bool {
        pendingCoachMarkCurveGestures[id] == gestureID && pendingCoachMarkGeometryBaselines[id] != nil
    }

    @discardableResult
    func previewCoachMarkCurve(id: UUID, gestureID: UUID, curve: CoachMarkCurve) -> Bool {
        guard !finishedCoachMarkCurveGestures.contains(gestureID),
              !isDrawing, curve.isValid,
              let mark = marks.first(where: { $0.id == id }), mark.kind == .arc else { return false }
        let owner = pendingCoachMarkCurveGestures[id]
        guard owner == gestureID || (owner == nil && !hasActiveCoachMarkGeometryPreview) else { return false }
        if owner != nil && pendingCoachMarkGeometryBaselines[id] == nil { return false }
        pendingCoachMarkCurveGestures[id] = gestureID
        let resolved = presentedCoachMarkGeometry(mark, at: playhead)
        let accepted = updateCoachMarkGeometry(id: id, start: resolved.start, end: resolved.end,
                                               curve: curve, broadcast: false)
        if !accepted && owner == nil { pendingCoachMarkCurveGestures.removeValue(forKey: id) }
        return accepted
    }

    @discardableResult
    func commitCoachMarkCurvePreview(id: UUID, gestureID: UUID) -> Bool {
        guard pendingCoachMarkCurveGestures[id] == gestureID,
              pendingCoachMarkGeometryBaselines[id] != nil,
              let mark = marks.first(where: { $0.id == id }), mark.kind == .arc else { return false }
        let resolved = presentedCoachMarkGeometry(mark, at: playhead)
        let accepted = updateCoachMarkGeometry(id: id, start: resolved.start, end: resolved.end,
                                               curve: mark.sampled(at: playhead).resolvedCurve, broadcast: true)
        finishCoachMarkCurveGesture(id: id, gestureID: gestureID)
        return accepted
    }

    @discardableResult
    func cancelCoachMarkCurvePreview(id: UUID, gestureID: UUID) -> Bool {
        guard pendingCoachMarkCurveGestures[id] == gestureID else { return false }
        let result = cancelCoachMarkGeometryPreview(id: id)
        finishCoachMarkCurveGesture(id: id, gestureID: gestureID)
        return result
    }

    @discardableResult
    func nudgeCoachMarkCurve(id: UUID, bendDelta: Float, liftDelta: Float) -> Bool {
        guard allowsMutationOutsideEndpointPreview(), !isDrawing,
              bendDelta.isFinite, liftDelta.isFinite,
              let mark = marks.first(where: { $0.id == id }), mark.kind == .arc else { return false }
        let curve = CoachMarkCurve(bend: mark.sampled(at: playhead).resolvedCurve.bend + bendDelta,
                                   lift: mark.sampled(at: playhead).resolvedCurve.lift + liftDelta,
                                   rollDegrees: mark.sampled(at: playhead).resolvedCurve.rollDegrees).clamped()
        guard curve != mark.sampled(at: playhead).resolvedCurve else { return false }
        let resolved = presentedCoachMarkGeometry(mark, at: playhead)
        return updateCoachMarkGeometry(id: id, start: resolved.start, end: resolved.end, curve: curve)
    }

    private func finishCoachMarkCurveGesture(id: UUID, gestureID: UUID) {
        guard pendingCoachMarkCurveGestures[id] == gestureID else { return }
        pendingCoachMarkCurveGestures.removeValue(forKey: id)
        finishedCoachMarkCurveGestures.append(gestureID)
        if finishedCoachMarkCurveGestures.count > 128 { finishedCoachMarkCurveGestures.removeFirst() }
    }

    /// Ends only an existing direct handle transaction. A delayed gesture end
    /// after cancellation or drill cleanup must not create a fresh edit.
    @discardableResult
    func commitCoachMarkGeometryPreview(
        id: UUID,
        start: PitchPoint,
        end: PitchPoint
    ) -> Bool {
        guard pendingCoachMarkGeometryBaselines[id] != nil,
              pendingCoachMarkEndpointPreviews[id] == nil else { return false }
        return updateCoachMarkGeometry(id: id, start: start, end: end, broadcast: true)
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
        guard allowsAnnotationAuthoring() else { return false }
        guard allowsMutationOutsideEndpointPreview() else { return false }
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
        let mark = marks[index]
        let resolved = presentedCoachMarkGeometry(mark, at: playhead)
        var start = resolved.start
        var end = resolved.end
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

        guard start != resolved.start || end != resolved.end else {
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

        let replacement = markReplacingGeometry(
            mark,
            start: start,
            end: end,
            resolvingTrackOffsetsAt: playhead
        )
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

    /// Raises or lowers an endpoint—or the complete stroke—in pitch metres.
    /// This is an atomic shared edit rather than a render-only transform: a
    /// late joiner, a seek, and every SharePlay participant reconstruct the
    /// same Y geometry from the serialized mark.
    @discardableResult
    func nudgeCoachMarkElevation(
        id: UUID,
        target: CoachMarkElevationTarget,
        by delta: Float
    ) -> Bool {
        guard allowsAnnotationAuthoring() else { return false }
        guard allowsMutationOutsideEndpointPreview() else { return false }
        guard localRole == .coach else { return false }
        guard delta.isFinite, delta != 0 else {
            statusMessage = "Choose a valid height adjustment"
            return false
        }

        let authoredIDs = Set(selectedScenario.coachMarks.map(\.id))
        guard !authoredIDs.contains(id),
              let index = marks.firstIndex(where: { $0.id == id }),
              marks[index].kind.requiresTwoPitchPoints,
              marks[index].playerID == nil else {
            statusMessage = authoredIDs.contains(id)
                ? "Authored match overlay kept"
                : "That annotation cannot be raised"
            return false
        }
        let mark = marks[index]
        let pose = mark.sampled(at: playhead)
        var start = pose.resolvedStartElevation
        var end = pose.resolvedEndElevation
        switch target {
        case .start:
            start = CoachMarkGeometryPolicy.clampedElevation(start + delta)
        case .end:
            end = CoachMarkGeometryPolicy.clampedElevation(end + delta)
        case .both:
            start = CoachMarkGeometryPolicy.clampedElevation(start + delta)
            end = CoachMarkGeometryPolicy.clampedElevation(end + delta)
        }
        guard start != pose.resolvedStartElevation
                || end != pose.resolvedEndElevation else {
            statusMessage = "Annotation is already at that height limit"
            return false
        }

        // Ground level remains nil on newly edited marks. This keeps the wire
        // payload compact and semantically identical to legacy annotations.
        var replacement = CoachMark(
            id: mark.id,
            kind: mark.kind,
            start: pose.start,
            end: pose.end,
            startElevation: start > 0.001 ? start : nil,
            endElevation: end > 0.001 ? end : nil,
            curve: pose.curve,
            label: mark.label,
            revealTime: mark.revealTime,
            hideTime: mark.hideTime,
            author: mark.author,
            playerID: mark.playerID,
            startTrackAnchor: mark.startTrackAnchor,
            endTrackAnchor: mark.endTrackAnchor,
            keyframes: mark.keyframes
        )
        if mark.hasKeyframes { replacement = replacement.recordingPose(at: playhead) }
        guard isValidSharedMark(replacement, for: selectedScenario) else {
            statusMessage = "Keep the annotation within four metres of the pitch"
            return false
        }

        marks[index] = replacement
        isPlaying = false
        statusMessage = switch target {
        case .start: "Annotation start height adjusted"
        case .end: "Annotation end height adjusted"
        case .both: "Annotation stroke height adjusted"
        }
        emitSnapshot()
        return true
    }

    /// Previews one joystick-controlled endpoint using a cumulative movement
    /// from the gesture's first accepted sample. The request is never applied
    /// incrementally: every update is recomputed from the immutable baseline,
    /// then clamped independently on both pitch axes. This means a four-notch
    /// diagonal request can truthfully apply (for example) 0.25 m horizontally
    /// and 0.50 m vertically without corrupting the gesture's reverse path.
    ///
    /// Preview geometry is masked by `makeSnapshot()`. In a shared room the
    /// first accepted sample publishes exactly one baseline pause, so followers
    /// freeze at the same replay instant instead of advancing and rewinding when
    /// the final geometry arrives.
    @discardableResult
    func previewCoachMarkEndpoint(
        id: UUID,
        endpoint: CoachMarkEndpoint,
        gestureID: UUID,
        cumulativeDelta: PitchPoint
    ) -> CoachMarkEndpointPreviewResult? {
        guard allowsAnnotationAuthoring() else { return nil }
        guard localRole == .coach else { return nil }
        guard !hasActiveTimelineScrub else {
            statusMessage = "Finish or cancel the timeline scrub first"
            return nil
        }
        guard !interruptedCoachMarkEndpointGestureIDs.contains(gestureID) else {
            statusMessage = "Lift, then start a new joystick adjustment"
            return nil
        }
        guard cumulativeDelta.x.isFinite, cumulativeDelta.z.isFinite else {
            invalidateCoachMarkEndpointPreview(id: id)
            statusMessage = "Choose a valid annotation movement"
            return nil
        }

        let authoredIDs = Set(selectedScenario.coachMarks.map(\.id))
        guard !authoredIDs.contains(id),
              let index = marks.firstIndex(where: { $0.id == id }),
              marks[index].kind.requiresTwoPitchPoints,
              marks[index].playerID == nil else {
            invalidateCoachMarkEndpointPreview(id: id)
            statusMessage = authoredIDs.contains(id)
                ? "Authored match overlay kept"
                : "That annotation cannot be moved"
            return nil
        }

        let existingPreview = pendingCoachMarkEndpointPreviews[id]
        guard existingPreview == nil || (
            existingPreview?.endpoint == endpoint
                && existingPreview?.gestureID == gestureID
        ) else {
            statusMessage = "Finish the current endpoint adjustment first"
            return nil
        }
        if existingPreview == nil {
            // One spatial edit at a time keeps snapshot masking and cancellation
            // deterministic even if two hands address different controls.
            guard pendingCoachMarkGeometryBaselines.isEmpty,
                  pendingCoachMarkEndpointPreviews.isEmpty else {
                statusMessage = "Finish the current annotation move first"
                return nil
            }
        }

        let mark = marks[index]
        let currentResolved = presentedCoachMarkGeometry(mark, at: playhead)
        let baselineStart = existingPreview?.resolvedStart ?? currentResolved.start
        let baselineEnd = existingPreview?.resolvedEnd ?? currentResolved.end
        var start = baselineStart
        var end = baselineEnd
        let baselineEndpoint: PitchPoint
        switch endpoint {
        case .start:
            baselineEndpoint = baselineStart
            let proposed = PitchPoint(
                x: baselineStart.x + cumulativeDelta.x,
                z: baselineStart.z + cumulativeDelta.z
            )
            guard proposed.x.isFinite, proposed.z.isFinite else {
                invalidateCoachMarkEndpointPreview(id: id)
                statusMessage = "Choose a valid annotation movement"
                return nil
            }
            start = Self.clampedPitchPoint(proposed)
        case .end:
            baselineEndpoint = baselineEnd
            let proposed = PitchPoint(
                x: baselineEnd.x + cumulativeDelta.x,
                z: baselineEnd.z + cumulativeDelta.z
            )
            guard proposed.x.isFinite, proposed.z.isFinite else {
                invalidateCoachMarkEndpointPreview(id: id)
                statusMessage = "Choose a valid annotation movement"
                return nil
            }
            end = Self.clampedPitchPoint(proposed)
        }
        let appliedEndpoint = endpoint == .start ? start : end
        let appliedDelta = PitchPoint(
            x: appliedEndpoint.x - baselineEndpoint.x,
            z: appliedEndpoint.z - baselineEndpoint.z
        )

        // An outward request made while already on a boundary is a valid no-op,
        // but it must not pause playback or create a transaction that later
        // converts centring the stick into an inward movement.
        if existingPreview == nil, appliedDelta == .zero {
            return CoachMarkEndpointPreviewResult(
                appliedDelta: .zero,
                hasActiveTransaction: false
            )
        }

        guard CoachMarkGeometryPolicy.accepts(
            kind: mark.kind,
            start: start,
            end: end
        ) else {
            invalidateCoachMarkEndpointPreview(id: id)
            statusMessage = "Keep the annotation large enough to read"
            return nil
        }

        let replacement = markReplacingGeometry(
            mark,
            start: start,
            end: end,
            resolvingTrackOffsetsAt: playhead
        )
        guard isValidSharedMark(replacement, for: selectedScenario) else {
            invalidateCoachMarkEndpointPreview(id: id)
            statusMessage = "Keep the annotation on the pitch"
            return nil
        }

        var preview: CoachMarkEndpointPreview
        if var existingPreview {
            existingPreview.latestSampleIsValid = true
            existingPreview.appliedDelta = appliedDelta
            preview = existingPreview
        } else {
            pendingCoachMarkGeometryBaselines[id] = CoachMarkGeometry(
                keyframes: mark.keyframes,
                start: mark.start,
                end: mark.end,
                startElevation: mark.startElevation,
                endElevation: mark.endElevation,
                curve: mark.curve,
                startTrackAnchor: mark.startTrackAnchor,
                endTrackAnchor: mark.endTrackAnchor
            )
            preview = CoachMarkEndpointPreview(
                gestureID: gestureID,
                endpoint: endpoint,
                resolvedStart: baselineStart,
                resolvedEnd: baselineEnd,
                wasPlaying: isPlaying,
                didPublishPause: isCollaborationActive,
                latestSampleIsValid: true,
                appliedDelta: appliedDelta
            )
            isPlaying = false
        }

        setPendingCoachMarkEndpointPreview(preview, for: id)
        marks[index] = replacement
        statusMessage = endpoint == .start
            ? "Adjusting annotation start"
            : "Adjusting annotation end"
        if existingPreview == nil, preview.didPublishPause {
            // `emitSnapshot()` normally rejects an active endpoint transaction.
            // This one deliberate packet is safe because makeSnapshot restores
            // the committed geometry baseline while publishing the paused clock.
            emitSnapshot(allowingGeometryPreview: true)
        }
        return CoachMarkEndpointPreviewResult(
            appliedDelta: appliedDelta,
            hasActiveTransaction: true
        )
    }

    /// Publishes final joystick geometry as one atomic shared mutation. A
    /// rejected last sample or a gesture returned to its origin rolls back. A
    /// solo preview restores its earlier transport state; a shared preview stays
    /// paused because followers already received the baseline pause packet.
    @discardableResult
    func commitCoachMarkEndpointPreview(id: UUID) -> PitchPoint? {
        guard let gestureID = pendingCoachMarkEndpointPreviews[id]?.gestureID else {
            return nil
        }
        return commitCoachMarkEndpointPreview(id: id, gestureID: gestureID)
    }

    /// Completes the transaction owned by one physical pinch. Supplying the
    /// gesture identity also releases a lifecycle interruption tombstone at the
    /// point the hand lifts, without allowing that same pinch to reopen sooner.
    @discardableResult
    func commitCoachMarkEndpointPreview(
        id: UUID,
        gestureID: UUID
    ) -> PitchPoint? {
        if triangleLockMode == .place {
            // A delayed lift cannot publish geometry hidden by an active drill.
            // Keep rollback usable and preserve the drill's definitive pause.
            _ = cancelCoachMarkEndpointPreview(id: id, gestureID: gestureID)
            isPlaying = false
            _ = allowsAnnotationAuthoring()
            return nil
        }
        defer { interruptedCoachMarkEndpointGestureIDs.remove(gestureID) }
        guard pendingCoachMarkEndpointPreviews[id]?.gestureID == gestureID,
              let preview = removePendingCoachMarkEndpointPreview(for: id) else {
            return nil
        }
        let baseline = pendingCoachMarkGeometryBaselines.removeValue(forKey: id)
        guard let baseline,
              let index = marks.firstIndex(where: { $0.id == id }) else {
            restorePlaybackAfterCancelledEndpointPreview(preview)
            return nil
        }

        guard preview.latestSampleIsValid,
              preview.appliedDelta != .zero else {
            marks[index] = markRestoringGeometry(marks[index], from: baseline)
            restorePlaybackAfterCancelledEndpointPreview(preview)
            statusMessage = "Annotation adjustment cancelled"
            return nil
        }

        let mark = marks[index]
        let resolved = presentedCoachMarkGeometry(mark, at: playhead)
        guard CoachMarkGeometryPolicy.accepts(
            kind: mark.kind,
            start: resolved.start,
            end: resolved.end
        ), isValidSharedMark(mark, for: selectedScenario) else {
            marks[index] = markRestoringGeometry(mark, from: baseline)
            restorePlaybackAfterCancelledEndpointPreview(preview)
            statusMessage = "Annotation adjustment cancelled"
            return nil
        }

        isPlaying = false
        statusMessage = preview.endpoint == .start
            ? "Annotation start adjusted"
            : "Annotation end adjusted"
        // A settled pinch may already have autosaved its masked baseline.
        // Committing unmasks geometry without changing the stored mark value.
        scheduleReviewAutosave()
        emitSnapshot()
        return preview.appliedDelta
    }

    /// Cancels a joystick preview, including SwiftUI disappearance and system
    /// gesture interruption paths. Geometry always returns to its baseline. A
    /// solo preview can also restore transport, while a shared preview remains
    /// on the pause already published to every participant.
    @discardableResult
    func cancelCoachMarkEndpointPreview(id: UUID) -> Bool {
        guard let gestureID = pendingCoachMarkEndpointPreviews[id]?.gestureID else {
            return false
        }
        return cancelCoachMarkEndpointPreview(id: id, gestureID: gestureID)
    }

    /// Cancels an active preview or acknowledges that an already-interrupted
    /// physical pinch has ended. The latter returns `false` because its geometry
    /// was restored by the lifecycle transition, but still releases the token.
    @discardableResult
    func cancelCoachMarkEndpointPreview(
        id: UUID,
        gestureID: UUID
    ) -> Bool {
        defer { interruptedCoachMarkEndpointGestureIDs.remove(gestureID) }
        guard pendingCoachMarkEndpointPreviews[id]?.gestureID == gestureID,
              let preview = removePendingCoachMarkEndpointPreview(for: id) else {
            return false
        }
        let baseline = pendingCoachMarkGeometryBaselines.removeValue(forKey: id)
        guard let baseline,
              let index = marks.firstIndex(where: { $0.id == id }) else {
            restorePlaybackAfterCancelledEndpointPreview(preview)
            return false
        }
        marks[index] = markRestoringGeometry(marks[index], from: baseline)
        restorePlaybackAfterCancelledEndpointPreview(preview)
        statusMessage = "Annotation adjustment cancelled"
        return true
    }

    private func invalidateCoachMarkEndpointPreview(id: UUID) {
        guard var preview = pendingCoachMarkEndpointPreviews[id] else { return }
        preview.latestSampleIsValid = false
        setPendingCoachMarkEndpointPreview(preview, for: id)
    }

    private func restorePlaybackAfterCancelledEndpointPreview(
        _ preview: CoachMarkEndpointPreview
    ) {
        isPlaying = !preview.didPublishPause
            && preview.wasPlaying
            && playhead < selectedScenario.duration
    }

    /// Restores a local handle-drag preview when the system cancels its pinch
    /// sequence. The baseline was never published, so rollback is deliberately
    /// local and emits no collaboration snapshot.
    @discardableResult
    func cancelCoachMarkGeometryPreview(id: UUID) -> Bool {
        if pendingCoachMarkEndpointPreviews[id] != nil {
            return cancelCoachMarkEndpointPreview(id: id)
        }
        guard let baseline = pendingCoachMarkGeometryBaselines.removeValue(forKey: id),
              let index = marks.firstIndex(where: { $0.id == id }) else {
            return false
        }
        marks[index] = markRestoringGeometry(marks[index], from: baseline)
        if let gestureID = pendingCoachMarkCurveGestures[id] {
            finishCoachMarkCurveGesture(id: id, gestureID: gestureID)
        }
        statusMessage = "Annotation move cancelled"
        return true
    }

    private func rollbackCoachMarkGeometryPreview(id: UUID, index: Int) {
        if let gestureID = pendingCoachMarkCurveGestures[id] {
            finishCoachMarkCurveGesture(id: id, gestureID: gestureID)
        }
        removePendingCoachMarkEndpointPreview(for: id)
        guard let baseline = pendingCoachMarkGeometryBaselines.removeValue(forKey: id) else {
            return
        }
        marks[index] = markRestoringGeometry(marks[index], from: baseline)
    }

    /// Clears only the transient first point after an interrupted spatial
    /// stroke. The selected tool stays armed so the coach can pinch-draw again.
    func resetPendingAnnotationPointAfterInterruption() {
        guard allowsMutationOutsideEndpointPreview() else { return }
        guard isDrawing else { return }
        pendingDrawStart = nil
        statusMessage = "Gesture interrupted. Pinch-draw again or tap a start point."
    }

    func clearMarks() {
        guard allowsAnnotationAuthoring() else { return }
        guard allowsMutationOutsideEndpointPreview() else { return }
        guard localRole == .coach else { return }
        let authoredIDs = Set(selectedScenario.coachMarks.map(\.id))
        let previousCount = marks.count
        let removedIDs = Set(marks.lazy.filter { !authoredIDs.contains($0.id) }.map(\.id))
        marks.removeAll { removedIDs.contains($0.id) }
        for id in removedIDs {
            pendingCoachMarkGeometryBaselines.removeValue(forKey: id)
            removePendingCoachMarkEndpointPreview(for: id)
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
        guard allowsMutationOutsideEndpointPreview() else { return false }
        let scenario = selectedScenario
        guard marks.count < Self.maximumSharedCoachMarks,
              !marks.contains(where: { $0.id == mark.id }),
              isValidSharedMark(mark, for: scenario) else { return false }
        marks.append(mark)
        annotationEditHistory.reset(to: marks)
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
        guard allowsMutationOutsideEndpointPreview() else { return }
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
        cancelTimelineScrub()
        if hasActiveCoachMarkGeometryPreview {
            rollbackAllCoachMarkGeometryPreviews(
                interruptingEndpointGesture: hasActiveCoachMarkEndpointPreview
            )
        }
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
        guard allowsMutationOutsideEndpointPreview() else { return }
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

    var trianglePlacementInputBlockReason: String? {
        if hasActiveTimelineScrub { return "Finish or cancel the timeline scrub before placing stations" }
        if hasActiveCoachMarkGeometryPreview { return "Finish or cancel the annotation adjustment before placing stations" }
        if isDrawing { return "Finish or cancel the annotation before placing stations" }
        return nil
    }

    @discardableResult
    func activateTrianglePlacement(anchorID: UUID) -> Bool {
        guard localRole == .coach, selectedScenario.kind == .shapeLab else { return false }
        if let reason = trianglePlacementInputBlockReason {
            statusMessage = reason
            return false
        }
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
        return true
    }

    /// Starts a solo, device-local rehearsal. Its WorldAnchor identifier never
    /// appears in `makeSnapshot()`, even if SharePlay begins later.
    @discardableResult
    func activateLocalTrianglePreview(anchorID: UUID) -> Bool {
        guard localRole == .coach,
              !isCollaborationActive,
              selectedScenario.kind == .shapeLab else { return false }
        if let reason = trianglePlacementInputBlockReason {
            statusMessage = reason
            return false
        }
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
        return true
    }

    func acknowledgeTrianglePlacementLocally(
        participantID: UUID? = nil,
        sharedSession: Bool = false
    ) {
        guard allowsMutationOutsideEndpointPreview() else { return }
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
        guard allowsMutationOutsideEndpointPreview() else { return }
        hasLocallyAcknowledgedTrianglePlacement = false
        if triangleLockMode == .place {
            statusMessage = "Physical station hidden on this headset until you confirm it again."
        }
    }

    func endTrianglePlacement() {
        guard localRole == .coach, triangleLockMode == .place else { return }
        // End drill is an escape, not a competing edit. Restore unpublished
        // checkpoints before applying the final pause and retiring this anchor.
        cancelTimelineScrub()
        rollbackAllCoachMarkGeometryPreviews(interruptingEndpointGesture: true)
        isDrawing = false
        pendingDrawStart = nil
        selectedTool = .run
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
        cancelTimelineScrub()
        if hasActiveCoachMarkGeometryPreview {
            rollbackAllCoachMarkGeometryPreviews(
                interruptingEndpointGesture: hasActiveCoachMarkEndpointPreview
            )
        }
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
        cancelTimelineScrub()
        isCollaborationActive = false
        latestCoachSnapshot = nil
        rollbackAllCoachMarkGeometryPreviews(interruptingEndpointGesture: true)
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
        guard allowsMutationOutsideEndpointPreview() else { return }
        if triangleLockMode == .place {
            endTrianglePlacement()
        }
        selectScenario(id: selectedScenarioID, broadcast: true, resettingReview: true)
    }

    func advance(by delta: TimeInterval) {
        guard !isDrawing, !hasActiveTimelineScrub, !hasActiveCoachMarkGeometryPreview else { return }
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
        // Every transient geometry path restores the committed endpoints. An
        // endpoint joystick also publishes a real pause at its first accepted
        // sample, so the snapshot's transport must reflect `isPlaying` rather
        // than resurrecting its pre-gesture clock.
        let sharedMarks = marks.map { mark in
            guard let baseline = pendingCoachMarkGeometryBaselines[mark.id] else { return mark }
            return markRestoringGeometry(mark, from: baseline)
        }
        let publishedPlayhead = timelineScrubCheckpoint?.playhead ?? playhead
        let publishedIsPlaying = timelineScrubCheckpoint?.isPlaying ?? isPlaying
        return SharedPlaybackSnapshot(
            scenarioID: selectedScenarioID,
            playhead: publishedPlayhead,
            isPlaying: publishedIsPlaying && publishedPlayhead < selectedScenario.duration,
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
        guard allowsMutationOutsideEndpointPreview() else { return false }
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
        let changesScenario = selectedScenarioID != scenario.id
        // Physical placement can replace an incompatible local scenario even
        // during comfort pause. Its clock, marks and view must move together.
        let adoptsPlacementScenario = changesScenario && sanitizedTriangleMode == .place
        selectedTool = .run
        pendingDrawStart = nil
        isDrawing = false
        pendingCoachMarkGeometryBaselines.removeAll(keepingCapacity: true)
        removeAllPendingCoachMarkEndpointPreviews()
        latestCoachSnapshot = sanitizedSnapshot
        participantSeatAssignments = sanitizedSeatAssignments
        if previousAnchorID != sanitizedSharedPitchAnchorID || triangleLockMode != sanitizedTriangleMode {
            hasLocallyAcknowledgedTrianglePlacement = false
        }
        sharedPitchAnchorID = sanitizedSharedPitchAnchorID
        triangleLockMode = sanitizedTriangleMode
        if sanitizedTriangleMode == .place {
            shapeFocusStage = .ideal
            isPlaying = false
            viewMode = .positional
        }
        guard !isLocallyPaused || adoptsPlacementScenario else {
            statusMessage = "Local comfort pause — coach state ready when you resume"
            return true
        }
        if changesScenario {
            retainedScenarioMarks[selectedScenarioID] = makeSnapshot().marks
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
        annotationEditHistory.reset(to: marks)
        showsLaneLens = sanitizedSnapshot.showsLaneLens
        shapeFocusStage = sanitizedSnapshot.shapeFocusStage
        statusMessage = isLocallyPaused
            ? "Local comfort pause — coach state ready when you resume"
            : "Coach state synchronized"
        return true
    }

    /// Local endpoint subtraction can round an exact touchline outward when
    /// the offset is added back to its player. Move only that generated offset
    /// one representable step inward. Stored fallback points and decoded
    /// anchors stay unchanged; the strict import validator gains no tolerance.
    private static func authoredTrackOffset(from origin: PitchPoint, to endpoint: PitchPoint) -> PitchPoint {
        func component(from origin: Float, to endpoint: Float, limit: Float) -> Float {
            let offset = endpoint - origin
            guard origin.isFinite, endpoint.isFinite,
                  abs(origin) <= limit, abs(endpoint) <= limit else { return offset }
            let reconstructed = origin + offset
            let corrected: Float
            if reconstructed > limit {
                corrected = offset.nextDown
            } else if reconstructed < -limit {
                corrected = offset.nextUp
            } else {
                return offset
            }
            let correctedPosition = origin + corrected
            return correctedPosition.isFinite && abs(correctedPosition) <= limit
                ? corrected : offset
        }
        return PitchPoint(
            x: component(from: origin.x, to: endpoint.x, limit: pitchHalfWidth),
            z: component(from: origin.z, to: endpoint.z, limit: pitchHalfLength)
        )
    }

    /// Shared marks become RealityKit entity trees, so bound both geometry and
    /// presentation data before accepting them. Collection-level duplicate ID
    /// rejection happens in `applyRemote` to keep scene dictionary keys unique.
    private func automaticTrackAnchors(
        for kind: CoachMarkKind,
        start: PitchPoint,
        end: PitchPoint,
        at time: TimeInterval
    ) -> (start: CoachMarkTrackAnchor?, end: CoachMarkTrackAnchor?) {
        guard kind.requiresTwoPitchPoints, kind != .space else { return (nil, nil) }

        func nearestAnchor(to point: PitchPoint) -> CoachMarkTrackAnchor? {
            var best: (player: PlayerTrack, distance: Float)?
            for player in selectedScenario.players {
                let position = presentedPlayerPose(for: player, at: time).position
                let distance = ReplayGeometry.distance(position, point)
                guard distance <= Self.coachMarkTrackSnapDistance else { continue }
                if let current = best,
                   distance > current.distance
                    || (distance == current.distance && player.id >= current.player.id) {
                    continue
                }
                best = (player, distance)
            }
            guard let player = best?.player else { return nil }
            let position = presentedPlayerPose(for: player, at: time).position
            return CoachMarkTrackAnchor(
                playerID: player.id,
                offset: Self.authoredTrackOffset(from: position, to: point)
            )
        }

        let startAnchor = nearestAnchor(to: start)
        if (kind == .run || kind == .arc), let startAnchor,
           let player = selectedScenario.player(id: startAnchor.playerID) {
            let position = presentedPlayerPose(for: player, at: time).position
            return (
                startAnchor,
                CoachMarkTrackAnchor(
                    playerID: player.id,
                    offset: Self.authoredTrackOffset(from: position, to: end)
                )
            )
        }
        return (startAnchor, nearestAnchor(to: end))
    }

    private func isValidSharedMark(
        _ mark: CoachMark,
        for scenario: ReplayScenario
    ) -> Bool {
        Self.isValidReviewMark(mark, for: scenario)
    }

    /// Disk and SharePlay inputs share the same geometry and identity gate.
    static func isValidReviewMark(_ mark: CoachMark, for scenario: ReplayScenario) -> Bool {
        let hasFiniteBoundedGeometry = Self.isPointOnPitch(mark.start)
            && Self.isPointOnPitch(mark.end)
        let hasValidElevation = CoachMarkGeometryPolicy.accepts(
            elevation: mark.startElevation
        ) && CoachMarkGeometryPolicy.accepts(elevation: mark.endElevation)
        // A zone is rendered as one horizontal tactical plane and exposes one
        // whole-zone height control. Reject a peer payload that would place its
        // two handles on different planes from that ring.
        let hasCoherentZoneElevation = mark.kind != .space
            || abs(mark.resolvedStartElevation - mark.resolvedEndElevation) <= 0.001
        let anchors = [mark.startTrackAnchor, mark.endTrackAnchor].compactMap { $0 }
        let hasValidTrackAnchors = anchors.allSatisfy { anchor in
            scenario.player(id: anchor.playerID) != nil
                && anchor.offset.x.isFinite
                && anchor.offset.z.isFinite
                && abs(anchor.offset.x) <= Self.pitchHalfWidth * 2
                && abs(anchor.offset.z) <= Self.pitchHalfLength * 2
        }
        let hasValidRevealTime = mark.revealTime.isFinite
            && mark.revealTime >= 0
            && mark.revealTime <= scenario.duration
        let hasFiniteBoundedResolvedGeometry: Bool
        if hasValidRevealTime {
            let resolved = mark.resolvedGeometry(
                in: scenario,
                at: mark.revealTime
            )
            hasFiniteBoundedResolvedGeometry = Self.isPointOnPitch(resolved.start)
                && Self.isPointOnPitch(resolved.end)
                || (hasValidTrackAnchors && Self.hasBoundedAuthoredPresentation(mark, in: scenario))
        } else {
            hasFiniteBoundedResolvedGeometry = false
        }
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
              mark.hasValidKeyframes(duration: scenario.duration),
              hasValidElevation,
              mark.kind == .arc ? (mark.curve?.isValid ?? true) : mark.curve == nil,
              hasCoherentZoneElevation,
              hasValidTrackAnchors,
              hasFiniteBoundedResolvedGeometry,
              hasValidRevealTime,
              hasValidWindow,
              hasValidText else { return false }
        guard mark.kind == .playerLabel else {
            return mark.playerID == nil
        }
        guard mark.startTrackAnchor == nil,
              mark.endTrackAnchor == nil,
              mark.startElevation == nil,
              mark.endElevation == nil else { return false }
        guard let playerID = mark.playerID else { return false }
        return scenario.player(id: playerID) != nil
    }

    /// Older marks remain valid against their original telemetry. A newly
    /// drawn mark can instead use the bundled impact or ideal-shape origin;
    /// its displayed endpoint may be on the touchline while the upright track
    /// would move that same offset beyond it. Admit only those exact authored
    /// alternatives, never a pose supplied by a file, caller or current UI.
    /// The surrounding validator still checks both stored fallback endpoints,
    /// finite values, identities and absolute offset limits independently.
    private static func hasBoundedAuthoredPresentation(
        _ mark: CoachMark,
        in scenario: ReplayScenario
    ) -> Bool {
        guard mark.followsPlayerTracks else { return false }

        func isBounded(in presentation: ReplayPlayerPresentation) -> Bool {
            let poses = Dictionary(uniqueKeysWithValues: mark.anchoredPlayerIDs.compactMap { id in
                scenario.player(id: id).map {
                    (id, presentation.pose(for: $0, at: mark.revealTime))
                }
            })
            let resolved = mark.resolvedGeometry(
                in: scenario, at: mark.revealTime, presentedPlayerPoses: poses
            )
            return Self.isPointOnPitch(resolved.start) && Self.isPointOnPitch(resolved.end)
        }

        if let impact = PlayerRagdollCue.authoredDemo(for: scenario),
           impact.isActive(at: mark.revealTime),
           isBounded(in: ReplayPlayerPresentation(scenario: scenario, viewMode: .tacticalTable)) {
            return true
        }
        if scenario.kind == .shapeLab,
           let authoredShape = DemoScenarios.scenario(for: .shapeLab),
           scenario.id == authoredShape.id,
           scenario.formationTargets == authoredShape.formationTargets {
            return isBounded(in: ReplayPlayerPresentation(
                scenario: scenario, viewMode: .positional, showsIdealBranch: true
            ))
        }
        return false
    }

    private func markReplacingGeometry(
        _ mark: CoachMark,
        start: PitchPoint,
        end: PitchPoint,
        curve: CoachMarkCurve? = nil,
        resolvingTrackOffsetsAt time: TimeInterval? = nil
    ) -> CoachMark {
        func adjustedAnchor(
            _ anchor: CoachMarkTrackAnchor?,
            endpoint: PitchPoint
        ) -> CoachMarkTrackAnchor? {
            guard let anchor,
                  let time,
                  let player = selectedScenario.player(id: anchor.playerID) else {
                return anchor
            }
            let playerPosition = presentedPlayerPose(for: player, at: time).position
            return CoachMarkTrackAnchor(
                playerID: anchor.playerID,
                offset: Self.authoredTrackOffset(from: playerPosition, to: endpoint)
            )
        }

        let posed = mark.sampled(at: time ?? playhead)
        let replacement = CoachMark(
            id: mark.id,
            kind: mark.kind,
            start: start,
            end: end,
            startElevation: posed.startElevation,
            endElevation: posed.endElevation,
            curve: curve ?? posed.curve,
            label: mark.label,
            revealTime: mark.revealTime,
            hideTime: mark.hideTime,
            author: mark.author,
            playerID: mark.playerID,
            startTrackAnchor: adjustedAnchor(mark.startTrackAnchor, endpoint: start),
            endTrackAnchor: adjustedAnchor(mark.endTrackAnchor, endpoint: end),
            keyframes: mark.keyframes
        )
        return mark.hasKeyframes ? replacement.recordingPose(at: time ?? playhead) : replacement
    }

    private func markRestoringGeometry(
        _ mark: CoachMark,
        from baseline: CoachMarkGeometry
    ) -> CoachMark {
        CoachMark(
            id: mark.id,
            kind: mark.kind,
            start: baseline.start,
            end: baseline.end,
            startElevation: baseline.startElevation,
            endElevation: baseline.endElevation,
            curve: baseline.curve,
            label: mark.label,
            revealTime: mark.revealTime,
            hideTime: mark.hideTime,
            author: mark.author,
            playerID: mark.playerID,
            startTrackAnchor: baseline.startTrackAnchor,
            endTrackAnchor: baseline.endTrackAnchor,
            keyframes: baseline.keyframes
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

    private func rollbackAllCoachMarkGeometryPreviews(
        interruptingEndpointGesture: Bool = false
    ) {
        for (id, gestureID) in Array(pendingCoachMarkCurveGestures) {
            finishCoachMarkCurveGesture(id: id, gestureID: gestureID)
        }
        guard !pendingCoachMarkGeometryBaselines.isEmpty ||
                !pendingCoachMarkEndpointPreviews.isEmpty else { return }
        if interruptingEndpointGesture {
            interruptedCoachMarkEndpointGestureIDs.formUnion(
                pendingCoachMarkEndpointPreviews.values.map(\.gestureID)
            )
        }
        let resumesPlayback = pendingCoachMarkEndpointPreviews.values.contains {
            !$0.didPublishPause && $0.wasPlaying
        }
        for index in marks.indices {
            let mark = marks[index]
            guard let baseline = pendingCoachMarkGeometryBaselines[mark.id] else { continue }
            marks[index] = markRestoringGeometry(mark, from: baseline)
        }
        pendingCoachMarkGeometryBaselines.removeAll(keepingCapacity: true)
        removeAllPendingCoachMarkEndpointPreviews()
        if resumesPlayback {
            isPlaying = playhead < selectedScenario.duration
        }
    }

    func setCollaborationActive(_ isActive: Bool) {
        guard isCollaborationActive != isActive else { return }
        cancelTimelineScrub()
        // Neither a joystick transaction nor a direct 3D handle drag may cross
        // a room-authority boundary. In particular, a drag begun while SharePlay
        // is waiting must not become committable after the session joins.
        rollbackAllCoachMarkGeometryPreviews(interruptingEndpointGesture: true)
        if isActive {
            discardLocalTrianglePreviewForSessionTransition()
        }
        isCollaborationActive = isActive
        guard !isActive else { return }
        rollbackAllCoachMarkGeometryPreviews(interruptingEndpointGesture: true)
        isCoachLocalReview = false
        followsCoach = true
        isLocallyPaused = false
    }

    func beginImmersiveOpen() -> UUID? {
        // Opening pauses playback. Do not acquire the room while a scrub or
        // annotation adjustment owns a checkpoint that could later restore
        // playback when the dashboard disappears. A paused drawing draft has
        // no such gesture owner and may carry into the spatial room intact.
        guard !roomPresentation.isBusy,
              allowsMutationOutsideEndpointPreview(),
              let requestID = roomPresentation.beginOpening() else { return nil }
        setPlaying(false)
        statusMessage = "Preparing match players…"
        return requestID
    }

    func completeImmersiveOpen(_ requestID: UUID, opened: Bool) -> Bool {
        guard roomPresentation.completeOpening(requestID, opened: opened) else { return false }
        // Appearance can precede the system result. Keep any newer interaction
        // message from the visible room instead of overwriting it with "ready".
        if opened,
           statusMessage == "Preparing match players…" || statusMessage == "Opening spatial replay…" {
            statusMessage = "Spatial replay ready"
        }
        return true
    }

    func immersiveRoomDidAppear(_ requestID: UUID) -> UUID? {
        roomPresentation.didAppear(requestID)
    }

    func beginImmersiveClose(_ requestID: UUID) -> Bool {
        guard roomPresentation.beginClosing(requestID) else { return false }
        prepareForImmersiveExit()
        return true
    }

    func immersiveRoomDidDisappear(_ requestID: UUID) -> Bool {
        // Clear visible ownership before child scrub controls disappear. Their
        // old playback checkpoints must not undo this definitive exit pause.
        guard roomPresentation.didDisappear(requestID) else { return false }
        prepareForImmersiveExit()
        return true
    }

    func completeImmersiveClose(_ requestID: UUID) {
        roomPresentation.completeClosing(requestID)
    }

    /// Ends any transient annotation adjustment before the immersive scene goes
    /// away, then leaves local transport definitively paused. If the coach's
    /// committed shared clock was running, one paused baseline snapshot is
    /// enough; an already-paused exit emits nothing.
    func prepareForImmersiveExit() {
        cancelTimelineScrub()
        if hasActiveCoachMarkEndpointPreview {
            rollbackAllCoachMarkGeometryPreviews(interruptingEndpointGesture: true)
        } else {
            // A direct pitch-handle preview also owns transient local geometry.
            // It already published its shared pause when it began, so rollback
            // needs no additional packet.
            rollbackAllCoachMarkGeometryPreviews()
        }

        let shouldPublishPause = localRole == .coach && isPlaying
        isPlaying = false
        if isCollaborationActive, localRole == .player {
            followsCoach = false
            isLocallyPaused = true
        }
        statusMessage = "Replay paused outside the immersive room"
        if shouldPublishPause {
            emitSnapshot()
        }
        flushReviewAutosave()
    }

    private func emitSnapshot(allowingGeometryPreview: Bool = false) {
        guard !hasActiveTimelineScrub else { return }
        guard allowingGeometryPreview || !hasActiveCoachMarkGeometryPreview else { return }
        let committed = makeSnapshot()
        // This legacy-named method is also the local committed-action boundary.
        // Journal even with no transport callback; previews stay baseline-masked.
        if !isCollaborationActive, localRole == .coach {
            annotationEditHistory.record(committed.marks)
        }
        onBroadcastSnapshot?(committed)
    }
}
