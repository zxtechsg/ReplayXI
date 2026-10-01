import RealityKit
import XCTest
import simd
@testable import ReplayXI

/// Checks the admitted native save, not a synthetic ball placed within arm
/// reach. Palm markers are the existing rig convention, not hand-mesh vertices.
@MainActor
final class ReplayReferenceSaveContactTests: XCTestCase {
    override func tearDown() {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayTripoAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    func testActualReboundSaveTouchesBothPalmsAcrossNearAndLowRigs() async throws {
        try await assertActualReboundSaveTouchesBothPalms(useTripo: false)
    }

    func testActualReboundSaveTouchesBothPalmsAcrossTripoNearAndLowRigs() async throws {
        try await assertActualReboundSaveTouchesBothPalms(useTripo: true)
    }

    private func assertActualReboundSaveTouchesBothPalms(useTripo: Bool) async throws {
        let rig = useTripo ? "Tripo52" : "Rocketbox80"
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
        let recording = try await ReplayNativeBallPhysics.bake(track: scenario.ball,
            players: scenario.players, plannedTouches: plan)
        XCTAssertEqual(recording.missedTouchCount, 0)
        XCTAssertEqual(recording.touches.count, plan.count)
        let saves = recording.touches.filter { $0.kind == .save }
        XCTAssertEqual(saves.count, 1, "The actual study must admit its keeper action")
        let touch = try XCTUnwrap(saves.first)
        let player = try XCTUnwrap(scenario.player(id: touch.playerID))
        XCTAssertTrue(player.isGoalkeeper)
        let presented = player.presentationPose(at: touch.time)
        let cue = ReplayAthleteInteractionCue(playerID: player.id, kind: .save,
            contactTime: touch.time, startTime: touch.time - 0.32, endTime: touch.time + 0.42,
            kickingLeg: touch.kickingLeg, contactBallWorldPosition: touch.position,
            outgoingDirectionWorld: touch.outgoingVelocity)
        let actor = Entity()
        actor.position = [presented.position.x, 0, presented.position.z]
        actor.orientation = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])
        if useTripo {
            try ReplayTripoAthleteProvider.prewarm()
        } else {
            try ReplaySkinnedAthleteProvider.prewarm()
            try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        }
        var rows: [[String: Any]] = []

        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try makeSkin(for: player, detail: detail, useTripo: useTripo)
            actor.addChild(skin.root)
            XCTAssertTrue(skin.update(at: touch.time, track: player,
                locomotion: player.locomotion(at: touch.time), lookTarget: touch.position,
                ballAction: nil, interaction: cue, presentationPose: presented))
            // Read back the transforms submitted to RealityKit before measuring.
            // This catches an in-memory pose that never reaches the native rig.
            let native = skin.model.jointTransforms
            var visible = skin.pose
            XCTAssertEqual(native.count, skin.motion.joints.count)
            guard native.count == skin.motion.joints.count else {
                skin.root.removeFromParent()
                continue
            }
            for index in native.indices {
                visible.translations[index] = native[index].translation
                visible.rotations[index] = native[index].rotation
                visible.scales[index] = native[index].scale
            }
            skin.motion.rebuildModelSpaceTransforms(in: &visible)
            let localFloor = skin.contactSurface.minimumY(in: visible)
            let worldFloor = skin.model.convert(position: [0, localFloor, 0], to: nil).y
            XCTAssertGreaterThanOrEqual(worldFloor, skin.contactSurface.paddingMetres - 0.000_01,
                                        "The save must not bury a planted boot to reach the ball")

            for side in ["left", "right"] {
                let elbow = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Elbow"])
                let wrist = try XCTUnwrap(skin.motion.semanticJointIndices[side + "Wrist"])
                let rest = skin.motion.restPose.modelSpaceTransforms
                let restForearm = position(rest[wrist]) - position(rest[elbow])
                let neutral = simd_quatf(from: simd_normalize(restForearm), to: [0, -1, 0])
                    * simd_quatf(rest[wrist])
                let marker = neutral.inverse.act(ReplayAthleteParryIK.palmMarker)
                let local = visible.modelSpaceTransforms[wrist] * SIMD4(marker, 1)
                let actual = skin.model.convert(position: [local.x, local.y, local.z], to: nil)
                let centreDistance = simd_distance(actual, touch.position)
                let signedSurfaceGap = centreDistance - ReplayNativeBallPhysics.radius
                let surfaceError = abs(signedSurfaceGap)
                XCTAssertLessThanOrEqual(surfaceError, 0.03,
                    "\(detail) \(side) palm: actual native save must meet the sphere within 3 cm")
                rows.append(["detail": String(describing: detail), "hand": side,
                    "palmMarkerToBallCentreMetres": centreDistance,
                    "signedSphereSurfaceGapMetres": signedSurfaceGap,
                    "sphereSurfaceErrorMetres": surfaceError,
                    "actualPalmMarker": [actual.x, actual.y, actual.z],
                    "floorClearanceMetres": worldFloor])
            }

            let first = native.map(\.rotation.vector)
            for time in [touch.time + 0.25, touch.time - 0.2, touch.time] {
                XCTAssertTrue(skin.update(at: time, track: player, locomotion: player.locomotion(at: time),
                    lookTarget: touch.position, ballAction: nil, interaction: cue,
                    presentationPose: player.presentationPose(at: time)))
            }
            XCTAssertEqual(first, skin.model.jointTransforms.map(\.rotation.vector),
                           "Seeking back to the save must restore the same hand pose")
            skin.root.removeFromParent()
        }

        XCTAssertEqual(rows.count, 4, "Both hands of both real skin details must be measured")
        let report: [String: Any] = ["scenario": scenario.id, "playerID": player.id, "rig": rig,
            "time": touch.time, "ballCentre": [touch.position.x, touch.position.y, touch.position.z],
            "playerRoot": [presented.position.x, 0, presented.position.z],
            "facingDegrees": presented.facingDegrees,
            "admittedContacts": recording.touches.count, "missedContacts": recording.missedTouchCount,
            "samples": rows,
            "scope": "Fresh native rebound save; read-back RealityKit joint transforms; existing rig palm markers; not hand-mesh vertices; no root or ball correction"]
        let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                    uniformTypeIdentifier: "public.json")
        receipt.name = "ReplayXI-Reference125-ActualSaveContact-\(rig).json"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    private func makeSkin(for player: PlayerTrack, detail: ReplaySkinnedAthleteProvider.Detail,
                          useTripo: Bool) throws -> ReplaySkinnedAthleteInstance {
        if useTripo {
            return try ReplayTripoAthleteProvider.make(for: player, detail: detail)
        }
        return try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
    }

    private func position(_ matrix: simd_float4x4) -> SIMD3<Float> {
        [matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z]
    }
}
