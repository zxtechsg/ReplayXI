import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayPOVLook182Tests: XCTestCase {
    func testRenderAndPollingCallbacksShareReplacementSceneReference() {
        let reference = ReplayMatchSceneReference()
        let render: (Entity?) -> Void = { reference.root = $0 }
        let poll: () -> Entity? = { reference.root }
        let first = Entity(), next = Entity()
        first.name = "match-root-first"
        next.name = "match-root-next"
        render(first)
        XCTAssertTrue(poll() === first)
        render(next)
        XCTAssertTrue(poll() === next)
        render(nil)
        XCTAssertNil(poll())
    }

    func testScenarioObserverDoesNotEraseTheRendererOwnedRoot() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: ".onChange(of: store.selectedScenarioID)"))
        let end = try XCTUnwrap(source.range(of: ".onChange(of: store.viewMode)",
            range: start.upperBound..<source.endIndex))
        XCTAssertFalse(source[start.upperBound..<end.lowerBound].contains("currentMatchRoot = nil"))
        XCTAssertTrue(source.contains("currentMatchRoot.name == \"match-root-\\(store.selectedScenarioID)\""))
    }

    func testHeadingUsesPitchYawAndRejectsDegenerateTargets() {
        let origin = PitchPoint(x: 3, z: -8)
        XCTAssertEqual(ReplayPOVLookRequest.heading(from: origin, to: [3, 1, 2]) ?? .nan,
            0, accuracy: 0.0001)
        XCTAssertEqual(ReplayPOVLookRequest.heading(from: origin, to: [13, 1, -8]) ?? .nan,
            90, accuracy: 0.0001)
        XCTAssertEqual(ReplayPOVLookRequest.heading(from: origin, to: [-7, 1, -8]) ?? .nan,
            -90, accuracy: 0.0001)
        XCTAssertEqual(abs(ReplayPOVLookRequest.heading(from: origin, to: [3, 1, -18]) ?? .nan),
            180, accuracy: 0.0001)
        XCTAssertNil(ReplayPOVLookRequest.heading(from: origin, to: [3, 8, -8]),
            "Height alone cannot define a horizontal heading")
        XCTAssertNil(ReplayPOVLookRequest.heading(from: origin, to: [3.001, 0, -8.001]))
        XCTAssertNil(ReplayPOVLookRequest.heading(from: origin, to: [.nan, 0, 0]))
        XCTAssertNil(ReplayPOVLookRequest.heading(from: origin, to: [0, .infinity, 0]))
    }

    func testControlArrivalChangesOnlyForNavigationOrExplicitLookRequest() {
        let lookID = UUID()
        let pov = PlaybackControlArrival(scenarioID: "match", view: .firstPerson,
            playerID: "p7", lookID: lookID)
        XCTAssertEqual(pov, PlaybackControlArrival(scenarioID: "match", view: .firstPerson,
            playerID: "p7", lookID: lookID))
        XCTAssertNotEqual(pov, PlaybackControlArrival(scenarioID: "match", view: .firstPerson,
            playerID: "p7", lookID: UUID()))
        XCTAssertNotEqual(pov, PlaybackControlArrival(scenarioID: "match", view: .firstPerson,
            playerID: "p8", lookID: lookID))
        XCTAssertNotEqual(pov, PlaybackControlArrival(scenarioID: "next", view: .firstPerson,
            playerID: "p7", lookID: lookID))
        let tactical = PlaybackControlArrival(scenarioID: "match", view: .tacticalTable,
            playerID: "p7", lookID: nil)
        XCTAssertEqual(tactical, PlaybackControlArrival(scenarioID: "match", view: .tacticalTable,
            playerID: "p8", lookID: nil),
            "Player changes outside POV must not reposition controls")
        XCTAssertNotEqual(tactical, PlaybackControlArrival(scenarioID: "match", view: .touchline,
            playerID: "p7", lookID: nil))
    }

    func testFacePOVTowardsCreatesOneShotRequestAndKeepsFreeLookDuringPlayback() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 2, broadcast: false)
        store.setPlaying(true, broadcast: false)
        var broadcasts = 0
        store.onBroadcastSnapshot = { _ in broadcasts += 1 }

        XCTAssertTrue(store.facePOVTowards([0, 1, 0]))
        let first = try XCTUnwrap(store.povLookRequest)
        XCTAssertEqual(first.scenarioID, store.selectedScenarioID)
        XCTAssertEqual(first.playerID, store.activePerspectiveID)
        XCTAssertEqual(first.target, [0, 1, 0])
        XCTAssertEqual(store.viewMode, .firstPerson)
        XCTAssertFalse(store.isPlaying)
        XCTAssertTrue(store.statusMessage.contains("free look"))
        XCTAssertEqual(broadcasts, 0, "A local one-shot aim does not lock or broadcast gaze")

        store.seek(to: 3, broadcast: false)
        store.setPlaying(true, broadcast: false)
        XCTAssertEqual(store.povLookRequest?.id, first.id,
            "Playback and head motion must not generate repeated aim requests")
        XCTAssertTrue(store.facePOVTowards([1, 1, 0]))
        XCTAssertNotEqual(store.povLookRequest?.id, first.id,
            "Only another deliberate action creates a fresh request")
    }

    func testFacePOVTowardsRejectsInvalidTargetAndUnavailableEditingStates() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let player = try XCTUnwrap(store.activePerspective)
        let pose = store.presentedPlayerPose(for: player, at: store.playhead)
        for target: SIMD3<Float> in [
            [35, 1, 0], [0, 1, 53], [0, -0.1, 0], [0, 12.1, 0],
            [.nan, 1, 0], [0, .infinity, 0],
            [pose.position.x, 1, pose.position.z]
        ] {
            XCTAssertFalse(store.facePOVTowards(target), "Rejected target: \(target)")
            XCTAssertNil(store.povLookRequest)
        }

        store.localRole = .player
        XCTAssertFalse(store.facePOVTowards([0, 1, 0]))
        store.localRole = .coach
        store.beginDrawing(.run)
        XCTAssertTrue(store.isDrawing)
        XCTAssertFalse(store.facePOVTowards([0, 1, 0]))
        store.cancelDrawing()
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertFalse(store.facePOVTowards([0, 1, 0]))
        store.cancelTimelineScrub()
        XCTAssertNil(store.povLookRequest)
    }
}
