import Foundation

enum SharedCommandKind: String, Codable, Sendable {
    case sync
    case coachAnnotation
    case requestState
}

struct SharedPlaybackSnapshot: Codable, Hashable, Sendable {
    let scenarioID: String
    let playhead: TimeInterval
    let isPlaying: Bool
    let playbackRate: Double
    let viewMode: ReplayViewMode
    let coachFocusPerspectiveID: String?
    let coachLockEnabled: Bool
    let marks: [CoachMark]
    let seatAssignments: [UUID: String]
    let showsLaneLens: Bool
    let sharedPitchAnchorID: UUID?
    let triangleLockMode: TriangleLockMode
    let shapeFocusStage: ShapeFocusStage

    init(
        scenarioID: String,
        playhead: TimeInterval,
        isPlaying: Bool,
        playbackRate: Double,
        viewMode: ReplayViewMode,
        coachFocusPerspectiveID: String?,
        coachLockEnabled: Bool,
        marks: [CoachMark],
        seatAssignments: [UUID: String],
        showsLaneLens: Bool,
        sharedPitchAnchorID: UUID?,
        triangleLockMode: TriangleLockMode,
        shapeFocusStage: ShapeFocusStage = .problem
    ) {
        self.scenarioID = scenarioID
        self.playhead = playhead
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
        self.viewMode = viewMode
        self.coachFocusPerspectiveID = coachFocusPerspectiveID
        self.coachLockEnabled = coachLockEnabled
        self.marks = marks
        self.seatAssignments = seatAssignments
        self.showsLaneLens = showsLaneLens
        self.sharedPitchAnchorID = sharedPitchAnchorID
        self.triangleLockMode = triangleLockMode
        self.shapeFocusStage = shapeFocusStage
    }

    private enum CodingKeys: String, CodingKey {
        case scenarioID
        case playhead
        case isPlaying
        case playbackRate
        case viewMode
        case coachFocusPerspectiveID
        case coachLockEnabled
        case marks
        case seatAssignments
        case showsLaneLens
        case sharedPitchAnchorID
        case triangleLockMode
        case shapeFocusStage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scenarioID = try container.decode(String.self, forKey: .scenarioID)
        playhead = try container.decode(TimeInterval.self, forKey: .playhead)
        isPlaying = try container.decode(Bool.self, forKey: .isPlaying)
        playbackRate = try container.decode(Double.self, forKey: .playbackRate)
        viewMode = try container.decode(ReplayViewMode.self, forKey: .viewMode)
        coachFocusPerspectiveID = try container.decodeIfPresent(
            String.self,
            forKey: .coachFocusPerspectiveID
        )
        coachLockEnabled = try container.decode(Bool.self, forKey: .coachLockEnabled)
        marks = try container.decode([CoachMark].self, forKey: .marks)
        seatAssignments = try container.decode([UUID: String].self, forKey: .seatAssignments)
        showsLaneLens = try container.decode(Bool.self, forKey: .showsLaneLens)
        sharedPitchAnchorID = try container.decodeIfPresent(UUID.self, forKey: .sharedPitchAnchorID)
        triangleLockMode = try container.decode(TriangleLockMode.self, forKey: .triangleLockMode)
        // Older in-flight messages predate Shape Focus synchronization. Treat
        // them as the safe, non-physical problem state rather than rejecting the room.
        shapeFocusStage = try container.decodeIfPresent(
            ShapeFocusStage.self,
            forKey: .shapeFocusStage
        ) ?? .problem
    }
}

struct SharedCommand: Codable, Hashable, Sendable {
    let kind: SharedCommandKind
    let sequence: UInt64
    let authorID: UUID
    let sentAt: Date
    let authorRole: SquadRole
    let snapshot: SharedPlaybackSnapshot?
    let mark: CoachMark?
}

/// Converts a coach's send-time playback snapshot into the match instant that
/// should be visible when the packet reaches another headset.
///
/// SharePlay transports semantic state rather than per-frame transforms. A
/// playing snapshot therefore needs a small, bounded transit correction before
/// every participant resumes its local deterministic sampler. Paused snapshots
/// are exact review instants and intentionally ignore transport age.
enum SharedTimelineProjector {
    /// Three missed two-second heartbeat windows indicate that a playing packet
    /// is no longer a trustworthy representation of current coach intent.
    static let maximumTransitAge: TimeInterval = 6

    /// Small clock skew must not move playback backwards. Larger future-dated
    /// packets are rejected so a badly skewed clock cannot establish authority.
    static let futureTimestampTolerance: TimeInterval = 0.5

    static func project(
        _ snapshot: SharedPlaybackSnapshot,
        sentAt: Date,
        receivedAt: Date,
        duration: TimeInterval
    ) -> SharedPlaybackSnapshot? {
        // Pause, seek and annotation review points are exact coach choices. They
        // remain applicable even if an old device encoded an unusual timestamp.
        guard snapshot.isPlaying else { return snapshot }

        let sentTime = sentAt.timeIntervalSinceReferenceDate
        let receivedTime = receivedAt.timeIntervalSinceReferenceDate
        guard sentTime.isFinite,
              receivedTime.isFinite,
              duration.isFinite,
              duration >= 0,
              snapshot.playhead.isFinite,
              snapshot.playbackRate.isFinite else { return nil }

        let rawTransitAge = receivedTime - sentTime
        guard rawTransitAge.isFinite,
              rawTransitAge >= -futureTimestampTolerance,
              rawTransitAge <= maximumTransitAge else { return nil }

        let transitAge = max(rawTransitAge, 0)
        let playbackRate = min(max(snapshot.playbackRate, 0.25), 4)
        let basePlayhead = min(max(snapshot.playhead, 0), duration)
        let remaining = max(duration - basePlayhead, 0)
        let requestedAdvance = transitAge >= remaining / playbackRate
            ? remaining
            : transitAge * playbackRate
        let projectedPlayhead = min(basePlayhead + requestedAdvance, duration)

        return SharedPlaybackSnapshot(
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
    }
}

struct SequenceGate: Sendable {
    private(set) var lastSequenceByAuthor: [UUID: UInt64] = [:]

    mutating func shouldAccept(_ command: SharedCommand) -> Bool {
        let previous = lastSequenceByAuthor[command.authorID] ?? 0
        guard command.sequence > previous else { return false }
        lastSequenceByAuthor[command.authorID] = command.sequence
        return true
    }

    mutating func reset() {
        lastSequenceByAuthor.removeAll(keepingCapacity: true)
    }
}
