import Combine
import Foundation
import GroupActivities
import Observation

@MainActor
@Observable
final class SquadSessionCoordinator {
    enum PhysicalPlacementRoute: Equatable {
        case localPreview
        case sharedSquad
    }

    enum ConnectionState: Equatable {
        case offline
        case preparing
        case waiting
        case joined
        case unavailable(String)

        var label: String {
            switch self {
            case .offline: "SOLO DEMO"
            case .preparing: "STARTING"
            case .waiting: "WAITING"
            case .joined: "LIVE ROOM"
            case .unavailable: "UNAVAILABLE"
            }
        }
    }

    let localID = UUID()

    var state: ConnectionState = .offline
    var participantCount = 1
    var nearbyParticipantCount = 1
    var supportsGroupImmersiveSpace = false
    var lastSync = Date.distantPast
    var roomID: UUID?
    var localParticipantID: UUID?
    var authoritativeCoachID: UUID?
    var authoritativeCoachParticipantID: UUID?

    /// A local preview is legal only in the fully offline state. Transitional
    /// SharePlay states intentionally expose no route, preventing a local anchor
    /// from being mistaken for a future shared one.
    var physicalPlacementRoute: PhysicalPlacementRoute? {
        switch state {
        case .offline: .localPreview
        case .joined: .sharedSquad
        case .preparing, .waiting, .unavailable: nil
        }
    }

    @ObservationIgnored private weak var store: ReplayStore?
    @ObservationIgnored private var groupSession: GroupSession<ReplayXIActivity>?
    @ObservationIgnored private var messenger: GroupSessionMessenger?
    @ObservationIgnored private var sessionObservationTask: Task<Void, Never>?
    @ObservationIgnored private var messageTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var nextSequence: UInt64 = 1
    @ObservationIgnored private var sequenceGate = SequenceGate()
    /// Last state the coach deliberately published. Heartbeats resend this
    /// snapshot instead of serializing transient local POVs or in-progress
    /// slider positions from the mutable store.
    @ObservationIgnored private var lastPublishedSnapshot: SharedPlaybackSnapshot?
    @ObservationIgnored private var lastPublishedInstant: ContinuousClock.Instant?
    @ObservationIgnored private let receiveDate: @MainActor () -> Date
    private let playbackClock = ContinuousClock()

    init(
        store: ReplayStore,
        receiveDate: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.store = store
        self.receiveDate = receiveDate
        store.onBroadcastSnapshot = { [weak self] snapshot in
            self?.publish(snapshot: snapshot)
        }
    }

    func startObserving() {
        guard sessionObservationTask == nil else { return }
        sessionObservationTask = Task { [weak self] in
            for await session in ReplayXIActivity.sessions() {
                guard let self, !Task.isCancelled else { return }
                await self.configure(session)
            }
        }
    }

    func startSharePlay() async {
        guard let store else { return }
        guard state == .offline || {
            if case .unavailable = state { return true }
            return false
        }() else { return }
        store.discardLocalTrianglePreviewForSessionTransition()
        state = .preparing
        let activity = ReplayXIActivity(
            roomID: localID,
            scenarioID: store.selectedScenarioID,
            coachInstanceID: localID
        )
        roomID = activity.roomID

        do {
            let activated = try await activity.activate()
            if activated {
                state = .waiting
            } else {
                roomID = nil
                state = .offline
            }
        } catch {
            roomID = nil
            state = .unavailable("SharePlay could not start")
        }
    }

    func leaveRoom() {
        groupSession?.leave()
        cleanUpSession()
    }

    func endRoom() {
        groupSession?.end()
        cleanUpSession()
    }

    func broadcastCurrentState() {
        guard let store else { return }
        publish(snapshot: store.makeSnapshot())
    }

    /// Changes player follow state without allowing a private POV inspection to
    /// replace the participant's assigned role. Rejoining first applies the
    /// latest cached coach snapshot, then restores the seat from that snapshot
    /// in the same main-actor transaction. UI follow controls should route
    /// through this method rather than mutating the store directly.
    func setFollowingCoach(_ follows: Bool) {
        guard let store else { return }
        store.setFollowingCoach(follows)
        if follows {
            applyLocalSeatAssignment(force: true)
        }
    }

    private func configure(_ session: GroupSession<ReplayXIActivity>) async {
        if let existing = groupSession, existing.id != session.id {
            existing.leave()
        }
        cleanUpSession(keepObserver: true)
        groupSession = session
        roomID = session.activity.roomID
        localParticipantID = session.localParticipant.id
        authoritativeCoachID = session.activity.coachInstanceID
        store?.localRole = session.isLocallyInitiated ? .coach : .player
        authoritativeCoachParticipantID = session.isLocallyInitiated
            ? session.localParticipant.id
            : nil
        if let scenarioID = store?.scenarios.first(where: { $0.id == session.activity.scenarioID })?.id {
            store?.selectScenario(id: scenarioID, broadcast: false)
        }

        if let coordinator = await session.systemCoordinator {
            var configuration = SystemCoordinator.Configuration()
            configuration.supportsGroupImmersiveSpace = true
            configuration.spatialTemplatePreference = .sideBySide.contentExtent(2.8)
            coordinator.configuration = configuration
            supportsGroupImmersiveSpace = true
        }

        let messenger = GroupSessionMessenger(session: session, deliveryMode: .reliable)
        self.messenger = messenger
        subscribe(to: session)
        receiveMessages(with: messenger)
        session.join()
        state = .waiting
    }

    private func subscribe(to session: GroupSession<ReplayXIActivity>) {
        session.$activeParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] participants in
                guard let self else { return }
                participantCount = max(participants.count, 1)
                nearbyParticipantCount = max(participants.filter(\.isNearbyWithLocalParticipant).count, 1)
                if isAuthoritativeCoach {
                    updateSeatAssignments(for: participants, localParticipant: session.localParticipant)
                    publishParticipantChange()
                }
            }
            .store(in: &cancellables)

        session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessionState in
                guard let self else { return }
                switch sessionState {
                case .waiting:
                    state = .waiting
                    store?.setCollaborationActive(false)
                case .joined:
                    let wasJoined = state == .joined
                    state = .joined
                    store?.setCollaborationActive(true)
                    if !wasJoined {
                        sendRequestState()
                        startHeartbeat()
                    }
                case .invalidated:
                    cleanUpSession()
                @unknown default:
                    state = .unavailable("Unknown SharePlay session state")
                    store?.setCollaborationActive(false)
                }
            }
            .store(in: &cancellables)
    }

    private func receiveMessages(with messenger: GroupSessionMessenger) {
        messageTask = Task { [weak self] in
            for await (command, context) in messenger.messages(of: SharedCommand.self) {
                guard let self, !Task.isCancelled else { return }
                receive(command, sourceParticipantID: context.source.id)
            }
        }
    }

    private func receive(_ command: SharedCommand, sourceParticipantID: UUID) {
        guard command.authorID != localID else { return }

        switch command.kind {
        case .sync:
            guard command.authorID == authoritativeCoachID,
                  command.authorRole == .coach,
                  let snapshot = command.snapshot,
                  let scenarioDuration = store?.scenarios.first(where: {
                      $0.id == snapshot.scenarioID
                  })?.duration else { return }
            if let coachParticipantID = authoritativeCoachParticipantID {
                guard sourceParticipantID == coachParticipantID else { return }
            }

            // Validate against a copy first. A corrupt/unsupported first packet
            // must not bind the room to its source or poison the sequence gate,
            // otherwise a late joiner can never accept the coach's recovery sync.
            var candidateGate = sequenceGate
            let receivedAt = receiveDate()
            guard candidateGate.shouldAccept(command),
                  let projectedSnapshot = SharedTimelineProjector.project(
                      snapshot,
                      sentAt: command.sentAt,
                      receivedAt: receivedAt,
                      duration: scenarioDuration
                  ),
                  store?.applyRemote(projectedSnapshot) == true else { return }
            sequenceGate = candidateGate
            if authoritativeCoachParticipantID == nil {
                authoritativeCoachParticipantID = sourceParticipantID
            }
            lastSync = receivedAt
            applyLocalSeatAssignment()

        case .coachAnnotation:
            guard command.authorID == authoritativeCoachID,
                  command.authorRole == .coach,
                  sourceParticipantID == authoritativeCoachParticipantID,
                  let mark = command.mark,
                  store?.isValidRemoteCoachMarkPayload(mark) == true else { return }
            var candidateGate = sequenceGate
            guard candidateGate.shouldAccept(command) else { return }
            // Application can be a no-op for a duplicate or a bounded-full
            // collection. The authenticated, valid command still establishes
            // ordering and prevents an older snapshot from rolling state back.
            _ = store?.appendRemoteCoachMark(mark)
            sequenceGate = candidateGate
            lastSync = receiveDate()

        case .requestState:
            // State requests are player-originated and carry no payload. Do not
            // let a malformed request claim the coach's author namespace and
            // suppress a later authoritative sync.
            guard command.authorRole == .player,
                  command.authorID != authoritativeCoachID,
                  command.snapshot == nil,
                  command.mark == nil,
                  sequenceGate.shouldAccept(command) else { return }
            if isAuthoritativeCoach {
                rebroadcastPublishedState()
            }
        }
    }

    private func publish(snapshot: SharedPlaybackSnapshot) {
        let outgoing = snapshotPreservingExplicitPOVShare(snapshot)
        lastPublishedSnapshot = outgoing
        lastPublishedInstant = playbackClock.now
        broadcast(snapshot: outgoing)
    }

    /// Internal seam for deterministic late-join and recovery tests.
    func receiveForTesting(
        _ command: SharedCommand,
        sourceParticipantID: UUID
    ) {
        receive(command, sourceParticipantID: sourceParticipantID)
    }

    private func snapshotPreservingExplicitPOVShare(
        _ snapshot: SharedPlaybackSnapshot
    ) -> SharedPlaybackSnapshot {
        guard store?.isCoachLocalReview == true,
              let published = lastPublishedSnapshot,
              published.scenarioID == snapshot.scenarioID
        else { return snapshot }

        return SharedPlaybackSnapshot(
            scenarioID: snapshot.scenarioID,
            playhead: snapshot.playhead,
            isPlaying: snapshot.isPlaying,
            playbackRate: snapshot.playbackRate,
            viewMode: published.viewMode,
            coachFocusPerspectiveID: published.coachFocusPerspectiveID,
            coachLockEnabled: published.coachLockEnabled,
            marks: snapshot.marks,
            seatAssignments: snapshot.seatAssignments,
            showsLaneLens: snapshot.showsLaneLens,
            sharedPitchAnchorID: snapshot.sharedPitchAnchorID,
            triangleLockMode: snapshot.triangleLockMode,
            shapeFocusStage: snapshot.shapeFocusStage
        )
    }

    private func rebroadcastPublishedState() {
        if lastPublishedSnapshot != nil {
            let now = playbackClock.now
            let elapsed = lastPublishedInstant.map {
                Self.seconds($0.duration(to: now))
            } ?? 0
            let snapshot = advancePublishedTimeline(by: elapsed)
            lastPublishedInstant = now
            guard let snapshot else { return }
            broadcast(snapshot: snapshot)
        } else {
            broadcastCurrentState()
        }
    }

    /// Advances only the shared clock fields while retaining the deliberately
    /// published view, focus, marks and room state. Production heartbeats use a
    /// monotonic elapsed duration; the internal seam keeps timing tests free of
    /// wall-clock sleeps.
    @discardableResult
    func advancePublishedTimelineForHeartbeat(
        by elapsed: TimeInterval
    ) -> SharedPlaybackSnapshot? {
        advancePublishedTimeline(by: elapsed)
    }

    private func advancePublishedTimeline(
        by elapsed: TimeInterval
    ) -> SharedPlaybackSnapshot? {
        guard let snapshot = lastPublishedSnapshot else { return nil }
        guard snapshot.isPlaying,
              elapsed.isFinite,
              elapsed >= 0,
              snapshot.playhead.isFinite,
              snapshot.playbackRate.isFinite,
              snapshot.playbackRate > 0,
              let duration = store?.scenarios.first(where: {
                  $0.id == snapshot.scenarioID
              })?.duration,
              duration.isFinite,
              duration >= 0 else { return snapshot }

        let clampedPlayhead = min(max(snapshot.playhead, 0), duration)
        let remaining = max(duration - clampedPlayhead, 0)
        let advance = elapsed >= remaining / snapshot.playbackRate
            ? remaining
            : elapsed * snapshot.playbackRate
        let projectedPlayhead = min(clampedPlayhead + advance, duration)
        let projected = SharedPlaybackSnapshot(
            scenarioID: snapshot.scenarioID,
            playhead: projectedPlayhead,
            isPlaying: projectedPlayhead < duration,
            playbackRate: snapshot.playbackRate,
            viewMode: snapshot.viewMode,
            coachFocusPerspectiveID: snapshot.coachFocusPerspectiveID,
            coachLockEnabled: snapshot.coachLockEnabled,
            marks: snapshot.marks,
            seatAssignments: snapshot.seatAssignments,
            showsLaneLens: snapshot.showsLaneLens,
            sharedPitchAnchorID: snapshot.sharedPitchAnchorID,
            triangleLockMode: snapshot.triangleLockMode,
            shapeFocusStage: snapshot.shapeFocusStage
        )
        lastPublishedSnapshot = projected
        return projected
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        Double(duration.components.seconds)
            + (Double(duration.components.attoseconds) / 1e18)
    }

    /// Internal seam for deterministic collaboration tests. It also documents
    /// the heartbeat contract: local, unpublished store edits are never read
    /// after a published snapshot exists.
    func snapshotForHeartbeat() -> SharedPlaybackSnapshot? {
        lastPublishedSnapshot
    }

    /// Participant membership can change while the coach is scrubbing or
    /// dragging an annotation handle. Merge only the new seat map into the
    /// committed, monotonically projected review state so a late join never
    /// receives a transient local preview.
    private func publishParticipantChange() {
        _ = publishParticipantChange(elapsed: nil)
    }

    /// Internal deterministic seam for late-join snapshot regression tests.
    @discardableResult
    func publishParticipantChangeForTesting(
        elapsed: TimeInterval
    ) -> SharedPlaybackSnapshot? {
        publishParticipantChange(elapsed: elapsed)
    }

    @discardableResult
    private func publishParticipantChange(
        elapsed elapsedOverride: TimeInterval?
    ) -> SharedPlaybackSnapshot? {
        guard let store else { return nil }

        let merged: SharedPlaybackSnapshot
        if lastPublishedSnapshot != nil {
            let now = playbackClock.now
            let elapsed = elapsedOverride ?? lastPublishedInstant.map {
                Self.seconds($0.duration(to: now))
            } ?? 0
            guard let published = advancePublishedTimeline(by: elapsed) else { return nil }
            merged = SharedPlaybackSnapshot(
                scenarioID: published.scenarioID,
                playhead: published.playhead,
                isPlaying: published.isPlaying,
                playbackRate: published.playbackRate,
                viewMode: published.viewMode,
                coachFocusPerspectiveID: published.coachFocusPerspectiveID,
                coachLockEnabled: published.coachLockEnabled,
                marks: published.marks,
                seatAssignments: store.participantSeatAssignments,
                showsLaneLens: published.showsLaneLens,
                sharedPitchAnchorID: published.sharedPitchAnchorID,
                triangleLockMode: published.triangleLockMode,
                shapeFocusStage: published.shapeFocusStage
            )
        } else {
            merged = store.makeSnapshot()
        }

        publish(snapshot: merged)
        return lastPublishedSnapshot
    }

    private func broadcast(snapshot: SharedPlaybackSnapshot) {
        guard state == .joined, isAuthoritativeCoach, let messenger, let store else { return }
        let command = SharedCommand(
            kind: .sync,
            sequence: takeSequence(),
            authorID: localID,
            sentAt: Date(),
            authorRole: store.localRole,
            snapshot: snapshot,
            mark: nil
        )
        Task {
            try? await messenger.send(command)
        }
    }

    private func sendRequestState() {
        guard let messenger, let store else { return }
        let command = SharedCommand(
            kind: .requestState,
            sequence: takeSequence(),
            authorID: localID,
            sentAt: Date(),
            authorRole: store.localRole,
            snapshot: nil,
            mark: nil
        )
        Task {
            try? await messenger.send(command)
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, state == .joined else { continue }
                if isAuthoritativeCoach {
                    rebroadcastPublishedState()
                }
            }
        }
    }

    private func takeSequence() -> UInt64 {
        defer { nextSequence &+= 1 }
        return nextSequence
    }

    private func cleanUpSession(keepObserver: Bool = false) {
        messageTask?.cancel()
        heartbeatTask?.cancel()
        messageTask = nil
        heartbeatTask = nil
        sequenceGate.reset()
        nextSequence = 1
        lastPublishedSnapshot = nil
        lastPublishedInstant = nil
        lastSync = .distantPast
        cancellables.removeAll()
        messenger = nil
        groupSession = nil
        participantCount = 1
        nearbyParticipantCount = 1
        supportsGroupImmersiveSpace = false
        state = .offline
        store?.resetCollaborationState()
        if !keepObserver {
            roomID = nil
            localParticipantID = nil
            authoritativeCoachID = nil
            authoritativeCoachParticipantID = nil
        }
    }

    var isAuthoritativeCoach: Bool {
        authoritativeCoachID == localID && store?.localRole == .coach
    }

    private func updateSeatAssignments(
        for participants: Set<Participant>,
        localParticipant: Participant
    ) {
        guard let store else { return }
        let playerParticipants = participants.filter { $0.id != authoritativeCoachParticipantID }
        let participantIDs = Set(playerParticipants.map(\.id))
        var assignments = store.participantSeatAssignments.filter { participantIDs.contains($0.key) }
        let physicalPlayerIDs = store.selectedScenario.kind == .shapeLab
            ? store.selectedScenario.formationTargets.map(\.playerID)
            : []
        let playerIDs = physicalPlayerIDs + store.selectedScenario.homePlayers.map(\.id).filter {
            !physicalPlayerIDs.contains($0)
        }
        var availablePlayerIDs = playerIDs.filter { !Set(assignments.values).contains($0) }

        let orderedParticipants = playerParticipants.sorted {
            if $0.id == localParticipant.id { return true }
            if $1.id == localParticipant.id { return false }
            return $0.id.uuidString < $1.id.uuidString
        }
        for participant in orderedParticipants where assignments[participant.id] == nil {
            guard !availablePlayerIDs.isEmpty else { break }
            assignments[participant.id] = availablePlayerIDs.removeFirst()
        }
        store.participantSeatAssignments = assignments
        if store.selectedScenario.kind == .shapeLab {
            store.prioritizePhysicalTriangleAssignments()
        }
        applyLocalSeatAssignment()
    }

    private func applyLocalSeatAssignment(force: Bool = false) {
        guard let store,
              force || (store.followsCoach && !store.isLocallyPaused),
              let participantID = localParticipantID,
              let perspectiveID = store.participantSeatAssignments[participantID]
        else { return }
        store.setLocalPerspective(perspectiveID, entersLocalReview: false)
    }
}
