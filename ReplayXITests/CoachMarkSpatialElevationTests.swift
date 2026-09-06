import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class CoachMarkSpatialElevationTests: XCTestCase {
    func testLegacyPayloadDefaultsToPitchLevel() throws {
        let json = Data(
            """
            {
              "id":"AAAAAAAA-0000-4000-8000-000000000901",
              "kind":"run",
              "start":{"x":1,"z":2},
              "end":{"x":5,"z":8},
              "label":"Overlap",
              "revealTime":3,
              "author":"Coach"
            }
            """.utf8
        )

        let mark = try JSONDecoder().decode(CoachMark.self, from: json)

        XCTAssertNil(mark.startElevation)
        XCTAssertNil(mark.endElevation)
        XCTAssertEqual(mark.resolvedStartElevation, 0)
        XCTAssertEqual(mark.resolvedEndElevation, 0)
        XCTAssertFalse(mark.hasSpatialElevation)
    }

    func testElevationEditIsAtomicSharePlayStateAndPreservesPlayerTracking() throws {
        let store = ReplayStore()
        store.seek(to: 10, broadcast: false)
        let mark = try makePass(in: store)
        XCTAssertTrue(store.setCoachMarkTracking(id: mark.id, playerID: "navy-rw"))
        let tracked = try self.mark(with: mark.id, in: store)
        store.setPlaying(true, broadcast: false)
        var snapshots: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { snapshots.append($0) }

        XCTAssertTrue(
            store.nudgeCoachMarkElevation(id: mark.id, target: .end, by: 0.75)
        )

        let raisedTip = try self.mark(with: mark.id, in: store)
        XCTAssertEqual(raisedTip.resolvedStartElevation, 0)
        XCTAssertEqual(raisedTip.resolvedEndElevation, 0.75)
        XCTAssertEqual(raisedTip.startTrackAnchor, tracked.startTrackAnchor)
        XCTAssertEqual(raisedTip.endTrackAnchor, tracked.endTrackAnchor)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].marks.first { $0.id == mark.id }, raisedTip)

        XCTAssertTrue(
            store.nudgeCoachMarkElevation(id: mark.id, target: .both, by: 0.25)
        )
        let raisedStroke = try self.mark(with: mark.id, in: store)
        XCTAssertEqual(raisedStroke.resolvedStartElevation, 0.25)
        XCTAssertEqual(raisedStroke.resolvedEndElevation, 1)
        XCTAssertEqual(snapshots.count, 2)

        let geometryAtEdit = raisedStroke.resolvedGeometry(
            in: store.selectedScenario,
            at: store.playhead
        )
        store.seek(to: 14, broadcast: false)
        let geometryAfterSeek = raisedStroke.resolvedGeometry(
            in: store.selectedScenario,
            at: store.playhead
        )
        XCTAssertNotEqual(geometryAfterSeek, geometryAtEdit)
        XCTAssertEqual(raisedStroke.resolvedStartElevation, 0.25)
        XCTAssertEqual(raisedStroke.resolvedEndElevation, 1)
    }

    func testElevationClampsToSafeVolumeAndGroundCanonicalizesToNil() throws {
        let store = ReplayStore()
        let mark = try makePass(in: store)
        var broadcastCount = 0
        store.onBroadcastSnapshot = { _ in broadcastCount += 1 }

        XCTAssertTrue(
            store.nudgeCoachMarkElevation(id: mark.id, target: .both, by: 40)
        )
        let ceiling = try self.mark(with: mark.id, in: store)
        XCTAssertEqual(ceiling.resolvedStartElevation, CoachMarkGeometryPolicy.maximumElevation)
        XCTAssertEqual(ceiling.resolvedEndElevation, CoachMarkGeometryPolicy.maximumElevation)
        XCTAssertFalse(
            store.nudgeCoachMarkElevation(id: mark.id, target: .both, by: 0.25)
        )
        XCTAssertEqual(broadcastCount, 1)

        XCTAssertTrue(
            store.nudgeCoachMarkElevation(id: mark.id, target: .start, by: -40)
        )
        let groundedStart = try self.mark(with: mark.id, in: store)
        XCTAssertNil(groundedStart.startElevation)
        XCTAssertEqual(groundedStart.resolvedStartElevation, 0)
        XCTAssertEqual(groundedStart.resolvedEndElevation, 4)
        XCTAssertEqual(broadcastCount, 2)
    }

    func testMalformedSharedElevationIsRejected() {
        let store = ReplayStore()
        let nonFinite = CoachMark(
            kind: .pass,
            start: PitchPoint(x: 1, z: 2),
            end: PitchPoint(x: 5, z: 8),
            startElevation: .nan,
            label: "Broken height",
            revealTime: 3
        )
        let tooHigh = CoachMark(
            kind: .run,
            start: PitchPoint(x: 1, z: 2),
            end: PitchPoint(x: 5, z: 8),
            endElevation: CoachMarkGeometryPolicy.maximumElevation + 0.01,
            label: "Unbounded height",
            revealTime: 3
        )
        let splitZone = CoachMark(
            kind: .space,
            start: PitchPoint(x: 1, z: 2),
            end: PitchPoint(x: 5, z: 8),
            startElevation: 0,
            endElevation: 4,
            label: "Disconnected zone",
            revealTime: 3
        )

        XCTAssertFalse(store.appendRemoteCoachMark(nonFinite))
        XCTAssertFalse(store.appendRemoteCoachMark(tooHigh))
        XCTAssertFalse(store.appendRemoteCoachMark(splitZone))
    }

    func testSpatialElevationRoundTripsThroughSharedCommand() throws {
        let mark = CoachMark(
            id: UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000902")!,
            kind: .pass,
            start: PitchPoint(x: -4, z: 2),
            end: PitchPoint(x: 6, z: 12),
            startElevation: 0.5,
            endElevation: 2,
            label: "Lofted release",
            revealTime: 6,
            hideTime: 12,
            startTrackAnchor: CoachMarkTrackAnchor(playerID: "navy-rw"),
            endTrackAnchor: CoachMarkTrackAnchor(playerID: "navy-rb")
        )
        let command = SharedCommand(
            kind: .coachAnnotation,
            sequence: 9,
            authorID: UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000903")!,
            sentAt: Date(timeIntervalSinceReferenceDate: 99),
            authorRole: .coach,
            snapshot: nil,
            mark: mark
        )

        let decoded = try JSONDecoder().decode(
            SharedCommand.self,
            from: JSONEncoder().encode(command)
        )

        XCTAssertEqual(decoded, command)
        XCTAssertEqual(decoded.mark?.startElevation, 0.5)
        XCTAssertEqual(decoded.mark?.endElevation, 2)
    }

    func testDirectHandlePreviewLocksTransportViewAndPOVUntilCancelled() throws {
        let store = ReplayStore()
        let mark = try makePass(in: store)
        let initialTime = store.playhead
        let initialView = store.viewMode
        let initialPerspective = store.localPerspectiveID

        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: PitchPoint(x: -8, z: 4),
                end: PitchPoint(x: 2, z: 14),
                broadcast: false
            )
        )
        XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertFalse(store.hasActiveCoachMarkEndpointPreview)

        store.seek(to: initialTime + 5, broadcast: false)
        store.setViewMode(.touchline, broadcast: false)
        store.openLocalPlayerPOV("navy-rb")

        XCTAssertEqual(store.playhead, initialTime)
        XCTAssertEqual(store.viewMode, initialView)
        XCTAssertEqual(store.localPerspectiveID, initialPerspective)
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)

        store.seek(to: initialTime + 5, broadcast: false)
        XCTAssertEqual(store.playhead, initialTime + 5)
    }

    func testSceneRendersSlopedRailArrowAndGroundTethers() throws {
        let store = ReplayStore()
        let scenario = store.selectedScenario
        let id = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000904")!
        let mark = CoachMark(
            id: id,
            kind: .pass,
            start: PitchPoint(x: -5, z: 0),
            end: PitchPoint(x: 5, z: 10),
            startElevation: 0.5,
            endElevation: 2,
            label: "Lifted lane",
            revealTime: 0
        )
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: 1,
            viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: [mark],
            selectedAnnotationID: id,
            selectedAnnotationIsEditable: true,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil
        )

        let markRoot = try XCTUnwrap(root.findEntity(named: "mark-\(id.uuidString)"))
        let rail = try XCTUnwrap(markRoot.findEntity(named: "annotation-mark-segment-0"))
        let arrow = try XCTUnwrap(markRoot.findEntity(named: "annotation-mark-arrow"))
        let startGuide = try XCTUnwrap(
            markRoot.findEntity(named: "annotation-mark-start-elevation-guide")
        )
        let endGuide = try XCTUnwrap(
            markRoot.findEntity(named: "annotation-mark-end-elevation-guide")
        )

        XCTAssertEqual(rail.position.y, 1.35, accuracy: 0.000_1)
        XCTAssertEqual(arrow.position.y, 2.12, accuracy: 0.000_1)
        XCTAssertTrue(startGuide.isEnabled)
        XCTAssertTrue(endGuide.isEnabled)
        XCTAssertEqual(startGuide.scale.y, 0.60, accuracy: 0.000_1)
        XCTAssertEqual(endGuide.scale.y, 2.10, accuracy: 0.000_1)

        let expectedDirection = simd_normalize(SIMD3<Float>(10, 1.5, 10))
        let renderedDirection = rail.orientation.act(SIMD3<Float>(0, 0, 1))
        XCTAssertGreaterThan(simd_dot(expectedDirection, renderedDirection), 0.999)

        let selection = try XCTUnwrap(
            root.findEntity(named: AnnotationSceneAffordance.selectionRootName)
        )
        let startHandle = try XCTUnwrap(selection.children.first {
            $0.name.hasPrefix("annotation-target-start-")
        })
        let endHandle = try XCTUnwrap(selection.children.first {
            $0.name.hasPrefix("annotation-target-end-")
        })
        XCTAssertEqual(startHandle.position.y, 0.98, accuracy: 0.000_1)
        XCTAssertEqual(endHandle.position.y, 2.48, accuracy: 0.000_1)
    }

    private func makePass(in store: ReplayStore) throws -> CoachMark {
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: -12, z: -8)))
        return try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: -4, z: 2))
        )
    }

    private func mark(with id: UUID, in store: ReplayStore) throws -> CoachMark {
        try XCTUnwrap(store.marks.first { $0.id == id })
    }
}
