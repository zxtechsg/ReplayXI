import XCTest
import simd
@testable import ReplayXI

@MainActor
final class CityLiverpoolReferenceScenarioTests: XCTestCase {
    func testTwoDistinctNativeMatchReplaysUseStableNonLegacyIDs() {
        let studies = CityLiverpoolReferenceScenarios.all
        XCTAssertEqual(studies.map(\.id), CityLiverpoolReferenceScenarios.ids)
        XCTAssertEqual(studies.count, 2)
        XCTAssertEqual(Set(studies.map(\.id)).count, 2)
        XCTAssertNotEqual(studies[0].ball, studies[1].ball)
        for scenario in studies {
            XCTAssertEqual(scenario.kind, .realWorldReplay)
            XCTAssertTrue(scenario.strapline.contains("Reconstruction"))
            XCTAssertTrue(scenario.matchContext.contains("4 Apr 2026"))
            XCTAssertTrue(scenario.proofPoint.contains("Not recovered tracking"))
            XCTAssertTrue(scenario.proofPoint.contains("inferred"))
            XCTAssertNotNil(scenario.player(id: scenario.defaultPerspectiveID))
            XCTAssertFalse(DemoScenarios.all.contains(where: { $0.id == scenario.id }))
        }
    }

    func testBothStudiesHaveTheNamedStartingTwentyTwoWithUniqueTeamShirts() {
        for scenario in CityLiverpoolReferenceScenarios.all {
            XCTAssertEqual(scenario.players.count, 22)
            XCTAssertEqual(Set(scenario.players.map(\.id)).count, 22)
            XCTAssertEqual(Set(scenario.homePlayers.map(\.shirtNumber)),
                           Set([1,27,45,15,33,16,20,42,10,11,9]))
            XCTAssertEqual(Set(scenario.awayPlayers.map(\.shirtNumber)),
                           Set([25,2,5,4,6,38,17,8,7,11,22]))
            XCTAssertEqual(scenario.players.filter(\.isGoalkeeper).map(\.id), ["city-1", "liv-25"])
            XCTAssertEqual(scenario.player(id: "city-9")?.displayName, "Haaland")
            XCTAssertEqual(scenario.player(id: "city-33")?.displayName, "O’Reilly")
            XCTAssertEqual(scenario.player(id: "liv-4")?.displayName, "Van Dijk")
            XCTAssertTrue(scenario.players.allSatisfy { !$0.displayName.contains("#") })
        }
    }

    func testRoutesCoverTheWholeClipAndBoundSpeedAndTurning() {
        for scenario in CityLiverpoolReferenceScenarios.all {
            XCTAssertEqual(scenario.ball.keyframes.first?.time, 0)
            XCTAssertEqual(scenario.ball.keyframes.last?.time, scenario.duration)
            for player in scenario.players {
                XCTAssertEqual(player.keyframes.first?.time, 0, player.id)
                XCTAssertEqual(player.keyframes.last?.time, scenario.duration, player.id)
                XCTAssertGreaterThan(player.motion(at: scenario.duration).distanceTravelled, 0.1, player.id)
                for pair in zip(player.keyframes, player.keyframes.dropFirst()) {
                    XCTAssertLessThanOrEqual(abs(pair.1.facingDegrees - pair.0.facingDegrees), 14.01, player.id)
                    XCTAssertLessThanOrEqual(ReplayGeometry.distance(pair.0.position, pair.1.position)
                        / Float(pair.1.time - pair.0.time), 10, player.id)
                    XCTAssertLessThanOrEqual(abs(pair.1.position.x), 34, player.id)
                    XCTAssertLessThanOrEqual(abs(pair.1.position.z), 52.5, player.id)
                }
            }
        }
    }

    func testTouchPlanMatchesObservedPlayersActionsAndVerifiedFeet() throws {
        let first = try XCTUnwrap(CityLiverpoolReferenceScenarios.all.first)
        let header = try XCTUnwrap(CityLiverpoolReferenceScenarios.touches(for: first))
        XCTAssertEqual(header.map(\.playerID), ["city-10", "city-42", "city-42", "city-42", "city-9"])
        XCTAssertEqual(header.map(\.kind), [.pass, .receive, .dribbleTouch, .pass, .header])
        XCTAssertEqual(header[3].kickingLeg, .right)
        XCTAssertEqual(header[3].targetHeight, 1.55)
        let second = CityLiverpoolReferenceScenarios.all[1]
        let cutback = try XCTUnwrap(CityLiverpoolReferenceScenarios.touches(for: second))
        XCTAssertEqual(cutback.map(\.playerID), ["city-11", "city-33", "city-33", "city-33", "city-9"])
        XCTAssertEqual(cutback.map(\.kind), [.pass, .receive, .dribbleTouch, .pass, .shot])
        XCTAssertEqual(cutback[3].kickingLeg, .left)
        XCTAssertEqual(cutback[4].kickingLeg, .left)
        XCTAssertGreaterThan(cutback[4].targetHeight, 2)
        XCTAssertLessThan(cutback[4].target.x, 0)
        XCTAssertNil(CityLiverpoolReferenceScenarios.touches(for: DemoScenarios.all[0]))
    }

    func testCutbackStrikerChecksAwayFromHisMarkerRatherThanRunningStraightThrough() throws {
        let scenario = CityLiverpoolReferenceScenarios.all[1]
        let striker = try XCTUnwrap(scenario.player(id: "city-9"))
        let marker = try XCTUnwrap(scenario.player(id: "liv-4"))
        let beforeCheck = striker.presentationPose(at: 2.6).position
        let atPass = striker.presentationPose(at: 3).position
        let atShot = striker.presentationPose(at: 4).position
        XCTAssertLessThan(atShot.z, beforeCheck.z)
        XCTAssertLessThan(atPass.x, beforeCheck.x)
        XCTAssertGreaterThan(marker.presentationPose(at: 4).position.z, atShot.z + 2)
    }

    func testNativeCityStudiesAdmitEveryContactAndFinishInsideTheGoal() async throws {
        for scenario in CityLiverpoolReferenceScenarios.all {
            let plan = try XCTUnwrap(CityLiverpoolReferenceScenarios.touches(for: scenario))
            let recording = try await ReplayNativeBallPhysics.bake(track: scenario.ball,
                players: scenario.players, plannedTouches: plan)
            let report: [String: Any] = [
                "scenario": scenario.id, "missed": recording.missedTouchCount,
                "planned": plan.count, "samples": recording.samples.count,
                "touches": recording.touches.map { touch in
                    ["player": touch.playerID, "kind": touch.kind.rawValue, "time": touch.time,
                     "position": [touch.position.x, touch.position.y, touch.position.z],
                     "velocity": [touch.outgoingVelocity.x, touch.outgoingVelocity.y, touch.outgoingVelocity.z]] as [String: Any]
                },
                "plannedSamples": plan.map { touch in
                    let sample = recording.sample(at: touch.time)
                    let player = scenario.player(id: touch.playerID)!.presentationPose(at: touch.time)
                    return ["player": touch.playerID, "time": touch.time,
                            "position": [sample.position.x, sample.position.y, sample.position.z],
                            "root": [player.position.x, player.position.z, player.facingDegrees]] as [String: Any]
                },
                "diagnostics": recording.diagnostics.map { sample in
                    ["time": sample.time,
                     "position": [sample.position.x, sample.position.y, sample.position.z],
                     "velocity": [sample.velocity.x, sample.velocity.y, sample.velocity.z],
                     "near": sample.nearestColliders] as [String: Any]
                }
            ]
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report,
                options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            attachment.name = "NativeCityStudy-\(scenario.id)"
            attachment.lifetime = .keepAlways
            add(attachment)
            if recording.missedTouchCount > 0 {
                let receipt = ["scenario": report["scenario"]!, "touches": report["touches"]!,
                               "plannedSamples": report["plannedSamples"]!]
                let data = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
                print("CITY_NATIVE_RECEIPT \(String(decoding: data, as: UTF8.self))")
            }
            XCTAssertEqual(recording.touches.count, plan.count, scenario.id)
            XCTAssertEqual(recording.missedTouchCount, 0, scenario.id)
            XCTAssertEqual(recording.touches.map(\.playerID), plan.map(\.playerID), scenario.id)
            XCTAssertTrue(recording.samples.allSatisfy {
                $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite && $0.position.y > -0.03
            }, scenario.id)
            XCTAssertTrue(recording.samples.contains {
                $0.time > plan.last!.time && $0.position.z > 52.61
                    && abs($0.position.x) < 3.55 && $0.position.y < 2.30
            }, "The reconstructed finish must enter the goal: \(scenario.id)")
            let sample = recording.sample(at: 2.3)
            _ = recording.sample(at: scenario.duration)
            _ = recording.sample(at: 0.1)
            XCTAssertEqual(sample.position, recording.sample(at: 2.3).position)
            XCTAssertEqual(sample.orientation.vector, recording.sample(at: 2.3).orientation.vector)
        }
    }
}
