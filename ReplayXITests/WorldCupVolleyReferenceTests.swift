import XCTest
@testable import ReplayXI

@MainActor
final class WorldCupVolleyReferenceTests: XCTestCase {
    func testRevisedTimingAndPlantedHeaderAreExplicitWithoutClaimingTracking() throws {
        let current = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-81-volley-v2" })
        let touches = try XCTUnwrap(FootballReferenceScenarios.touches(for: current))
        XCTAssertEqual(current.duration, 10.5)
        XCTAssertEqual(touches.map(\.playerID), ["fra-20", "fra-14", "fra-10", "fra-26", "fra-10"])
        XCTAssertEqual(touches.map(\.time), [0, 2.6, 4.6, 5.6, 7.4])
        XCTAssertEqual(touches.map(\.arrivalTime), [2.6, 4.6, 5.6, 7.4, 8.2])
        XCTAssertEqual(touches.map(\.kind), [.pass, .pass, .header, .pass, .shot])
        XCTAssertEqual(touches.filter { $0.headerSupportLeg != nil }.count, 1)
        XCTAssertEqual(touches[2].headerSupportLeg, .right)
        // Header metadata is anatomical; the frozen kick API names X lanes.
        // `.left` is the -X lane and therefore the source's anatomical R_Foot.
        XCTAssertEqual(touches[4].kickingLeg, .left)
        XCTAssertGreaterThanOrEqual(touches[4].time - touches[0].time, 7)
        XCTAssertLessThanOrEqual(touches[4].time - touches[0].time, 8)
        XCTAssertEqual(current.moments.map(\.time), [0, 4.6, 7.4])
        let reference = try XCTUnwrap(ReplayReferenceLibrary.reference(for: current.id))
        XCTAssertTrue(reference.reconstructionNote.contains("inferred"))
        XCTAssertTrue(reference.reconstructionNote.contains("not measured tracking"))
        XCTAssertTrue(current.proofPoint.contains("Not recovered tracking"))
    }

    func testSupportingRoutesRetainWidthCoverAndAnIndividuallyTurningMarker() throws {
        let scenario = WorldCupVolleyReference.scenario
        XCTAssertEqual(scenario.players.count, 22)
        for player in scenario.players {
            XCTAssertEqual(player.keyframes.count, 106)
            for frame in player.keyframes {
                XCTAssertTrue(frame.time.isFinite && frame.facingDegrees.isFinite, player.id)
                XCTAssertTrue(frame.position.x.isFinite && frame.position.z.isFinite, player.id)
                XCTAssertLessThanOrEqual(abs(frame.position.x), 34, player.id)
                XCTAssertLessThanOrEqual(abs(frame.position.z), 52.5, player.id)
            }
            for pair in zip(player.keyframes, player.keyframes.dropFirst()) {
                XCTAssertGreaterThan(pair.1.time, pair.0.time)
                XCTAssertLessThanOrEqual(abs(pair.1.facingDegrees - pair.0.facingDegrees), 14.01)
            }
        }
        let marker = try XCTUnwrap(scenario.player(id: "arg-26"))
        XCTAssertEqual(marker.pose(at: 4.6).facingDegrees, 158, accuracy: 0.001)
        XCTAssertEqual(marker.pose(at: 6.3).facingDegrees, 40, accuracy: 0.001)
        XCTAssertGreaterThan(marker.pose(at: 7.4).position.z, marker.pose(at: 4.6).position.z)

        let farRunner = try XCTUnwrap(scenario.player(id: "fra-12"))
        let mbappe = try XCTUnwrap(scenario.player(id: "fra-10"))
        XCTAssertGreaterThan(farRunner.pose(at: 7.4).position.x - mbappe.pose(at: 7.4).position.x, 15)
        XCTAssertGreaterThan(farRunner.pose(at: 7.4).position.z, 40)
        for playerID in ["fra-4", "fra-18"] {
            let cover = try XCTUnwrap(scenario.player(id: playerID))
            XCTAssertLessThan(cover.pose(at: 7.4).position.z, 5,
                              "Rest defence should not chase the final pass into the box")
        }
        let messi = try XCTUnwrap(scenario.player(id: "arg-10"))
        XCTAssertLessThan(messi.pose(at: 7.4).position.z, 20)
        XCTAssertGreaterThan(try XCTUnwrap(scenario.player(id: "arg-19")).pose(at: 7.4).position.z, 40)
    }

    func testLegacyVolleyRetainsTheOriginalRosterBallContactsAndSourceMetadata() throws {
        let legacy = try XCTUnwrap(DemoScenarios.catalogue.first { $0.id == "final-81-volley" })
        XCTAssertFalse(FootballReferenceScenarios.all.contains(where: { $0.id == legacy.id }))
        XCTAssertTrue(FootballReferenceScenarios.legacy.contains(legacy))
        XCTAssertTrue(FootballReferenceScenarios.contains(legacy))
        XCTAssertEqual(legacy.duration, 8.5)
        XCTAssertEqual(legacy.title, "The one-two volley")
        XCTAssertEqual(legacy.strapline, "World Cup final · 81′ · Reconstruction")
        XCTAssertEqual(legacy.objective, "Pass, turn and attack the return before the defence sets.")
        XCTAssertEqual(legacy.defaultPerspectiveID, "fra-10")
        XCTAssertEqual(legacy.featuredPerspectiveIDs, ["fra-20", "fra-14", "fra-10", "fra-26"])
        XCTAssertEqual(legacy.moments.map(\.time), [0, 2.6, 4.5])
        XCTAssertEqual(legacy.ball.keyframes, [
            .init(time: 0, position: .init(x: -8, z: 5), height: 0.11),
            .init(time: 1.1, position: .init(x: -12, z: 13), height: 0.11),
            .init(time: 2.6, position: .init(x: -16, z: 28), height: 1.63),
            .init(time: 3.55, position: .init(x: -7, z: 32), height: 0.11),
            .init(time: 4.5, position: .init(x: -12, z: 37), height: 0.50),
            .init(time: 5.4, position: .init(x: 1.6, z: 54), height: 0.30),
            .init(time: 8.5, position: .init(x: 1.6, z: 54), height: 0.11)
        ])
        let touches = try XCTUnwrap(FootballReferenceScenarios.touches(for: legacy))
        XCTAssertEqual(touches.map(\.time), [0, 1.1, 2.6, 3.55, 4.5])
        XCTAssertEqual(touches.map(\.arrivalTime), [1.1, 2.6, 3.55, 4.5, 5.4])
        XCTAssertEqual(touches.map(\.playerID), ["fra-20", "fra-14", "fra-10", "fra-26", "fra-10"])
        XCTAssertTrue(touches.allSatisfy { $0.kickingLeg == .right && $0.headerSupportLeg == nil })
        XCTAssertEqual(legacy.homePlayers.map(\.shirtNumber), [23,26,13,19,3,24,7,20,10,9,8])
        XCTAssertEqual(legacy.awayPlayers.map(\.shirtNumber), [1,5,4,18,25,8,14,20,12,26,10])
        XCTAssertEqual(FootballReferenceScenarios.teamTitle(.home, in: legacy), "Argentina")
        XCTAssertEqual(FootballReferenceScenarios.teamTitle(.away, in: legacy), "France")
        let source = try XCTUnwrap(ReplayReferenceLibrary.reference(for: legacy.id))
        XCTAssertEqual(source, ReplayVideoReference(
            matchTitle: "Argentina v France · World Cup final · 18 Dec 2022",
            shortLabel: "ARG–FRA · 81′", videoID: "RgqKdplLIk4", startSeconds: 5_439, endSeconds: 5_460,
            reconstructionNote: "Manually reconstructed from the broadcast. Off-camera movement, body poses and gaze are inferred, not measured tracking. Neutral demo kits."))

        // Frozen original endpoints for every player, including fallback
        // support slots. In particular Acuña must not silently become Di María.
        let expected: [String: (PitchPoint, PitchPoint)] = [
            "arg-23": (.init(x:0,z:50.5), .init(x:-2,z:50)),
            "arg-26": (.init(x:25,z:23), .init(x:22,z:33)),
            "arg-13": (.init(x:9,z:33), .init(x:7.92,z:43)),
            "arg-19": (.init(x:-9,z:33), .init(x:-7.92,z:43)),
            "arg-3": (.init(x:-25,z:23), .init(x:-22,z:33)),
            "arg-24": (.init(x:0,z:15), .init(x:0,z:25)),
            "arg-7": (.init(x:13,z:8), .init(x:11.44,z:18)),
            "arg-20": (.init(x:-13,z:8), .init(x:-11.44,z:18)),
            "arg-10": (.init(x:25,z:8), .init(x:22,z:18)),
            "arg-9": (.init(x:0,z:8), .init(x:0,z:18)),
            "arg-8": (.init(x:-25,z:8), .init(x:-22,z:18)),
            "fra-1": (.init(x:0,z:-48), .init(x:0,z:-46.8)),
            "fra-5": (.init(x:25,z:-8), .init(x:22,z:4)),
            "fra-4": (.init(x:9,z:-18), .init(x:7.92,z:-6)),
            "fra-18": (.init(x:-9,z:-18), .init(x:-7.92,z:-6)),
            "fra-25": (.init(x:-25,z:-8), .init(x:-22,z:4)),
            "fra-8": (.init(x:0,z:0), .init(x:0,z:12)),
            "fra-14": (.init(x:-12,z:9), .init(x:-2,z:32)),
            "fra-20": (.init(x:-8,z:4.5), .init(x:2,z:31)),
            "fra-12": (.init(x:25,z:20), .init(x:22,z:32)),
            "fra-26": (.init(x:-6,z:24), .init(x:2,z:44)),
            "fra-10": (.init(x:-21,z:16), .init(x:-5,z:44))
        ]
        XCTAssertEqual(Set(expected.keys), Set(legacy.players.map(\.id)))
        for player in legacy.players {
            let endpoints = try XCTUnwrap(expected[player.id])
            XCTAssertEqual(player.keyframes.count, 86)
            XCTAssertEqual(player.pose(at: 0).position.x, endpoints.0.x, accuracy: 0.000_01, player.id)
            XCTAssertEqual(player.pose(at: 0).position.z, endpoints.0.z, accuracy: 0.000_01, player.id)
            XCTAssertEqual(player.pose(at: 8.5).position.x, endpoints.1.x, accuracy: 0.000_01, player.id)
            XCTAssertEqual(player.pose(at: 8.5).position.z, endpoints.1.z, accuracy: 0.000_01, player.id)
        }
        let mbappe = try XCTUnwrap(legacy.player(id: "fra-10"))
        XCTAssertEqual(mbappe.pose(at: 2.6).position.x, -15.96, accuracy: 0.000_01)
        XCTAssertEqual(mbappe.pose(at: 2.6).position.z, 27.7, accuracy: 0.000_01)
        XCTAssertEqual(mbappe.pose(at: 4.5).position, .init(x: -12, z: 36.5))
    }

    func testOldAndNewVolleyReviewsKeepSeparateTimesAndAnnotations() throws {
        let legacy = try XCTUnwrap(DemoScenarios.catalogue.first { $0.id == "final-81-volley" })
        let current = try XCTUnwrap(DemoScenarios.catalogue.first { $0.id == "final-81-volley-v2" })
        let store = ReplayStore(scenarios: DemoScenarios.catalogue)
        store.selectScenario(id: legacy.id)
        store.seek(to: 4.5)
        store.beginDrawing(.arc)
        XCTAssertTrue(store.isDrawing)
        XCTAssertFalse(store.isPlaying)
        _ = store.registerPitchTap(.init(x: -12, z: 37))
        // The recording's goal waypoint is behind the goal line (z54), but
        // annotation taps intentionally accept only points inside the pitch.
        let legacyMark = try XCTUnwrap(store.registerPitchTap(.init(x: 1.6, z: 52)))
        XCTAssertTrue(store.saveReview(named: "Original volley"))
        let savedLegacy = try XCTUnwrap(store.savedReviews.first { $0.name == "Original volley" })

        store.selectScenario(id: current.id)
        store.seek(to: 7.4)
        store.beginDrawing(.run)
        XCTAssertTrue(store.isDrawing)
        XCTAssertFalse(store.isPlaying)
        _ = store.registerPitchTap(.init(x: -16, z: 28))
        let currentMark = try XCTUnwrap(store.registerPitchTap(.init(x: -12, z: 37)))
        XCTAssertTrue(store.saveReview(named: "Revised volley"))
        let savedCurrent = try XCTUnwrap(store.savedReviews.first { $0.name == "Revised volley" })

        XCTAssertTrue(store.restoreReview(savedLegacy))
        XCTAssertEqual(store.selectedScenario, legacy)
        XCTAssertEqual(store.playhead, 4.5)
        XCTAssertTrue(store.marks.contains { $0.id == legacyMark.id && $0.start == legacyMark.start && $0.end == legacyMark.end })
        XCTAssertFalse(store.marks.contains { $0.id == currentMark.id })
        XCTAssertTrue(store.restoreReview(savedCurrent))
        XCTAssertEqual(store.selectedScenario, current)
        XCTAssertEqual(store.playhead, 7.4)
        XCTAssertTrue(store.marks.contains { $0.id == currentMark.id })
        XCTAssertFalse(store.marks.contains { $0.id == legacyMark.id })
    }
}
