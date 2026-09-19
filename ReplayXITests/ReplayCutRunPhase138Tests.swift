import CoreGraphics
import CryptoKit
import RealityKit
import UIKit
import XCTest
import simd
@testable import ReplayXI

private final class Cut138RenderCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    func complete() { lock.withLock { finished = true } }
    var isComplete: Bool { lock.withLock { finished } }
}

/// Authored animation diagnostics, not recovered real-match contact data.
/// The imported asset has no force/contact events: its floor/backward sweep
/// is reported separately from the procedural gait's explicit load signal.
@MainActor
final class ReplayCutRunPhase138Tests: XCTestCase {
    private struct Context {
        let scenario: ReplayScenario
        let track: PlayerTrack
        let recording: ReplayNativeBallPhysics.Recording
        let cues: [ReplayAthleteInteractionCue]

        func cue(at time: Double) -> ReplayAthleteInteractionCue? {
            cues.filter { ReplayAthleteMovementIntent.includesPreparation($0, at: time) }
                .min { abs($0.contactTime - time) < abs($1.contactTime - time) }
        }
    }

    private struct SourceFoot {
        let sole: SIMD3<Float>
        let derivativePerRadian: SIMD3<Float>
        let authored: ReplayAthleteFootfall
    }

    override func tearDown() {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    private func context(_ scenario: ReplayScenario, _ track: PlayerTrack) async throws -> Context {
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball,
            players: scenario.players, plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        let cues = try recording.touches.filter { $0.playerID == track.id }.map {
            ReplayAthleteInteractionCue(playerID: track.id,
                kind: try XCTUnwrap(ReplayAthleteInteractionCue.Kind(rawValue: $0.kind.rawValue)),
                contactTime: $0.time, startTime: $0.time - 0.32, endTime: $0.time + 0.42,
                kickingLeg: $0.kickingLeg, contactBallWorldPosition: $0.position,
                outgoingDirectionWorld: $0.outgoingVelocity, headerSupportLeg: $0.headerSupportLeg)
        }
        return .init(scenario: scenario, track: track, recording: recording, cues: cues)
    }

    private func sole(_ side: String, motion: ReplaySkinnedAthleteMotion,
                      pose: ReplaySkinnedAthleteMotion.Pose) throws -> SIMD3<Float> {
        let contact = try XCTUnwrap(motion.footContacts[side])
        let point = pose.modelSpaceTransforms[contact.footJointIndex] * SIMD4(contact.solePoint, 1)
        return [point.x, point.y - motion.geometry.restMinY, point.z]
    }

    private func sourceFeet(motion: ReplaySkinnedAthleteMotion, phase: Float,
                            locomotion: PlayerLocomotionSample) throws -> [String: SourceFoot] {
        var centre = motion.makePoseBuffer(), before = centre, after = centre
        let delta: Float = 0.001
        motion.sample(time: 0, locomotionEffort: 1, gaitPhase: phase, into: &centre)
        motion.sample(time: 0, locomotionEffort: 1, gaitPhase: phase - delta, into: &before)
        motion.sample(time: 0, locomotionEffort: 1, gaitPhase: phase + delta, into: &after)
        var result: [String: SourceFoot] = [:]
        for side in ["left", "right"] {
            let hip = try XCTUnwrap(motion.semanticJointIndices[side + "Hip"])
            let root = try XCTUnwrap(motion.semanticJointIndices["hips"])
            // Retargeter chooses lanes by rest X, not semantic source names.
            // This asset's semantic right boot is procedural negative-X/left.
            let negativeLane = motion.restPose.modelSpaceTransforms[hip].columns.3.x
                < motion.restPose.modelSpaceTransforms[root].columns.3.x
            let footfall = ReplayAthleteMotion.footfall(for: locomotion,
                phase: phase + (negativeLane ? 0 : .pi))
            result[side] = .init(sole: try sole(side, motion: motion, pose: centre),
                derivativePerRadian: try (sole(side, motion: motion, pose: after)
                    - sole(side, motion: motion, pose: before)) / (2 * delta), authored: footfall)
        }
        return result
    }

    private func update(_ skin: ReplaySkinnedAthleteInstance, context: Context, time: Double) -> PlayerPose {
        let presented = context.track.presentationPose(at: time)
        let poses = Dictionary(uniqueKeysWithValues: context.scenario.players.map {
            ($0.id, $0.presentationPose(at: time))
        })
        let look = ReplayAthleteTacticalAttention.target(for: context.track, at: time, pose: presented,
            ball: context.recording.sample(at: time).position, players: context.scenario.players,
            poses: poses, contacts: context.cues)
        XCTAssertTrue(skin.update(at: time, track: context.track,
            locomotion: context.track.locomotion(at: time), lookTarget: look,
            ballAction: nil, interaction: context.cue(at: time), presentationPose: presented))
        return presented
    }

    func testIndependentAssetPhaseConflictAndExactContinuousSupportBaseline() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-36-counter-v2" })
        let track = try XCTUnwrap(scenario.player(id: "fra-22"))
        let skin = try ReplaySkinnedAthleteProvider.make(for: track)
        let time = 6.875, phase = track.gaitPhase(at: time), locomotion = track.locomotion(at: time)
        let feet = try sourceFeet(motion: skin.motion, phase: phase, locomotion: locomotion)
        let right = try XCTUnwrap(feet["right"])
        // Independent raw asset vs authored clock evidence. Future alignment
        // must not erase this baseline by redefining source support as height.
        XCTAssertGreaterThan(right.sole.y, 0.18)
        XCTAssertGreaterThan(right.derivativePerRadian.z, 0.4)
        XCTAssertTrue(right.authored.isStance)
        XCTAssertGreaterThan(right.authored.contactWeight, 0.95)
        let influence = ReplaySkinnedAthleteFootballPose.influence(locomotion: locomotion, ballAction: nil)
        XCTAssertGreaterThan(influence, 0.50)
        XCTAssertLessThan(influence, 0.65)
        var rows: [[String: Any]] = [["time": time, "phase": phase,
            "speed": locomotion.speedMetresPerSecond, "turnRate": locomotion.turnRateDegreesPerSecond,
            "cutWeight": influence, "sourceRight": vector(right.sole),
            "sourceRightDerivativePerRadian": vector(right.derivativePerRadian),
            "authoredRightLoad": right.authored.contactWeight]]
        for index in 0...360 {
            let phase = Float(index) * 2 * .pi / 360
            for (side, foot) in try sourceFeet(motion: skin.motion, phase: phase, locomotion: locomotion) {
                rows.append(["curve": true, "side": side, "phase": phase,
                    "sourceSole": vector(foot.sole), "sourceDerivativePerRadian": vector(foot.derivativePerRadian),
                    "authoredLoad": foot.authored.contactWeight, "authoredStance": foot.authored.isStance])
            }
        }
        try receipt(rows, name: "IndependentPhaseConflict")
    }

    func testActualCutReleaseAndProtectedContactNearLowFloorBonesAndRewind() async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        var rows: [[String: Any]] = []
        for (id, player, start, end) in [
            ("final-36-counter-v2", "fra-22", 6.80, 7.15),
            ("final-108-rebound-v2", "arg-10", 1.20, 1.65)
        ] {
            let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == id })
            let track = try XCTUnwrap(scenario.player(id: player))
            let context = try await context(scenario, track)
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
                try measure(skin, context: context, start: start, end: end, rows: &rows)
            }
        }
        try receipt(rows, name: "ActualCutReleaseAndContact")
    }

    func testAllFiveBothTeamPartialCutSourceSupportScanAndNativeWorstWindows() async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        var rows: [[String: Any]] = []
        var visitedTeams = Set<FootballTeam>()
        for scenario in FootballReferenceScenarios.all {
            let contacts = Set((FootballReferenceScenarios.touches(for: scenario) ?? []).map(\.playerID))
            for team in FootballTeam.allCases {
                var worst: (track: PlayerTrack, time: Double, score: Float)?
                var samples = 0, conflicts = 0
                var maxHeight: Float = 0
                for track in scenario.players where track.team == team && !track.isGoalkeeper && !contacts.contains(track.id) {
                    let skin = try ReplaySkinnedAthleteProvider.make(for: track)
                    for index in 0...Int(scenario.duration * 30) {
                        let time = Double(index) / 30
                        let locomotion = track.locomotion(at: time)
                        let weight = ReplaySkinnedAthleteFootballPose.influence(locomotion: locomotion, ballAction: nil)
                        guard locomotion.speedMetresPerSecond > 3.8, weight > 0.05, weight < 0.95 else { continue }
                        samples += 1
                        let feet = try sourceFeet(motion: skin.motion, phase: track.gaitPhase(at: time), locomotion: locomotion)
                        for foot in feet.values where foot.authored.contactWeight > 0.8 {
                            maxHeight = max(maxHeight, foot.sole.y)
                            if foot.sole.y > 0.10 { conflicts += 1 }
                            let score = foot.authored.contactWeight * foot.sole.y * (1 - abs(weight * 2 - 1))
                            if worst == nil || score > worst!.score { worst = (track, time, score) }
                        }
                    }
                }
                visitedTeams.insert(team)
                var summary: [String: Any] = ["scanSummary": true, "scenario": scenario.id, "team": team.rawValue,
                    "partialCutSamples30Hz": samples, "loadedAuthoredSourceAbove10cm": conflicts,
                    "maxSourceHeightDuringAuthoredLoad": maxHeight]
                if let worst {
                    summary["worstPlayer"] = worst.track.id; summary["worstTime"] = worst.time
                    let context = try await context(scenario, worst.track)
                    for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                        let skin = try ReplaySkinnedAthleteProvider.make(for: worst.track, detail: detail)
                        try measure(skin, context: context,
                            start: max(0, worst.time - 0.075), end: min(scenario.duration, worst.time + 0.075), rows: &rows)
                    }
                }
                rows.append(summary)
            }
        }
        XCTAssertEqual(visitedTeams, Set(FootballTeam.allCases))
        XCTAssertEqual(rows.filter { $0["scanSummary"] as? Bool == true }.count, 10)
        try receipt(rows, name: "AllFiveBothTeams")
    }

    private func measure(_ skin: ReplaySkinnedAthleteInstance, context: Context,
                         start: Double, end: Double, rows: inout [[String: Any]]) throws {
        let track = context.track
        let legacy = try ReplaySkinnedAthleteProvider.make(for: track, detail: skin.detail)
        legacy.disablesCutPhaseAlignmentForTesting = true
        let times = stride(from: start, through: end + 0.00001, by: 1.0 / 120).map { $0 }
        var saved: [[Transform]] = [], previousFeet: [String: SIMD3<Float>] = [:]
        var legacySaved: [[Transform]] = [], legacyPreviousFeet: [String: SIMD3<Float>] = [:]
        var fingerprint = SHA256(), legacyFingerprint = SHA256()
        var maxBoneError: Float = 0, maxJointStep: Float = 0, minFloor = Float.infinity
        var legacyMaxJointStep: Float = 0, maximumSoleSpeed: Float = 0, legacyMaximumSoleSpeed: Float = 0
        var coreSamples = 0
        for time in times {
            let locomotion = track.locomotion(at: time), phase = track.gaitPhase(at: time)
            let presented = update(skin, context: context, time: time)
            _ = update(legacy, context: context, time: time)
            let feet = try sourceFeet(motion: skin.motion, phase: phase, locomotion: locomotion)
            let alignedFeet = try sourceFeet(motion: skin.motion,
                phase: phase - ReplaySkinnedAthleteCutPhase.offset, locomotion: locomotion)
            let movement = ReplayAthleteMovementIntent.sample(track: track, at: time,
                presentationPose: presented, lookTarget: context.recording.sample(at: time).position,
                interaction: context.cue(at: time))
            let interaction = ReplayAthleteInteractionPose.sample(cue: context.cue(at: time), at: time,
                track: track, presentationPose: presented)
            let cut = ReplaySkinnedAthleteFootballPose.influence(locomotion: locomotion, ballAction: nil)
            let actualInfluence = max(cut, movement?.influence ?? 0, interaction?.influence ?? 0)
            let alignment = ReplaySkinnedAthleteCutPhase.weight(source: skin.motion.sourceCommit, track: track,
                at: time, locomotion: locomotion, interaction: context.cue(at: time),
                retargetInfluence: actualInfluence, enabled: true)
            let protection = ReplayAthleteMovementIntent.contactProtection(for: context.cue(at: time), track: track, at: time)
            if protection >= 1 {
                XCTAssertEqual(alignment, 0)
                XCTAssertEqual(skin.model.jointTransforms, legacy.model.jointTransforms,
                    "A protected contact core stays byte-exact at \(track.id) \(time)")
                coreSamples += 1
            }
            let heading = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
            var row: [String: Any] = ["scenario": context.scenario.id, "player": track.id,
                "team": track.team.rawValue, "detail": String(describing: skin.detail), "time": time,
                "phase": phase, "speed": locomotion.speedMetresPerSecond,
                "turnRate": locomotion.turnRateDegreesPerSecond, "cutWeight": cut,
                "actualRetargetInfluence": actualInfluence, "movementInfluence": movement?.influence ?? 0,
                "interactionInfluence": interaction?.influence ?? 0, "protectedCue": context.cue(at: time) != nil,
                "alignmentAdmission": alignment, "contactProtection": protection]
            for side in ["left", "right"] {
                let foot = try XCTUnwrap(feet[side])
                let local = try sole(side, motion: skin.motion, pose: skin.pose)
                let world = heading.act(local * skin.root.scale) + SIMD3<Float>(presented.position.x, 0, presented.position.z)
                row[side + "SourceSole"] = vector(foot.sole)
                row[side + "SourceDerivativePerRadian"] = vector(foot.derivativePerRadian)
                row[side + "AuthoredLoad"] = foot.authored.contactWeight
                row[side + "AuthoredStance"] = foot.authored.isStance
                let aligned = try XCTUnwrap(alignedFeet[side]).authored
                row[side + "AlignedTargetLoad"] = aligned.contactWeight
                row[side + "BlendedAuthoredLoad"] = foot.authored.contactWeight
                    + (aligned.contactWeight - foot.authored.contactWeight) * alignment
                row[side + "FinalSole"] = vector(world)
                if let before = previousFeet[side] {
                    let velocity = (world - before) * 120
                    row[side + "FinalVelocity"] = vector(velocity)
                    maximumSoleSpeed = max(maximumSoleSpeed, hypot(velocity.x, velocity.z))
                }
                previousFeet[side] = world
                let legacyLocal = try sole(side, motion: legacy.motion, pose: legacy.pose)
                let legacyWorld = heading.act(legacyLocal * legacy.root.scale) + SIMD3<Float>(presented.position.x, 0, presented.position.z)
                row[side + "LegacySole"] = vector(legacyWorld)
                if let before = legacyPreviousFeet[side] {
                    let velocity = (legacyWorld - before) * 120
                    row[side + "LegacyVelocity"] = vector(velocity)
                    legacyMaximumSoleSpeed = max(legacyMaximumSoleSpeed, hypot(velocity.x, velocity.z))
                }
                legacyPreviousFeet[side] = legacyWorld
                // Animation-event support marker from the independent raw
                // source curve. Not foot force and not final-sole height.
                let markerPhase = (phase - (side == "left" ? .pi : 0)).truncatingRemainder(dividingBy: 2 * .pi)
                let positivePhase = markerPhase < 0 ? markerPhase + 2 * .pi : markerPhase
                row[side + "SourceSupportEvent"] = positivePhase >= 2.30 && positivePhase <= 3.40
                for limb in ["Wrist", "Ankle"] {
                    let joint = try XCTUnwrap(skin.motion.semanticJointIndices[side + limb])
                    let p = skin.pose.modelSpaceTransforms[joint].columns.3
                    let prior = legacy.pose.modelSpaceTransforms[joint].columns.3
                    row[side + limb + "Model"] = [p.x, p.y, p.z]
                    row[side + limb + "LegacyModel"] = [prior.x, prior.y, prior.z]
                }
                for pair in [("Hip", "Knee"), ("Knee", "Ankle")] {
                    let a = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.0])
                    let b = try XCTUnwrap(skin.motion.semanticJointIndices[side + pair.1])
                    let length = simd_distance(skin.pose.modelSpaceTransforms[a].columns.3, skin.pose.modelSpaceTransforms[b].columns.3)
                    let rest = simd_distance(skin.motion.restPose.modelSpaceTransforms[a].columns.3, skin.motion.restPose.modelSpaceTransforms[b].columns.3)
                    maxBoneError = max(maxBoneError, abs(length - rest))
                    XCTAssertEqual(length, rest, accuracy: 0.0002)
                }
            }
            let floor = skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY
            minFloor = min(minFloor, floor)
            XCTAssertGreaterThanOrEqual(floor, skin.contactSurface.paddingMetres - 0.0001)
            if let previous = saved.last {
                for i in previous.indices {
                    let dot = min(abs(simd_dot(previous[i].rotation.vector, skin.model.jointTransforms[i].rotation.vector)), 1)
                    maxJointStep = max(maxJointStep, 2 * acos(dot) * 180 / .pi)
                }
            }
            if let previous = legacySaved.last {
                for i in previous.indices {
                    let dot = min(abs(simd_dot(previous[i].rotation.vector, legacy.model.jointTransforms[i].rotation.vector)), 1)
                    legacyMaxJointStep = max(legacyMaxJointStep, 2 * acos(dot) * 180 / .pi)
                }
            }
            saved.append(skin.model.jointTransforms)
            legacySaved.append(legacy.model.jointTransforms)
            for joint in skin.model.jointTransforms {
                let values = [joint.translation.x, joint.translation.y, joint.translation.z,
                    joint.rotation.vector.x, joint.rotation.vector.y, joint.rotation.vector.z, joint.rotation.vector.w,
                    joint.scale.x, joint.scale.y, joint.scale.z]
                for value in values { fingerprint.update(data: Data("\(value.bitPattern),".utf8)) }
            }
            for joint in legacy.model.jointTransforms {
                let values = [joint.translation.x, joint.translation.y, joint.translation.z,
                    joint.rotation.vector.x, joint.rotation.vector.y, joint.rotation.vector.z, joint.rotation.vector.w,
                    joint.scale.x, joint.scale.y, joint.scale.z]
                for value in values { legacyFingerprint.update(data: Data("\(value.bitPattern),".utf8)) }
            }
            rows.append(row)
        }
        for index in times.indices.reversed() {
            _ = update(skin, context: context, time: times[index])
            XCTAssertEqual(skin.model.jointTransforms, saved[index])
        }
        let originalHash = legacyFingerprint.finalize().map { String(format: "%02x", $0) }.joined()
        if track.id == "arg-10", abs(start - 1.20) < 0.0001 {
            let expected = skin.detail == .near
                ? "b929095326f8cae80bafaf3e35ae7ad8bb7ce24c806ad5ab29f912c3ffd239ef"
                : "9e4358cd739bebc3183ddd5b25f3cf7895eafc04600060e76ebfaec5ffd3d666"
            XCTAssertEqual(originalHash, expected, "Independent native baseline, not regenerated from candidate")
            XCTAssertGreaterThan(coreSamples, 0)
        }
        if track.id == "fra-22", abs(start - 6.80) < 0.0001, abs(end - 7.15) < 0.0001 {
            // Native A/B:12.785→11.423m/s in both LODs. This guards actual
            // provider wiring, not only the independent phase-policy helper.
            // It measures all horizontal sole motion, not planted-foot slip.
            XCTAssertLessThan(maximumSoleSpeed, legacyMaximumSoleSpeed * 0.95,
                "The native cut-release gain must survive provider integration")
        }
        XCTAssertLessThanOrEqual(maxJointStep, max(10, legacyMaxJointStep + 1),
            "Phase alignment must not trade mismatch for a new pose snap: \(track.id)")
        rows.append(["windowSummary": true, "scenario": context.scenario.id, "player": track.id,
            "team": track.team.rawValue, "detail": String(describing: skin.detail), "start": start, "end": end,
            "poseSHA256": fingerprint.finalize().map { String(format: "%02x", $0) }.joined(),
            "legacyPoseSHA256": originalHash, "protectedCoreSamples": coreSamples,
            "maximumBoneLengthError": maxBoneError, "minimumSkinFloor": minFloor,
            "maximumJointStepDegrees": maxJointStep, "legacyMaximumJointStepDegrees": legacyMaxJointStep,
            "maximumHorizontalSoleSpeed": maximumSoleSpeed, "legacyMaximumHorizontalSoleSpeed": legacyMaximumSoleSpeed,
            "exactRewind": true])
    }

    private func vector(_ value: SIMD3<Float>) -> [Float] { [value.x, value.y, value.z] }

    func testWholePoseAdmissionEndpointsWrapCounterphaseAndSingleEvaluation() throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-36-counter-v2" })
        let track = try XCTUnwrap(scenario.player(id: "fra-22"))
        let locomotion = track.locomotion(at: 6.875)
        func authored(_ phase: Float) -> ReplayAthleteLocomotionPose {
            ReplayAthleteMotion.locomotionPose(for: track, at: 6.875, locomotion: locomotion,
                gaitPhase: phase, lookTargetWorldPosition: nil, allowsOffBallPose: false)
        }
        func joints(_ pose: ReplayAthleteLocomotionPose) -> [simd_quatf] {
            [pose.bodyOrientation, pose.hipsOrientation, pose.spineOrientation, pose.neckOrientation,
             pose.headOrientation, pose.leftHipOrientation, pose.rightHipOrientation,
             pose.leftKneeOrientation, pose.rightKneeOrientation, pose.leftAnkleOrientation,
             pose.rightAnkleOrientation, pose.leftShoulderOrientation, pose.rightShoulderOrientation,
             pose.leftElbowOrientation, pose.rightElbowOrientation, pose.leftWristOrientation, pose.rightWristOrientation]
        }
        var rows: [[String: Any]] = []
        for weight: Float in [0, 0.00001, 0.5, 0.99999, 1] {
            var previous: [simd_quatf]?
            var maxStep: Float = 0
            for index in -3...123 {
                // Cross both0 and2π in a complete gait cycle. Arms and legs
                // share each same fixed-phase pose, including partial weights.
                let phase = Float(index) * 2 * .pi / 120
                var evaluations = 0
                let pose = ReplaySkinnedAthleteCutPhase.authoredPose(phase: phase, weight: weight) { p in
                    evaluations += 1; return authored(p)
                }
                XCTAssertEqual(evaluations, weight == 0 || weight == 1 ? 1 : 2)
                let current = joints(pose)
                if weight == 0 { XCTAssertEqual(current.map(\.vector), joints(authored(phase)).map(\.vector)) }
                if weight == 1 {
                    XCTAssertEqual(current.map(\.vector), joints(authored(phase - ReplaySkinnedAthleteCutPhase.offset)).map(\.vector))
                }
                for q in current {
                    XCTAssertTrue(q.vector.x.isFinite && q.vector.y.isFinite && q.vector.z.isFinite && q.vector.w.isFinite)
                    XCTAssertEqual(simd_length(q.vector), 1, accuracy: 0.00001)
                }
                if let previous {
                    for (a, b) in zip(previous, current) {
                        maxStep = max(maxStep, 2 * acos(min(abs(simd_dot(a.vector, b.vector)), 1)) * 180 / .pi)
                    }
                }
                previous = current
                // Repeated absolute-time evaluation is exact; the native
                // window tests separately seek the complete sequence backwards.
                let rewind = ReplaySkinnedAthleteCutPhase.authoredPose(phase: phase, weight: weight, sample: authored)
                XCTAssertEqual(current.map(\.vector), joints(rewind).map(\.vector))
            }
            XCTAssertLessThan(maxStep, 8, "No wrap/admission gait snap at weight\(weight)")
            rows.append(["weight": weight, "maxJointStepDegrees": maxStep])
        }
        let skin = try ReplaySkinnedAthleteProvider.make(for: track)
        // Source-derived right support event: its boot moves back close to the
        // floor while the opposite boot recovers. Retiming keeps the authored
        // opposite-arm pairing on that same beat, not the old clock's beat.
        let phase: Float = 2.7
        let feet = try sourceFeet(motion: skin.motion, phase: phase, locomotion: locomotion)
        XCTAssertLessThan(try XCTUnwrap(feet["right"]).sole.y, 0.035)
        XCTAssertLessThan(try XCTUnwrap(feet["right"]).derivativePerRadian.z, -0.3)
        XCTAssertGreaterThan(try XCTUnwrap(feet["left"]).sole.y, 0.20)
        let aligned = authored(phase - ReplaySkinnedAthleteCutPhase.offset)
        let alignedFeet = try sourceFeet(motion: skin.motion,
            phase: phase - ReplaySkinnedAthleteCutPhase.offset, locomotion: locomotion)
        XCTAssertGreaterThan(try XCTUnwrap(alignedFeet["right"]).authored.contactWeight, 0.8)
        XCTAssertEqual(try XCTUnwrap(alignedFeet["left"]).authored.contactWeight, 0)
        // Procedural negative-X hip pairs with positive-X shoulder and vice
        // versa. Their sagittal directions must agree contralaterally.
        XCTAssertGreaterThan(aligned.leftHipOrientation.act(SIMD3<Float>(0, -1, 0)).z
            * aligned.rightShoulderOrientation.act(SIMD3<Float>(0, -1, 0)).z, 0)
        XCTAssertGreaterThan(aligned.rightHipOrientation.act(SIMD3<Float>(0, -1, 0)).z
            * aligned.leftShoulderOrientation.act(SIMD3<Float>(0, -1, 0)).z, 0)
        let influence = ReplaySkinnedAthleteFootballPose.influence(locomotion: locomotion, ballAction: nil)
        XCTAssertEqual(ReplaySkinnedAthleteCutPhase.weight(source: "unmatched-asset", track: track, at: 6.875,
            locomotion: locomotion, interaction: nil, retargetInfluence: influence, enabled: true), 0)
        XCTAssertEqual(ReplaySkinnedAthleteCutPhase.weight(source: skin.motion.sourceCommit, track: track, at: 6.875,
            locomotion: locomotion, interaction: nil, retargetInfluence: influence, enabled: false), 0)
        XCTAssertEqual(ReplaySkinnedAthleteCutPhase.weight(source: skin.motion.sourceCommit, track: track, at: 6.875,
            locomotion: locomotion, interaction: nil, retargetInfluence: 0, enabled: true), 0)
        try receipt(rows, name: "PolicyEndpointsAndCounterphase")
    }

    func testAllFiveAdmissionEvaluationCostAndProtectedCoreGuard() async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        // Sampled policy-work estimate assuming each actor uses a native skin
        // in active locomotion. This does not instrument provider calls and
        // omits stationary/teaching/impact admission and keeper readiness.
        // Consequently these are not measured production calls, CPU cost or FPS.
        var rows: [[String: Any]] = []
        var playerSamples = 0, affected = 0, extra = 0, originalAuthored = 0
        for scenario in FootballReferenceScenarios.all {
            var sceneSamples = 0, sceneAffected = 0, sceneExtra = 0, sceneAuthored = 0, core = 0
            for track in scenario.players {
                let context = try await context(scenario, track)
                for index in 0...Int(scenario.duration * 30) {
                    let time = Double(index) / 30
                    let pose = track.presentationPose(at: time)
                    let locomotion = track.locomotion(at: time)
                    let cue = context.cue(at: time)
                    let interaction = ReplayAthleteInteractionPose.sample(cue: cue, at: time, track: track, presentationPose: pose)
                    let movement = ReplayAthleteMovementIntent.sample(track: track, at: time,
                        presentationPose: pose, lookTarget: context.recording.sample(at: time).position, interaction: cue)
                    let cut = ReplaySkinnedAthleteFootballPose.influence(locomotion: locomotion, ballAction: nil)
                    let influence = max(cut, interaction?.influence ?? 0, movement?.influence ?? 0)
                    let weight = ReplaySkinnedAthleteCutPhase.weight(source: ReplaySkinnedAthleteCutPhase.sourceCommit,
                        track: track, at: time, locomotion: locomotion, interaction: cue,
                        retargetInfluence: influence, enabled: true)
                    sceneSamples += 1
                    if influence > 0 { sceneAuthored += 1 }
                    if weight > 0 { sceneAffected += 1 }
                    if weight > 0, weight < 1 { sceneExtra += 1 }
                    let protection = ReplayAthleteMovementIntent.contactProtection(for: cue, track: track, at: time)
                    if protection >= 1 {
                        core += 1; XCTAssertEqual(weight, 0, "Protected core must use one unmodified authored pose")
                    }
                    if track.isGoalkeeper || influence == 0 { XCTAssertEqual(weight, 0) }
                }
            }
            rows.append(["scenario": scenario.id, "playerSamples30Hz": sceneSamples,
                "policyEstimateOnly": true, "assumedSourcePoseEvaluations": sceneSamples,
                "estimatedBaseAuthoredEvaluationsIgnoringKeeperReadiness": sceneAuthored,
                "affectedPolicySamples": sceneAffected, "estimatedExtraAuthoredPoseEvaluations": sceneExtra,
                "protectedCoreSamplesUnchanged": core])
            playerSamples += sceneSamples; affected += sceneAffected; extra += sceneExtra; originalAuthored += sceneAuthored
        }
        XCTAssertGreaterThan(affected, 0)
        XCTAssertGreaterThan(extra, 0)
        rows.append(["summary": true, "policyEstimateOnly": true, "playerSamples30Hz": playerSamples,
            "affectedPolicySamples": affected,
            "estimatedBaseAuthoredEvaluationsIgnoringKeeperReadiness": originalAuthored,
            "estimatedExtraAuthoredPoseEvaluations": extra,
            "estimatedExtraFractionOfAssumedEvaluations": Double(extra) / Double(playerSamples + originalAuthored),
            "limits": "Assumes all actors use native skins in active locomotion; omits stationary, teaching, impact and keeper-readiness admission. Not measured provider calls, CPU cost or FPS."])
        try receipt(rows, name: "AllFiveEvaluationCost")
    }

    func testCaptureNativeCutReleaseNearAndLow() async throws {
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        let calibration = try await calibrate()
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-36-counter-v2" })
        let track = try XCTUnwrap(scenario.player(id: "fra-22"))
        let context = try await context(scenario, track)
        let middle = track.presentationPose(at: 6.875).position
        let origin = SIMD3<Float>(middle.x, 0, middle.z)
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplaySkinnedAthleteProvider.make(for: track, detail: detail)
            for time in [6.85, 6.875, 6.925] {
                let presented = update(skin, context: context, time: time)
                let scene = Entity(), actor = Entity()
                actor.position = SIMD3<Float>(presented.position.x, 0, presented.position.z) - origin
                actor.orientation = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
                actor.addChild(skin.root); scene.addChild(actor)
                defer {
                    skin.root.removeFromParent()
                    for child in Array(scene.children) { child.removeFromParent() }
                }
                let floor = ModelEntity(mesh: .generateBox(size: [8, 0.008, 8]),
                    materials: [SimpleMaterial(color: UIColor(red: 0.07, green: 0.12, blue: 0.09, alpha: 1),
                                               roughness: 1, isMetallic: false)])
                floor.position.y = -0.006; scene.addChild(floor)
                let ball = ModelEntity(mesh: .generateSphere(radius: 0.11),
                    materials: [SimpleMaterial(color: .white, roughness: 0.7, isMetallic: false)])
                ball.position = context.recording.sample(at: time).position - origin; scene.addChild(ball)
                let camera = PerspectiveCamera()
                camera.camera = .init(near: 0.05, far: 80, fieldOfViewInDegrees: 35)
                camera.look(at: [0, 0.8, 0], from: [4, 2, -3.2], relativeTo: nil)
                let key = DirectionalLight(), fill = DirectionalLight()
                key.light.intensity = 2_200; key.look(at: [0, 0.8, 0], from: [3, 4, -3], relativeTo: nil)
                fill.light.intensity = 500; fill.look(at: [0, 0.8, 0], from: [-3, 2, -2], relativeTo: nil)
                let frame = try await render([scene, camera, key, fill], camera: camera, size: 512)
                let image = XCTAttachment(data: try ReplayRealityRendererAudit.png(frame, calibration: calibration),
                                          uniformTypeIdentifier: "public.png")
                image.name = "ReplayXI-CutRunPhase138-fra-22-\(detail)-\(time).png"
                image.lifetime = .keepAlways; add(image)
            }
        }
    }

    private func calibrate() async throws -> ReplayRealityRendererAudit.Calibration {
        let root = Entity()
        defer { for child in Array(root.children) { child.removeFromParent() } }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        for index in ReplayRealityRendererAudit.swatches.indices {
            let color = try XCTUnwrap(CGColor(colorSpace: space,
                components: ReplayRealityRendererAudit.swatches[index].map { CGFloat($0) / 255 } + [1]))
            let tile = ModelEntity(mesh: .generateBox(size: [1.2, 0.6, 0.01]),
                materials: [UnlitMaterial(color: UIColor(cgColor: color), applyPostProcessToneMap: false)])
            tile.position = ReplayRealityRendererAudit.swatchPosition(index); root.addChild(tile)
        }
        let camera = PerspectiveCamera()
        camera.camera = .init(near: 0.05, far: 10, fieldOfViewInDegrees: 90); camera.position = [0, 0, 2]
        let probe = try ReplayRealityRendererAudit.probe(await render([root, camera], camera: camera, size: 256))
        let candidates = probe.candidates.filter { $0.maximumChannelError <= 4 }
        XCTAssertEqual(candidates.count, 1)
        return try XCTUnwrap(candidates.first)
    }

    private func render(_ entities: [Entity], camera: Entity, size: Int) async throws -> ReplayRealityRendererAudit.Frame {
        let renderer = try RealityRenderer()
        renderer.entities.append(contentsOf: entities)
        defer { renderer.activeCamera = nil; renderer.entities.removeAll() }
        renderer.activeCamera = camera
        renderer.cameraSettings.isToneMappingEnabled = true
        renderer.cameraSettings.antialiasing = .none
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        let texture = try ReplayRealityRendererAudit.makeTexture(size: size)
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let done = expectation(description: "Cut/run native frame"), flag = Cut138RenderCompletion()
        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in flag.complete(); done.fulfill() })
        await fulfillment(of: [done], timeout: 10)
        guard flag.isComplete else { throw ReplayRealityRendererAudit.Failure.unsupported("Cut/run frame timed out") }
        return try withExtendedLifetime((renderer, entities, camera, output)) {
            try ReplayRealityRendererAudit.read(texture)
        }
    }

    private func receipt(_ rows: [[String: Any]], name: String) throws {
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-CutRunPhase138-\(name).json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
