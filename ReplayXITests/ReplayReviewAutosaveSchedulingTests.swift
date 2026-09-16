import XCTest
@testable import ReplayXI

@MainActor
final class ReplayReviewAutosaveSchedulingTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testSixHundredScrubSamplesReuseOneAutosaveWorker() throws {
        let (_, store) = try makeFixture()
        defer { store.flushReviewAutosave() }
        var workers = Set<UUID>()
        for frame in 1...600 {
            store.seek(to: Double(frame) / 100, broadcast: false)
            workers.insert(try XCTUnwrap(store.scheduledReviewAutosaveID))
        }
        XCTAssertEqual(workers.count, 1, "A drag should extend one save deadline, not allocate a task per sample")
        XCTAssertEqual(store.playhead, 6)
    }

    func testMemoryOnlyDemoDoesNotScheduleDiskAutosave() {
        let store = ReplayStore()
        for frame in 1...600 { store.seek(to: Double(frame) / 100, broadcast: false) }
        XCTAssertNil(store.scheduledReviewAutosaveID)
        XCTAssertNil(store.autosavedReview)
    }

    func testExplicitFlushRetiresItsWorkerAndSavesTheLatestTime() throws {
        let (url, store) = try makeFixture()
        store.seek(to: 5, broadcast: false)
        XCTAssertNotNil(store.scheduledReviewAutosaveID)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertNil(store.scheduledReviewAutosaveID)
        XCTAssertEqual(ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url).autosavedReview?.state.playhead, 5)
    }

    func testNewEditExtendsSameDeadlineWithoutSavingEarly() async throws {
        let (url, store) = try makeFixture()
        defer { store.flushReviewAutosave() }
        store.seek(to: 5, broadcast: false)
        let worker = try XCTUnwrap(store.scheduledReviewAutosaveID)
        try await Task.sleep(for: .milliseconds(400))
        store.seek(to: 7, broadcast: false)
        XCTAssertEqual(store.scheduledReviewAutosaveID, worker)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(store.autosavedReview, "The first deadline must not save while the latest edit is still settling")
        XCTAssertEqual(store.scheduledReviewAutosaveID, worker)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertNil(store.scheduledReviewAutosaveID)
        XCTAssertEqual(ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url).autosavedReview?.state.playhead, 7)
    }

    func testRestoreRetiresOldWorkerAndNewEditsStillAutosave() async throws {
        let (url, store) = try makeFixture()
        defer { store.flushReviewAutosave() }
        store.seek(to: 5, broadcast: false)
        XCTAssertTrue(store.flushReviewAutosave())
        store.seek(to: 7, broadcast: false)
        let oldWorker = try XCTUnwrap(store.scheduledReviewAutosaveID)
        XCTAssertTrue(store.restoreAutosavedReview())
        let newWorker = try XCTUnwrap(store.scheduledReviewAutosaveID)
        XCTAssertNotEqual(oldWorker, newWorker)
        store.seek(to: 9, broadcast: false)
        XCTAssertEqual(store.scheduledReviewAutosaveID, newWorker)
        try await Task.sleep(for: .milliseconds(850))
        XCTAssertNil(store.scheduledReviewAutosaveID)
        XCTAssertEqual(ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url).autosavedReview?.state.playhead, 9)
    }

    func testFutureSchemaDoesNotScheduleWorkersOrOverwriteItsFile() throws {
        let (url, _) = try makeFixture()
        let original = Data("{\"version\":2}".utf8)
        try original.write(to: url)
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        XCTAssertTrue(library.isReadOnly)
        let store = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library)
        for frame in 1...600 { store.seek(to: Double(frame) / 100, broadcast: false) }
        XCTAssertNil(store.scheduledReviewAutosaveID)
        XCTAssertFalse(store.flushReviewAutosave())
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testPassivePlaybackDoesNotCreateSaveWorkers() throws {
        let (_, store) = try makeFixture()
        store.seek(to: 1, broadcast: false)
        store.setPlaying(true, broadcast: false)
        XCTAssertTrue(store.flushReviewAutosave())
        for _ in 0..<120 { store.advance(by: 0.05) }
        XCTAssertEqual(store.playhead, 7, accuracy: 0.000_001)
        XCTAssertNil(store.scheduledReviewAutosaveID)
    }

    func testSleepingWorkerDoesNotRetainTheStore() async throws {
        let (url, fixture) = try makeFixture()
        // Use a distinct Store so the fixture tuple doesn't retain the subject.
        var store: ReplayStore? = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: fixture.reviewLibrary)
        weak var weakStore = store
        store?.seek(to: 5, broadcast: false)
        await Task.yield()
        store = nil
        XCTAssertNil(weakStore)
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "A released Store must not write later")
    }

    private func makeFixture() throws -> (URL, ReplayStore) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayAutosaveScheduling-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        let url = directory.appendingPathComponent("reviews.json")
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        return (url, ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library))
    }
}
