// Legacy snapshot compatibility harness. Test-only; no networking or Apple group APIs.
import Foundation
import Observation
@testable import ReplayXI

@MainActor
@Observable
final class LegacySnapshotCoordinator {
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
    @ObservationIgnored private var nextSequence: UInt64 = 1
    @ObservationIgnored private var sequenceGate = SequenceGate()
    /// Last state the coach deliberately published. Heartbeats resend this
    /// snapshot instead of serializing transient local POVs or in-progress
    /// slider positions from the mutable store.
    @ObservationIgnored private var lastPublishedSnapshot: SharedPlaybackSnapshot?
    @ObservationIgnored private var lastPublishedInstant: ContinuousClock.Instant?
    /// Receive instant associated with the latest accepted full coach snapshot.
    /// `lastSync` also advances for legacy annotation-only commands, so it cannot
    /// safely be used to project transport when a player rejoins coach follow.
    @ObservationIgnored private var lastCoachSnapshotReceivedAt = Date.distantPast
    /// A rejoin request made without a recent full snapshot waits for the next
    /// authenticated sync instead of applying an arbitrarily stale playhead.
    @ObservationIgnored private var awaitsFreshCoachSnapshotForRejoin = false
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





    func leaveRoom() {
        cleanUpSession()
    }

    func endRoom() {
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
        guard follows else {
            awaitsFreshCoachSnapshotForRejoin = false
            store.setFollowingCoach(false)
            return
        }

        // Outside a joined player room this remains the store's local state
        // transition. The receive-time projection below is specifically a
        // SharePlay rejoin contract.
        guard state == .joined,
              store.localRole == .player,
              store.isCollaborationActive else {
            store.setFollowingCoach(true)
            applyLocalSeatAssignment(force: true)
            return
        }

        let now = receiveDate()
        let snapshotAge = now.timeIntervalSince(lastCoachSnapshotReceivedAt)
        guard lastCoachSnapshotReceivedAt != .distantPast,
              snapshotAge.isFinite,
              snapshotAge >= -SharedTimelineProjector.futureTimestampTolerance,
              snapshotAge <= SharedTimelineProjector.maximumTransitAge else {
            // We cannot know whether a stale playing snapshot remained playing
            // or whether the coach sought/paused after it. Stay in the local
            // comfort pause and ask for authoritative recovery rather than
            // presenting an invented timeline position.
            awaitsFreshCoachSnapshotForRejoin = true
            store.statusMessage = "Waiting for a fresh coach state"
            sendRequestState()
            return
        }

        awaitsFreshCoachSnapshotForRejoin = false
        store.setFollowingCoach(true)
        // The cached snapshot is projected to its receive instant. Advance from
        // that instant to this pinch so track-bound marks and player poses use
        // the same current replay time as the rest of the squad.
        store.advance(by: max(snapshotAge, 0))
        applyLocalSeatAssignment(force: true)
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
            lastCoachSnapshotReceivedAt = receivedAt
            if awaitsFreshCoachSnapshotForRejoin {
                awaitsFreshCoachSnapshotForRejoin = false
                // `applyRemote` cached the just-projected snapshot while the
                // wearer remained locally paused. Applying it again after
                // enabling follow commits that same authoritative instant.
                store?.setFollowingCoach(true)
            }
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

    private func broadcast(snapshot: SharedPlaybackSnapshot) {}

    private func sendRequestState() {}



    private func takeSequence() -> UInt64 {
        defer { nextSequence &+= 1 }
        return nextSequence
    }

    private func cleanUpSession(keepObserver: Bool = false) {
        sequenceGate.reset()
        nextSequence = 1
        lastPublishedSnapshot = nil
        lastPublishedInstant = nil
        lastCoachSnapshotReceivedAt = .distantPast
        awaitsFreshCoachSnapshotForRejoin = false
        lastSync = .distantPast
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



    private func applyLocalSeatAssignment(force: Bool = false) {
        guard let store,
              force || (store.followsCoach && !store.isLocallyPaused),
              let participantID = localParticipantID,
              let perspectiveID = store.participantSeatAssignments[participantID]
        else { return }
        store.setLocalPerspective(perspectiveID, entersLocalReview: false)
    }
}
