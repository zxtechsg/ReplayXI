import Foundation
import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAthletePublication178Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplayTripoAthleteProvider.resetForTesting()
    }

    override func tearDown() {
        ReplayTripoAthleteProvider.resetForTesting()
        super.tearDown()
    }

    private var track: PlayerTrack {
        PlayerTrack(id: "publication-player", displayName: "Player", role: "CM", shirtNumber: 3,
            team: .home, isGoalkeeper: false, keyframes: [
                .init(time: 0, position: .init(x: 0, z: -2), facingDegrees: 0),
                .init(time: 4, position: .init(x: 0, z: 2), facingDegrees: 0)])
    }

    private func make(diverse: Bool, detail: ReplaySkinnedAthleteProvider.Detail = .near) throws
        -> ReplaySkinnedAthleteInstance {
        try diverse ? ReplayTripoAthleteProvider.makeDiverse(for: track, detail: detail)
            : ReplayTripoAthleteProvider.make(for: track, detail: detail)
    }

    @discardableResult
    private func update(_ skin: ReplaySkinnedAthleteInstance, time: Double = 1.25,
                        look: SIMD3<Float> = [8, 1.6, 8], stationary: Bool = false,
                        interaction: ReplayAthleteInteractionCue? = nil) -> Bool {
        skin.update(at: time, track: track, locomotion: track.locomotion(at: time),
            lookTarget: look, ballAction: nil,
            stationaryPose: stationary ? track.presentationPose(at: time) : nil,
            interaction: interaction, presentationPose: track.presentationPose(at: time))
    }

    private struct Frame {
        var time = 1.25
        var track: PlayerTrack
        var locomotion: PlayerLocomotionSample
        var look: SIMD3<Float>? = [8, 1.6, 8]
        var action: ReplayAthleteBallActionPose?
        var impact: PlayerRagdollPlayback.Sample?
        var stationary: PlayerPose?
        var interaction: ReplayAthleteInteractionCue?
        var presentation: PlayerPose?
        var offBall = true
        var keeper: ReplayGoalkeeperReadiness.Sample?
        var trackSampling = false
        var slowWeight: Float = 0
        var armCut: ReplayArmCutTimeline.Admission?

        init(track: PlayerTrack) {
            self.track = track
            locomotion = track.locomotion(at: 1.25)
            presentation = track.presentationPose(at: 1.25)
        }

        func apply(to skin: ReplaySkinnedAthleteInstance) -> Bool {
            skin.update(at: time, track: track, locomotion: locomotion, lookTarget: look,
                ballAction: action, impact: impact, stationaryPose: stationary,
                interaction: interaction, presentationPose: presentation, allowsOffBallPose: offBall,
                goalkeeperReadiness: keeper, allowsTrackLocomotionSampling: trackSampling,
                slowRunWeight: slowWeight, armCutAdmission: armCut)
        }
    }

    func testEverySameTimeInputInvalidatesMemoizationAndMatchesFreshEvaluation() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let timeline = try XCTUnwrap(ReplayArmCutTimeline(track: track, interactions: [], duration: 4))
        let admission = try XCTUnwrap(timeline.admission(at: 1.25, locomotion: track.locomotion(at: 1.25)))
        let pass = ReplayAthleteInteractionCue(playerID: track.id, kind: .pass,
            contactTime: 1.25, startTime: 0.9, endTime: 1.65, kickingLeg: .right,
            contactBallWorldPosition: [0.14, 0.11, 0.42], outgoingDirectionWorld: [0, 0, 1])
        let impact = try XCTUnwrap(PlayerRagdollPlayback.sample(
            for: PlayerRagdollCue(playerID: track.id, impactTime: 1), at: 1.25))
        let edits: [(String, (inout Frame) -> Void)] = [
            ("time", { $0.time = 0.5 }),
            ("track value", { frame in
                frame.track = PlayerTrack(id: frame.track.id, displayName: "Edited", role: "CM",
                    shirtNumber: 3, team: .home, isGoalkeeper: false, keyframes: [
                        .init(time: 0, position: .init(x: -2, z: -2), facingDegrees: 35),
                        .init(time: 4, position: .init(x: 2, z: 2), facingDegrees: 35)])
            }),
            ("supplied locomotion", { frame in
                frame.locomotion = PlayerLocomotionSample(motion: frame.locomotion.motion,
                    speedMetresPerSecond: 3, accelerationMetresPerSecondSquared: 2,
                    turnRateDegreesPerSecond: 75, state: .cut)
            }),
            ("look", { $0.look = [-8, 1.6, 8] }),
            ("no look", { $0.look = nil }),
            ("action", { $0.action = ReplayAthleteBallActionPose(kind: .pass, contactTime: 1.25,
                kickingLeg: .right, influence: 0.7, kickingHipFlexion: 0.5, kickingKneeFlexion: 0.2,
                kickingFootPitch: 0.1, supportHipFlexion: 0.1, supportKneeFlexion: 0.1,
                supportFootPitch: 0, supportLateralShift: 0.02) }),
            ("impact", { $0.impact = impact }),
            ("stationary", { $0.stationary = $0.track.presentationPose(at: $0.time) }),
            ("contact", { $0.interaction = pass }),
            ("presentation", { $0.presentation = PlayerPose(position: .init(x: 1, z: 2), facingDegrees: 45) }),
            ("off ball", { $0.offBall = false }),
            ("keeper", { $0.keeper = .init(readiness: 0.5, reaction: 0.3, lateralIntent: 0.3,
                highShot: 0.1, closeRange: 0.2, stanceWeight: 0.8) }),
            ("track sampling", { $0.trackSampling = true }),
            ("slow run", { $0.slowWeight = 0.5 }),
            ("arm admission", { $0.armCut = admission })
        ]
        for diverse in [false, true] {
            let optimized = try make(diverse: diverse)
            let control = try make(diverse: diverse)
            control.disablesPoseInputMemoizationForTesting = true
            for (name, edit) in edits {
                var frame = Frame(track: track)
                XCTAssertTrue(frame.apply(to: optimized))
                edit(&frame)
                let evaluations = optimized.poseEvaluationCountForTesting
                XCTAssertTrue(frame.apply(to: optimized), name)
                XCTAssertEqual(optimized.poseEvaluationCountForTesting, evaluations + 1, name)
                XCTAssertTrue(frame.apply(to: control), name)
                XCTAssertEqual(optimized.model.jointTransforms, control.model.jointTransforms, name)
                XCTAssertEqual(optimized.pose.modelSpaceTransforms, control.pose.modelSpaceTransforms, name)
                XCTAssertEqual(optimized.front.jointTransforms, control.front.jointTransforms, name)
                XCTAssertEqual(optimized.back.jointTransforms, control.back.jointTransforms, name)
                let hits = optimized.poseInputCacheHitCountForTesting
                XCTAssertTrue(frame.apply(to: optimized), name)
                XCTAssertEqual(optimized.poseInputCacheHitCountForTesting, hits + 1, name)
                XCTAssertEqual(optimized.poseEvaluationCountForTesting, evaluations + 1, name)
            }
            var invalid = Frame(track: track)
            invalid.impact = PlayerRagdollPlayback.Sample(playerID: "different-player", time: invalid.time,
                pose: impact.pose, influence: impact.influence)
            XCTAssertFalse(invalid.apply(to: optimized))
            XCTAssertFalse(optimized.root.isEnabled)
            let evaluations = optimized.poseEvaluationCountForTesting
            XCTAssertTrue(Frame(track: track).apply(to: optimized))
            XCTAssertEqual(optimized.poseEvaluationCountForTesting, evaluations + 1)
            XCTAssertTrue(optimized.root.isEnabled)
        }
    }

    func testDiagnosticsForceEvaluationAndEveryDiagnosticSwitchInvalidatesInput() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let skin = try make(diverse: false)
        let control = try make(diverse: false)
        control.disablesPoseInputMemoizationForTesting = true
        let switches: [ReferenceWritableKeyPath<ReplaySkinnedAthleteInstance, Bool>] = [
            \.disablesCutPhaseAlignmentForTesting, \.disablesCutWeightSmoothingForTesting,
            \.disablesHeaderHandoffForTesting, \.disablesOffBallReadyArmsForTesting,
            \.disablesCervicalAimForTesting, \.disablesUpperBodyFlowForTesting,
            \.disablesArmCutSmoothingForTesting
        ]
        for flag in switches {
            XCTAssertTrue(update(skin))
            let before = skin.poseEvaluationCountForTesting
            skin[keyPath: flag] = true
            control[keyPath: flag] = true
            XCTAssertTrue(update(skin))
            XCTAssertTrue(update(control))
            XCTAssertEqual(skin.poseEvaluationCountForTesting, before + 1)
            XCTAssertEqual(skin.model.jointTransforms, control.model.jointTransforms)
            skin[keyPath: flag] = false
            control[keyPath: flag] = false
        }
        var observed = 0
        skin.authoredPoseObserverForTesting = { _, _, _ in observed += 1 }
        let before = skin.poseEvaluationCountForTesting
        for _ in 0..<3 { XCTAssertTrue(update(skin)) }
        XCTAssertEqual(skin.poseEvaluationCountForTesting, before + 3)
        XCTAssertGreaterThan(observed, 0)
        skin.authoredPoseObserverForTesting = nil
        XCTAssertTrue(update(skin))
        let evaluations = skin.poseEvaluationCountForTesting
        XCTAssertTrue(skin.setFirstPersonBodyPresentation(true))
        XCTAssertTrue(update(skin))
        XCTAssertEqual(skin.poseEvaluationCountForTesting, evaluations)
        XCTAssertFalse(skin.front.isEnabled)
        XCTAssertTrue(skin.setFirstPersonBodyPresentation(false))
        XCTAssertTrue(update(skin))
        XCTAssertEqual(skin.poseEvaluationCountForTesting, evaluations)
        XCTAssertTrue(skin.front.isEnabled)
        XCTAssertEqual(skin.model.jointTransforms, skin.front.jointTransforms)
        XCTAssertEqual(skin.model.jointTransforms, skin.back.jointTransforms)
    }

    func testPausedSkinsAvoidNativeJointWritesWithoutSkippingPoseEvaluation() throws {
        try ReplayTripoAthleteProvider.prewarm()
        for diverse in [false, true] {
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try make(diverse: diverse, detail: detail)
                let grounded = try XCTUnwrap(skin.root.children.first)
                XCTAssertEqual(grounded.position.y, -skin.motion.geometry.restMinY, accuracy: 0.000_001)
                XCTAssertTrue(update(skin))
                XCTAssertEqual(skin.jointPoseWriteCountForTesting, 3)
                let saved = skin.model.jointTransforms
                let bridgeWrites = skin.neckBridgeWriteCountForTesting
                var observed = 0
                skin.poseStageObserverForTesting = { stage, _ in
                    if stage == .finalFloor { observed += 1 }
                }
                for _ in 0..<24 { XCTAssertTrue(update(skin)) }
                skin.poseStageObserverForTesting = nil
                XCTAssertEqual(observed, 24, "Only native publication is coalesced, not animation logic")
                XCTAssertEqual(skin.jointPoseWriteCountForTesting, 3)
                XCTAssertEqual(skin.neckBridgeWriteCountForTesting, bridgeWrites)
                XCTAssertEqual(skin.model.jointTransforms, saved)
                XCTAssertEqual(skin.front.jointTransforms, saved)
                XCTAssertEqual(skin.back.jointTransforms, saved)
                XCTAssertFalse(update(skin, time: .nan))
                XCTAssertFalse(skin.root.isEnabled)
                XCTAssertTrue(update(skin))
                XCTAssertTrue(skin.root.isEnabled)
                XCTAssertEqual(skin.model.jointTransforms, saved)
                XCTAssertEqual(skin.jointPoseWriteCountForTesting, 3)
            }
        }
    }

    func testSameTimeGazePostureContactsAndSeeksMatchUncoalescedControl() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let pass = ReplayAthleteInteractionCue(playerID: track.id, kind: .pass,
            contactTime: 1.25, startTime: 0.9, endTime: 1.65, kickingLeg: .right,
            contactBallWorldPosition: [0.14, 0.11, 0.42], outgoingDirectionWorld: [0, 0, 1],
            supportFootWorldPosition: [-0.14, 0, 0.035])
        for diverse in [false, true] {
            let optimized = try make(diverse: diverse)
            let control = try make(diverse: diverse)
            control.disablesPoseWriteCoalescingForTesting = true
            for frame in 0..<12 {
                let time = frame >= 8 ? [2.5, 0.5, 1.25, 1.25][frame - 8] : 1.25
                let look: SIMD3<Float> = frame == 2 || frame == 3 ? [-8, 1.6, 8] : [8, 1.6, 8]
                let stationary = frame == 4 || frame == 5
                let interaction = frame == 6 || frame == 7 ? pass : nil
                XCTAssertTrue(update(optimized, time: time, look: look, stationary: stationary, interaction: interaction))
                XCTAssertTrue(update(control, time: time, look: look, stationary: stationary, interaction: interaction))
                XCTAssertEqual(optimized.model.jointTransforms, control.model.jointTransforms)
                XCTAssertEqual(optimized.front.jointTransforms, control.front.jointTransforms)
                XCTAssertEqual(optimized.back.jointTransforms, control.back.jointTransforms)
                XCTAssertEqual(optimized.contactSurface.minimumY(in: optimized.pose),
                               control.contactSurface.minimumY(in: control.pose))
            }
            XCTAssertLessThan(optimized.jointPoseWriteCountForTesting, control.jointPoseWriteCountForTesting)
            XCTAssertGreaterThan(optimized.jointPoseWriteCountForTesting, 3,
                                 "Same timestamp must not freeze changed gaze, posture or a contact")
        }
    }

    func testHiddenFPVNeckStopsUpdatingAndRestoresTheLatestPoseImmediately() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let skin = try make(diverse: true)
        let control = try make(diverse: true)
        XCTAssertTrue(update(skin))
        let bridge = try XCTUnwrap(skin.neckBridge)
        let before = bridge.transform
        let writeCount = skin.neckBridgeWriteCountForTesting
        XCTAssertTrue(skin.setFirstPersonBodyPresentation(true))
        for time in [1.5, 2.0, 2.5] {
            XCTAssertTrue(update(skin, time: time, look: [-8, 1.6, 8]))
            XCTAssertEqual(bridge.transform, before)
            XCTAssertEqual(skin.neckBridgeWriteCountForTesting, writeCount)
            XCTAssertFalse(bridge.isEnabled)
        }
        XCTAssertTrue(update(control, time: 2.5, look: [-8, 1.6, 8]))
        XCTAssertTrue(skin.setFirstPersonBodyPresentation(false))
        XCTAssertEqual(skin.neckBridgeWriteCountForTesting, writeCount + 1)
        let expected = try XCTUnwrap(control.neckBridge)
        XCTAssertLessThan(simd_distance(bridge.position, expected.position), 0.000_01)
        XCTAssertLessThan(simd_distance(bridge.scale, expected.scale), 0.000_01)
        XCTAssertLessThan(simd_distance(bridge.orientation.vector, expected.orientation.vector), 0.000_01)
        XCTAssertTrue(bridge.isEnabled)
        XCTAssertEqual(skin.model.jointTransforms, control.model.jointTransforms)
        XCTAssertEqual(skin.front.jointTransforms, control.front.jointTransforms)
    }

    func testRecordsBoundedFullSquadPausedPublicationSavings() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let players = scenario.players
        XCTAssertEqual(players.count, 22)
        let optimized = try players.enumerated().map {
            try ReplayTripoAthleteProvider.makePreferred(for: $0.element, detail: $0.offset == 0 ? .near : .lowDetail)
        }
        let control = try players.enumerated().map {
            try ReplayTripoAthleteProvider.makePreferred(for: $0.element, detail: $0.offset == 0 ? .near : .lowDetail)
        }
        for skin in control { skin.disablesPoseWriteCoalescingForTesting = true }
        let time = 1.25
        let locomotions = players.map { $0.locomotion(at: time) }
        let poses = players.map { $0.presentationPose(at: time) }
        func frame(_ skins: [ReplaySkinnedAthleteInstance]) -> Double {
            let start = DispatchTime.now().uptimeNanoseconds
            for index in skins.indices {
                _ = skins[index].update(at: time, track: players[index], locomotion: locomotions[index],
                    lookTarget: [0, 0.11, 10], ballAction: nil, presentationPose: poses[index])
            }
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        }
        _ = frame(optimized); _ = frame(control)
        let initialOptimized = optimized.reduce(0) { $0 + $1.jointPoseWriteCountForTesting }
        let initialControl = control.reduce(0) { $0 + $1.jointPoseWriteCountForTesting }
        var fast: [Double] = [], baseline: [Double] = []
        for _ in 0..<16 { fast.append(frame(optimized)); baseline.append(frame(control)) }
        let avoided = optimized.reduce(0) { $0 + $1.jointPoseWriteCountForTesting } - initialOptimized
        let written = control.reduce(0) { $0 + $1.jointPoseWriteCountForTesting } - initialControl
        XCTAssertEqual(avoided, 0)
        XCTAssertEqual(written, 16 * 22 * 3)
        XCTAssertEqual(optimized.reduce(0) { $0 + $1.poseEvaluationCountForTesting }, 22)
        XCTAssertEqual(optimized.reduce(0) { $0 + $1.poseInputCacheHitCountForTesting }, 16 * 22)
        XCTAssertEqual(control.reduce(0) { $0 + $1.poseEvaluationCountForTesting }, 17 * 22)
        for index in players.indices {
            XCTAssertEqual(optimized[index].model.jointTransforms, control[index].model.jointTransforms)
        }
        let report: [String: Any] = [
            "scope": "Debug simulator, paused full-squad pose evaluation and publication; not GPU or headset FPS",
            "players": 22, "frames": 16, "optimizedNativeJointArrayWrites": avoided,
            "controlNativeJointArrayWrites": written,
            "optimizedPoseEvaluationsAfterWarmup": 0, "controlPoseEvaluationsAfterWarmup": 16 * 22,
            "optimizedMedianMilliseconds": fast.sorted()[8], "controlMedianMilliseconds": baseline.sorted()[8]
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-PausedSquad178-Publication.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
