import XCTest
import simd
@testable import ReplayXI

@MainActor
final class FootballReferenceScenarioTests: XCTestCase {
    func testThreeDistinctStudiesPreserveLegacySavedReviewIDs() {
        let studies = FootballReferenceScenarios.all
        XCTAssertEqual(studies.count, 3)
        XCTAssertEqual(Set(studies.map(\.id)).count, 3)
        XCTAssertEqual(Set(DemoScenarios.catalogue.map(\.id)).count, 9)
        XCTAssertEqual(ReplayAppMode.situationRoleplay.featuredScenarios(in: DemoScenarios.catalogue).map(\.id),
                       FootballReferenceScenarios.ids)
        XCTAssertNotEqual(studies[0].ball, studies[1].ball)
        XCTAssertNotEqual(studies[1].ball, studies[2].ball)
        XCTAssertTrue(DemoScenarios.all.allSatisfy { legacy in DemoScenarios.catalogue.contains(legacy) })
        for scenario in studies {
            XCTAssertEqual(scenario.players.count, 22)
            XCTAssertEqual(scenario.homePlayers.count, 11)
            XCTAssertEqual(scenario.awayPlayers.count, 11)
            XCTAssertEqual(Set(scenario.players.map(\.id)).count, 22)
            XCTAssertNotNil(scenario.player(id: scenario.defaultPerspectiveID))
            XCTAssertTrue(scenario.strapline.contains("Reconstruction"))
            XCTAssertTrue(scenario.proofPoint.contains("Not recovered tracking"))
            XCTAssertEqual(scenario.ball.keyframes.first?.time, 0)
            XCTAssertEqual(scenario.ball.keyframes.last?.time, scenario.duration)
            for player in scenario.players {
                XCTAssertEqual(player.keyframes.first?.time, 0)
                XCTAssertEqual(player.keyframes.last?.time, scenario.duration)
                XCTAssertGreaterThan(player.motion(at: scenario.duration).distanceTravelled, 0.1,
                                     "Off-ball player must not be a stationary cutout: \(player.id)")
                for pair in zip(player.keyframes,player.keyframes.dropFirst()) {
                    XCTAssertLessThanOrEqual(abs(pair.1.facingDegrees-pair.0.facingDegrees),14.01)
                }
            }
        }
    }

    func testReferencesSaveRestoreAndBindAnnotationsWithoutLegacyCollision() throws {
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.catalogue)
        let store = ReplayStore(scenarios: DemoScenarios.catalogue, reviewLibrary: library)
        for scenario in FootballReferenceScenarios.all {
            store.selectScenario(id: scenario.id)
            store.seek(to: 2)
            store.beginDrawing(.arc)
            _ = store.registerPitchTap(.init(x: 2,z: 18))
            let mark = try XCTUnwrap(store.registerPitchTap(.init(x: -8,z: 29)))
            XCTAssertTrue(store.saveReview(named: scenario.title))
            let saved = try XCTUnwrap(store.savedReviews.first(where: { $0.name == scenario.title }))
            store.selectScenario(id: "eleven-eyes")
            XCTAssertTrue(store.restoreReview(saved))
            XCTAssertEqual(store.selectedScenarioID, scenario.id)
            XCTAssertTrue(store.marks.contains(where: { $0.id == mark.id }))
        }
    }

    func testReferenceTeamNamesMatchTheirCountriesAndLegacyNamesStayExact() {
        for scenario in FootballReferenceScenarios.all {
            XCTAssertEqual(FootballReferenceScenarios.teamTitle(.home, in: scenario), "Argentina", scenario.id)
            XCTAssertEqual(FootballReferenceScenarios.teamTitle(.away, in: scenario), "France", scenario.id)
            XCTAssertEqual(FootballReferenceScenarios.teamTitle(.home, in: scenario).prefix(3).uppercased(), "ARG")
            XCTAssertEqual(FootballReferenceScenarios.teamTitle(.away, in: scenario).prefix(3).uppercased(), "FRA")
        }
        for scenario in DemoScenarios.all {
            for team in FootballTeam.allCases {
                XCTAssertEqual(FootballReferenceScenarios.teamTitle(team, in: scenario), team.shortTitle, scenario.id)
            }
        }
    }

    func testNativeStudiesExecuteEveryPlannedTouchAndProduceFiniteSeekableRecordings() async throws {
        for scenario in FootballReferenceScenarios.all {
            let plan = try XCTUnwrap(FootballReferenceScenarios.touches(for: scenario))
            let start = ContinuousClock.now
            let recording = try await ReplayNativeBallPhysics.bake(track: scenario.ball,
                players: scenario.players, plannedTouches: plan)
            let elapsed = start.duration(to: .now)
            let report: [String:Any] = [
                "scenario":scenario.id, "samples":recording.samples.count,
                "missed":recording.missedTouchCount,"planned":plan.count,
                "elapsed":String(describing: elapsed),
                "diagnostics":recording.diagnostics.map { sample in
                    ["time":sample.time, "position":[sample.position.x,sample.position.y,sample.position.z],
                     "velocity":[sample.velocity.x,sample.velocity.y,sample.velocity.z],
                     "near":sample.nearestColliders] as [String:Any]
                },
                "touches":recording.touches.map { touch in
                    let actor = scenario.player(id: touch.playerID)!.presentationPose(at: touch.time)
                    return ["player":touch.playerID,"time":touch.time,"kind":touch.kind.rawValue,
                     "actor":[actor.position.x,actor.position.z,actor.facingDegrees],
                     "position":[touch.position.x,touch.position.y,touch.position.z],
                     "velocity":[touch.outgoingVelocity.x,touch.outgoingVelocity.y,touch.outgoingVelocity.z]] as [String:Any]
                },
                "atPlannedTouches":plan.map { touch in
                    let p = recording.sample(at: touch.time)
                    return ["player":touch.playerID,"time":touch.time,
                            "ball":[p.position.x,p.position.y,p.position.z]] as [String:Any]
                }
            ]
            let attachment = XCTAttachment(data:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),
                                           uniformTypeIdentifier:"public.json")
            attachment.name = "NativeStudy-\(scenario.id)"; attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertEqual(recording.touches.count, plan.count, scenario.id)
            XCTAssertEqual(recording.missedTouchCount, 0, scenario.id)
            XCTAssertGreaterThan(recording.nativeStepCount, 500)
            XCTAssertTrue(recording.samples.allSatisfy { $0.position.y.isFinite && $0.position.y > -0.03 })
            XCTAssertTrue(recording.samples.contains {
                $0.time > plan.last!.time && $0.position.z > 52.61
                    && abs($0.position.x) < 3.55 && $0.position.y < 2.30
            }, "The reconstructed finish must actually enter the goal: \(scenario.id)")
            let first = recording.sample(at: 2.3)
            _ = recording.sample(at: scenario.duration)
            _ = recording.sample(at: 0.1)
            XCTAssertEqual(first.position, recording.sample(at: 2.3).position)
            XCTAssertEqual(first.orientation.vector, recording.sample(at: 2.3).orientation.vector)
        }
    }
}
