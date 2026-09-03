import Foundation

enum ExperienceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case squadReplay
    case coachFocus
    case shapeLab
    case passingChannels
    case perspectiveMatrix

    var id: String { rawValue }

    var number: String {
        switch self {
        case .squadReplay: "01"
        case .coachFocus: "02"
        case .shapeLab: "03"
        case .passingChannels: "04"
        case .perspectiveMatrix: "05"
        }
    }

    var shortLabel: String {
        switch self {
        case .squadReplay: "Match playback"
        case .coachFocus: "Coach focus"
        case .shapeLab: "Shape lab"
        case .passingChannels: "Passing lanes"
        case .perspectiveMatrix: "Perspective matrix"
        }
    }

    var systemImage: String {
        switch self {
        case .squadReplay: "person.3.sequence.fill"
        case .coachFocus: "scope"
        case .shapeLab: "triangle"
        case .passingChannels: "arrow.triangle.branch"
        case .perspectiveMatrix: "rectangle.split.2x2"
        }
    }
}

enum ReplayViewMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case firstPerson
    case tacticalTable
    case touchline
    case positional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstPerson: "Player POV"
        case .tacticalTable: "Tactical"
        case .touchline: "Touchline"
        case .positional: "Positioning"
        }
    }

    var systemImage: String {
        switch self {
        case .firstPerson: "viewfinder"
        case .tacticalTable: "rectangle.3.group"
        case .touchline: "figure.soccer"
        case .positional: "move.3d"
        }
    }
}

enum TriangleLockMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case visualise
    case place

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visualise: "Visualise"
        case .place: "Place"
        }
    }
}

/// The coach-authored comparison shown by Shape Focus.
///
/// This is deliberately separate from `TriangleLockMode`: problem/ideal chooses
/// the tactical picture, while visualise/place chooses whether that picture is a
/// tabletop model or a consent-gated physical rehearsal.
enum ShapeFocusStage: String, Codable, CaseIterable, Identifiable, Sendable {
    case problem
    case ideal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .problem: "Problem"
        case .ideal: "Ideal"
        }
    }

    var systemImage: String {
        switch self {
        case .problem: "exclamationmark.triangle.fill"
        case .ideal: "checkmark.circle.fill"
        }
    }

    /// A stable authored moment makes the before/after comparison legible even
    /// if the user previously scrubbed somewhere unrelated in the replay.
    var referenceTime: TimeInterval {
        switch self {
        case .problem: 14
        case .ideal: 16
        }
    }
}

enum SquadRole: String, Codable, CaseIterable, Sendable {
    case coach
    case player

    var title: String { rawValue.uppercased() }
}

enum FootballTeam: String, Codable, CaseIterable, Identifiable, Sendable {
    case home
    case away

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .home: "Northbridge XI"
        case .away: "Eastport XI"
        }
    }

    var compactTitle: String {
        switch self {
        case .home: "HOME XI"
        case .away: "OPPOSITION XI"
        }
    }
}

struct PitchPoint: Codable, Hashable, Sendable {
    var x: Float
    var z: Float

    static let zero = PitchPoint(x: 0, z: 0)

    func interpolated(to other: PitchPoint, fraction: Float) -> PitchPoint {
        let clamped = min(max(fraction, 0), 1)
        return PitchPoint(
            x: x + ((other.x - x) * clamped),
            z: z + ((other.z - z) * clamped)
        )
    }
}

struct MotionKeyframe: Codable, Hashable, Sendable {
    let time: TimeInterval
    let position: PitchPoint
    let facingDegrees: Float
}

struct PlayerPose: Hashable, Sendable {
    let position: PitchPoint
    let facingDegrees: Float
}

struct PlayerMotionState: Hashable, Sendable {
    let speedMetresPerSecond: Float
    let distanceTravelled: Float
    let locomotionPhase: Float

    var effort: Float {
        min(max(speedMetresPerSecond / 7.2, 0), 1)
    }
}

/// Seek-stable football movement semantics derived only from the authored
/// telemetry around an absolute match timestamp. No rendered-frame history is
/// involved, so reverse playback and SharePlay resynchronisation classify the
/// same instant identically.
enum PlayerLocomotionState: String, CaseIterable, Hashable, Sendable {
    case idle
    case walk
    case jog
    case sprint
    case cut

    /// The bundled imported pilot contains a forward running cycle. Jog and
    /// sprint can safely reuse it because clip phase follows travelled distance;
    /// standing, walking and direction changes require different body mechanics.
    var supportsImportedRunClip: Bool {
        self == .jog || self == .sprint
    }
}

struct PlayerLocomotionSample: Hashable, Sendable {
    let motion: PlayerMotionState
    let speedMetresPerSecond: Float
    let accelerationMetresPerSecondSquared: Float
    let turnRateDegreesPerSecond: Float
    let state: PlayerLocomotionState

    var effort: Float {
        min(max(speedMetresPerSecond / 7.2, 0), 1)
    }

    var turnResponse: Float {
        min(max(turnRateDegreesPerSecond / 180, -1), 1)
    }

    var accelerationResponse: Float {
        min(max(accelerationMetresPerSecondSquared / 8, -1), 1)
    }

    static func classify(
        speedMetresPerSecond rawSpeed: Float,
        turnRateDegreesPerSecond rawTurnRate: Float
    ) -> PlayerLocomotionState {
        let speed = rawSpeed.isFinite ? max(rawSpeed, 0) : 0
        let turnRate = rawTurnRate.isFinite ? abs(rawTurnRate) : 0

        // A cut is a moving change of direction, not a stationary scan. Test it
        // before the pace bands so a fast turn never presents as a straight run.
        if speed >= 1.10, turnRate >= 70 {
            return .cut
        }
        if speed < 0.22 { return .idle }
        if speed < 1.65 { return .walk }
        if speed < 3.80 { return .jog }
        return .sprint
    }
}

struct PlayerTrack: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let displayName: String
    let role: String
    let shirtNumber: Int
    let team: FootballTeam
    let isGoalkeeper: Bool
    let keyframes: [MotionKeyframe]
    private let samplingIndex: SamplingIndex

    /// Derived lookup data is intentionally excluded from the Codable payload.
    /// Replay files keep the same schema while repeated render-frame seeks avoid
    /// walking every preceding telemetry sample.
    private struct SamplingIndex: Sendable {
        let supportsBinaryLookup: Bool
        let cumulativeDistances: [Float]

        init(keyframes: [MotionKeyframe]) {
            var supportsBinaryLookup = true
            var cumulativeDistances = Array(repeating: Float.zero, count: keyframes.count)

            for index in keyframes.indices {
                let timestamp = keyframes[index].time
                if !timestamp.isFinite {
                    supportsBinaryLookup = false
                }
                if index > keyframes.startIndex {
                    let previousIndex = keyframes.index(before: index)
                    if timestamp < keyframes[previousIndex].time {
                        supportsBinaryLookup = false
                    }
                    cumulativeDistances[index] = cumulativeDistances[previousIndex]
                        + ReplayGeometry.distance(
                            keyframes[previousIndex].position,
                            keyframes[index].position
                        )
                }
            }

            self.supportsBinaryLookup = supportsBinaryLookup
            self.cumulativeDistances = cumulativeDistances
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case role
        case shirtNumber
        case team
        case isGoalkeeper
        case keyframes
    }

    init(
        id: String,
        displayName: String,
        role: String,
        shirtNumber: Int,
        team: FootballTeam,
        isGoalkeeper: Bool,
        keyframes: [MotionKeyframe]
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.shirtNumber = shirtNumber
        self.team = team
        self.isGoalkeeper = isGoalkeeper
        self.keyframes = keyframes
        samplingIndex = SamplingIndex(keyframes: keyframes)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            role: try container.decode(String.self, forKey: .role),
            shirtNumber: try container.decode(Int.self, forKey: .shirtNumber),
            team: try container.decode(FootballTeam.self, forKey: .team),
            isGoalkeeper: try container.decode(Bool.self, forKey: .isGoalkeeper),
            keyframes: try container.decode([MotionKeyframe].self, forKey: .keyframes)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(role, forKey: .role)
        try container.encode(shirtNumber, forKey: .shirtNumber)
        try container.encode(team, forKey: .team)
        try container.encode(isGoalkeeper, forKey: .isGoalkeeper)
        try container.encode(keyframes, forKey: .keyframes)
    }

    static func == (lhs: PlayerTrack, rhs: PlayerTrack) -> Bool {
        lhs.id == rhs.id
            && lhs.displayName == rhs.displayName
            && lhs.role == rhs.role
            && lhs.shirtNumber == rhs.shirtNumber
            && lhs.team == rhs.team
            && lhs.isGoalkeeper == rhs.isGoalkeeper
            && lhs.keyframes == rhs.keyframes
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(displayName)
        hasher.combine(role)
        hasher.combine(shirtNumber)
        hasher.combine(team)
        hasher.combine(isGoalkeeper)
        hasher.combine(keyframes)
    }

    /// Compact, conventional shirt-position identity for labels that must stay
    /// readable on a shared tactical board. The authored role remains the
    /// descriptive source of truth everywhere longer copy is appropriate.
    var positionCode: String {
        switch role.lowercased() {
        case "goalkeeper": "GK"
        case "right back": "RB"
        case "right centre-back": "RCB"
        case "left centre-back": "LCB"
        case "left back": "LB"
        case "holding midfielder": "DM"
        case "right holding midfielder": "RDM"
        case "left holding midfielder": "LDM"
        case "right midfielder": "RM"
        case "left midfielder": "LM"
        case "attacking midfielder": "AM"
        case "right winger": "RW"
        case "centre forward": "CF"
        case "left winger": "LW"
        default:
            role.split(separator: " ")
                .compactMap(\.first)
                .map { String($0).uppercased() }
                .joined()
        }
    }

    func pose(at time: TimeInterval) -> PlayerPose {
        guard let first = keyframes.first else {
            return PlayerPose(position: .zero, facingDegrees: 0)
        }
        guard keyframes.count > 1, time > first.time else {
            return PlayerPose(position: first.position, facingDegrees: first.facingDegrees)
        }
        guard let last = keyframes.last else {
            return PlayerPose(position: first.position, facingDegrees: first.facingDegrees)
        }
        guard time < last.time else {
            return PlayerPose(position: last.position, facingDegrees: last.facingDegrees)
        }

        guard samplingIndex.supportsBinaryLookup else {
            return linearPose(at: time, fallback: last)
        }

        // Pose interpolation is left-continuous: at a duplicated timestamp the
        // first segment ending there wins, matching the original authored walk.
        let endIndex = lowerBoundKeyframeIndex(for: time)
        let start = keyframes[endIndex - 1]
        let end = keyframes[endIndex]
        return interpolatedPose(from: start, to: end, at: time)
    }

    /// A seek-stable locomotion clock derived from telemetry distance rather
    /// than rendered frames. Scrubbing to the same instant therefore produces
    /// the same stride, and changing playback rate never changes gait shape.
    func motion(at time: TimeInterval) -> PlayerMotionState {
        let stablePhaseOffset = locomotionPhaseOffset
        guard keyframes.count > 1, let first = keyframes.first else {
            return PlayerMotionState(
                speedMetresPerSecond: 0,
                distanceTravelled: 0,
                locomotionPhase: stablePhaseOffset
            )
        }

        guard samplingIndex.supportsBinaryLookup else {
            return linearMotion(at: time, phaseOffset: stablePhaseOffset, first: first)
        }

        let clampedTime = max(time, first.time)
        guard !clampedTime.isNaN else {
            return PlayerMotionState(
                speedMetresPerSecond: 0,
                distanceTravelled: 0,
                locomotionPhase: stablePhaseOffset
            )
        }

        // Motion is right-continuous: every segment whose end equals the sample
        // time contributes its full distance before the next velocity is read.
        let nextIndex = upperBoundKeyframeIndex(for: clampedTime)
        guard nextIndex < keyframes.count else {
            let distanceTravelled = samplingIndex.cumulativeDistances.last ?? 0
            return PlayerMotionState(
                speedMetresPerSecond: 0,
                distanceTravelled: distanceTravelled,
                locomotionPhase: (distanceTravelled * 3.10) + stablePhaseOffset
            )
        }

        let startIndex = nextIndex - 1
        let start = keyframes[startIndex]
        let end = keyframes[nextIndex]
        let segmentDuration = max(end.time - start.time, 0.000_1)
        let segmentDistance = ReplayGeometry.distance(start.position, end.position)
        let fraction = Float((clampedTime - start.time) / segmentDuration)
        let distanceTravelled = samplingIndex.cumulativeDistances[startIndex]
            + (segmentDistance * min(max(fraction, 0), 1))

        return PlayerMotionState(
            speedMetresPerSecond: segmentDistance / Float(segmentDuration),
            distanceTravelled: distanceTravelled,
            locomotionPhase: (distanceTravelled * 3.10) + stablePhaseOffset
        )
    }

    /// A centered, allocation-free motion descriptor for animation selection.
    /// Incoming and outgoing velocity capture acceleration and sharp path turns
    /// that a single interpolated pose cannot express. The fixed sampling window
    /// also prevents classification from depending on display refresh cadence.
    func locomotion(at time: TimeInterval) -> PlayerLocomotionSample {
        let baseMotion = motion(at: time)
        guard time.isFinite, keyframes.count > 1 else {
            let speed = baseMotion.speedMetresPerSecond.isFinite
                ? max(baseMotion.speedMetresPerSecond, 0)
                : 0
            return PlayerLocomotionSample(
                motion: baseMotion,
                speedMetresPerSecond: speed,
                accelerationMetresPerSecondSquared: 0,
                turnRateDegreesPerSecond: 0,
                state: PlayerLocomotionSample.classify(
                    speedMetresPerSecond: speed,
                    turnRateDegreesPerSecond: 0
                )
            )
        }

        let halfWindow: TimeInterval = 0.12
        let before = pose(at: time - halfWindow)
        let centre = pose(at: time)
        let after = pose(at: time + halfWindow)
        let seconds = Float(halfWindow)

        let incomingX = centre.position.x - before.position.x
        let incomingZ = centre.position.z - before.position.z
        let outgoingX = after.position.x - centre.position.x
        let outgoingZ = after.position.z - centre.position.z
        let incomingDistance = hypot(incomingX, incomingZ)
        let outgoingDistance = hypot(outgoingX, outgoingZ)
        let incomingSpeed = incomingDistance / seconds
        let outgoingSpeed = outgoingDistance / seconds
        let speed = max((incomingSpeed + outgoingSpeed) * 0.5, 0)
        let acceleration = min(max((outgoingSpeed - incomingSpeed) / seconds, -30), 30)

        let facingTurn = Self.shortestAngleDelta(
            from: before.facingDegrees,
            to: after.facingDegrees
        ) / Float(halfWindow * 2)
        var pathTurn: Float = 0
        if incomingDistance > 0.005, outgoingDistance > 0.005 {
            let cross = (incomingX * outgoingZ) - (incomingZ * outgoingX)
            let dot = (incomingX * outgoingX) + (incomingZ * outgoingZ)
            pathTurn = atan2(cross, dot) * 180 / .pi / seconds
        }
        let strongestTurn = abs(pathTurn) > abs(facingTurn) ? pathTurn : facingTurn
        let turnRate = min(max(strongestTurn, -360), 360)

        return PlayerLocomotionSample(
            motion: baseMotion,
            speedMetresPerSecond: speed,
            accelerationMetresPerSecondSquared: acceleration,
            turnRateDegreesPerSecond: turnRate,
            state: PlayerLocomotionSample.classify(
                speedMetresPerSecond: speed,
                turnRateDegreesPerSecond: turnRate
            )
        )
    }

    private static func shortestAngleDelta(from start: Float, to end: Float) -> Float {
        var delta = (end - start).truncatingRemainder(dividingBy: 360)
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }
        return delta
    }

    private var locomotionPhaseOffset: Float {
        Float(
            id.utf8.reduce(UInt32(2_166_136_261)) { partial, byte in
                (partial ^ UInt32(byte)) &* 16_777_619
            } % 628
        ) / 100
    }

    /// First keyframe whose time is greater than or equal to the sample.
    private func lowerBoundKeyframeIndex(for time: TimeInterval) -> Int {
        var lower = keyframes.startIndex
        var upper = keyframes.endIndex
        while lower < upper {
            let middle = lower + ((upper - lower) / 2)
            if keyframes[middle].time < time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    /// First keyframe whose time is strictly greater than the sample.
    private func upperBoundKeyframeIndex(for time: TimeInterval) -> Int {
        var lower = keyframes.startIndex
        var upper = keyframes.endIndex
        while lower < upper {
            let middle = lower + ((upper - lower) / 2)
            if keyframes[middle].time <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func interpolatedPose(
        from start: MotionKeyframe,
        to end: MotionKeyframe,
        at time: TimeInterval
    ) -> PlayerPose {
        let span = max(end.time - start.time, 0.000_1)
        let fraction = Float((time - start.time) / span)
        return PlayerPose(
            position: start.position.interpolated(to: end.position, fraction: fraction),
            facingDegrees: ReplayGeometry.interpolateAngle(
                from: start.facingDegrees,
                to: end.facingDegrees,
                fraction: fraction
            )
        )
    }

    /// Compatibility path for externally supplied malformed telemetry. Valid
    /// chronological replay tracks never pay this linear cost.
    private func linearPose(at time: TimeInterval, fallback: MotionKeyframe) -> PlayerPose {
        for (start, end) in zip(keyframes, keyframes.dropFirst()) {
            guard time >= start.time, time <= end.time else { continue }
            return interpolatedPose(from: start, to: end, at: time)
        }
        return PlayerPose(position: fallback.position, facingDegrees: fallback.facingDegrees)
    }

    private func linearMotion(
        at time: TimeInterval,
        phaseOffset: Float,
        first: MotionKeyframe
    ) -> PlayerMotionState {
        let clampedTime = max(time, first.time)
        var distanceTravelled: Float = 0
        var speed: Float = 0

        for (start, end) in zip(keyframes, keyframes.dropFirst()) {
            let segmentDuration = max(end.time - start.time, 0.000_1)
            let segmentDistance = ReplayGeometry.distance(start.position, end.position)

            if clampedTime >= end.time {
                distanceTravelled += segmentDistance
                continue
            }

            if clampedTime >= start.time {
                let fraction = Float((clampedTime - start.time) / segmentDuration)
                distanceTravelled += segmentDistance * min(max(fraction, 0), 1)
                speed = segmentDistance / Float(segmentDuration)
            }
            break
        }

        if let last = keyframes.last, clampedTime >= last.time {
            speed = 0
        }

        return PlayerMotionState(
            speedMetresPerSecond: speed,
            distanceTravelled: distanceTravelled,
            locomotionPhase: (distanceTravelled * 3.10) + phaseOffset
        )
    }
}

struct BallKeyframe: Codable, Hashable, Sendable {
    let time: TimeInterval
    let position: PitchPoint
    let height: Float
}

struct BallPose: Hashable, Sendable {
    let position: PitchPoint
    let height: Float
}

struct BallTrack: Codable, Hashable, Sendable {
    let keyframes: [BallKeyframe]

    func pose(at time: TimeInterval) -> BallPose {
        guard let first = keyframes.first else {
            return BallPose(position: .zero, height: 0.11)
        }
        guard keyframes.count > 1, time > first.time else {
            return BallPose(position: first.position, height: first.height)
        }
        guard let last = keyframes.last else {
            return BallPose(position: first.position, height: first.height)
        }
        guard time < last.time else {
            return BallPose(position: last.position, height: last.height)
        }

        for pair in zip(keyframes, keyframes.dropFirst()) {
            let start = pair.0
            let end = pair.1
            guard time >= start.time, time <= end.time else { continue }
            let span = max(end.time - start.time, 0.000_1)
            let fraction = Float((time - start.time) / span)
            return BallPose(
                position: start.position.interpolated(to: end.position, fraction: fraction),
                height: start.height + ((end.height - start.height) * fraction)
            )
        }

        return BallPose(position: last.position, height: last.height)
    }
}

enum CoachMarkKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case run
    case pass
    case danger
    case space
    case playerLabel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: "Run"
        case .pass: "Pass"
        case .danger: "Pressure"
        case .space: "Space"
        case .playerLabel: "Player label"
        }
    }

    var systemImage: String {
        switch self {
        case .run: "figure.run"
        case .pass: "arrow.up.right"
        case .danger: "exclamationmark.triangle"
        case .space: "circle.dashed"
        case .playerLabel: "tag.fill"
        }
    }

    /// Pitch marks use a start and destination. A player label instead resolves
    /// its single target from the selected player's authored pose.
    var requiresTwoPitchPoints: Bool {
        self != .playerLabel
    }

    /// Short, conventional football language for fast spatial authoring. These
    /// options deliberately fit on a single glanceable control; a coach should
    /// not need a floating keyboard to explain a common movement or trigger.
    var suggestedLabels: [String] {
        switch self {
        case .run:
            ["Overlap", "Underlap", "Third-player run", "Attack the space", "Hold width"]
        case .pass:
            ["Pass into space", "Switch play", "Bounce pass", "Cutback", "Release the lane"]
        case .danger:
            ["Press trigger", "Cover shadow", "Track runner", "Protect channel", "Delay"]
        case .space:
            ["Free player", "Overload", "Passing lane", "Weak side", "Useful space"]
        case .playerLabel:
            []
        }
    }
}

/// Shared authoring gate for both continuous pinch strokes and the two-tap
/// fallback. Centralising it prevents an accessible path from creating a
/// zero-length or unreadably small spatial instruction.
enum CoachMarkGeometryPolicy {
    static let minimumDirectionalLength: Float = 0.80
    static let minimumZoneRadius: Float = 1.10

    static func minimumDistance(for kind: CoachMarkKind) -> Float? {
        switch kind {
        case .run, .pass, .danger: minimumDirectionalLength
        case .space: minimumZoneRadius
        case .playerLabel: nil
        }
    }

    static func accepts(kind: CoachMarkKind, start: PitchPoint, end: PitchPoint) -> Bool {
        guard let minimum = minimumDistance(for: kind) else { return false }
        return ReplayGeometry.distance(start, end) >= minimum
    }
}

struct CoachMark: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: CoachMarkKind
    let start: PitchPoint
    let end: PitchPoint
    let label: String
    let revealTime: TimeInterval
    /// Optional end of the annotation's authored moment. Older replay files
    /// omit this value and intentionally retain their cumulative mark behavior.
    let hideTime: TimeInterval?
    let author: String
    /// Stable authored track identity for a player-attached annotation. This is
    /// optional so marks encoded before player labels existed still decode.
    let playerID: String?

    init(
        id: UUID = UUID(),
        kind: CoachMarkKind,
        start: PitchPoint,
        end: PitchPoint,
        label: String,
        revealTime: TimeInterval = 0,
        hideTime: TimeInterval? = nil,
        author: String = "Coach",
        playerID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.label = label
        self.revealTime = revealTime
        self.hideTime = hideTime
        self.author = author
        self.playerID = playerID
    }

    func isVisible(at time: TimeInterval) -> Bool {
        revealTime <= time && (hideTime.map { time < $0 } ?? true)
    }
}

struct CueMoment: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let time: TimeInterval
    let kicker: String
    let headline: String
    let explanation: String
}

struct FormationTarget: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let playerID: String
    let position: PitchPoint
    let toleranceMetres: Float
    let label: String
}

enum TriangleLockLayout {
    static let visualiseScale: Float = 0.035
    static let placeMinimumCentreSeparation: Float = 1.50
    static let placeTolerance: Float = 0.25
    static let placeForwardOffset: Float = 2.20
    static let visualiseForwardOffset: Float = 2.0
    static let visualiseHeight: Float = 1.06
    static let visualiseHorizontalOffset: Float = 0.52
    static let visualiseRingRadius: Float = 0.065

    static func minimumPairwiseDistance(in targets: [FormationTarget]) -> Float? {
        guard targets.count > 1 else { return nil }
        var minimum = Float.greatestFiniteMagnitude
        for firstIndex in targets.indices {
            for secondIndex in targets.indices where secondIndex > firstIndex {
                minimum = min(
                    minimum,
                    ReplayGeometry.distance(
                        targets[firstIndex].position,
                        targets[secondIndex].position
                    )
                )
            }
        }
        return minimum.isFinite ? minimum : nil
    }

    static func placeScale(for targets: [FormationTarget]) -> Float {
        guard let minimumDistance = minimumPairwiseDistance(in: targets), minimumDistance > 0 else {
            return 0.075
        }
        return max(0.075, placeMinimumCentreSeparation / minimumDistance)
    }

    static func scale(for mode: TriangleLockMode, targets: [FormationTarget]) -> Float {
        switch mode {
        case .visualise: visualiseScale
        case .place: placeScale(for: targets)
        }
    }

    static func tolerance(for mode: TriangleLockMode) -> Float {
        switch mode {
        case .visualise: visualiseRingRadius
        case .place: placeTolerance
        }
    }
}

struct ReplayScenario: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let kind: ExperienceKind
    let title: String
    let strapline: String
    let matchContext: String
    let objective: String
    let coachPrompt: String
    let proofPoint: String
    let duration: TimeInterval
    let defaultViewMode: ReplayViewMode
    let defaultPerspectiveID: String
    let featuredPerspectiveIDs: [String]
    let players: [PlayerTrack]
    let ball: BallTrack
    let moments: [CueMoment]
    let coachMarks: [CoachMark]
    let formationTargets: [FormationTarget]

    var homePlayers: [PlayerTrack] { players.filter { $0.team == .home } }
    var awayPlayers: [PlayerTrack] { players.filter { $0.team == .away } }

    func player(id: String) -> PlayerTrack? {
        players.first { $0.id == id }
    }

    func activeMoment(at time: TimeInterval) -> CueMoment? {
        guard time.isFinite else { return nil }
        return moments.reduce(into: Optional<CueMoment>.none) { active, candidate in
            guard candidate.time.isFinite, candidate.time <= time else { return }
            guard let current = active else {
                active = candidate
                return
            }
            if candidate.time > current.time
                || (candidate.time == current.time && candidate.id > current.id) {
                active = candidate
            }
        }
    }
}

struct ReplayGeometry {
    static func interpolateAngle(from start: Float, to end: Float, fraction: Float) -> Float {
        var delta = (end - start).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return start + (delta * min(max(fraction, 0), 1))
    }

    static func distance(_ first: PitchPoint, _ second: PitchPoint) -> Float {
        hypot(second.x - first.x, second.z - first.z)
    }

    static func angle(at vertex: PitchPoint, first: PitchPoint, second: PitchPoint) -> Float {
        let a = atan2(first.z - vertex.z, first.x - vertex.x)
        let b = atan2(second.z - vertex.z, second.x - vertex.x)
        var degrees = abs((b - a) * 180 / .pi)
        if degrees > 180 { degrees = 360 - degrees }
        return degrees
    }

    static func distanceFromSegment(point: PitchPoint, start: PitchPoint, end: PitchPoint) -> Float {
        let dx = end.x - start.x
        let dz = end.z - start.z
        let lengthSquared = (dx * dx) + (dz * dz)
        guard lengthSquared > 0.000_1 else { return distance(point, start) }
        let projection = (((point.x - start.x) * dx) + ((point.z - start.z) * dz)) / lengthSquared
        let fraction = min(max(projection, 0), 1)
        let nearest = PitchPoint(x: start.x + (dx * fraction), z: start.z + (dz * fraction))
        return distance(point, nearest)
    }

    static func laneClearance(from start: PitchPoint, to end: PitchPoint, defenders: [PitchPoint]) -> Float {
        defenders.map { distanceFromSegment(point: $0, start: start, end: end) }.min() ?? .infinity
    }
}
