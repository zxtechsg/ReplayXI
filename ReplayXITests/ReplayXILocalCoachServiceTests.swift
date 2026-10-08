import XCTest
@testable import ReplayXI

@MainActor
final class ReplayXILocalCoachServiceTests: XCTestCase {
    func testServiceStaysOffUntilStartedAndRejectsStaleOrPlayingEdits() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let service = ReplayXILocalCoachService(store: store)
        XCTAssertFalse(service.isRunning)
        var create = edit("create", store: store)
        create.kind = "run"
        create.start = .init(x: 0, z: 0)
        create.end = .init(x: 5, z: 5)
        create.startHeight = 0
        create.endHeight = 0
        create.label = "Mac run"

        store.setPlaying(true)
        XCTAssertFalse(service.apply(create))
        store.setPlaying(false)
        store.seek(to: 3)
        XCTAssertFalse(service.apply(create)) // wrong time
        create.time = store.playhead
        create.expectedRevision = 1
        XCTAssertFalse(service.apply(create)) // wrong revision
        create.expectedRevision = 0
        XCTAssertTrue(service.apply(create))
        let mark = try XCTUnwrap(store.marks.first { $0.label == "Mac run" })

        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: true))
        XCTAssertFalse(service.apply(.init(name: "play", value: true)))
        XCTAssertFalse(store.isPlaying)
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: false))

        let clear = edit("clear", store: store)
        XCTAssertTrue(service.apply(clear))
        XCTAssertFalse(store.marks.contains { $0.id == mark.id })
        XCTAssertEqual(store.marks.map(\.id), store.selectedScenario.coachMarks.map(\.id))
    }

    func testPlayerLabelUsesStoreAndKeepsAuthoredOverlays() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let service = ReplayXILocalCoachService(store: store)
        let player = try XCTUnwrap(store.selectedScenario.players.first)
        var command = edit("labelPlayer", store: store)
        command.playerID = player.id
        XCTAssertTrue(service.apply(command))
        XCTAssertTrue(store.marks.contains { $0.kind == .playerLabel && $0.playerID == player.id })
        XCTAssertTrue(service.apply(edit("clear", store: store)))
        XCTAssertEqual(store.marks.map(\.id), store.selectedScenario.coachMarks.map(\.id))
    }

    private func edit(_ name: String, store: ReplayStore) -> ReplayXIWireCommand {
        var command = ReplayXIWireCommand(name: name)
        command.expectedRevision = 0
        command.expectedScenarioID = store.selectedScenarioID
        command.time = store.playhead
        return command
    }
}
