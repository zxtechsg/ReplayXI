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

        ReplayAthleteMotion.update(rig, from: player, at: 19.0, ragdollCue: cue)
        ReplayAthleteMotion.update(rig, from: player, at: 14.1, ragdollCue: cue)
        XCTAssertEqual(rig.joints[.bodyRoot].position, firstPosition)
        XCTAssertEqual(rig.joints[.bodyRoot].orientation.vector, firstOrientation)
        XCTAssertEqual(rig.joints[.leftKnee].orientation.vector, firstKnee)
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
            }
        }
    }

    func testSprintFootfallRollsFromHeelStrikeThroughToeOffIntoTuckedRecovery() {
        let turn = Float.pi * 2
        let touchdown = ReplayAthleteMotion.footfall(for: .sprint, phase: turn * 0.851)
        let lateStance = ReplayAthleteMotion.footfall(for: .sprint, phase: turn * 0.21)
        let midRecovery = ReplayAthleteMotion.footfall(for: .sprint, phase: turn * 0.55)

        XCTAssertTrue(touchdown.isStance)
        XCTAssertLessThan(touchdown.stride, -0.95)
        XCTAssertLessThan(touchdown.footPitch, -0.10, "heel strike should leave the toe lifted")

        XCTAssertTrue(lateStance.isStance)
        XCTAssertGreaterThan(lateStance.stride, 0.90)
        XCTAssertGreaterThan(lateStance.footPitch, 0.15, "toe-off should roll through the forefoot")

        XCTAssertFalse(midRecovery.isStance)
        XCTAssertGreaterThan(midRecovery.swingLift, 0.95, "recovery leg should fold quickly for clearance")
        XCTAssertLessThan(midRecovery.footPitch, -0.10, "swing boot should dorsiflex for turf clearance")
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
