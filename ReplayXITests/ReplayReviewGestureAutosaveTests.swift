import XCTest
@testable import ReplayXI

@MainActor
final class ReplayReviewGestureAutosaveTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testJoystickCommitAutosavesAfterMaskedPreviewSaveWithoutAnotherStateChange() async throws {
        let (url, store, original) = try makeFixture()
        defer { store.flushReviewAutosave() }
        let gestureID = UUID()
        let delta = PitchPoint(x: 0.5, z: 0.25)
        let preview = try XCTUnwrap(store.previewCoachMarkEndpoint(
            id: original.id,
            endpoint: .end,
            gestureID: gestureID,
            cumulativeDelta: delta
        ))
        XCTAssertTrue(preview.hasActiveTransaction)
        let expected = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertNotEqual(expected, original)

        // A long, motionless pinch lets the debounce finish while geometry is
        // still masked. Flush produces that state without a timing-dependent
        // setup and consumes the outstanding preview save task.
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(try reloadedMark(original.id, at: url), original)

        XCTAssertEqual(
            store.commitCoachMarkEndpointPreview(id: original.id, gestureID: gestureID),
            delta
        )
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertEqual(store.marks.first { $0.id == original.id }, expected)
        XCTAssertFalse(store.isPlaying)

        try await Task.sleep(for: .milliseconds(850))

        XCTAssertEqual(
            try reloadedMark(original.id, at: url),
            expected,
            "Lifting a settled joystick must persist the committed geometry without another action"
        )
    }

    func testDirectHandleCommitAutosavesWhenFinalSampleEqualsAlreadySavedPreview() async throws {
        let (url, store, original) = try makeFixture()
        defer { store.flushReviewAutosave() }
        let start = PitchPoint(x: -4, z: 8)
        let end = PitchPoint(x: 4, z: 16)
        XCTAssertTrue(store.updateCoachMarkGeometry(
            id: original.id,
            start: start,
            end: end,
            broadcast: false
        ))
        let expected = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertNotEqual(expected, original)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(try reloadedMark(original.id, at: url), original)

        XCTAssertTrue(store.updateCoachMarkGeometry(
            id: original.id,
            start: start,
            end: end,
            broadcast: true
        ))
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertEqual(store.marks.first { $0.id == original.id }, expected)
        XCTAssertFalse(store.isPlaying)

        try await Task.sleep(for: .milliseconds(850))

        XCTAssertEqual(
            try reloadedMark(original.id, at: url),
            expected,
            "Committing an unchanged final drag sample must replace the masked disk baseline"
        )
    }

    private func makeFixture() throws -> (URL, ReplayStore, CoachMark) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayGestureAutosave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        let url = directory.appendingPathComponent("reviews.json")
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        let store = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library)
        store.seek(to: 5)
        store.beginDrawing(.pass)
        XCTAssertNil(store.registerPitchTap(PitchPoint(x: 2, z: 3)))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: 8, z: 10)))
        store.cancelDrawing()
        XCTAssertTrue(store.flushReviewAutosave())
        return (url, store, mark)
    }

    private func reloadedMark(_ id: UUID, at url: URL) throws -> CoachMark {
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        return try XCTUnwrap(library.autosavedReview?.state.marks.first { $0.id == id })
    }
}
