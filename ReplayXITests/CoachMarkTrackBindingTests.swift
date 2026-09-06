import Foundation
import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class CoachMarkTrackBindingTests: XCTestCase {
    func testRunDrawnFromPlayerFollowsThatTrackWithoutChangingItsShape() throws {
        let store = ReplayStore()
        store.selectScenario(id: "eleven-eyes", broadcast: false)
        store.seek(to: 8, broadcast: false)

        let player = try XCTUnwrap(store.selectedScenario.player(id: "navy-rw"))
        let authoredStart = player.presentationPose(at: 8).position
        let authoredEnd = PitchPoint(x: authoredStart.x + 4, z: authoredStart.z + 7)
        store.beginDrawing(.run)
        XCTAssertNil(store.registerPitchTap(authoredStart))
        let mark = try XCTUnwrap(store.registerPitchTap(authoredEnd))

        XCTAssertEqual(mark.startTrackAnchor?.playerID, player.id)
        XCTAssertEqual(mark.endTrackAnchor?.playerID, player.id)
        XCTAssertEqual(
            mark.resolvedGeometry(in: store.selectedScenario, at: 8),
            ResolvedCoachMarkGeometry(start: authoredStart, end: authoredEnd)
        )

        let laterTime: TimeInterval = 14
        let laterPlayerPosition = player.presentationPose(at: laterTime).position
        let later = mark.resolvedGeometry(in: store.selectedScenario, at: laterTime)
        XCTAssertEqual(later.start.x, laterPlayerPosition.x, accuracy: 0.000_1)
        XCTAssertEqual(later.start.z, laterPlayerPosition.z, accuracy: 0.000_1)
        XCTAssertEqual(later.end.x - later.start.x, 4, accuracy: 0.000_1)
        XCTAssertEqual(later.end.z - later.start.z, 7, accuracy: 0.000_1)
    }

    func testPassEndpointsCanFollowDifferentPlayers() throws {
        let store = ReplayStore()
        store.seek(to: 10, broadcast: false)
        let source = try XCTUnwrap(store.selectedScenario.player(id: "navy-rw"))
        let receiver = try XCTUnwrap(store.selectedScenario.player(id: "navy-rb"))
        let start = source.presentationPose(at: 10).position
        let end = receiver.presentationPose(at: 10).position

        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(start))
        let mark = try XCTUnwrap(store.registerPitchTap(end))

        XCTAssertEqual(mark.startTrackAnchor?.playerID, source.id)
        XCTAssertEqual(mark.endTrackAnchor?.playerID, receiver.id)
        let later = mark.resolvedGeometry(in: store.selectedScenario, at: 13)
        XCTAssertEqual(later.start, source.presentationPose(at: 13).position)
        XCTAssertEqual(later.end, receiver.presentationPose(at: 13).position)
    }

    func testTrackingTogglePreservesCurrentGeometryAndPublishesOnce() throws {
        let store = ReplayStore()
        store.seek(to: 9, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: -7, z: 3)))
        let original = try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: 2, z: 12))
        )
        let before = original.resolvedGeometry(in: store.selectedScenario, at: store.playhead)
        var snapshots: [SharedPlaybackSnapshot] = []
        store.onBroadcastSnapshot = { snapshots.append($0) }

        XCTAssertTrue(store.setCoachMarkTracking(id: original.id, playerID: "navy-dm"))
        let tracked = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertEqual(
            tracked.resolvedGeometry(in: store.selectedScenario, at: store.playhead),
            before
        )
        XCTAssertEqual(tracked.anchoredPlayerIDs, ["navy-dm"])
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(
            snapshots[0].marks.first { $0.id == original.id }?.startTrackAnchor,
            tracked.startTrackAnchor
        )

        XCTAssertTrue(store.setCoachMarkTracking(id: original.id, playerID: nil))
        let fixed = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertFalse(fixed.followsPlayerTracks)
        XCTAssertEqual(fixed.start, before.start)
        XCTAssertEqual(fixed.end, before.end)
        XCTAssertEqual(snapshots.count, 2)
    }

    func testManualTrackingCanFollowEveryPlayerInBothXIsAtCurrentTimestamp() throws {
        let store = ReplayStore()
        store.selectScenario(id: "eleven-eyes", broadcast: false)
        store.seek(to: 10, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: -2, z: 1)))
        let created = try XCTUnwrap(
            store.registerPitchTap(PitchPoint(x: 3, z: 7))
        )
        XCTAssertEqual(store.selectedScenario.homePlayers.count, 11)
        XCTAssertEqual(store.selectedScenario.awayPlayers.count, 11)

        for player in store.selectedScenario.players {
            let current = try XCTUnwrap(store.marks.first { $0.id == created.id })
            let before = current.resolvedGeometry(
                in: store.selectedScenario,
                at: store.playhead
            )

            XCTAssertTrue(
                store.setCoachMarkTracking(id: created.id, playerID: player.id),
                "Expected manual tracking to accept \(player.team.rawValue) #\(player.shirtNumber)"
            )
            let tracked = try XCTUnwrap(store.marks.first { $0.id == created.id })
            XCTAssertEqual(tracked.startTrackAnchor?.playerID, player.id)
            XCTAssertEqual(tracked.endTrackAnchor?.playerID, player.id)

            let after = tracked.resolvedGeometry(
                in: store.selectedScenario,
                at: store.playhead
            )
            XCTAssertEqual(after.start.x, before.start.x, accuracy: 0.000_1)
            XCTAssertEqual(after.start.z, before.start.z, accuracy: 0.000_1)
            XCTAssertEqual(after.end.x, before.end.x, accuracy: 0.000_1)
            XCTAssertEqual(after.end.z, before.end.z, accuracy: 0.000_1)
        }

        XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: nil))
        let fixed = try XCTUnwrap(store.marks.first { $0.id == created.id })
        XCTAssertFalse(fixed.followsPlayerTracks)
    }

    func testLegacyCoachMarkPayloadWithoutAnchorsStillDecodesAsFixedPitch() throws {
        let json = Data(
            """
            {
              "id":"AAAAAAAA-0000-4000-8000-000000000001",
              "kind":"run",
              "start":{"x":1,"z":2},
              "end":{"x":4,"z":8},
              "label":"Overlap",
              "revealTime":3,
              "author":"Coach"
            }
            """.utf8
        )

        let mark = try JSONDecoder().decode(CoachMark.self, from: json)

        XCTAssertNil(mark.startTrackAnchor)
        XCTAssertNil(mark.endTrackAnchor)
        XCTAssertNil(mark.playerID)
        XCTAssertEqual(mark.start, PitchPoint(x: 1, z: 2))
        XCTAssertEqual(mark.end, PitchPoint(x: 4, z: 8))
    }

    func testRemoteMarkRejectsUnknownOrNonFiniteTrackAnchors() {
        let store = ReplayStore()
        let unknown = CoachMark(
            kind: .run,
            start: PitchPoint(x: 1, z: 2),
            end: PitchPoint(x: 4, z: 8),
            label: "Unknown runner",
            revealTime: 3,
            startTrackAnchor: CoachMarkTrackAnchor(playerID: "missing-player")
        )
        let nonFinite = CoachMark(
            kind: .pass,
            start: PitchPoint(x: 1, z: 2),
            end: PitchPoint(x: 4, z: 8),
            label: "Broken offset",
            revealTime: 3,
            startTrackAnchor: CoachMarkTrackAnchor(
                playerID: "navy-rw",
                offset: PitchPoint(x: .infinity, z: 0)
            )
        )

        XCTAssertFalse(store.appendRemoteCoachMark(unknown))
        XCTAssertFalse(store.appendRemoteCoachMark(nonFinite))
    }

    func testTrackingToggleIsRejectedDuringGeometryPreviewAndCancelRestoresBaseline() throws {
        let store = ReplayStore()
        store.seek(to: 9, broadcast: false)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: -8, z: 2)))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 1, z: 10)))

        XCTAssertTrue(
            store.updateCoachMarkGeometry(
                id: mark.id,
                start: PitchPoint(x: -7, z: 3),
                end: PitchPoint(x: 2, z: 11),
                broadcast: false
            )
        )
        XCTAssertFalse(store.setCoachMarkTracking(id: mark.id, playerID: "navy-rw"))
        XCTAssertEqual(store.statusMessage, "Finish the current annotation move first")
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: mark.id))

        let restored = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertEqual(restored.start, mark.start)
        XCTAssertEqual(restored.end, mark.end)
        XCTAssertNil(restored.startTrackAnchor)
        XCTAssertNil(restored.endTrackAnchor)
    }

    func testRemoteMarkRejectsTrackGeometryThatResolvesOffPitch() {
        let store = ReplayStore()
        let mark = CoachMark(
            kind: .run,
            start: PitchPoint(x: 1, z: 2),
            end: PitchPoint(x: 4, z: 8),
            label: "Malicious displacement",
            revealTime: 3,
            startTrackAnchor: CoachMarkTrackAnchor(
                playerID: "navy-rw",
                offset: PitchPoint(x: 60, z: 0)
            )
        )

        XCTAssertFalse(store.appendRemoteCoachMark(mark))
    }

    func testAnchoredSharedCommandJSONRoundTripAndRemoteApplication() throws {
        let source = try XCTUnwrap(ReplayStore().selectedScenario.player(id: "navy-rw"))
        let receiver = try XCTUnwrap(ReplayStore().selectedScenario.player(id: "navy-rb"))
        let revealTime: TimeInterval = 10
        let mark = CoachMark(
            id: UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000123")!,
            kind: .pass,
            start: source.presentationPose(at: revealTime).position,
            end: receiver.presentationPose(at: revealTime).position,
            label: "Tracked release",
            revealTime: revealTime,
            startTrackAnchor: CoachMarkTrackAnchor(playerID: source.id),
            endTrackAnchor: CoachMarkTrackAnchor(playerID: receiver.id)
        )
        let command = SharedCommand(
            kind: .coachAnnotation,
            sequence: 7,
            authorID: UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000456")!,
            sentAt: Date(timeIntervalSinceReferenceDate: 9_000),
            authorRole: .coach,
            snapshot: nil,
            mark: mark
        )

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(SharedCommand.self, from: data)
        XCTAssertEqual(decoded, command)

        let remote = ReplayStore()
        XCTAssertTrue(remote.appendRemoteCoachMark(try XCTUnwrap(decoded.mark)))
        XCTAssertEqual(remote.marks.last?.startTrackAnchor, mark.startTrackAnchor)
        XCTAssertEqual(remote.marks.last?.endTrackAnchor, mark.endTrackAnchor)
    }

    func testAnchoredMarkArrivingDuringLocalPauseAppearsWhenFollowingResumes() throws {
        let coach = ReplayStore()
        coach.setCollaborationActive(true)
        let player = ReplayStore()
        player.localRole = .player
        player.setCollaborationActive(true)
        XCTAssertTrue(player.applyRemote(coach.makeSnapshot()))
        player.setFollowingCoach(false)

        coach.seek(to: 10, broadcast: false)
        let source = try XCTUnwrap(coach.selectedScenario.player(id: "navy-rw"))
        let receiver = try XCTUnwrap(coach.selectedScenario.player(id: "navy-rb"))
        coach.beginDrawing(.pass)
        XCTAssertNil(coach.registerPitchTap(source.presentationPose(at: 10).position))
        let mark = try XCTUnwrap(
            coach.registerPitchTap(receiver.presentationPose(at: 10).position)
        )
        XCTAssertNotNil(mark.startTrackAnchor)
        XCTAssertNotNil(mark.endTrackAnchor)

        XCTAssertTrue(player.applyRemote(coach.makeSnapshot()))
        XCTAssertFalse(player.marks.contains { $0.id == mark.id })

        player.setFollowingCoach(true)
        let resumed = try XCTUnwrap(player.marks.first { $0.id == mark.id })
        XCTAssertEqual(resumed.startTrackAnchor, mark.startTrackAnchor)
        XCTAssertEqual(resumed.endTrackAnchor, mark.endTrackAnchor)
    }

    func testTrackedPresentationMovesInPlaceWithoutReplacingRealityKitTree() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .realWorldReplay))
        let mark = try XCTUnwrap(
            scenario.coachMarks.first { $0.id.uuidString.hasSuffix("000000000601") }
        )
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)

        updateScene(root: root, scenario: scenario, time: mark.revealTime)
        let markEntity = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
        let segment = try XCTUnwrap(markEntity.findEntity(named: "annotation-mark-segment-0"))
        let initialPosition = segment.position

        updateScene(root: root, scenario: scenario, time: 18)
        let updatedEntity = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
        let updatedSegment = try XCTUnwrap(updatedEntity.findEntity(named: "annotation-mark-segment-0"))

        XCTAssertTrue(markEntity === updatedEntity)
        XCTAssertTrue(segment === updatedSegment)
        XCTAssertNotEqual(updatedSegment.position, initialPosition)
    }

    func testBallEmphasisToggleUsesStableSceneEntity() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let emphasis = try XCTUnwrap(root.findEntity(named: "ball-emphasis"))

        updateScene(root: root, scenario: scenario, time: 12, emphasizesBall: false)
        XCTAssertFalse(emphasis.isEnabled)
        updateScene(root: root, scenario: scenario, time: 12, emphasizesBall: true)
        XCTAssertTrue(emphasis.isEnabled)
        XCTAssertTrue(emphasis === root.findEntity(named: "ball-emphasis"))
    }

    private func updateScene(
        root: Entity,
        scenario: ReplayScenario,
        time: TimeInterval,
        emphasizesBall: Bool = true
    ) {
        PitchSceneFactory.update(
            root: root,
            scenario: scenario,
            time: time,
            viewMode: .tacticalTable,
            perspectiveID: scenario.defaultPerspectiveID,
            marks: scenario.coachMarks,
            showsLaneLens: false,
            isDrawing: false,
            positionalOriginTransform: nil,
            emphasizesBall: emphasizesBall
        )
    }
}
