import Foundation

/// The upstream system that supplied a replay package. Capture technology and
/// temporal sampling are intentionally separate: an optical sample can still
/// be interpolated, while this app's authored demo is always visibly synthetic.
enum ReplaySourceKind: String, Codable, CaseIterable, Sendable {
    case opticalTracking
    case localPositioning
    case satelliteTracking
    case broadcastReconstruction
    case synthetic

    var shortLabel: String {
        switch self {
        case .opticalTracking: "OPTICAL"
        case .localPositioning: "LPS"
        case .satelliteTracking: "GNSS"
        case .broadcastReconstruction: "RECONSTRUCTED"
        case .synthetic: "SYNTHETIC"
        }
    }
}

/// How the pose at the review timestamp relates to samples in the source feed.
enum ReplaySampleClassification: String, Codable, CaseIterable, Sendable {
    case observed
    case interpolated
    case inferred

    fileprivate var uncertaintyRank: Int {
        switch self {
        case .observed: 0
        case .interpolated: 1
        case .inferred: 2
        }
    }
}

/// Provenance travels with every decision snapshot. Confidence is optional by
/// design: Replay XI must not invent a percentage when a provider has not
/// supplied and scoped one.
struct ReplayDataProvenance: Codable, Hashable, Sendable {
    let providerName: String
    let pipelineVersion: String
    let sourceKind: ReplaySourceKind
    let declaredConfidence: Float?
    let confidenceScope: String?

    init(
        providerName: String,
        pipelineVersion: String,
        sourceKind: ReplaySourceKind,
        declaredConfidence: Float? = nil,
        confidenceScope: String? = nil
    ) {
        let trimmedProvider = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVersion = pipelineVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.providerName = trimmedProvider.isEmpty ? "Unknown provider" : trimmedProvider
        self.pipelineVersion = trimmedVersion.isEmpty ? "Unversioned" : trimmedVersion
        self.sourceKind = sourceKind
        if let declaredConfidence, declaredConfidence.isFinite {
            self.declaredConfidence = min(max(declaredConfidence, 0), 1)
        } else {
            self.declaredConfidence = nil
        }
        let trimmedScope = confidenceScope?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.confidenceScope = trimmedScope?.isEmpty == false ? trimmedScope : nil
    }

    static let syntheticDemo = ReplayDataProvenance(
        providerName: "Replay XI",
        pipelineVersion: "demo-sequence-1",
        sourceKind: .synthetic,
        confidenceScope: "Synthetic sequence; capture accuracy is not applicable"
    )

    var confidenceLabel: String {
        if sourceKind == .synthetic {
            return "SYNTHETIC • CONFIDENCE N/A"
        }
        guard let declaredConfidence else {
            return "\(sourceKind.shortLabel) • CONFIDENCE UNAVAILABLE"
        }
        return "\(sourceKind.shortLabel) • \(Int((declaredConfidence * 100).rounded()))%"
    }
}

struct ReplayDecisionEvidence: Codable, Hashable, Sendable {
    let provenance: ReplayDataProvenance
    let sampleClassification: ReplaySampleClassification

    var compactLabel: String {
        "\(provenance.sourceKind.shortLabel) • \(sampleClassification.rawValue.uppercased())"
    }
}

/// A bounded period before the freeze frame. `bodyTurnDegrees` and the context
/// IDs are derived from the authored body-facing track; neither claims to
/// represent eye gaze, head rotation, perception, or memory.
struct ReplayDecisionScanWindow: Codable, Hashable, Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let activeCueID: String?
    let bodyTurnDegrees: Float
    let bodyFacingContextPlayerIDs: [String]

    var duration: TimeInterval { max(0, endTime - startTime) }

    static let evidenceLabel = "BODY ORIENTATION PROXY • NO GAZE DATA"
}

struct ReplayReceivingOrientation: Codable, Hashable, Sendable {
    let sampleTime: TimeInterval
    let ballDistanceMetres: Float
    let facingToBallDegrees: Float
    let facingToAttackingDirectionDegrees: Float
    let ballToAttackingDirectionDegrees: Float
    let isWithinControlRadius: Bool

    static let evidenceLabel = "BODY FACING, NOT RECORDED HEAD OR EYE DIRECTION"
}

enum ReplayLaneAvailability: String, Codable, CaseIterable, Sendable {
    case blocked
    case tight
    case clear
}

enum ReplayDecisionOptionRole: String, Codable, CaseIterable, Sendable {
    /// The receiver nearest the replayed ball at the bounded look-ahead time.
    case replayedDestination
    /// An explicitly authored coach instruction, never an automatic verdict.
    case coachSuggestion
    /// A geometric comparison offered without a tactical recommendation.
    case descriptiveAlternative
}

struct ReplayPassingLaneOption: Identifiable, Codable, Hashable, Sendable {
    var id: String { receiverID }

    let receiverID: String
    let passDistanceMetres: Float
    let laneClearanceMetres: Float?
    let targetPressureMetres: Float?
    let nearestLaneDefenderID: String?
    let availability: ReplayLaneAvailability
    let roles: [ReplayDecisionOptionRole]

    var isReplayedDestination: Bool { roles.contains(.replayedDestination) }
    var isCoachSuggestion: Bool { roles.contains(.coachSuggestion) }

    static let metricLabel = "DESCRIPTIVE SPACING AT THIS TIMESTAMP"
}

struct ReplayObservedDestination: Codable, Hashable, Sendable {
    let receiverID: String
    let sampleTime: TimeInterval
    let ballSeparationMetres: Float

    static let evidenceLabel = "REPLAYED BALL DESTINATION"
}

struct ReplayCoachSuggestion: Codable, Hashable, Sendable {
    enum Origin: String, Codable, Sendable {
        case coachAnnotation
        case explicitInput
    }

    let receiverID: String
    let label: String
    let author: String
    let origin: Origin
    let coachMarkID: UUID?

    init(
        receiverID: String,
        label: String,
        author: String = "Coach",
        origin: Origin = .explicitInput,
        coachMarkID: UUID? = nil
    ) {
        self.receiverID = receiverID
        self.label = label
        self.author = author
        self.origin = origin
        self.coachMarkID = coachMarkID
    }

    static let evidenceLabel = "COACH AUTHORED • NOT AN OBSERVED FACT"
}

struct ReplayDecisionSnapshot: Codable, Hashable, Sendable {
    let scenarioID: String
    let playerID: String
    let time: TimeInterval
    let cue: CueMoment?
    let scanWindow: ReplayDecisionScanWindow
    let receivingOrientation: ReplayReceivingOrientation
    let passingOptions: [ReplayPassingLaneOption]
    let observedDestination: ReplayObservedDestination?
    let coachSuggestion: ReplayCoachSuggestion?
    let evidence: ReplayDecisionEvidence

    var replayedOption: ReplayPassingLaneOption? {
        passingOptions.first(where: \.isReplayedDestination)
    }

    var coachSuggestedOption: ReplayPassingLaneOption? {
        passingOptions.first(where: \.isCoachSuggestion)
    }
}

/// Thresholds describe a visualization heuristic, not pass quality or tactical
/// correctness. Keeping them explicit lets analysts tune a future package
/// without changing the deterministic calculation.
struct ReplayDecisionConfiguration: Codable, Hashable, Sendable {
    var scanWindowDuration: TimeInterval = 3
    var scanSampleCount: Int = 9
    var bodyFacingHalfAngleDegrees: Float = 65
    var contextDistanceMetres: Float = 35
    var outcomeLookAhead: TimeInterval = 3
    var possessionRadiusMetres: Float = 2
    var destinationRadiusMetres: Float = 3
    var coachMarkStartRadiusMetres: Float = 4
    var coachMarkTargetRadiusMetres: Float = 5
    var maximumPassDistanceMetres: Float = 40
    var maximumOptions: Int = 4
    var blockedLaneClearanceMetres: Float = 0.8
    var tightLaneClearanceMetres: Float = 1.8

    static let standard = ReplayDecisionConfiguration()
}

/// Pure, seek-stable analysis over the existing replay tracks. It intentionally
/// reports geometry and replay evidence rather than assigning a player grade or
/// claiming that one pass was correct.
enum ReplayDecisionReview {
    static func snapshot(
        scenario: ReplayScenario,
        at requestedTime: TimeInterval,
        playerID: String,
        provenance: ReplayDataProvenance = .syntheticDemo,
        coachSuggestion explicitSuggestion: ReplayCoachSuggestion? = nil,
        currentMarks: [CoachMark]? = nil,
        configuration: ReplayDecisionConfiguration = .standard
    ) -> ReplayDecisionSnapshot? {
        guard requestedTime.isFinite,
              scenario.duration.isFinite,
              scenario.duration >= 0,
              let subject = scenario.player(id: playerID)
        else { return nil }

        let time = min(max(requestedTime, 0), scenario.duration)
        let cue = scenario.activeMoment(at: time)
        let scanWindow = makeScanWindow(
            scenario: scenario,
            subject: subject,
            time: time,
            cue: cue,
            configuration: configuration
        )
        let orientation = makeReceivingOrientation(
            scenario: scenario,
            subject: subject,
            time: time,
            controlRadius: configuration.possessionRadiusMetres
        )
        let observedDestination = makeObservedDestination(
            scenario: scenario,
            subject: subject,
            time: time,
            configuration: configuration
        )
        let suggestion = validatedSuggestion(
            explicitSuggestion,
            scenario: scenario,
            subject: subject
        ) ?? suggestionFromCoachMark(
            scenario: scenario,
            subject: subject,
            time: time,
            marks: currentMarks ?? scenario.coachMarks,
            configuration: configuration
        )
        let options = makePassingOptions(
            scenario: scenario,
            subject: subject,
            time: time,
            observedDestination: observedDestination,
            coachSuggestion: suggestion,
            configuration: configuration
        )
        let evidence = ReplayDecisionEvidence(
            provenance: provenance,
            sampleClassification: aggregateSampleClassification(
                scenario: scenario,
                at: time
            )
        )

        return ReplayDecisionSnapshot(
            scenarioID: scenario.id,
            playerID: playerID,
            time: time,
            cue: cue,
            scanWindow: scanWindow,
            receivingOrientation: orientation,
            passingOptions: options,
            observedDestination: observedDestination,
            coachSuggestion: suggestion,
            evidence: evidence
        )
    }

    private static func makeScanWindow(
        scenario: ReplayScenario,
        subject: PlayerTrack,
        time: TimeInterval,
        cue: CueMoment?,
        configuration: ReplayDecisionConfiguration
    ) -> ReplayDecisionScanWindow {
        let boundedDuration = finiteNonnegative(configuration.scanWindowDuration)
        let priorCueTime = scenario.moments
            .filter { $0.time.isFinite && $0.time < (cue?.time ?? time) }
            .map(\.time)
            .max()
        let lowerBound = max(0, time - boundedDuration)
        let startTime = max(lowerBound, min(priorCueTime ?? lowerBound, time))
        let sampleCount = min(max(configuration.scanSampleCount, 2), 64)
        let sampleTimes = (0..<sampleCount).map { index in
            let fraction = Double(index) / Double(sampleCount - 1)
            return startTime + ((time - startTime) * fraction)
        }

        var bodyTurnDegrees: Float = 0
        var previousFacing: Float?
        var contextIDs = Set<String>()
        let halfAngle = min(max(finiteNonnegative(configuration.bodyFacingHalfAngleDegrees), 0), 180)
        let contextDistance = finiteNonnegative(configuration.contextDistanceMetres)

        for sampleTime in sampleTimes {
            let pose = subject.presentationPose(at: sampleTime)
            if let previousFacing {
                bodyTurnDegrees += absoluteAngleDifference(previousFacing, pose.facingDegrees)
            }
            previousFacing = pose.facingDegrees

            for player in scenario.players where player.id != subject.id {
                let target = player.presentationPose(at: sampleTime).position
                guard ReplayGeometry.distance(pose.position, target) <= contextDistance else { continue }
                let bearing = heading(from: pose.position, to: target, fallback: pose.facingDegrees)
                if absoluteAngleDifference(pose.facingDegrees, bearing) <= halfAngle {
                    contextIDs.insert(player.id)
                }
            }
        }

        let endPosition = subject.presentationPose(at: time).position
        let sortedContextIDs = contextIDs.sorted { lhs, rhs in
            let leftDistance = scenario.player(id: lhs).map {
                ReplayGeometry.distance(endPosition, $0.presentationPose(at: time).position)
            } ?? .greatestFiniteMagnitude
            let rightDistance = scenario.player(id: rhs).map {
                ReplayGeometry.distance(endPosition, $0.presentationPose(at: time).position)
            } ?? .greatestFiniteMagnitude
            if leftDistance == rightDistance { return lhs < rhs }
            return leftDistance < rightDistance
        }

        return ReplayDecisionScanWindow(
            startTime: startTime,
            endTime: time,
            activeCueID: cue?.id,
            bodyTurnDegrees: bodyTurnDegrees,
            bodyFacingContextPlayerIDs: sortedContextIDs
        )
    }

    private static func makeReceivingOrientation(
        scenario: ReplayScenario,
        subject: PlayerTrack,
        time: TimeInterval,
        controlRadius: Float
    ) -> ReplayReceivingOrientation {
        let playerPose = subject.presentationPose(at: time)
        let ballPose = scenario.ball.pose(at: time)
        let ballDistance = ReplayGeometry.distance(playerPose.position, ballPose.position)
        let ballBearing = heading(
            from: playerPose.position,
            to: ballPose.position,
            fallback: playerPose.facingDegrees
        )
        let attackHeading: Float = subject.team == .home ? 0 : 180

        return ReplayReceivingOrientation(
            sampleTime: time,
            ballDistanceMetres: ballDistance,
            facingToBallDegrees: absoluteAngleDifference(playerPose.facingDegrees, ballBearing),
            facingToAttackingDirectionDegrees: absoluteAngleDifference(
                playerPose.facingDegrees,
                attackHeading
            ),
            ballToAttackingDirectionDegrees: absoluteAngleDifference(ballBearing, attackHeading),
            isWithinControlRadius: ballDistance <= finiteNonnegative(controlRadius)
        )
    }

    private static func makeObservedDestination(
        scenario: ReplayScenario,
        subject: PlayerTrack,
        time: TimeInterval,
        configuration: ReplayDecisionConfiguration
    ) -> ReplayObservedDestination? {
        let playerPosition = subject.presentationPose(at: time).position
        let ballPosition = scenario.ball.pose(at: time).position
        guard ReplayGeometry.distance(playerPosition, ballPosition)
            <= finiteNonnegative(configuration.possessionRadiusMetres)
        else { return nil }

        let sampleTime = min(
            scenario.duration,
            time + finiteNonnegative(configuration.outcomeLookAhead)
        )
        let futureBall = scenario.ball.pose(at: sampleTime).position
        // Consider every body, including the source player and opposition. A
        // retained ball or interception must not be mislabeled as a completed
        // pass merely because a teammate happens to be within the radius.
        let candidate = scenario.players
            .map { player in
                (
                    player: player,
                    separation: ReplayGeometry.distance(
                        player.presentationPose(at: sampleTime).position,
                        futureBall
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.separation == rhs.separation { return lhs.player.id < rhs.player.id }
                return lhs.separation < rhs.separation
            }
            .first

        guard let candidate,
              candidate.player.id != subject.id,
              candidate.player.team == subject.team,
              candidate.separation <= finiteNonnegative(configuration.destinationRadiusMetres)
        else { return nil }
        return ReplayObservedDestination(
            receiverID: candidate.player.id,
            sampleTime: sampleTime,
            ballSeparationMetres: candidate.separation
        )
    }

    private static func validatedSuggestion(
        _ suggestion: ReplayCoachSuggestion?,
        scenario: ReplayScenario,
        subject: PlayerTrack
    ) -> ReplayCoachSuggestion? {
        guard let suggestion,
              let receiver = scenario.player(id: suggestion.receiverID),
              receiver.team == subject.team,
              receiver.id != subject.id
        else { return nil }
        return suggestion
    }

    private static func suggestionFromCoachMark(
        scenario: ReplayScenario,
        subject: PlayerTrack,
        time: TimeInterval,
        marks: [CoachMark],
        configuration: ReplayDecisionConfiguration
    ) -> ReplayCoachSuggestion? {
        let startRadius = finiteNonnegative(configuration.coachMarkStartRadiusMetres)
        let targetRadius = finiteNonnegative(configuration.coachMarkTargetRadiusMetres)
        let eligibleMarks = marks
            .filter { mark in
                guard mark.kind == .pass,
                      mark.revealTime.isFinite,
                      mark.revealTime <= time,
                      mark.isVisible(at: time)
                else { return false }
                let sourceAtReveal = subject.presentationPose(at: mark.revealTime).position
                let markAtReveal = mark.resolvedGeometry(
                    in: scenario,
                    at: mark.revealTime
                )
                return ReplayGeometry.distance(sourceAtReveal, markAtReveal.start) <= startRadius
            }
            .sorted { lhs, rhs in
                if lhs.revealTime == rhs.revealTime { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.revealTime > rhs.revealTime
            }

        guard let mark = eligibleMarks.first else { return nil }
        let targetTime = min(
            scenario.duration,
            mark.revealTime + finiteNonnegative(configuration.outcomeLookAhead)
        )
        let target = mark.resolvedGeometry(in: scenario, at: targetTime).end
        let receiver = scenario.players
            .filter { $0.team == subject.team && $0.id != subject.id }
            .map { player in
                (
                    player: player,
                    separation: ReplayGeometry.distance(
                        player.presentationPose(at: targetTime).position,
                        target
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.separation == rhs.separation { return lhs.player.id < rhs.player.id }
                return lhs.separation < rhs.separation
            }
            .first

        guard let receiver, receiver.separation <= targetRadius else { return nil }
        return ReplayCoachSuggestion(
            receiverID: receiver.player.id,
            label: mark.label,
            author: mark.author,
            origin: .coachAnnotation,
            coachMarkID: mark.id
        )
    }

    private static func makePassingOptions(
        scenario: ReplayScenario,
        subject: PlayerTrack,
        time: TimeInterval,
        observedDestination: ReplayObservedDestination?,
        coachSuggestion: ReplayCoachSuggestion?,
        configuration: ReplayDecisionConfiguration
    ) -> [ReplayPassingLaneOption] {
        let start = subject.presentationPose(at: time).position
        let defenders = scenario.players
            .filter { $0.team != subject.team }
            .map { player in
                (id: player.id, position: player.presentationPose(at: time).position)
            }
        let forcedIDs = Set([
            observedDestination?.receiverID,
            coachSuggestion?.receiverID
        ].compactMap { $0 })
        let maximumDistance = finiteNonnegative(configuration.maximumPassDistanceMetres)

        let candidates = scenario.players.filter { player in
            guard player.team == subject.team, player.id != subject.id else { return false }
            let distance = ReplayGeometry.distance(
                start,
                player.presentationPose(at: time).position
            )
            return forcedIDs.contains(player.id) || distance <= maximumDistance
        }

        let options = candidates.map { player -> ReplayPassingLaneOption in
            let end = player.presentationPose(at: time).position
            let passDistance = ReplayGeometry.distance(start, end)
            let nearestLaneDefender = defenders
                .map { defender in
                    (
                        id: defender.id,
                        clearance: ReplayGeometry.distanceFromSegment(
                            point: defender.position,
                            start: start,
                            end: end
                        )
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.clearance == rhs.clearance { return lhs.id < rhs.id }
                    return lhs.clearance < rhs.clearance
                }
                .first
            let targetPressure = defenders
                .map { ReplayGeometry.distance($0.position, end) }
                .min()
            let effectiveClearance = min(
                nearestLaneDefender?.clearance ?? .greatestFiniteMagnitude,
                targetPressure ?? .greatestFiniteMagnitude
            )
            let availability: ReplayLaneAvailability
            let blockedThreshold = finiteNonnegative(
                configuration.blockedLaneClearanceMetres
            )
            let tightThreshold = max(
                blockedThreshold,
                finiteNonnegative(configuration.tightLaneClearanceMetres)
            )
            if effectiveClearance < blockedThreshold {
                availability = .blocked
            } else if effectiveClearance < tightThreshold {
                availability = .tight
            } else {
                availability = .clear
            }

            var roles: [ReplayDecisionOptionRole] = []
            if observedDestination?.receiverID == player.id { roles.append(.replayedDestination) }
            if coachSuggestion?.receiverID == player.id { roles.append(.coachSuggestion) }
            if roles.isEmpty { roles.append(.descriptiveAlternative) }

            return ReplayPassingLaneOption(
                receiverID: player.id,
                passDistanceMetres: passDistance,
                laneClearanceMetres: nearestLaneDefender?.clearance,
                targetPressureMetres: targetPressure,
                nearestLaneDefenderID: nearestLaneDefender?.id,
                availability: availability,
                roles: roles
            )
        }

        let maximumOptions = min(max(configuration.maximumOptions, forcedIDs.count), 11)
        return options.sorted { lhs, rhs in
            let leftPriority = optionPriority(lhs)
            let rightPriority = optionPriority(rhs)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            if lhs.passDistanceMetres != rhs.passDistanceMetres {
                return lhs.passDistanceMetres < rhs.passDistanceMetres
            }
            return lhs.receiverID < rhs.receiverID
        }
        .prefix(maximumOptions)
        .map { $0 }
    }

    private static func optionPriority(_ option: ReplayPassingLaneOption) -> Int {
        if option.isReplayedDestination { return 0 }
        if option.isCoachSuggestion { return 1 }
        return 2
    }

    private static func aggregateSampleClassification(
        scenario: ReplayScenario,
        at time: TimeInterval
    ) -> ReplaySampleClassification {
        var classifications = scenario.players.map { player in
            sampleClassification(player.keyframes.map(\.time), at: time)
        }
        classifications.append(sampleClassification(scenario.ball.keyframes.map(\.time), at: time))
        return classifications.max { lhs, rhs in
            lhs.uncertaintyRank < rhs.uncertaintyRank
        } ?? .inferred
    }

    private static func sampleClassification(
        _ sampleTimes: [TimeInterval],
        at time: TimeInterval
    ) -> ReplaySampleClassification {
        let finiteTimes = sampleTimes.filter(\.isFinite)
        guard let first = finiteTimes.min(), let last = finiteTimes.max() else { return .inferred }
        guard time >= first, time <= last else { return .inferred }
        if finiteTimes.contains(where: { abs($0 - time) <= 0.000_001 }) {
            return .observed
        }
        return .interpolated
    }

    private static func heading(
        from start: PitchPoint,
        to end: PitchPoint,
        fallback: Float
    ) -> Float {
        let deltaX = end.x - start.x
        let deltaZ = end.z - start.z
        guard abs(deltaX) + abs(deltaZ) > 0.000_1 else { return fallback }
        return atan2(deltaX, deltaZ) * 180 / .pi
    }

    private static func absoluteAngleDifference(_ first: Float, _ second: Float) -> Float {
        var delta = (second - first).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return abs(delta)
    }

    private static func finiteNonnegative<T: BinaryFloatingPoint>(_ value: T) -> T {
        value.isFinite ? max(0, value) : 0
    }
}

extension ReplayScenario {
    /// Convenience surface for the playback UI. Ingested packages should pass
    /// their own provenance rather than accepting the synthetic demo default.
    /// Pass the store's live mark collection to include shared annotations;
    /// `nil` preserves the scenario marks, while `[]` explicitly clears them.
    func decisionReview(
        at time: TimeInterval,
        playerID: String,
        provenance: ReplayDataProvenance = .syntheticDemo,
        coachSuggestion: ReplayCoachSuggestion? = nil,
        currentMarks: [CoachMark]? = nil,
        configuration: ReplayDecisionConfiguration = .standard
    ) -> ReplayDecisionSnapshot? {
        ReplayDecisionReview.snapshot(
            scenario: self,
            at: time,
            playerID: playerID,
            provenance: provenance,
            coachSuggestion: coachSuggestion,
            currentMarks: currentMarks,
            configuration: configuration
        )
    }
}
