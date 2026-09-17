import Foundation

enum ExperienceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case squadReplay
    case coachFocus
    case shapeLab
    case passingChannels
    case perspectiveMatrix
    case realWorldReplay

    var id: String { rawValue }

    var number: String {
        switch self {
        case .squadReplay: "01"
        case .coachFocus: "02"
        case .shapeLab: "03"
        case .passingChannels: "04"
        case .perspectiveMatrix: "05"
        case .realWorldReplay: "06"
        }
    }

    var shortLabel: String {
        switch self {
        case .squadReplay: "Match playback"
        case .coachFocus: "Coach focus"
        case .shapeLab: "Shape lab"
        case .passingChannels: "Passing lanes"
        case .perspectiveMatrix: "Perspective matrix"
        case .realWorldReplay: "World replay"
        }
    }

    var systemImage: String {
        switch self {
        case .squadReplay: "person.3.sequence.fill"
        case .coachFocus: "scope"
        case .shapeLab: "triangle"
        case .passingChannels: "arrow.triangle.branch"
        case .perspectiveMatrix: "rectangle.split.2x2"
        case .realWorldReplay: "cube.transparent"
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
        let supportsSmoothPresentation: Bool
        let cumulativeDistances: [Float]
        let cumulativeGaitPhases: [Float]

        init(keyframes: [MotionKeyframe]) {
            var supportsBinaryLookup = true
            var supportsSmoothPresentation = true
            var cumulativeDistances = Array(repeating: Float.zero, count: keyframes.count)
            var cumulativeGaitPhases = Array(repeating: Float.zero, count: keyframes.count)

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
                    if timestamp <= keyframes[previousIndex].time {
                        supportsSmoothPresentation = false
                    }
                    cumulativeDistances[index] = cumulativeDistances[previousIndex]
                        + ReplayGeometry.distance(
                            keyframes[previousIndex].position,
                            keyframes[index].position
                        )
                    cumulativeGaitPhases[index] = cumulativeGaitPhases[previousIndex]
                        + PlayerTrack.gaitPhaseIncrement(
                            from: keyframes[previousIndex],
                            to: keyframes[index]
                        )
                }
            }

            self.supportsBinaryLookup = supportsBinaryLookup
            self.supportsSmoothPresentation = supportsBinaryLookup
                && supportsSmoothPresentation
            self.cumulativeDistances = cumulativeDistances
            self.cumulativeGaitPhases = cumulativeGaitPhases
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

    /// A deterministic render pose that rounds sparse telemetry corners without
    /// rewriting the authoritative keyframes returned by `pose(at:)`.
    ///
    /// Component-wise monotone cubic Hermite interpolation keeps every sample
    /// inside the neighbouring keyframe bounds, while sharing one tangent on
    /// both sides of a knot makes velocity continuous. Dense tracking, seeks,
    /// SharePlay and player-bound annotations therefore resolve to the same
    /// presentation sample without the stop/start velocity of linear segments.
    func presentationPose(at time: TimeInterval) -> PlayerPose {
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

        // Duplicate or malformed timestamps can encode deliberate discontinuity.
        // Preserve the legacy left-continuous sampler instead of inventing a
        // tangent across a zero/negative time span.
        guard samplingIndex.supportsSmoothPresentation else {
            return pose(at: time)
        }

        let endIndex = lowerBoundKeyframeIndex(for: time)
        let startIndex = endIndex - 1
        let start = keyframes[startIndex]
        let end = keyframes[endIndex]
        let span = end.time - start.time
        guard span.isFinite, span > 0 else { return pose(at: time) }

        let fraction = min(max(Float((time - start.time) / span), 0), 1)
        let scaledSpan = Float(span)
        let x = Self.hermite(
            start: start.position.x,
            end: end.position.x,
            startTangent: presentationTangent(at: startIndex, component: .x) * scaledSpan,
            endTangent: presentationTangent(at: endIndex, component: .x) * scaledSpan,
            fraction: fraction
        )
        let z = Self.hermite(
            start: start.position.z,
            end: end.position.z,
            startTangent: presentationTangent(at: startIndex, component: .z) * scaledSpan,
            endTangent: presentationTangent(at: endIndex, component: .z) * scaledSpan,
            fraction: fraction
        )
        let unwrappedFacing = start.facingDegrees + Self.shortestAngleDelta(
            from: start.facingDegrees,
            to: end.facingDegrees
        )
        let facing = Self.hermite(
            start: start.facingDegrees,
            end: unwrappedFacing,
            startTangent: presentationTangent(at: startIndex, component: .facing) * scaledSpan,
            endTangent: presentationTangent(at: endIndex, component: .facing) * scaledSpan,
            fraction: fraction
        )

        guard x.isFinite, z.isFinite, facing.isFinite else { return pose(at: time) }
        return PlayerPose(
            position: PitchPoint(x: x, z: z),
            facingDegrees: facing
        )
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

    /// Seek-stable gait phase integrated from time and segment velocity.
    ///
    /// `motion(at:)` intentionally retains its original distance clock because
    /// it is part of the replay sampling contract. Rendering uses this cadence
    /// clock instead: a walk takes shorter, slower steps while a sprint lengthens
    /// its stride without producing an implausibly frantic leg cycle. The
    /// cumulative index keeps the phase continuous at every keyframe and O(log n)
    /// to sample, even when a dense real-world telemetry track is scrubbed.
    func gaitPhase(at time: TimeInterval) -> Float {
        let phaseOffset = locomotionPhaseOffset
        guard keyframes.count > 1, let first = keyframes.first else {
            return phaseOffset
        }
        guard samplingIndex.supportsBinaryLookup else {
            return motion(at: time).locomotionPhase
        }

        let clampedTime = max(time, first.time)
        guard !clampedTime.isNaN else { return phaseOffset }
        let nextIndex = upperBoundKeyframeIndex(for: clampedTime)
        guard nextIndex < keyframes.count else {
            return (samplingIndex.cumulativeGaitPhases.last ?? 0) + phaseOffset
        }

        let startIndex = nextIndex - 1
        let start = keyframes[startIndex]
        let end = keyframes[nextIndex]
        let duration = end.time - start.time
        guard duration.isFinite, duration > 0 else {
            return samplingIndex.cumulativeGaitPhases[startIndex] + phaseOffset
        }
        let fraction = Float((clampedTime - start.time) / duration)
        let segmentPhase = Self.gaitPhaseIncrement(from: start, to: end)
        return samplingIndex.cumulativeGaitPhases[startIndex]
            + (segmentPhase * min(max(fraction, 0), 1))
            + phaseOffset
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
        let before = presentationPose(at: time - halfWindow)
        let centre = presentationPose(at: time)
        let after = presentationPose(at: time + halfWindow)
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
            // A positive pitch bearing turns +Z towards +X. Use the Y
            // component of the 3D cross product so path and facing turns agree.
            let cross = (incomingZ * outgoingX) - (incomingX * outgoingZ)
            let dot = (incomingX * outgoingX) + (incomingZ * outgoingZ)
            let boundedPathTurn = min(max(atan2(cross, dot) * 180 / .pi / seconds, -360), 360)
            // Direction is poorly constrained during a near-stop. The old
            // 5 mm switch could admit a full ±360°/s cue in one sample. Fade
            // confidence over 5–25 mm of travel in both half-windows instead.
            let confidence = min(max((min(incomingDistance, outgoingDistance) - 0.005) / 0.020, 0), 1)
            // Near idle, small trajectory reversals should not overpower an
            // independently authored body turn. Keep full path anticipation
            // once moving; both confidence joins have zero endpoint slope.
            let moving = min(max((speed - 0.18) / 0.22, 0), 1)
            let movingConfidence = moving * moving * (3 - 2 * moving)
            pathTurn = boundedPathTurn * confidence * confidence * (3 - 2 * confidence) * movingConfidence
        }
        let boundedFacingTurn = min(max(facingTurn, -360), 360)
        let turnRate: Float
        if pathTurn * boundedFacingTurn < 0 {
            // When travel and authored body facing disagree, a hard magnitude
            // winner flips the sign at equal strength. Blend the bounded cues
            // continuously, while retaining their signs and relative strength.
            let pathWeight = pathTurn * pathTurn
            let facingWeight = boundedFacingTurn * boundedFacingTurn
            turnRate = boundedFacingTurn
                + ((pathTurn - boundedFacingTurn) * pathWeight / (pathWeight + facingWeight))
        } else {
            // Same-sign winners join continuously; pure path cuts and turning
            // on the spot therefore retain their previous response exactly.
            turnRate = abs(pathTurn) > abs(boundedFacingTurn) ? pathTurn : boundedFacingTurn
        }

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

    /// A teaching station retains the player's deterministic idle variation,
    /// without copying its track or advancing a running-distance clock.
    var stationaryLocomotion: PlayerLocomotionSample {
        PlayerLocomotionSample(
            motion: PlayerMotionState(
                speedMetresPerSecond: 0,
                distanceTravelled: 0,
                locomotionPhase: locomotionPhaseOffset
            ),
            speedMetresPerSecond: 0,
            accelerationMetresPerSecondSquared: 0,
            turnRateDegreesPerSecond: 0,
            state: .idle
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

    private enum PresentationComponent {
        case x
        case z
        case facing
    }

    private func presentationTangent(
        at index: Int,
        component: PresentationComponent
    ) -> Float {
        guard keyframes.indices.contains(index) else { return 0 }
        if index == keyframes.startIndex {
            return presentationSlope(from: index, to: index + 1, component: component)
        }
        if index == keyframes.index(before: keyframes.endIndex) {
            return presentationSlope(from: index - 1, to: index, component: component)
        }

        let previous = keyframes[index - 1]
        let current = keyframes[index]
        let next = keyframes[index + 1]
        let incomingDuration = current.time - previous.time
        let outgoingDuration = next.time - current.time
        guard incomingDuration.isFinite, outgoingDuration.isFinite,
              incomingDuration > 0, outgoingDuration > 0 else { return 0 }

        let incoming = presentationSlope(
            from: index - 1,
            to: index,
            component: component
        )
        let outgoing = presentationSlope(
            from: index,
            to: index + 1,
            component: component
        )
        guard incoming.isFinite, outgoing.isFinite,
              incoming != 0, outgoing != 0,
              incoming.sign == outgoing.sign else { return 0 }

        // Fritsch-Carlson weighted harmonic mean. It preserves the direction
        // of both adjacent secants and cannot introduce component overshoot.
        let h0 = Float(incomingDuration)
        let h1 = Float(outgoingDuration)
        let w1 = (2 * h1) + h0
        let w2 = h1 + (2 * h0)
        let denominator = (w1 / incoming) + (w2 / outgoing)
        guard denominator.isFinite, abs(denominator) > 0.000_001 else { return 0 }
        return (w1 + w2) / denominator
    }

    private func presentationSlope(
        from startIndex: Int,
        to endIndex: Int,
        component: PresentationComponent
    ) -> Float {
        let start = keyframes[startIndex]
        let end = keyframes[endIndex]
        let duration = end.time - start.time
        guard duration.isFinite, duration > 0 else { return 0 }
        let delta: Float = switch component {
        case .x:
            end.position.x - start.position.x
        case .z:
            end.position.z - start.position.z
        case .facing:
            Self.shortestAngleDelta(from: start.facingDegrees, to: end.facingDegrees)
        }
        return delta / Float(duration)
    }

    private static func hermite(
        start: Float,
        end: Float,
        startTangent: Float,
        endTangent: Float,
        fraction: Float
    ) -> Float {
        let t2 = fraction * fraction
        let t3 = t2 * fraction
        let h00 = (2 * t3) - (3 * t2) + 1
        let h10 = t3 - (2 * t2) + fraction
        let h01 = (-2 * t3) + (3 * t2)
        let h11 = t3 - t2
        return (h00 * start)
            + (h10 * startTangent)
            + (h01 * end)
            + (h11 * endTangent)
    }

    private var locomotionPhaseOffset: Float {
        Float(
            id.utf8.reduce(UInt32(2_166_136_261)) { partial, byte in
                (partial ^ UInt32(byte)) &* 16_777_619
            } % 628
        ) / 100
    }

    private static func gaitPhaseIncrement(
        from start: MotionKeyframe,
        to end: MotionKeyframe
    ) -> Float {
        let duration = end.time - start.time
        guard duration.isFinite, duration > 0 else { return 0 }
        let distance = ReplayGeometry.distance(start.position, end.position)
        guard distance.isFinite, distance > 0.000_1 else { return 0 }
        let speed = distance / Float(duration)
        guard speed.isFinite, speed > 0 else { return 0 }

        // Empirical football cadence envelope: roughly 115 total steps/minute
        // around 1.2 m/s and 180 around 6 m/s. One phase turn is a complete
        // left-to-left gait cycle (two footfalls), hence cycles/second here.
        let boundedSpeed = min(speed, 10)
        let gaitCyclesPerSecond = 0.58 + (0.38 * sqrt(boundedSpeed))
        return Float(duration) * gaitCyclesPerSecond * (2 * .pi)
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
    case arc
    case danger
    case space
    case playerLabel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: "Run"
        case .pass: "Pass"
        case .arc: "Arc"
        case .danger: "Pressure"
        case .space: "Space"
        case .playerLabel: "Player label"
        }
    }

    var systemImage: String {
        switch self {
        case .run: "figure.run"
        case .pass: "arrow.up.right"
        case .arc: "point.topleft.down.to.point.bottomright.curvepath"
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
        case .arc:
            ["Curved run", "Bend around", "Lofted pass", "Overlap", "Curl into space"]
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
    /// Tactical marks may be lifted above the pitch to describe aerial runs,
    /// pressing layers, or a passing window without becoming unbounded scene
    /// content. A nil value in an older replay is exactly ground level.
    static let maximumElevation: Float = 4
    static let elevationStep: Float = 0.25

    static func minimumDistance(for kind: CoachMarkKind) -> Float? {
        switch kind {
        case .run, .pass, .arc, .danger: minimumDirectionalLength
        case .space: minimumZoneRadius
        case .playerLabel: nil
        }
    }

    static func accepts(kind: CoachMarkKind, start: PitchPoint, end: PitchPoint) -> Bool {
        guard let minimum = minimumDistance(for: kind) else { return false }
        return ReplayGeometry.distance(start, end) >= minimum
    }

    static func accepts(elevation: Float?) -> Bool {
        guard let elevation else { return true }
        return elevation.isFinite && (0...maximumElevation).contains(elevation)
    }

    static func clampedElevation(_ elevation: Float) -> Float {
        guard elevation.isFinite else { return 0 }
        return min(max(elevation, 0), maximumElevation)
    }
}

struct CoachMark: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: CoachMarkKind
    let start: PitchPoint
    let end: PitchPoint
    /// Metres above the pitch for each authored endpoint. Optional storage
    /// keeps pre-spatial replay payloads source- and wire-compatible; renderers
    /// consume `resolvedStartElevation` / `resolvedEndElevation` instead.
    let startElevation: Float?
    let endElevation: Float?
    /// Optional for compatibility with reviews saved before curved paths.
    let curve: CoachMarkCurve?
    let label: String
    let revealTime: TimeInterval
    /// Optional end of the annotation's authored moment. Older replay files
    /// omit this value and intentionally retain their cumulative mark behavior.
    let hideTime: TimeInterval?
    let author: String
    /// Stable authored track identity for a player-attached annotation. This is
    /// optional so marks encoded before player labels existed still decode.
    let playerID: String?
    /// Optional telemetry anchors for the two authored pitch points. Each
    /// anchor stores its offset from a stable player track, allowing a run or
    /// pass to stay attached while the replay is scrubbed without serializing
    /// per-frame world transforms. Missing anchors preserve legacy fixed-pitch
    /// annotation behavior.
    let startTrackAnchor: CoachMarkTrackAnchor?
    let endTrackAnchor: CoachMarkTrackAnchor?

    init(
        id: UUID = UUID(),
        kind: CoachMarkKind,
        start: PitchPoint,
        end: PitchPoint,
        startElevation: Float? = nil,
        endElevation: Float? = nil,
        curve: CoachMarkCurve? = nil,
        label: String,
        revealTime: TimeInterval = 0,
        hideTime: TimeInterval? = nil,
        author: String = "Coach",
        playerID: String? = nil,
        startTrackAnchor: CoachMarkTrackAnchor? = nil,
        endTrackAnchor: CoachMarkTrackAnchor? = nil
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.startElevation = startElevation
        self.endElevation = endElevation
        self.curve = curve
        self.label = label
        self.revealTime = revealTime
        self.hideTime = hideTime
        self.author = author
        self.playerID = playerID
        self.startTrackAnchor = startTrackAnchor
        self.endTrackAnchor = endTrackAnchor
    }

    func isVisible(at time: TimeInterval) -> Bool {
        revealTime <= time && (hideTime.map { time < $0 } ?? true)
    }

    var resolvedStartElevation: Float { startElevation ?? 0 }
    var resolvedEndElevation: Float { endElevation ?? 0 }
    var resolvedCurve: CoachMarkCurve { curve ?? .initial(start: start, end: end) }

    var hasSpatialElevation: Bool {
        resolvedStartElevation > 0.001 || resolvedEndElevation > 0.001
    }
}

/// A compact, deterministic attachment between one annotation endpoint and a
/// player's authored telemetry. The pitch-space offset is intentional: a run
/// destination can follow its runner without collapsing onto the player's feet,
/// while a pass endpoint can independently attach to a moving receiver.
struct CoachMarkTrackAnchor: Codable, Hashable, Sendable {
    let playerID: String
    let offset: PitchPoint

    init(playerID: String, offset: PitchPoint = .zero) {
        self.playerID = playerID
        self.offset = offset
    }
}

struct ResolvedCoachMarkGeometry: Hashable, Sendable {
    let start: PitchPoint
    let end: PitchPoint
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

/// One view-specific source for the positions shown on the pitch. Authored
/// telemetry stays unchanged, but an impact may hold a player at its contact
/// point and the ideal-shape view may move a role onto its teaching target.
/// Bodies, identity tags and player-bound annotations must sample this same
/// context instead of independently choosing between those positions.
struct ReplayPlayerPresentation: Sendable {
    let impactCue: PlayerRagdollCue?
    private let idealTargets: [FormationTarget]

    init(
        scenario: ReplayScenario,
        viewMode: ReplayViewMode,
        showsIdealBranch: Bool = false,
        triangleLockMode: TriangleLockMode = .visualise,
        impactCue: PlayerRagdollCue? = nil
    ) {
        if viewMode == .positional {
            self.impactCue = nil
        } else if let impactCue {
            self.impactCue = impactCue
        } else {
            // The default POV remains upright, with headset-controlled free
            // look. A caller must explicitly request an impact in that view.
            self.impactCue = viewMode == .firstPerson
                ? nil
                : PlayerRagdollCue.authoredDemo(for: scenario)
        }
        // Physical placement uses the same teaching targets as the ideal
        // overview. When tracking drops, that overview becomes visible again;
        // annotation input must not jump back to raw telemetry meanwhile.
        idealTargets = viewMode == .positional
            && (showsIdealBranch || triangleLockMode == .place)
            ? scenario.formationTargets
            : []
    }

    func pose(for player: PlayerTrack, at time: TimeInterval) -> PlayerPose {
        let source = player.presentationPose(at: time)
        if let target = idealTargets.first(where: { $0.playerID == player.id }) {
            return PlayerPose(position: target.position, facingDegrees: source.facingDegrees)
        }
        guard let impactCue, impactCue.playerID == player.id,
              impactCue.isActive(at: time) else { return source }
        let contact = player.presentationPose(at: impactCue.impactTime)
        let release = impactCue.telemetryRelease(at: time)
        return PlayerPose(
            position: contact.position.interpolated(to: source.position, fraction: release),
            facingDegrees: ReplayGeometry.interpolateAngle(
                from: contact.facingDegrees, to: source.facingDegrees, fraction: release
            )
        )
    }

    /// Ideal teaching targets stand still and face the displayed ball. Return
    /// nil for normal replay and untargeted defenders so their motion stays raw.
    func stationaryPose(
        for player: PlayerTrack,
        at time: TimeInterval,
        facing target: PitchPoint
    ) -> PlayerPose? {
        guard let station = idealTargets.first(where: { $0.playerID == player.id }) else { return nil }
        let dx = target.x - station.position.x
        let dz = target.z - station.position.z
        let facing = hypot(dx, dz) > 0.05
            ? atan2(dx, dz) * 180 / .pi
            : player.presentationPose(at: time).facingDegrees
        return PlayerPose(position: station.position, facingDegrees: facing)
    }

    func poses(in scenario: ReplayScenario, at time: TimeInterval) -> [String: PlayerPose] {
        Dictionary(uniqueKeysWithValues: scenario.players.map { ($0.id, pose(for: $0, at: time)) })
    }
}

extension CoachMark {
    /// Resolves track-relative endpoints at one replay instant. The result is a
    /// pure function of the shared mark, scenario telemetry and timestamp, so
    /// every participant renders the same geometry after a seek or late join.
    func resolvedGeometry(
        in scenario: ReplayScenario,
        at time: TimeInterval,
        presentedPlayerPoses: [String: PlayerPose]? = nil
    ) -> ResolvedCoachMarkGeometry {
        let sampleTime = time.isFinite
            ? min(max(time, 0), max(scenario.duration, 0))
            : min(max(revealTime, 0), max(scenario.duration, 0))

        func resolve(
            fallback: PitchPoint,
            anchor: CoachMarkTrackAnchor?
        ) -> PitchPoint {
            guard let anchor,
                  let player = scenario.player(id: anchor.playerID) else {
                return fallback
            }
            let playerPosition = presentedPlayerPoses?[player.id]?.position
                ?? player.presentationPose(at: sampleTime).position
            return PitchPoint(
                x: playerPosition.x + anchor.offset.x,
                z: playerPosition.z + anchor.offset.z
            )
        }

        // Legacy player labels already carry one attached identity. Treat that
        // as a zero-offset endpoint anchor so existing files gain the same
        // deterministic resolution path without changing their payload.
        if kind == .playerLabel,
           let playerID,
           let player = scenario.player(id: playerID) {
            let position = presentedPlayerPoses?[player.id]?.position
                ?? player.presentationPose(at: sampleTime).position
            return ResolvedCoachMarkGeometry(start: position, end: position)
        }

        return ResolvedCoachMarkGeometry(
            start: resolve(fallback: start, anchor: startTrackAnchor),
            end: resolve(fallback: end, anchor: endTrackAnchor)
        )
    }

    var followsPlayerTracks: Bool {
        playerID != nil || startTrackAnchor != nil || endTrackAnchor != nil
    }

    var anchoredPlayerIDs: Set<String> {
        var result = Set<String>()
        if let playerID { result.insert(playerID) }
        if let startTrackAnchor { result.insert(startTrackAnchor.playerID) }
        if let endTrackAnchor { result.insert(endTrackAnchor.playerID) }
        return result
    }

    /// Returns a render-only value with current resolved endpoints while
    /// preserving identity, timing and anchor metadata. Shared state continues
    /// to store the compact authored geometry; RealityKit can consume this
    /// value directly with its existing mark cache and hit-target code.
    func resolvingTrackGeometry(
        in scenario: ReplayScenario,
        at time: TimeInterval,
        presentedPlayerPoses: [String: PlayerPose]? = nil
    ) -> CoachMark {
        let geometry = resolvedGeometry(
            in: scenario, at: time, presentedPlayerPoses: presentedPlayerPoses
        )
        guard geometry.start != start || geometry.end != end else { return self }
        return CoachMark(
            id: id,
            kind: kind,
            start: geometry.start,
            end: geometry.end,
            startElevation: startElevation,
            endElevation: endElevation,
            curve: curve,
            label: label,
            revealTime: revealTime,
            hideTime: hideTime,
            author: author,
            playerID: playerID,
            startTrackAnchor: startTrackAnchor,
            endTrackAnchor: endTrackAnchor
        )
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
