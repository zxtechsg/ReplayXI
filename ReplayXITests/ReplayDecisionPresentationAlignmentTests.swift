import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayDecisionPresentationAlignmentTests: XCTestCase {
    private func store(playerID: String = "red-lb") -> ReplayStore {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: "everyone-with-seven", broadcast: false)
        store.openLocalPlayerPOV(playerID)
        store.setViewMode(.tacticalTable, broadcast: false)
        store.seek(to: 15, broadcast: false)
        return store
    }

    /// Mirrors both decision snapshot producers in FootballImmersiveView.
    private func snapshot(from store: ReplayStore) throws -> ReplayDecisionSnapshot {
        try XCTUnwrap(store.selectedScenario.decisionReview(
            at: store.playhead,
            playerID: store.activePerspectiveID,
            currentMarks: store.marks,
            presentation: store.playerPresentation
        ))
    }

    private func update(
        _ root: Entity, from store: ReplayStore, snapshot: ReplayDecisionSnapshot
    ) {
        PitchSceneFactory.update(
            root: root, scenario: store.selectedScenario, time: store.playhead,
            viewMode: store.viewMode, perspectiveID: store.activePerspectiveID,
            marks: store.marks, decisionSnapshot: snapshot,
            showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil,
            triangleLockMode: store.triangleLockMode,
            showsIdealBranch: store.showsIdealBranch
        )
    }

    private func point(_ vector: SIMD3<Float>) -> PitchPoint {
        PitchPoint(x: vector.x, z: vector.z)
    }

    private func assertPoint(
        _ actual: PitchPoint, _ expected: PitchPoint,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.000_1, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: 0.000_1, file: file, line: line)
    }

    func testFallenSourceRailsMatchTheBodyThroughRecoveryAndExactRewind() throws {
        let store = store()
        let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
        var firstEndpoints: [PitchPoint] = []
        var firstSnapshot: ReplayDecisionSnapshot?

        for (step, time) in [15.0, 16.0, 15.0].enumerated() {
            store.seek(to: time, broadcast: false)
            let snapshot = try snapshot(from: store)
            XCTAssertEqual(snapshot.passingOptions.count, 4)
            update(root, from: store, snapshot: snapshot)
            let body = try XCTUnwrap(root.findEntity(named: "player-red-lb"))
            let overlay = try XCTUnwrap(root.findEntity(named: DecisionOptionSceneOverlay.rootName))
            XCTAssertTrue(body.isEnabled)
            XCTAssertTrue(overlay.isEnabled)
            var endpoints: [PitchPoint] = []

            for (index, option) in snapshot.passingOptions.enumerated() {
                let slot = try XCTUnwrap(overlay.findEntity(named: "decision-slot-\(index)"))
                let rail = try XCTUnwrap(slot.findEntity(named: "decision-option-rail"))
                let start = point(rail.position + rail.orientation.act([0, 0, -rail.scale.z / 2]))
                let end = point(rail.position + rail.orientation.act([0, 0, rail.scale.z / 2]))
                let receiver = try XCTUnwrap(root.findEntity(named: "player-\(option.receiverID)"))
                XCTAssertTrue(slot.isEnabled)
                assertPoint(start, point(body.position))
                assertPoint(end, point(receiver.position))
                endpoints.append(contentsOf: [start, end])
            }
            if step == 0 {
                firstEndpoints = endpoints
                firstSnapshot = snapshot
            } else if step == 2 {
                XCTAssertEqual(endpoints, firstEndpoints)
                XCTAssertEqual(snapshot, firstSnapshot)
            }
        }
    }

    func testFallenReceiverTargetAndRailEndMatchTheBody() throws {
        let store = store(playerID: "red-lw")
        let snapshot = try snapshot(from: store)
        let index = try XCTUnwrap(snapshot.passingOptions.firstIndex { $0.receiverID == "red-lb" })
        let root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
        update(root, from: store, snapshot: snapshot)
        let body = try XCTUnwrap(root.findEntity(named: "player-red-lb"))
        let slot = try XCTUnwrap(root.findEntity(named: "decision-slot-\(index)"))
        let ring = try XCTUnwrap(slot.findEntity(named: "decision-option-target-outer"))
        let rail = try XCTUnwrap(slot.findEntity(named: "decision-option-rail"))
        XCTAssertTrue(slot.isEnabled)
        assertPoint(point(ring.position), point(body.position))
        assertPoint(
            point(rail.position + rail.orientation.act([0, 0, rail.scale.z / 2])),
            point(body.position)
        )
    }

    func testLaneMetricsUseTheDisplayedSourceReceiversAndDefenders() throws {
        for subjectID in ["red-lb", "navy-rw"] {
            let store = store(playerID: subjectID)
            let snapshot = try snapshot(from: store)
            let scenario = store.selectedScenario
            let subject = try XCTUnwrap(scenario.player(id: subjectID))
            let poses = store.playerPresentation.poses(in: scenario, at: store.playhead)
            let start = try XCTUnwrap(poses[subjectID]).position
            let defenders = scenario.players.filter { $0.team != subject.team }

            for option in snapshot.passingOptions {
                let end = try XCTUnwrap(poses[option.receiverID]).position
                var clearances: [(id: String, distance: Float)] = []
                var pressures: [Float] = []
                for defender in defenders {
                    let position = try XCTUnwrap(poses[defender.id]).position
                    clearances.append((
                        id: defender.id,
                        distance: ReplayGeometry.distanceFromSegment(
                            point: position, start: start, end: end
                        )
                    ))
                    pressures.append(ReplayGeometry.distance(position, end))
                }
                clearances.sort {
                    $0.distance == $1.distance ? $0.id < $1.id : $0.distance < $1.distance
                }
                let clearance = try XCTUnwrap(clearances.first)
                let pressure = try XCTUnwrap(pressures.min())
                let effective = min(clearance.distance, pressure)
                let expectedAvailability: ReplayLaneAvailability = effective < 0.8
                    ? .blocked : (effective < 1.8 ? .tight : .clear)
                XCTAssertEqual(option.passDistanceMetres, ReplayGeometry.distance(start, end), accuracy: 0.000_1)
                XCTAssertEqual(try XCTUnwrap(option.laneClearanceMetres), clearance.distance, accuracy: 0.000_1)
                XCTAssertEqual(try XCTUnwrap(option.targetPressureMetres), pressure, accuracy: 0.000_1)
                XCTAssertEqual(option.nearestLaneDefenderID, clearance.id)
                XCTAssertEqual(option.availability, expectedAvailability)
            }
        }
    }

    func testHistoricalEvidenceAndNormalFreeLookRemainUnchanged() throws {
        let store = store()
        for time in [14.1, 15, 16] {
            store.seek(to: time, broadcast: false)
            let presented = try snapshot(from: store)
            let raw = try XCTUnwrap(store.selectedScenario.decisionReview(
                at: time, playerID: store.activePerspectiveID, currentMarks: store.marks
            ))
            XCTAssertEqual(presented.scanWindow, raw.scanWindow)
            XCTAssertEqual(presented.receivingOrientation, raw.receivingOrientation)
            XCTAssertEqual(presented.observedDestination, raw.observedDestination)
            XCTAssertEqual(presented.coachSuggestion, raw.coachSuggestion)
            XCTAssertEqual(presented.evidence, raw.evidence)

            store.setViewMode(.firstPerson, broadcast: false)
            XCTAssertEqual(try snapshot(from: store), raw)
            store.setViewMode(.tacticalTable, broadcast: false)
        }
    }
}
