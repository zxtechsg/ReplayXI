import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayAthleteRigTests: XCTestCase {
    func testEveryLODHonoursNamedHierarchyAndGeometryBudget() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))

        let exactModelCounts: [ReplayAthleteLOD: Int] = [.near: 29, .mid: 19, .far: 7]
        for lod in ReplayAthleteLOD.allCases {
            let instance = try ReplayAthleteFactory.make(for: player, lod: lod)
            XCTAssertEqual(instance.root.name, "full-rig")
            XCTAssertTrue(instance.metrics.fits(lod.budget), "\(lod) exceeded \(lod.budget)")
            XCTAssertEqual(countModels(in: instance.root), instance.metrics.modelEntities)
            XCTAssertEqual(instance.metrics.modelEntities, exactModelCounts[lod])
            for joint in ReplayAthleteJoint.allCases {
                XCTAssertEqual(instance.joints[joint].name, joint.rawValue)
                XCTAssertEqual(instance.joints[joint].parent?.name, joint.expectedParentName)
            }
            XCTAssertEqual(instance.root.findEntity(named: "neck-shell") == nil, lod == .far)

            let bounds = instance.root.visualBounds(relativeTo: instance.root)
            XCTAssertGreaterThan(bounds.extents.y, 1.65)
            XCTAssertLessThan(bounds.extents.y, 2.15)
            XCTAssertGreaterThan(bounds.extents.x, 0.42)
            XCTAssertLessThan(bounds.extents.x, 0.78)
        }
    }

    func testFarLODUsesSevenDrawUpperBoundAndDefersUnreadableNumberToTacticalTag() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let far = try ReplayAthleteFactory.make(for: player, lod: .far)

        XCTAssertEqual(far.metrics.modelEntities, 7)
        XCTAssertNil(far.root.findEntity(named: "shirt-number"))
        XCTAssertNil(far.root.findEntity(named: "chest-number"))
        XCTAssertNotNil(far.root.findEntity(named: "left-leg"))
        XCTAssertNotNil(far.root.findEntity(named: "right-leg"))
        XCTAssertFalse(ReplayAthleteLOD.far.supportsDistalArticulation)
        XCTAssertFalse(ReplayAthleteLOD.far.supportsRagdoll)
    }

    func testNearLODHasCrispFrontAndBackGeometryNumbersWithoutTextEntities() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let near = try ReplayAthleteFactory.make(for: player, lod: .near)

        let back = try XCTUnwrap(near.root.findEntity(named: "shirt-number"))
        let chest = try XCTUnwrap(near.root.findEntity(named: "chest-number"))
        XCTAssertNotNil(back.components[ModelComponent.self])
        XCTAssertNotNil(chest.components[ModelComponent.self])
        XCTAssertTrue(back.children.isEmpty)
        XCTAssertTrue(chest.children.isEmpty)
        XCTAssertEqual(back.position.z, -0.149, accuracy: 0.000_1)
        XCTAssertEqual(chest.position.z, 0.149, accuracy: 0.000_1)

        let first = try ReplayAthleteMeshLibrary.jerseyNumber(player.shirtNumber)
        let second = try ReplayAthleteMeshLibrary.jerseyNumber(player.shirtNumber)
        XCTAssertTrue(first.mesh === second.mesh, "number meshes must be cached and shared")
        XCTAssertGreaterThan(first.metrics.vertices, 0)
        XCTAssertGreaterThan(first.metrics.triangles, 0)
    }

    func testSharedMeshesAreReusedAcrossPlayersWhileMaterialsRemainConfigurable() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let home = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let away = try XCTUnwrap(scenario.player(id: "red-lb"))
        let homeRig = try ReplayAthleteFactory.make(for: home, lod: .near)
        let awayRig = try ReplayAthleteFactory.make(for: away, lod: .near)
        let homeTorso = try XCTUnwrap(
            homeRig.root.findEntity(named: "torso")?.components[ModelComponent.self]
        )
        let awayTorso = try XCTUnwrap(
            awayRig.root.findEntity(named: "torso")?.components[ModelComponent.self]
        )

        XCTAssertTrue(homeTorso.mesh === awayTorso.mesh)
        XCTAssertNotEqual(homeRig.configuration.kit.shirt, awayRig.configuration.kit.shirt)
    }

    func testProceduralBootHasHumanScaleSixStageFootballSilhouette() throws {
        let asset = try ReplayAthleteMeshLibrary.mesh(for: .boot, lod: .near)
        let boot = ModelEntity(mesh: asset.mesh)
        let bounds = boot.visualBounds(relativeTo: boot)
        let length = bounds.extents.z
        let width = bounds.extents.x

        // Six longitudinal sections retain the deliberately low-poly language
        // while providing a heel counter, midfoot waist, forefoot and rocker toe.
        XCTAssertEqual(asset.metrics.vertices, 88)
        XCTAssertEqual(asset.metrics.triangles, 44)
        XCTAssertGreaterThanOrEqual(length, 0.30)
        XCTAssertLessThanOrEqual(length, 0.325)
        XCTAssertGreaterThanOrEqual(width, 0.10)
        XCTAssertLessThanOrEqual(width, 0.125)
        XCTAssertGreaterThan(length / width, 2.55)
        XCTAssertEqual(bounds.min.y, -0.10, accuracy: 0.000_1)
        XCTAssertGreaterThan(bounds.max.y, 0.035, "the heel collar should rise above the instep")
    }

    func testRefinedBootRemainsOneSharedMeshPerLODWithoutSpendingAnotherDraw() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let home = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let away = try XCTUnwrap(scenario.player(id: "red-lb"))
        let homeRig = try ReplayAthleteFactory.make(for: home, lod: .near)
        let awayRig = try ReplayAthleteFactory.make(for: away, lod: .near)
        let homeLeft = try XCTUnwrap(
            homeRig.root.findEntity(named: "left-boot")?.components[ModelComponent.self]
        )
        let homeRight = try XCTUnwrap(
            homeRig.root.findEntity(named: "right-boot")?.components[ModelComponent.self]
        )
        let awayLeft = try XCTUnwrap(
            awayRig.root.findEntity(named: "left-boot")?.components[ModelComponent.self]
        )

        XCTAssertTrue(homeLeft.mesh === homeRight.mesh)
        XCTAssertTrue(homeLeft.mesh === awayLeft.mesh)
        XCTAssertEqual(homeRig.metrics.modelEntities, 29)
        XCTAssertTrue(homeRig.metrics.fits(ReplayAthleteLOD.near.budget))
        XCTAssertNotNil(homeRig.root.findEntity(named: "shirt-number"))
        XCTAssertNotNil(homeRig.root.findEntity(named: "chest-number"))
    }

    func testNearShoulderUsesRoundedHardCappedSleeveWithInsetPivots() throws {
        let torso = try ReplayAthleteMeshLibrary.mesh(for: .torso, lod: .near)
        let sleeve = try ReplayAthleteMeshLibrary.mesh(for: .sleeve, lod: .near)

        // Eight/five authored rings plus two separate cap rings and centres.
        // Separate cap vertices preserve flat end normals instead of smearing
        // side normals into dark radial wedges at the animated shoulder seam.
        XCTAssertEqual(torso.metrics.vertices, 142)
        XCTAssertEqual(torso.metrics.triangles, 224)
        XCTAssertEqual(sleeve.metrics.vertices, 100)
        XCTAssertEqual(sleeve.metrics.triangles, 140)

        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "red-lb"))
        let rig = try ReplayAthleteFactory.make(for: player, lod: .near)
        XCTAssertEqual(rig.joints[.leftShoulder].position.x, -0.218, accuracy: 0.000_1)
        XCTAssertEqual(rig.joints[.rightShoulder].position.x, 0.218, accuracy: 0.000_1)

        let torsoEntity = try XCTUnwrap(rig.root.findEntity(named: "torso"))
        let leftSleeve = try XCTUnwrap(rig.root.findEntity(named: "left-sleeve"))
        let torsoBounds = torsoEntity.visualBounds(relativeTo: rig.root)
        let sleeveBounds = leftSleeve.visualBounds(relativeTo: rig.root)
        let horizontalOverlap = min(torsoBounds.max.x, sleeveBounds.max.x)
            - max(torsoBounds.min.x, sleeveBounds.min.x)
        let verticalOverlap = min(torsoBounds.max.y, sleeveBounds.max.y)
            - max(torsoBounds.min.y, sleeveBounds.min.y)
        XCTAssertGreaterThan(horizontalOverlap, 0.10)
        XCTAssertGreaterThan(verticalOverlap, 0.18)
    }

    func testHeadAndNeckUseAConnectedTwoJointGazeChain() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let rig = try ReplayAthleteFactory.make(for: player, lod: .near)

        XCTAssertEqual(rig.joints[.neck].parent?.name, ReplayAthleteJoint.spine.rawValue)
        XCTAssertEqual(rig.joints[.headRoot].parent?.name, ReplayAthleteJoint.neck.rawValue)
        XCTAssertNotNil(rig.root.findEntity(named: "neck-shell"))

        let ball = scenario.ball.pose(at: 14.1)
        ReplayAthleteMotion.update(
            rig,
            from: player,
            at: 14.1,
            lookTargetWorldPosition: [ball.position.x, ball.height, ball.position.z]
        )
        XCTAssertNotEqual(rig.joints[.neck].orientation.vector, simd_quatf().vector)
        XCTAssertNotEqual(rig.joints[.headRoot].orientation.vector, simd_quatf().vector)
    }

    func testFootballGazeTracksEitherSideAndSplitsRotationAcrossNeckAndHead() {
        let track = PlayerTrack(
            id: "gaze-test-seven",
            displayName: "Gaze Test",
            role: "Right winger",
            shirtNumber: 7,
            team: .home,
            isGoalkeeper: false,
            keyframes: [
                MotionKeyframe(time: 0, position: .init(x: 0, z: 0), facingDegrees: 0),
                MotionKeyframe(time: 10, position: .init(x: 0, z: 10), facingDegrees: 0),
            ]
        )
        let right = ReplayAthleteMotion.lookPose(
            for: track,
            at: 5,
            targetWorldPosition: [10, 0.11, 10]
        )
        let left = ReplayAthleteMotion.lookPose(
            for: track,
            at: 5,
            targetWorldPosition: [-10, 0.11, 10]
        )

        XCTAssertGreaterThan(right.combinedYawRadians, 0.25)
        XCTAssertLessThan(left.combinedYawRadians, -0.25)
        XCTAssertEqual(
            right.neckYawRadians / right.combinedYawRadians,
            0.42,
            accuracy: 0.000_1
        )
        XCTAssertLessThanOrEqual(abs(right.combinedYawRadians), 64 * .pi / 180)
        XCTAssertLessThanOrEqual(abs(left.combinedYawRadians), 64 * .pi / 180)
    }

    func testCloseBallGlanceLooksFurtherDownWithoutPinningHeadOrBreakingSeek() {
        let track = PlayerTrack(
            id: "gaze-test-nine",
            displayName: "Gaze Test",
            role: "Centre forward",
            shirtNumber: 9,
            team: .home,
            isGoalkeeper: false,
            keyframes: [
                MotionKeyframe(time: 0, position: .init(x: 0, z: 0), facingDegrees: 0),
                MotionKeyframe(time: 10, position: .init(x: 0, z: 10), facingDegrees: 0),
            ]
        )
        let close = ReplayAthleteMotion.lookPose(
            for: track,
            at: 5,
            targetWorldPosition: [0, 0.11, 5.6]
        )
        let distant = ReplayAthleteMotion.lookPose(
            for: track,
            at: 5,
            targetWorldPosition: [0, 0.11, 30]
        )
        let soughtAgain = ReplayAthleteMotion.lookPose(
            for: track,
            at: 5,
            targetWorldPosition: [0, 0.11, 5.6]
        )

        XCTAssertEqual(close, soughtAgain)
        XCTAssertGreaterThan(close.combinedPitchRadians, distant.combinedPitchRadians)
        XCTAssertGreaterThan(close.combinedPitchRadians, 0.15)
        XCTAssertLessThanOrEqual(close.combinedPitchRadians, 25 * .pi / 180)

        let malformed = ReplayAthleteMotion.lookPose(
            for: track,
            at: .nan,
            targetWorldPosition: [.nan, .infinity, -.infinity]
        )
        XCTAssertTrue(malformed.combinedYawRadians.isFinite)
        XCTAssertTrue(malformed.combinedPitchRadians.isFinite)
    }

    func testFootballGazeRemainsContinuousAcrossBallAttentionDistances() {
        let track = PlayerTrack(
            id: "gaze-distance-continuity-seven",
            displayName: "Gaze Test",
            role: "Right winger",
            shirtNumber: 7,
            team: .home,
            isGoalkeeper: false,
            keyframes: [
                MotionKeyframe(time: 0, position: .init(x: 0, z: 0), facingDegrees: 0),
                MotionKeyframe(time: 10, position: .init(x: 0, z: 10), facingDegrees: 0),
            ]
        )

        func look(distance: Float) -> ReplayAthleteLookPose {
            let bearing: Float = 48 * .pi / 180
            return ReplayAthleteMotion.lookPose(
                for: track,
                at: 5,
                targetWorldPosition: [
                    sin(bearing) * distance,
                    0.11,
                    5 + (cos(bearing) * distance),
                ]
            )
        }

        for boundary: Float in [0.04, 1.25, 4] {
            let before = look(distance: boundary - 0.01)
            let after = look(distance: boundary + 0.01)
            XCTAssertLessThan(
                abs(after.combinedYawRadians - before.combinedYawRadians),
                0.025,
                "ball attention snapped in yaw near \(boundary) metres"
            )
            XCTAssertLessThan(
                abs(after.combinedPitchRadians - before.combinedPitchRadians),
                0.025,
                "ball attention snapped in pitch near \(boundary) metres"
            )
        }

        let near = look(distance: 0.45)
        let far = look(distance: 8)
        XCTAssertGreaterThan(
            abs(far.combinedYawRadians),
            abs(near.combinedYawRadians),
            "distant play should still attract more gaze than a ball at the feet"
        )
    }

    func testDemoOverlapContainsMatchPaceBurstWithoutTeleporting() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let rightBack = try XCTUnwrap(scenario.player(id: "navy-rb"))
        let recoveringWinger = try XCTUnwrap(scenario.player(id: "red-lw"))

        XCTAssertGreaterThan(rightBack.locomotion(at: 12.8).speedMetresPerSecond, 4.8)
        XCTAssertGreaterThan(recoveringWinger.locomotion(at: 14.0).speedMetresPerSecond, 4.0)

        for player in scenario.players {
            for (start, end) in zip(player.keyframes, player.keyframes.dropFirst()) {
                let duration = Float(end.time - start.time)
                XCTAssertGreaterThan(duration, 0, "non-increasing telemetry for \(player.id)")
                let speed = ReplayGeometry.distance(start.position, end.position) / duration
                XCTAssertLessThan(speed, 9, "implausible teleport for \(player.id)")
            }
        }
    }

    func testLODPolicyUsesHysteresisAndSanitizesDistances() {
        let policy = ReplayAthleteLODPolicy(nearDistance: 8, farDistance: 23, hysteresis: 1.5)
        XCTAssertEqual(policy.level(forDistance: 5), .near)
        XCTAssertEqual(policy.level(forDistance: 8.8, current: .near), .near)
        XCTAssertEqual(policy.level(forDistance: 9.6, current: .near), .mid)
        XCTAssertEqual(policy.level(forDistance: 22.2, current: .far), .far)
        XCTAssertEqual(policy.level(forDistance: 21.0, current: .far), .mid)
        XCTAssertEqual(policy.level(forDistance: -.infinity), .far)
        XCTAssertEqual(policy.level(forDistance: -.greatestFiniteMagnitude), .near)
    }

    func testDeploymentPlansExposeAthleteOnlyHeadroomWithoutClaimingWholeSceneFit() {
        let shared = ReplayAthleteDeploymentPlan.sharedSpaceXI
        let full = ReplayAthleteDeploymentPlan.fullSpaceXI
        XCTAssertEqual(shared.playerCount, 22)
        XCTAssertEqual(full.playerCount, 22)

        let sharedLimits = ReplayAthleteRenderingSpace.shared.appleGuidance
        let fullLimits = ReplayAthleteRenderingSpace.full.appleGuidance
        let sharedMetrics = shared.athleteOnlyUpperBound
        let fullMetrics = full.athleteOnlyUpperBound
        XCTAssertEqual(sharedMetrics.drawCalls, 176)
        XCTAssertEqual(fullMetrics.drawCalls, 242)
        XCTAssertTrue(sharedMetrics.fitsWithin(sharedLimits))
        XCTAssertTrue(fullMetrics.fitsWithin(fullLimits))
        XCTAssertEqual(sharedMetrics.remainingWithin(sharedLimits).drawCalls, 74)
        XCTAssertEqual(fullMetrics.remainingWithin(fullLimits).drawCalls, 258)
    }

    func testLocomotionAndRagdollMappingAreSeekDeterministic() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let player = try XCTUnwrap(scenario.player(id: "red-lb"))
        let rig = try ReplayAthleteFactory.make(for: player, lod: .near)
        let cue = PlayerRagdollCue(
            playerID: player.id,
            impactTime: 13.55,
            duration: 2.8,
            impactDirection: [-0.55, 0.84],
            impulse: 0.92
        )

        ReplayAthleteMotion.update(rig, from: player, at: 14.1, ragdollCue: cue)
        let firstPosition = rig.joints[.bodyRoot].position
        let firstOrientation = rig.joints[.bodyRoot].orientation.vector
        let firstKnee = rig.joints[.leftKnee].orientation.vector
        let firstNeck = rig.joints[.neck].orientation.vector

        ReplayAthleteMotion.update(rig, from: player, at: 19.0, ragdollCue: cue)
        ReplayAthleteMotion.update(rig, from: player, at: 14.1, ragdollCue: cue)
        XCTAssertEqual(rig.joints[.bodyRoot].position, firstPosition)
        XCTAssertEqual(rig.joints[.bodyRoot].orientation.vector, firstOrientation)
        XCTAssertEqual(rig.joints[.leftKnee].orientation.vector, firstKnee)
        XCTAssertEqual(rig.joints[.neck].orientation.vector, firstNeck)
    }

    func testProceduralPoseHasDistinctIdleSprintAndCutMechanicsAtOnePhase() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let phase: Float = .pi / 2

        func sample(
            state: PlayerLocomotionState,
            speed: Float,
            turn: Float = 0,
            acceleration: Float = 0
        ) -> PlayerLocomotionSample {
            PlayerLocomotionSample(
                motion: PlayerMotionState(
                    speedMetresPerSecond: speed,
                    distanceTravelled: 0,
                    locomotionPhase: phase
                ),
                speedMetresPerSecond: speed,
                accelerationMetresPerSecondSquared: acceleration,
                turnRateDegreesPerSecond: turn,
                state: state
            )
        }

        let idle = ReplayAthleteMotion.locomotionPose(
            for: player,
            at: 12,
            locomotion: sample(state: .idle, speed: 0)
        )
        let sprint = ReplayAthleteMotion.locomotionPose(
            for: player,
            at: 12,
            locomotion: sample(state: .sprint, speed: 6.4, acceleration: 5)
        )
        let cut = ReplayAthleteMotion.locomotionPose(
            for: player,
            at: 12,
            locomotion: sample(state: .cut, speed: 3, turn: 180)
        )

        let down = SIMD3<Float>(0, -1, 0)
        XCTAssertGreaterThan(
            simd_distance(
                idle.leftHipOrientation.act(down),
                sprint.leftHipOrientation.act(down)
            ),
            0.35,
            "Sprint needs a visibly longer stride than idle"
        )
        XCTAssertGreaterThan(
            simd_distance(
                sprint.bodyOrientation.act(down),
                idle.bodyOrientation.act(down)
            ),
            0.01,
            "Sprint acceleration needs a distinct forward body lean"
        )
        XCTAssertGreaterThan(
            simd_distance(
                cut.hipsOrientation.act(down),
                sprint.hipsOrientation.act(down)
            ),
            0.08,
            "A cut needs a planted lateral bank rather than straight-run posing"
        )
    }

    func testProceduralPoseRemainsContinuousAcrossSemanticPaceAndCutThresholds() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let phase: Float = .pi * 0.73

        func sample(speed: Float, turn: Float = 0) -> PlayerLocomotionSample {
            PlayerLocomotionSample(
                motion: PlayerMotionState(
                    speedMetresPerSecond: speed,
                    distanceTravelled: 7.5,
                    locomotionPhase: phase
                ),
                speedMetresPerSecond: speed,
                accelerationMetresPerSecondSquared: 0,
                turnRateDegreesPerSecond: turn,
                state: PlayerLocomotionSample.classify(
                    speedMetresPerSecond: speed,
                    turnRateDegreesPerSecond: turn
                )
            )
        }

        func pose(_ sample: PlayerLocomotionSample) -> ReplayAthleteLocomotionPose {
            ReplayAthleteMotion.locomotionPose(
                for: player,
                at: 12,
                locomotion: sample,
                gaitPhase: phase
            )
        }

        let boundaries: [(PlayerLocomotionSample, PlayerLocomotionSample)] = [
            (sample(speed: 0.219), sample(speed: 0.221)),
            (sample(speed: 1.649), sample(speed: 1.651)),
            (sample(speed: 3.799), sample(speed: 3.801)),
            (sample(speed: 3, turn: 69.9), sample(speed: 3, turn: 70.1)),
        ]
        XCTAssertNotEqual(boundaries[0].0.state, boundaries[0].1.state)
        XCTAssertNotEqual(boundaries[1].0.state, boundaries[1].1.state)
        XCTAssertNotEqual(boundaries[2].0.state, boundaries[2].1.state)
        XCTAssertNotEqual(boundaries[3].0.state, boundaries[3].1.state)

        let referenceAxes: [SIMD3<Float>] = [
            [0, -1, 0],
            [0, 0, 1],
        ]
        for (beforeSample, afterSample) in boundaries {
            let before = pose(beforeSample)
            let after = pose(afterSample)
            let orientationPairs: [(simd_quatf, simd_quatf)] = [
                (before.bodyOrientation, after.bodyOrientation),
                (before.hipsOrientation, after.hipsOrientation),
                (before.spineOrientation, after.spineOrientation),
                (before.leftHipOrientation, after.leftHipOrientation),
                (before.rightHipOrientation, after.rightHipOrientation),
                (before.leftKneeOrientation, after.leftKneeOrientation),
                (before.rightKneeOrientation, after.rightKneeOrientation),
                (before.leftShoulderOrientation, after.leftShoulderOrientation),
                (before.rightShoulderOrientation, after.rightShoulderOrientation),
            ]
            for (beforeOrientation, afterOrientation) in orientationPairs {
                for axis in referenceAxes {
                    XCTAssertLessThan(
                        simd_distance(
                            beforeOrientation.act(axis),
                            afterOrientation.act(axis)
                        ),
                        0.012,
                        "A semantic state boundary must not become a visible pose cut"
                    )
                }
            }
            XCTAssertLessThan(
                simd_distance(before.bodyPosition, after.bodyPosition),
                0.002,
                "Root grounding and sway must remain continuous across state labels"
            )
        }
    }

    func testFootfallTimingAddsWalkSupportAndSprintFlightWithoutFrameHistory() {
        let flightPhase = Float.pi * 2 * 0.30
        let oppositePhase = flightPhase + .pi

        let walkingLead = ReplayAthleteMotion.footfall(for: .walk, phase: flightPhase)
        let walkingTrail = ReplayAthleteMotion.footfall(for: .walk, phase: oppositePhase)
        let sprintingLead = ReplayAthleteMotion.footfall(for: .sprint, phase: flightPhase)
        let sprintingTrail = ReplayAthleteMotion.footfall(for: .sprint, phase: oppositePhase)

        XCTAssertTrue(
            walkingLead.isStance || walkingTrail.isStance,
            "A walking athlete should retain ground support at this phase"
        )
        XCTAssertFalse(
            sprintingLead.isStance || sprintingTrail.isStance,
            "A sprint needs a brief flight phase instead of a marching walk cycle"
        )

        for state in PlayerLocomotionState.allCases {
            for phase in [Float.nan, -Float.infinity, -13.7, 0, 29.4] {
                let first = ReplayAthleteMotion.footfall(for: state, phase: phase)
                let soughtAgain = ReplayAthleteMotion.footfall(for: state, phase: phase)
                XCTAssertEqual(first, soughtAgain)
                XCTAssertTrue(first.stride.isFinite)
                XCTAssertTrue(first.swingLift.isFinite)
                XCTAssertTrue(first.stanceCompression.isFinite)
                XCTAssertTrue(first.footPitch.isFinite)
                XCTAssertTrue(first.contactWeight.isFinite)
                XCTAssertGreaterThanOrEqual(first.contactWeight, 0)
                XCTAssertLessThanOrEqual(first.contactWeight, 1)
            }
        }
    }

    func testSprintFootfallRollsFromHeelStrikeThroughToeOffIntoTuckedRecovery() {
        let turn = Float.pi * 2
        let touchdown = ReplayAthleteMotion.footfall(for: .sprint, phase: turn * 0.031)
        let lateStance = ReplayAthleteMotion.footfall(for: .sprint, phase: turn * 0.24)
        let midRecovery = ReplayAthleteMotion.footfall(for: .sprint, phase: turn * 0.64)

        XCTAssertTrue(touchdown.isStance)
        XCTAssertLessThan(touchdown.stride, -0.95)
        XCTAssertLessThan(touchdown.footPitch, -0.10, "heel strike should leave the toe lifted")
        XCTAssertLessThan(touchdown.contactWeight, 0.02, "heel strike must load without a support pop")

        XCTAssertTrue(lateStance.isStance)
        XCTAssertGreaterThan(lateStance.stride, 0.90)
        XCTAssertGreaterThan(lateStance.footPitch, 0.15, "toe-off should roll through the forefoot")
        XCTAssertLessThan(lateStance.contactWeight, 0.10, "toe-off must unload before flight")

        XCTAssertFalse(midRecovery.isStance)
        XCTAssertGreaterThan(midRecovery.swingLift, 0.95, "recovery leg should fold quickly for clearance")
        XCTAssertLessThan(midRecovery.footPitch, -0.10, "swing boot should dorsiflex for turf clearance")
        XCTAssertEqual(midRecovery.contactWeight, 0)
    }

    func testNearRigGroundingKeepsAtLeastOneBootOnOrAboveTurfAcrossGait() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let player = try XCTUnwrap(scenario.player(id: "navy-rw"))
        let rig = try ReplayAthleteFactory.make(for: player, lod: .near)
        let leftBoot = try XCTUnwrap(rig.root.findEntity(named: "left-boot"))
        let rightBoot = try XCTUnwrap(rig.root.findEntity(named: "right-boot"))

        for time in stride(from: 0.0, through: scenario.duration, by: 1.0) {
            ReplayAthleteMotion.update(rig, from: player, at: time)
            let leftMin = leftBoot.visualBounds(relativeTo: rig.root).min.y
            let rightMin = rightBoot.visualBounds(relativeTo: rig.root).min.y
            let stanceSole = min(leftMin, rightMin)
            XCTAssertGreaterThanOrEqual(stanceSole, -0.012, "turf penetration at \(time)s")
            XCTAssertLessThanOrEqual(stanceSole, 0.045, "both feet float at \(time)s")
        }
    }

    func testLoadedSprintBootStaysWithinThirtyPercentOfTrackTravelDuringSupport() throws {
        let track = PlayerTrack(
            id: "contact-sprint-seven",
            displayName: "Contact Sprint",
            role: "Right winger",
            shirtNumber: 7,
            team: .home,
            isGoalkeeper: false,
            keyframes: [
                MotionKeyframe(time: 0, position: .init(x: 0, z: 0), facingDegrees: 0),
                MotionKeyframe(time: 3, position: .init(x: 0, z: 18), facingDegrees: 0),
            ]
        )
        let rig = try ReplayAthleteFactory.make(for: track, lod: .near)
        let leftBoot = try XCTUnwrap(rig.root.findEntity(named: "left-boot"))

        struct Episode {
            let rootTravel: Float
            let bootTravel: Float
        }
        var episodes: [Episode] = []
        var startRootZ: Float?
        var startBootZ: Float?
        var latestRootZ: Float = 0
        var latestBootZ: Float = 0

        func finishEpisode() {
            guard let startRootZ, let startBootZ else { return }
            episodes.append(
                Episode(
                    rootTravel: abs(latestRootZ - startRootZ),
                    bootTravel: abs(latestBootZ - startBootZ)
                )
            )
        }

        for frame in 0 ... 360 {
            let time = Double(frame) / 120
            let pose = track.presentationPose(at: time)
            ReplayAthleteMotion.update(rig, from: track, at: time)
            let phase = track.gaitPhase(at: time)
            let footfall = ReplayAthleteMotion.footfall(for: .sprint, phase: phase)
            let bounds = leftBoot.visualBounds(relativeTo: rig.root)
            let worldBootZ = pose.position.z + ((bounds.min.z + bounds.max.z) * 0.5)

            if footfall.contactWeight >= 0.35 {
                if startRootZ == nil {
                    startRootZ = pose.position.z
                    startBootZ = worldBootZ
                }
                latestRootZ = pose.position.z
                latestBootZ = worldBootZ
            } else if startRootZ != nil {
                finishEpisode()
                startRootZ = nil
                startBootZ = nil
            }
        }
        finishEpisode()

        let representative = try XCTUnwrap(episodes.max { $0.rootTravel < $1.rootTravel })
        XCTAssertGreaterThan(representative.rootTravel, 0.50)
        XCTAssertLessThan(
            representative.bootTravel / representative.rootTravel,
            0.30,
            "The loaded boot should stay visually planted while the telemetry root advances"
        )
    }

    func testSupportGroundingLoadsOneBootAndPreservesRunningFlightClearance() throws {
        let track = PlayerTrack(
            id: "ground-contact-eleven",
            displayName: "Ground Contact",
            role: "Left winger",
            shirtNumber: 11,
            team: .home,
            isGoalkeeper: false,
            keyframes: [
                MotionKeyframe(time: 0, position: .init(x: 0, z: 0), facingDegrees: 0),
                MotionKeyframe(time: 3, position: .init(x: 0, z: 18), facingDegrees: 0),
            ]
        )
        let rig = try ReplayAthleteFactory.make(for: track, lod: .near)
        let leftBoot = try XCTUnwrap(rig.root.findEntity(named: "left-boot"))
        let rightBoot = try XCTUnwrap(rig.root.findEntity(named: "right-boot"))
        var loadedSoleHeights: [Float] = []
        var flightSoleHeights: [Float] = []
        var forwardBodyHeights: [SIMD3<Float>] = []

        let sampleTimes = stride(from: 0.0, through: 2.0, by: 1.0 / 180)
        for time in sampleTimes {
            ReplayAthleteMotion.update(rig, from: track, at: time)
            let phase = track.gaitPhase(at: time)
            let left = ReplayAthleteMotion.footfall(for: .sprint, phase: phase)
            let right = ReplayAthleteMotion.footfall(for: .sprint, phase: phase + .pi)
            let leftMinimum = leftBoot.visualBounds(relativeTo: rig.root).min.y
            let rightMinimum = rightBoot.visualBounds(relativeTo: rig.root).min.y

            if max(left.contactWeight, right.contactWeight) >= 0.85 {
                loadedSoleHeights.append(
                    left.contactWeight >= right.contactWeight ? leftMinimum : rightMinimum
                )
            } else if !left.isStance, !right.isStance {
                flightSoleHeights.append(min(leftMinimum, rightMinimum))
            }
            forwardBodyHeights.append(rig.joints[.bodyRoot].position)
        }

        XCTAssertFalse(loadedSoleHeights.isEmpty)
        XCTAssertFalse(flightSoleHeights.isEmpty)
        XCTAssertGreaterThanOrEqual(loadedSoleHeights.min() ?? -.infinity, -0.012)
        XCTAssertLessThanOrEqual(loadedSoleHeights.max() ?? .infinity, 0.035)

        let loadedMean = loadedSoleHeights.reduce(0, +) / Float(loadedSoleHeights.count)
        let flightMean = flightSoleHeights.reduce(0, +) / Float(flightSoleHeights.count)
        XCTAssertGreaterThan(
            flightMean,
            loadedMean + 0.008,
            "Both boots should visibly clear the turf during the sprint flight phase"
        )

        let reverseBodyHeights = sampleTimes.reversed().map {
            ReplayAthleteMotion.locomotionPose(for: track, at: $0).bodyPosition
        }.reversed()
        XCTAssertEqual(Array(reverseBodyHeights), forwardBodyHeights)
    }

    func testIdleBreathingArticulatesTorsoWithoutMovingBodyRoot() {
        let track = PlayerTrack(
            id: "breathing-six",
            displayName: "Breathing Six",
            role: "Centre back",
            shirtNumber: 6,
            team: .home,
            isGoalkeeper: false,
            keyframes: [
                MotionKeyframe(time: 0, position: .zero, facingDegrees: 0),
                MotionKeyframe(time: 6, position: .zero, facingDegrees: 0),
            ]
        )

        let first = ReplayAthleteMotion.locomotionPose(for: track, at: 0)
        let second = ReplayAthleteMotion.locomotionPose(for: track, at: 2.3)

        XCTAssertEqual(first.bodyPosition, second.bodyPosition)
        XCTAssertNotEqual(first.spineOrientation, second.spineOrientation)
    }

    func testRagdollProxyContractHasUniqueMappedJointsAndHumanScaleMass() {
        let parts = ReplayAthleteRagdollProfile.parts
        XCTAssertEqual(Set(parts.map(\.joint.rawValue)).count, parts.count)
        XCTAssertEqual(ReplayAthleteRagdollProfile.totalMass, 76.0, accuracy: 0.001)
        XCTAssertTrue(parts.allSatisfy { ReplayAthleteJoint.allCases.contains($0.joint) })
        XCTAssertTrue(parts.allSatisfy { $0.mass > 0 })
    }

    private func countModels(in entity: Entity) -> Int {
        (entity.components[ModelComponent.self] == nil ? 0 : 1)
            + entity.children.reduce(0) { $0 + countModels(in: $1) }
    }
}
