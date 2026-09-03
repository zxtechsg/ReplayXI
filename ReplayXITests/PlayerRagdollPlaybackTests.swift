import Foundation
import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlayerRagdollPlaybackTests: XCTestCase {
    func testCueSanitizesBoundsAndUsesSoftPlaybackEdges() {
        let cue = PlayerRagdollCue(
            playerID: "navy-rw",
            impactTime: 12,
            duration: 20,
            impactDirection: .zero,
            impulse: 8
        )

        XCTAssertEqual(cue.duration, PlayerRagdollCue.maximumDuration)
        XCTAssertEqual(cue.impactDirection, SIMD2<Float>(0, 1))
        XCTAssertEqual(cue.impulse, 2.1)
        XCTAssertFalse(cue.isActive(at: 11.999))
        XCTAssertTrue(cue.isActive(at: 12))
        XCTAssertFalse(cue.isActive(at: cue.endTime))
        XCTAssertEqual(cue.influence(at: 12), 0)
        XCTAssertGreaterThan(cue.influence(at: 12.5), 0.99)
        XCTAssertLessThan(cue.influence(at: cue.endTime - 0.05), 0.05)
        XCTAssertEqual(cue.telemetryRelease(at: 12.5), 0)
        XCTAssertGreaterThan(cue.telemetryRelease(at: cue.endTime - 0.05), 0.98)
    }

    func testCoachFocusAuthoredImpactRequiresExplicitOptInInPlayerPOV() throws {
        let coachFocus = try XCTUnwrap(DemoScenarios.scenario(for: .coachFocus))
        let squadReplay = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let cue = try XCTUnwrap(PlayerRagdollCue.authoredDemo(for: coachFocus))

        XCTAssertEqual(cue.playerID, "red-lb")
        XCTAssertTrue(cue.isActive(at: 14.1))
        XCTAssertNil(PlayerRagdollCue.authoredDemo(for: squadReplay))

        let root = PitchSceneFactory.makeMatchRoot(for: coachFocus)
        PitchSceneFactory.update(
            root: root,
            scenario: coachFocus,
            time: 14.1,
            viewMode: .firstPerson,
            perspectiveID: coachFocus.defaultPerspectiveID,
            marks: coachFocus.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )
        XCTAssertNil(
            root.findEntity(named: "player-red-lb")?
                .findEntity(named: "ragdoll-physics-active")
        )

        PitchSceneFactory.update(
            root: root,
            scenario: coachFocus,
            time: 14.1,
            viewMode: .firstPerson,
            perspectiveID: coachFocus.defaultPerspectiveID,
            marks: coachFocus.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil,
            ragdollCue: cue
        )
        XCTAssertNotNil(
            root.findEntity(named: "player-red-lb")?
                .findEntity(named: "ragdoll-physics-active")
        )
    }

    func testFixedStepRagdollIsSeekDeterministicAndGroundConstrained() {
        let cue = PlayerRagdollCue(
            playerID: "red-lb",
            impactTime: 10,
            impactDirection: SIMD2<Float>(0.8, 0.6),
            impulse: 1.15
        )
        let upright = PlayerRagdollPlayback.pose(for: cue, at: 10)
        let falling = PlayerRagdollPlayback.pose(for: cue, at: 10.25)
        let settled = PlayerRagdollPlayback.pose(for: cue, at: 12.4)
        _ = PlayerRagdollPlayback.pose(for: cue, at: 13.1)
        let seekedFalling = PlayerRagdollPlayback.pose(for: cue, at: 10.25)

        XCTAssertEqual(falling, seekedFalling)
        XCTAssertEqual(upright.fallAngle, 0, accuracy: 0.000_001)
        XCTAssertGreaterThan(falling.fallAngle, 0.4)
        XCTAssertGreaterThan(settled.fallAngle, falling.fallAngle)
        XCTAssertLessThan(settled.bodyCenter.y, upright.bodyCenter.y)
        XCTAssertGreaterThanOrEqual(settled.bodyCenter.y, 0.18)
        XCTAssertGreaterThan(settled.leftKnee, 0)
        XCTAssertGreaterThan(settled.leftElbow, 0)
        XCTAssertLessThanOrEqual(settled.leftKnee, 1.62)
        XCTAssertLessThanOrEqual(settled.leftElbow, 1.72)
        XCTAssertEqual(simd_length(settled.fallAxis), 1, accuracy: 0.000_1)
        XCTAssertLessThanOrEqual(PlayerRagdollPlayback.maximumStepCount, 360)
    }

    func testSceneRagdollIsSingleSubjectSeekableAndRemovesPhysicsAfterCue() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let playerID = scenario.defaultPerspectiveID
        let cue = PlayerRagdollCue(
            playerID: playerID,
            impactTime: 12,
            duration: 3.2,
            impactDirection: SIMD2<Float>(0.45, 0.89),
            impulse: 1.1
        )
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        func update(at time: TimeInterval) {
            PitchSceneFactory.update(
                root: root,
                scenario: scenario,
                time: time,
                viewMode: .tacticalTable,
                perspectiveID: playerID,
                marks: scenario.coachMarks,
                showsLaneLens: false,
                isDrawing: false,
                positionalOriginTransform: nil,
                ragdollCue: cue
            )
        }

        update(at: 13)
        let selected = try XCTUnwrap(root.findEntity(named: "player-\(playerID)"))
        let fullRig = try XCTUnwrap(selected.findEntity(named: "full-rig"))
        let body = try XCTUnwrap(fullRig.findEntity(named: "body-root"))
        let firstBodyPosition = body.position
        let firstBodyOrientation = body.orientation.vector

        XCTAssertNotNil(fullRig.findEntity(named: "ragdoll-physics-active"))
        XCTAssertEqual(
            scenario.players.compactMap {
                root.findEntity(named: "player-\($0.id)")?
                    .findEntity(named: "ragdoll-physics-active")
            }.count,
            1
        )

        for name in [
            "hips", "spine", "head-root", "left-hip", "right-hip",
            "left-knee", "right-knee", "left-shoulder", "right-shoulder",
            "left-elbow", "right-elbow",
        ] {
            let part = try XCTUnwrap(fullRig.findEntity(named: name), name)
            XCTAssertEqual(part.components[PhysicsBodyComponent.self]?.mode, .kinematic, name)
            XCTAssertNotNil(part.components[PhysicsMotionComponent.self], name)
            XCTAssertNotNil(part.components[CollisionComponent.self], name)
        }

        update(at: 16)
        XCTAssertNil(fullRig.findEntity(named: "ragdoll-physics-active"))
        XCTAssertNil(fullRig.findEntity(named: "spine")?.components[PhysicsBodyComponent.self])
        XCTAssertNil(fullRig.findEntity(named: "spine")?.components[CollisionComponent.self])

        update(at: 13)
        XCTAssertEqual(body.position.x, firstBodyPosition.x, accuracy: 0.000_001)
        XCTAssertEqual(body.position.y, firstBodyPosition.y, accuracy: 0.000_001)
        XCTAssertEqual(body.position.z, firstBodyPosition.z, accuracy: 0.000_001)
        XCTAssertEqual(body.orientation.vector, firstBodyOrientation)
    }

    func testFirstPersonRagdollPromotesSubjectWithoutBreakingRigBudget() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let wearerID = scenario.defaultPerspectiveID
        let time: TimeInterval = 12
        let wearerPosition = try XCTUnwrap(
            scenario.player(id: wearerID)?.pose(at: time).position
        )
        let distantPlayer = try XCTUnwrap(
            scenario.players
                .filter { $0.id != wearerID }
                .max {
                    ReplayGeometry.distance($0.pose(at: time).position, wearerPosition)
                        < ReplayGeometry.distance($1.pose(at: time).position, wearerPosition)
                }
        )
        let cue = PlayerRagdollCue(
            playerID: distantPlayer.id,
            impactTime: 11,
            impactDirection: SIMD2<Float>(-0.3, 0.95)
        )
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: time,
            viewMode: .firstPerson,
            perspectiveID: wearerID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil,
            ragdollCue: cue
        )

        let detailedPlayers = scenario.players.filter {
            root.findEntity(named: "player-\($0.id)")?
                .findEntity(named: "full-rig") != nil
        }
        XCTAssertEqual(detailedPlayers.count, PitchSceneFactory.firstPersonDetailedRigLimit)
        XCTAssertNil(
            root.findEntity(named: "player-\(wearerID)")?
                .findEntity(named: "full-rig")
        )
        XCTAssertNotNil(
            root.findEntity(named: "player-\(distantPlayer.id)")?
                .findEntity(named: "ragdoll-physics-active")
        )
    }

    func testDetailedRigExposesNearLODIdentityFaceKitAndLimbReadability() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 12,
            viewMode: .touchline,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )

        let player = try XCTUnwrap(root.findEntity(named: "player-\(scenario.defaultPerspectiveID)"))
        for name in [
            "left-eye", "right-eye", "nose", "hair",
            "left-kit-stripe", "right-kit-stripe",
            "left-thigh", "right-shin", "left-upper-arm", "right-forearm",
            "left-hand", "right-boot-accent",
            "shirt-number", "chest-number",
        ] {
            XCTAssertNotNil(player.findEntity(named: name), name)
        }
    }
}
