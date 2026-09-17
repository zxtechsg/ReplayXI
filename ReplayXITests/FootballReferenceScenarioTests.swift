import XCTest
import simd
@testable import ReplayXI

@MainActor
final class FootballReferenceScenarioTests: XCTestCase {
    func testFiveReferencedStudiesPreserveLegacySavedReviewIDs() {
        let studies = FootballReferenceScenarios.all
        XCTAssertEqual(studies.count, 5)
        XCTAssertEqual(Set(studies.map(\.id)).count, 5)
        XCTAssertEqual(Set(DemoScenarios.catalogue.map(\.id)).count, 13)
        XCTAssertEqual(ReplayAppMode.situationRoleplay.featuredScenarios(in: DemoScenarios.catalogue).map(\.id),
                       FootballReferenceScenarios.worldCupIDs)
        XCTAssertEqual(ReplayAppMode.matchReplay.featuredScenarios(in: DemoScenarios.catalogue).map(\.id),
                       CityLiverpoolReferenceScenarios.ids)
        XCTAssertTrue(studies.allSatisfy { ReplayReferenceLibrary.reference(for: $0.id) != nil })
        XCTAssertTrue(DemoScenarios.all.allSatisfy { ReplayReferenceLibrary.reference(for: $0.id) == nil })
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

    func testBroadcastCorrectionsPreserveTheEarlyLayoffAndReboundChain() throws {
        let counter = try XCTUnwrap(FootballReferenceScenarios.touches(for: FootballReferenceScenarios.all[0]))
        XCTAssertEqual(counter.map(\.playerID), ["arg-26", "arg-20", "arg-10", "arg-9", "arg-20", "arg-11"])
        let rebound = try XCTUnwrap(FootballReferenceScenarios.touches(for: FootballReferenceScenarios.all[2]))
        XCTAssertEqual(rebound.map(\.playerID), ["arg-22", "arg-10", "arg-24", "arg-22", "fra-1", "arg-10"])
        XCTAssertEqual(rebound.last?.kickingLeg, .right)
    }

    func testCounterUsesTheFullFieldButLegacyReviewTimingRemainsAvailable() throws {
        let current = FootballReferenceScenarios.all[0]
        XCTAssertEqual(current.id, "final-36-counter-v2")
        XCTAssertLessThan(current.ball.keyframes[0].position.z, -15)
        XCTAssertGreaterThan(current.ball.keyframes[0].position.x, 28)
        XCTAssertLessThan(try XCTUnwrap(current.player(id: "arg-11")).pose(at: 0).position.z, 0)
        let shot = try XCTUnwrap(FootballReferenceScenarios.touches(for: current)?.last)
        XCTAssertGreaterThan(shot.time, 10)
        XCTAssertGreaterThan(current.ball.pose(at: shot.time).position.z, 44)
        let legacy = try XCTUnwrap(DemoScenarios.catalogue.first { $0.id == "final-36-counter" })
        XCTAssertEqual(legacy.duration, 10.5)
        XCTAssertEqual(FootballReferenceScenarios.touches(for: legacy)?.count, 5)
        XCTAssertEqual(FootballReferenceScenarios.touches(for: legacy)?.last?.time, 6.8)
        let store = ReplayStore(scenarios: DemoScenarios.catalogue)
        store.selectScenario(id: legacy.id)
        store.seek(to: 6.8)
        XCTAssertTrue(store.saveReview(named: "Legacy counter timing"))
        let saved = try XCTUnwrap(store.savedReviews.first)
        store.selectScenario(id: current.id)
        XCTAssertTrue(store.restoreReview(saved))
        XCTAssertEqual(store.selectedScenarioID, legacy.id)
        XCTAssertEqual(store.playhead, 6.8)
    }

    func testLegacyReboundKeepsOriginalBallContactsPositionsAndReceivingFacing() throws {
        let legacy = try XCTUnwrap(DemoScenarios.catalogue.first { $0.id == "final-108-rebound" })
        let current = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        XCTAssertFalse(FootballReferenceScenarios.all.contains(where: { $0.id == legacy.id }))
        XCTAssertTrue(FootballReferenceScenarios.legacy.contains(legacy))
        XCTAssertEqual(legacy.duration, 7)
        // Frozen ball anchors from the original pre-correction study.
        let originalBall: [BallKeyframe] = [
            .init(time: 0, position: .init(x: 3, z: 25), height: 0.11),
            .init(time: 0.9, position: .init(x: 6, z: 30), height: 0.11),
            .init(time: 1.8, position: .init(x: 3, z: 33), height: 0.11),
            .init(time: 2.8, position: .init(x: 11, z: 40), height: 0.11),
            .init(time: 3.55, position: .init(x: 1, z: 48), height: 0.65),
            .init(time: 4.2, position: .init(x: -1, z: 47), height: 0.11),
            .init(time: 4.55, position: .init(x: -1.8, z: 54), height: 0.11),
            .init(time: 7, position: .init(x: -1.8, z: 54), height: 0.11)
        ]
        XCTAssertEqual(legacy.ball.keyframes, originalBall)
        let touches = try XCTUnwrap(FootballReferenceScenarios.touches(for: legacy))
        XCTAssertEqual(touches.map(\.time), [0, 0.9, 1.8, 2.8, 3.55, 4.2])
        XCTAssertEqual(touches.map(\.arrivalTime), [0.9, 1.8, 2.8, 3.55, 4.2, 4.55])
        XCTAssertEqual(touches.map(\.playerID), ["arg-24", "arg-10", "arg-24", "arg-22", "fra-1", "arg-10"])
        XCTAssertEqual(touches.map(\.kickingLeg), [.right, .left, .right, .right, .right, .left])
        let lautaro = try XCTUnwrap(legacy.player(id: "arg-22"))
        XCTAssertEqual(lautaro.pose(at: 0).position, .init(x: 14, z: 29))
        XCTAssertEqual(lautaro.pose(at: 0).facingDegrees, atan2(Float(-11), Float(-4)) * 180 / .pi, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(legacy.player(id: "arg-24")).pose(at: 0).position, .init(x: 3, z: 24.5))
        XCTAssertEqual(try XCTUnwrap(legacy.player(id: "arg-10")).pose(at: 0).position, .init(x: 6, z: 24.5))
        XCTAssertEqual(legacy.homePlayers.map(\.shirtNumber), [23,4,13,19,3,24,5,20,10,22,8])
        XCTAssertEqual(legacy.awayPlayers.map(\.shirtNumber), [1,5,4,18,25,8,13,20,12,26,10])
        XCTAssertEqual(current.ball.keyframes.first?.position, .init(x: 14, z: 29))
        XCTAssertEqual(current.player(id: "arg-22")?.pose(at: 0).position, .init(x: 14, z: 28.5))
        XCTAssertEqual(FootballReferenceScenarios.touches(for: current)?.last?.kickingLeg, .right)
        XCTAssertTrue(try XCTUnwrap(ReplayReferenceLibrary.reference(for: legacy.id)).shortLabel.contains("Legacy"))
        XCTAssertFalse(try XCTUnwrap(ReplayReferenceLibrary.reference(for: current.id)).shortLabel.contains("Legacy"))
    }

    func testLegacyReboundSaveRestoresItsOriginalSceneAndAnnotation() throws {
        let legacy = try XCTUnwrap(DemoScenarios.catalogue.first { $0.id == "final-108-rebound" })
        let store = ReplayStore(scenarios: DemoScenarios.catalogue)
        store.selectScenario(id: legacy.id)
        store.seek(to: 0.9)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: 3, z: 25))
        let mark = try XCTUnwrap(store.registerPitchTap(.init(x: 6, z: 30)))
        XCTAssertTrue(store.saveReview(named: "Legacy rebound annotation"))
        let saved = try XCTUnwrap(store.savedReviews.first)
        store.selectScenario(id: "final-108-rebound-v2")
        XCTAssertTrue(store.restoreReview(saved))
        XCTAssertEqual(store.selectedScenarioID, legacy.id)
        XCTAssertEqual(store.playhead, 0.9)
        XCTAssertEqual(store.selectedScenario.ball, legacy.ball)
        XCTAssertEqual(store.selectedScenario.players, legacy.players)
        XCTAssertTrue(store.marks.contains(where: { $0.id == mark.id && $0.start == mark.start && $0.end == mark.end }))
    }

    func testReferenceTeamNamesMatchTheirCountriesAndLegacyNamesStayExact() {
        for scenario in FootballReferenceScenarios.all where FootballReferenceScenarios.worldCupIDs.contains(scenario.id) {
            XCTAssertEqual(FootballReferenceScenarios.teamTitle(.home, in: scenario), "Argentina", scenario.id)
            XCTAssertEqual(FootballReferenceScenarios.teamTitle(.away, in: scenario), "France", scenario.id)
            XCTAssertEqual(FootballReferenceScenarios.teamTitle(.home, in: scenario).prefix(3).uppercased(), "ARG")
            XCTAssertEqual(FootballReferenceScenarios.teamTitle(.away, in: scenario).prefix(3).uppercased(), "FRA")
        }
        for scenario in CityLiverpoolReferenceScenarios.all {
            XCTAssertEqual(FootballReferenceScenarios.teamTitle(.home, in: scenario), "Manchester City")
            XCTAssertEqual(FootballReferenceScenarios.teamTitle(.away, in: scenario), "Liverpool")
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
