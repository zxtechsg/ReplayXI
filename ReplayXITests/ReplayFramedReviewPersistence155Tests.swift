import XCTest
@testable import ReplayXI

@MainActor
final class ReplayFramedReviewPersistence155Tests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories { try FileManager.default.removeItem(at: directory) }
        temporaryDirectories.removeAll()
    }

    func testLegacyOnlyRemainsVersion1AndMatchesIndependentEncoder() throws {
        let url = try makeURL(), library = library(at: url)
        let legacy = mark(keyBearing: nil, hasKeys: true)
        let state = state(marks: [legacy])
        XCTAssertTrue(library.save(named: "Old keys", state: state, now: Date(timeIntervalSince1970: 1)))
        XCTAssertTrue(library.autosave(state, now: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(try version(at: url), 1)
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("bendBearingDegrees"))
        try assertIndependentEncoding(library, version: 1, at: url)
        let reopened = self.library(at: url)
        XCTAssertFalse(reopened.isReadOnly)
        XCTAssertEqual(reopened.savedReviews, library.savedReviews)
        XCTAssertEqual(reopened.autosavedReview?.state, state)
    }

    func testNamedFramedReviewKeepsVersion2AcrossCachedLegacyAutosavesThenDowngrades() throws {
        let url = try makeURL(), library = library(at: url)
        let framed = state(marks: [mark(baseBearing: -135)])
        XCTAssertTrue(library.save(named: "Framed", state: framed, now: Date(timeIntervalSince1970: 1)))
        let framedID = try XCTUnwrap(library.savedReviews.first?.id)
        XCTAssertEqual(try version(at: url), 2)
        library.resetPersistenceWorkForTesting()
        XCTAssertTrue(library.autosave(state(marks: [mark()]), now: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 1)
        XCTAssertEqual(library.persistenceWork.namedReviewEncoding.calls, 0)
        XCTAssertEqual(try version(at: url), 2)
        try assertIndependentEncoding(library, version: 2, at: url)
        XCTAssertEqual(self.library(at: url).savedReviews.first?.state, framed)
        XCTAssertTrue(library.delete(id: framedID))
        XCTAssertEqual(try version(at: url), 1)
        try assertIndependentEncoding(library, version: 1, at: url)
    }

    func testKeyframeOnlyAndOtherScenarioFramesUpgradeCachedAutosaveWithoutLosingFields() throws {
        let url = try makeURL(), library = library(at: url)
        let legacy = state(marks: [mark()])
        XCTAssertTrue(library.save(named: "Legacy", state: legacy, now: Date(timeIntervalSince1970: 1)))
        let keyed = mark(keyBearing: 175, hasKeys: true)
        XCTAssertNil(keyed.curve?.bendBearingDegrees)
        let framedState = state(marks: [], extraMarks: [DemoScenarios.all[1].id: [keyed]])
        library.resetPersistenceWorkForTesting()
        XCTAssertTrue(library.autosave(framedState, now: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(try version(at: url), 2)
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 1)
        XCTAssertEqual(library.persistenceWork.namedReviewEncoding.calls, 0)
        XCTAssertEqual(self.library(at: url).autosavedReview?.state, framedState)
        try assertIndependentEncoding(library, version: 2, at: url)
        library.resetPersistenceWorkForTesting()
        XCTAssertTrue(library.autosave(legacy, now: Date(timeIntervalSince1970: 3)))
        XCTAssertEqual(try version(at: url), 1)
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 1)
        try assertIndependentEncoding(library, version: 1, at: url)

        // The same scan must include keys of every named review, not just autosave.
        XCTAssertTrue(library.save(named: "Other scenario keys", state: framedState,
                                   now: Date(timeIntervalSince1970: 4)))
        XCTAssertEqual(try version(at: url), 2)
        XCTAssertEqual(self.library(at: url).savedReviews.first?.state, framedState)
    }

    func testReaderAcceptsBothKnownVersionsPreservesFieldsAndProtectsFutureDocument() throws {
        let framedState = state(marks: [mark(baseBearing: 120, keyBearing: -160, hasKeys: true)])
        let review = SavedReplayReview(id: UUID(), name: "Compatible", savedAt: Date(timeIntervalSince1970: 1),
                                      state: framedState)
        for schema in [1, 2] {
            let url = try makeURL()
            try encoded(Document(version: schema, savedReviews: [review], autosavedReview: nil)).write(to: url)
            let loaded = library(at: url)
            XCTAssertFalse(loaded.isReadOnly)
            XCTAssertEqual(loaded.savedReviews, [review], "Known frame fields must not be dropped even in a v1 envelope")
            XCTAssertTrue(loaded.rename(id: review.id, name: "Retained"))
            XCTAssertEqual(try version(at: url), 2)
            XCTAssertEqual(library(at: url).savedReviews.first?.state, framedState)
        }

        let futureURL = try makeURL()
        let future = Data("{\"version\":3,\"savedReviews\":\"future payload\",\"unknown\":true}".utf8)
        let backup = try encoded(Document(version: 1, savedReviews: [], autosavedReview: nil))
        try future.write(to: futureURL)
        try backup.write(to: futureURL.appendingPathExtension("backup"))
        let readonly = library(at: futureURL)
        XCTAssertTrue(readonly.isReadOnly)
        XCTAssertFalse(readonly.save(named: "No overwrite", state: framedState))
        XCTAssertFalse(readonly.autosave(framedState))
        XCTAssertEqual(try Data(contentsOf: futureURL), future)
        XCTAssertEqual(try Data(contentsOf: futureURL.appendingPathExtension("backup")), backup)
        XCTAssertEqual(readonly.persistenceWork.documentEncoding.calls, 0)
    }

    func testFailedUpgradeDoesNotCommitVersionCacheAndVersion2BackupRecoversFrames() throws {
        let url = try makeURL(), library = library(at: url)
        let legacy = state(marks: [mark()])
        let framed = state(marks: [mark(baseBearing: 90)])
        XCTAssertTrue(library.save(named: "Legacy", state: legacy, now: Date(timeIntervalSince1970: 1)))
        let original = try Data(contentsOf: url)
        let backupURL = url.appendingPathExtension("backup")
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: false)
        XCTAssertFalse(library.autosave(framed, now: Date(timeIntervalSince1970: 2)))
        XCTAssertNil(library.autosavedReview)
        XCTAssertEqual(try Data(contentsOf: url), original)
        try FileManager.default.removeItem(at: backupURL)
        library.resetPersistenceWorkForTesting()
        XCTAssertTrue(library.autosave(legacy, now: Date(timeIntervalSince1970: 3)))
        XCTAssertEqual(try version(at: url), 1)
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 1)
        XCTAssertTrue(library.autosave(framed, now: Date(timeIntervalSince1970: 4)))
        XCTAssertEqual(try version(at: url), 2)
        XCTAssertTrue(library.rename(id: try XCTUnwrap(library.savedReviews.first?.id), name: "Backup checkpoint"))
        let goodVersion2 = try Data(contentsOf: backupURL)
        XCTAssertEqual(try version(at: backupURL), 2)
        try Data("damaged".utf8).write(to: url)
        let recovered = self.library(at: url)
        XCTAssertFalse(recovered.isReadOnly)
        XCTAssertEqual(recovered.autosavedReview?.state, framed)
        XCTAssertEqual(try Data(contentsOf: url), goodVersion2)
    }

    func testMixedInteriorCollapseCannotReplaceValidDiskState() throws {
        let url = try makeURL(), library = library(at: url)
        XCTAssertTrue(library.autosave(state(marks: [mark()])))
        let original = try Data(contentsOf: url)
        var invalid = mark()
        invalid.keyframes = [
            .init(time: 1, mark: CoachMark(kind: .arc, start: .init(x: 0, z: 0), end: .init(x: 2, z: 0),
                                         curve: .init(bend: 1, lift: 0), label: "Old")),
            .init(time: 2, mark: CoachMark(kind: .arc, start: .init(x: 0, z: 0), end: .init(x: -2, z: 0),
                                         curve: .init(bend: 1, lift: 0, bendBearingDegrees: 90), label: "New"))
        ]
        XCTAssertFalse(invalid.hasSafeArcKeyframeIntervals)
        XCTAssertFalse(library.accepts(state(marks: [invalid])))
        XCTAssertFalse(library.autosave(state(marks: [invalid])))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testSpatialPreviewMasksSchemaUpgradeUntilCommitAndUndoRestoresLegacyVersion1() throws {
        let url = try makeURL(), library = library(at: url)
        let original = mark()
        XCTAssertNil(original.curve?.bendBearingDegrees)
        XCTAssertTrue(library.autosave(state(marks: [original])))
        let store = ReplayStore(scenarios: DemoScenarios.all, reviewLibrary: library)
        defer { store.flushReviewAutosave() }
        XCTAssertTrue(store.restoreAutosavedReview())
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(try version(at: url), 1)
        let newStart = PitchPoint(x: -3, z: 2), newEnd = PitchPoint(x: 5, z: 9)
        XCTAssertTrue(store.updateCoachMarkGeometry(id: original.id, start: newStart, end: newEnd, broadcast: false))
        XCTAssertNotNil(store.marks.first { $0.id == original.id }?.curve?.bendBearingDegrees)
        XCTAssertTrue(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(try version(at: url), 1)
        XCTAssertEqual(self.library(at: url).autosavedReview?.state.marks, [original])
        XCTAssertTrue(store.cancelCoachMarkGeometryPreview(id: original.id))
        XCTAssertEqual(store.marks, [original])
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(try version(at: url), 1)

        XCTAssertTrue(store.updateCoachMarkGeometry(id: original.id, start: newStart, end: newEnd, broadcast: false))
        let candidate = try XCTUnwrap(store.marks.first { $0.id == original.id })
        XCTAssertNotNil(candidate.curve?.bendBearingDegrees)
        XCTAssertTrue(store.commitCoachMarkGeometryPreview(id: original.id, start: newStart, end: newEnd))
        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(try version(at: url), 2)
        XCTAssertEqual(self.library(at: url).autosavedReview?.state.marks, [candidate])
        XCTAssertTrue(store.undoAnnotationEdit())
        XCTAssertEqual(store.marks, [original])
        XCTAssertTrue(store.flushReviewAutosave())
        XCTAssertEqual(try version(at: url), 1)
        XCTAssertEqual(self.library(at: url).autosavedReview?.state.marks, [original])
    }

    private struct Document: Codable {
        let version: Int
        let savedReviews: [SavedReplayReview]
        let autosavedReview: SavedReplayReview?
    }

    private func mark(baseBearing: Float? = nil, keyBearing: Float? = nil, hasKeys: Bool = false) -> CoachMark {
        var mark = CoachMark(kind: .arc, start: .init(x: 0, z: 0), end: .init(x: 4, z: 4),
                             curve: .init(bend: 2, lift: 1, rollDegrees: 20, bendBearingDegrees: baseBearing),
                             label: "155 saved arc")
        if hasKeys {
            mark.keyframes = [
                .init(time: 1, mark: mark),
                .init(time: 2, mark: CoachMark(kind: .arc, start: .init(x: 1, z: 1), end: .init(x: 6, z: 4),
                                             curve: .init(bend: 3, lift: 2, rollDegrees: 40, bendBearingDegrees: keyBearing),
                                             label: "Second key"))
            ]
        }
        return mark
    }

    private func state(marks: [CoachMark], extraMarks: [String: [CoachMark]] = [:]) -> SavedReplayState {
        let scenario = DemoScenarios.all[0]
        var allMarks = extraMarks
        allMarks[scenario.id] = marks
        return SavedReplayState(scenarioID: scenario.id, playhead: 1, playbackRate: 1,
                                viewMode: .tacticalTable, perspectiveID: scenario.defaultPerspectiveID,
                                showsLaneLens: false, shapeFocusStage: .problem, marksByScenario: allMarks)
    }

    private func library(at url: URL) -> ReplayReviewLibrary {
        ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
    }

    private func makeURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayFramedReview155-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent("reviews.json")
    }

    private func version(at url: URL) throws -> Int {
        struct Header: Decodable { let version: Int }
        return try JSONDecoder().decode(Header.self, from: Data(contentsOf: url)).version
    }

    private func encoded(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }

    private func assertIndependentEncoding(_ library: ReplayReviewLibrary, version: Int, at url: URL,
                                           file: StaticString = #filePath, line: UInt = #line) throws {
        let document = Document(version: version, savedReviews: library.savedReviews, autosavedReview: library.autosavedReview)
        XCTAssertEqual(try Data(contentsOf: url), try encoded(document), file: file, line: line)
    }
}
