import RealityKit
import XCTest
import simd
@testable import ReplayXI

/// Native solver contacts must also be reachable by the visible rigs. This
/// measures marker error; it neither teleports roots nor changes kick admission.
@MainActor
final class ReplayReferenceContactReachTests: XCTestCase {
    override func tearDown() {
        ReplayNativeBallPhysics.resetCacheForTesting()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }

    func testCounterattackActualContactsReachAllThreePlayerLODs() async throws { try await check(0) }
    func testVolleyActualFootContactsReachAllThreePlayerLODs() async throws { try await check(1) }
    func testReboundActualFootContactsReachAllThreePlayerLODs() async throws { try await check(2) }
    func testCityCrossActualFootContactsReachAllThreePlayerLODs() async throws { try await check(3) }
    func testCityCutbackActualFootContactsReachAllThreePlayerLODs() async throws { try await check(4) }

    private func check(_ index: Int) async throws {
        let scenario = FootballReferenceScenarios.all[index]
        let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
        let recording = try await ReplayNativeBallPhysics.bake(track: scenario.ball, players: scenario.players,
                                                              plannedTouches: plan)
        try ReplaySkinnedAthleteProvider.prewarm()
        try ReplaySkinnedAthleteProvider.prewarmLowDetail()
        try ReplayFarAthleteHeadProvider.prewarm()
        try ReplayArticulatedFarProvider.prewarm()
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.far])
        var rows: [[String: Any]] = []
        var footCount = 0
        for touch in recording.touches {
            guard let kind = ReplayAthleteInteractionCue.Kind(rawValue: touch.kind.rawValue), kind.usesFeet else { continue }
            footCount += 1
            let player = try XCTUnwrap(scenario.player(id: touch.playerID))
            let cue = ReplayAthleteInteractionCue(playerID: player.id, kind: kind,
                contactTime: touch.time, startTime: touch.time - 0.32, endTime: touch.time + 0.42,
                kickingLeg: touch.kickingLeg, contactBallWorldPosition: touch.position,
                outgoingDirectionWorld: touch.outgoingVelocity)
            let directionLength = simd_length(touch.outgoingVelocity)
            XCTAssertGreaterThan(directionLength, 0.000_01)
            guard directionLength > 0.000_01 else { continue }
            let expected = touch.position - touch.outgoingVelocity / directionLength * ReplayNativeBallPhysics.radius
            let presented = player.presentationPose(at: touch.time)
            let actor = Entity()
            actor.position = [presented.position.x, 0, presented.position.z]
            actor.orientation = simd_quatf(angle: presented.facingDegrees * .pi / 180, axis: [0, 1, 0])

            let far = try ReplayAthleteFactory.make(for: player, lod: .far)
            actor.addChild(far.root)
            ReplayAthleteMotion.update(far, from: player, at: touch.time,
                lookTargetWorldPosition: touch.position, interaction: cue, presentationPose: presented)
            let ankle = far.joints[touch.kickingLeg == .left ? .leftAnkle : .rightAnkle]
            let farActual = ankle.convert(position: ReplayAthleteInteractionPose.bootStrikeMarker, to: nil)
            let farFloor = try XCTUnwrap(far.joints.articulatedFar).minimumY(relativeTo: far.root)
            XCTAssertGreaterThanOrEqual(farFloor, -0.000_01)
            measure(actual: farActual, expected: expected, detail: "far", floor: farFloor,
                    player: player, touch: touch, presented: presented, rows: &rows)
            far.root.removeFromParent()

            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try ReplaySkinnedAthleteProvider.make(for: player, detail: detail)
                actor.addChild(skin.root)
                XCTAssertTrue(skin.update(at: touch.time, track: player, locomotion: player.locomotion(at: touch.time),
                                          lookTarget: touch.position, ballAction: nil,
                                          interaction: cue, presentationPose: presented))
                let marker = try XCTUnwrap(skin.bootMarkers?.markers.first {
                    (skin.motion.restPose.modelSpaceTransforms[$0.ankleIndex].columns.3.x < 0)
                        == (touch.kickingLeg == .left)
                })
                let local = skin.pose.modelSpaceTransforms[marker.ankleIndex] * SIMD4(marker.ankleLocalPosition, 1)
                let actual = skin.model.convert(position: [local.x, local.y, local.z], to: nil)
                let floor = skin.contactSurface.minimumY(in: skin.pose) - skin.motion.geometry.restMinY
                XCTAssertGreaterThanOrEqual(floor, skin.contactSurface.paddingMetres - 0.000_01)
                measure(actual: actual, expected: expected, detail: String(describing: detail), floor: floor,
                        player: player, touch: touch, presented: presented, rows: &rows)
                skin.root.removeFromParent()
            }
        }
        XCTAssertGreaterThan(footCount, 0, "A study with no admitted foot contacts cannot prove visible reach")
        let report: [String: Any] = ["scenario": scenario.id, "plannedContacts": plan.count,
                                   "admittedContacts": recording.touches.count,
                                   "missedContacts": recording.missedTouchCount,
                                   "footContactsMeasured": footCount, "samples": rows,
                                   "scope": "Actual native ball contacts, procedural far marker and native near/low boot vertices; headers/saves excluded; no root correction"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Reference125-ContactReach-\(scenario.id).json"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    private func measure(actual: SIMD3<Float>, expected: SIMD3<Float>, detail: String, floor: Float,
                         player: PlayerTrack, touch: ReplayNativeBallPhysics.Touch, presented: PlayerPose,
                         rows: inout [[String: Any]]) {
        let error = simd_distance(actual, expected)
        XCTAssertLessThanOrEqual(error, 0.03,
                                "\(player.id) \(detail) @ \(touch.time): admitted contact must be within3cm of visible boot")
        rows.append(["playerID": player.id, "kind": touch.kind.rawValue, "leg": touch.kickingLeg.rawValue,
                     "time": touch.time, "detail": detail, "surfaceErrorMetres": error,
                     "actualBootMarker": [actual.x, actual.y, actual.z],
                     "expectedSphereSurface": [expected.x, expected.y, expected.z],
                     "ballCentre": [touch.position.x, touch.position.y, touch.position.z],
                     "outgoingVelocity": [touch.outgoingVelocity.x, touch.outgoingVelocity.y, touch.outgoingVelocity.z],
                     "playerRoot": [presented.position.x, 0, presented.position.z],
                     "facingDegrees": presented.facingDegrees, "floorClearanceMetres": floor])
    }
}
