import Dispatch
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayReviewPersistenceWorkTests: XCTestCase {
    private var directories: [URL] = []

    override func tearDownWithError() throws {
        for directory in directories { try FileManager.default.removeItem(at: directory) }
        directories.removeAll()
    }

    private struct FixtureDocument: Encodable {
        let version = 1
        let savedReviews: [SavedReplayReview]
        let autosavedReview: SavedReplayReview?
    }

    private struct Phase: Codable {
        let name: String
        let operations: Int
        let elapsedNanoseconds: UInt64
        let work: ReplayReviewLibrary.PersistenceWork
    }

    private struct Report: Codable {
        let initialFileBytes: Int
        let fileLimitBytes: Int
        let namedReviewCount: Int
        let currentAnnotationCount: Int
        let positionKeysPerAnnotation: Int
        let phases: [Phase]
        let qualification: String
    }

    func testNearCapacityKeyframeLibraryCapturesSynchronousStageBaseline() throws {
        let url = try temporaryURL()
        let initialBytes = try makeNearCapacityFixture(at: url)
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.catalogue, fileURL: url)
        XCTAssertFalse(library.isReadOnly)
        let initial = try XCTUnwrap(library.autosavedReview?.state)
        XCTAssertEqual(initial.marks.count, ReplayStore.maximumSharedCoachMarks)
        XCTAssertTrue(initial.marks.allSatisfy { $0.keyframes?.count == CoachMark.maximumKeyframes })
        XCTAssertGreaterThan(initialBytes.count, ReplayReviewLibrary.maximumFileBytes * 95 / 100)
        XCTAssertLessThan(initialBytes.count, ReplayReviewLibrary.maximumFileBytes)
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_100)
        var phases: [Phase] = []

        library.resetPersistenceWorkForTesting()
        let unchangedStarted = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<5 {
            // Match the Store's committed snapshot: a fresh annotation array
            // whose immutable keyframe buffers may still share storage.
            let snapshot = replacing(initial, playhead: initial.playhead, marks: initial.marks.map { $0 })
            XCTAssertTrue(library.autosave(snapshot, now: fixedNow))
        }
        phases.append(Phase(name: "five_unchanged_autosaves", operations: 5,
                            elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds &- unchangedStarted,
                            work: library.persistenceWork))
        XCTAssertEqual(library.persistenceWork.unchangedAutosaveSkips, 5)
        XCTAssertEqual(library.persistenceWork.stateValidation.calls, 0,
                       "Previously accepted equal snapshots need no second validation")
        XCTAssertEqual(library.persistenceWork.documentEncoding.calls, 0)
        XCTAssertEqual(library.persistenceWork.backupWrite.calls, 0)
        XCTAssertEqual(library.persistenceWork.primaryWrite.calls, 0)
        XCTAssertEqual(try Data(contentsOf: url), initialBytes)

        let advanced = replacing(initial, playhead: 1)
        library.resetPersistenceWorkForTesting()
        let advanceStarted = DispatchTime.now().uptimeNanoseconds
        XCTAssertTrue(library.autosave(advanced, now: fixedNow))
        phases.append(Phase(name: "playhead_only_change", operations: 1,
                            elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds &- advanceStarted,
                            work: library.persistenceWork))
        let advancedBytes = try Data(contentsOf: url)
        assertOneWrite(library.persistenceWork, previousBytes: initialBytes.count, currentBytes: advancedBytes.count)
        XCTAssertEqual(library.persistenceWork.namedReviewEncoding.calls, 1,
                       "First save after load still encodes the retained reviews")
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 0)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("backup")), initialBytes)

        var changedMarks = advanced.marks
        let original = try XCTUnwrap(changedMarks.first)
        let frame = try XCTUnwrap(original.keyframes?[32])
        let replacement = CoachMark(kind: .arc, start: frame.start, end: frame.end,
                                    startElevation: frame.startElevation, endElevation: frame.endElevation,
                                    curve: .init(bend: 3, lift: 1, rollDegrees: 20), label: original.label)
        changedMarks[0].keyframes?[32] = .init(time: frame.time, mark: replacement)
        let edited = replacing(advanced, playhead: advanced.playhead, marks: changedMarks)
        library.resetPersistenceWorkForTesting()
        let editStarted = DispatchTime.now().uptimeNanoseconds
        XCTAssertTrue(library.autosave(edited, now: fixedNow.addingTimeInterval(1)))
        phases.append(Phase(name: "single_position_key_change", operations: 1,
                            elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds &- editStarted,
                            work: library.persistenceWork))
        let editedBytes = try Data(contentsOf: url)
        assertOneWrite(library.persistenceWork, previousBytes: advancedBytes.count, currentBytes: editedBytes.count)
        XCTAssertEqual(library.persistenceWork.namedReviewEncoding.calls, 0)
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 1)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("backup")), advancedBytes)
        let finalState = replacing(edited, playhead: 2)
        library.resetPersistenceWorkForTesting()
        let warmStarted = DispatchTime.now().uptimeNanoseconds
        XCTAssertTrue(library.autosave(finalState, now: fixedNow.addingTimeInterval(2)))
        phases.append(Phase(name: "cached_playhead_only_change", operations: 1,
                            elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds &- warmStarted,
                            work: library.persistenceWork))
        let finalBytes = try Data(contentsOf: url)
        assertOneWrite(library.persistenceWork, previousBytes: editedBytes.count, currentBytes: finalBytes.count)
        XCTAssertEqual(library.persistenceWork.namedReviewEncoding.calls, 0)
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 1)
        XCTAssertGreaterThan(library.persistenceWork.reusedNamedReviewBytes, 6 * 1_024 * 1_024)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("backup")), editedBytes)
        try assertIndependentEncoding(library, at: url)
        let reopened = ReplayReviewLibrary(scenarios: DemoScenarios.catalogue, fileURL: url)
        XCTAssertEqual(reopened.autosavedReview?.state, finalState)
        XCTAssertEqual(reopened.savedReviews, library.savedReviews)

        let report = Report(initialFileBytes: initialBytes.count,
                            fileLimitBytes: ReplayReviewLibrary.maximumFileBytes,
                            namedReviewCount: library.savedReviews.count,
                            currentAnnotationCount: initial.marks.count,
                            positionKeysPerAnnotation: CoachMark.maximumKeyframes,
                            phases: phases,
                            qualification: "DEBUG simulator synchronous elapsed time with instrumentation; not CPU time, allocation bytes, device latency or headset FPS. No timing threshold. Fixture generation/load/reopen and validation assertions are not persistence-stage measurements. Atomic file payload byte counts are successful writes, not physical storage traffic.")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Cycle136-NearCapacity-PersistenceWork.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFailedBackupIsCountedAndCannotAdvancePrimaryOrMemory() throws {
        let url = try temporaryURL()
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.catalogue, fileURL: url)
        let state = ReplayStore().makeSavedReviewState()
        XCTAssertTrue(library.autosave(state))
        let original = try Data(contentsOf: url)
        // A directory at the exact backup target forces a real atomic-write
        // failure without changing permissions or mocking persistence order.
        try FileManager.default.createDirectory(at: url.appendingPathExtension("backup"), withIntermediateDirectories: false)
        library.resetPersistenceWorkForTesting()
        XCTAssertFalse(library.autosave(replacing(state, playhead: 1)))
        XCTAssertEqual(library.persistenceWork.stateValidation.calls, 1)
        XCTAssertEqual(library.persistenceWork.documentEncoding.succeeded, 1)
        XCTAssertEqual(library.persistenceWork.backupWrite.calls, 1)
        XCTAssertEqual(library.persistenceWork.backupWrite.succeeded, 0)
        XCTAssertEqual(library.persistenceWork.backupWrite.bytes, 0)
        XCTAssertEqual(library.persistenceWork.primaryWrite.calls, 0)
        XCTAssertEqual(library.autosavedReview?.state, state)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(library.status, "Save failed. Check device storage.")
    }

    func testRejectedStateDoesNotEncodeOrWrite() throws {
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.catalogue, fileURL: try temporaryURL())
        let invalid = replacing(ReplayStore().makeSavedReviewState(), playhead: .nan)
        library.resetPersistenceWorkForTesting()
        XCTAssertFalse(library.autosave(invalid))
        XCTAssertEqual(library.persistenceWork.stateValidation.calls, 1)
        XCTAssertEqual(library.persistenceWork.stateValidation.succeeded, 0)
        XCTAssertEqual(library.persistenceWork.documentEncoding.calls, 0)
        XCTAssertEqual(library.persistenceWork.backupWrite.calls, 0)
        XCTAssertEqual(library.persistenceWork.primaryWrite.calls, 0)
    }

    func testCachedFragmentsMatchIndependentEncoderForOptionalUnicodeAndReviewMutations() throws {
        let url = try temporaryURL()
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.catalogue, fileURL: url)
        let base = ReplayStore().makeSavedReviewState()
        let mark = CoachMark(kind: .arc, start: .init(x: -2.75, z: 3.125), end: .init(x: 4, z: 7.5),
                             curve: .init(bend: 2.25, lift: 1.5, rollDegrees: -30),
                             label: "Pass / \"left\" \\ 🏟️")
        let state = replacing(base, playhead: 0, marks: [mark.recordingPose(at: 0)])
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for name in ["Équipe / \"A\" \\ ⚽", "Same date", "同時刻"] {
            XCTAssertTrue(library.save(named: name, state: state, now: now))
            XCTAssertNil(library.autosavedReview)
            try assertIndependentEncoding(library, at: url)
            let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            XCTAssertNil(dictionary["autosavedReview"], "Synthesised Codable omits nil, rather than writing null")
        }
        XCTAssertEqual(library.savedReviews.map(\.name), ["同時刻", "Same date", "Équipe / \"A\" \\ ⚽"])
        library.resetPersistenceWorkForTesting()
        XCTAssertTrue(library.autosave(state, now: now))
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 1)
        try assertIndependentEncoding(library, at: url)

        let id = try XCTUnwrap(library.savedReviews.first?.id)
        library.resetPersistenceWorkForTesting()
        XCTAssertTrue(library.rename(id: id, name: "Renamed / \"é\" ⚽"))
        XCTAssertEqual(library.persistenceWork.namedReviewEncoding.calls, 1)
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 0)
        try assertIndependentEncoding(library, at: url)
        library.resetPersistenceWorkForTesting()
        XCTAssertTrue(library.autosave(replacing(state, playhead: 1), now: now))
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 1)
        try assertIndependentEncoding(library, at: url)
        library.resetPersistenceWorkForTesting()
        XCTAssertTrue(library.delete(id: id))
        XCTAssertEqual(library.persistenceWork.namedReviewEncoding.calls, 1)
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 0)
        try assertIndependentEncoding(library, at: url)
    }

    func testCacheDoesNotAssumeInsertionOrderMatchesSortedReviewOrder() throws {
        let url = try temporaryURL()
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.catalogue, fileURL: url)
        let state = ReplayStore().makeSavedReviewState()
        XCTAssertTrue(library.save(named: "Newer", state: state, now: Date(timeIntervalSince1970: 200)))
        let newer = try XCTUnwrap(library.savedReviews.first)
        XCTAssertTrue(library.save(named: "Older", state: state, now: Date(timeIntervalSince1970: 100)))
        let older = try XCTUnwrap(library.savedReviews.first { $0.name == "Older" })
        XCTAssertEqual(library.savedReviews.map(\.id), [newer.id, older.id])
        // Preserve the existing transaction bytes: save prepends; adoption
        // sorts memory. A following autosave must notice the changed order.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try Data(contentsOf: url), try encoder.encode(
            FixtureDocument(savedReviews: [older, newer], autosavedReview: nil)))
        library.resetPersistenceWorkForTesting()
        XCTAssertTrue(library.autosave(state))
        XCTAssertEqual(library.persistenceWork.namedReviewEncoding.calls, 1)
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 0)
        try assertIndependentEncoding(library, at: url)
        library.resetPersistenceWorkForTesting()
        XCTAssertTrue(library.autosave(replacing(state, playhead: 1)))
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 1)
        try assertIndependentEncoding(library, at: url)
    }

    func testFailedBackupOrPrimaryDoesNotAdoptCandidateNamedReviewCache() throws {
        for failsBackup in [true, false] {
            let url = try temporaryURL()
            let library = ReplayReviewLibrary(scenarios: DemoScenarios.catalogue, fileURL: url)
            let state = ReplayStore().makeSavedReviewState()
            XCTAssertTrue(library.save(named: "Original", state: state))
            XCTAssertTrue(library.autosave(state))
            let originalBytes = try Data(contentsOf: url)
            let originalReviews = library.savedReviews
            let target = failsBackup ? url.appendingPathExtension("backup") : url
            let heldFile = target.appendingPathExtension("held")
            try FileManager.default.moveItem(at: target, to: heldFile)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            library.resetPersistenceWorkForTesting()
            XCTAssertFalse(library.rename(id: try XCTUnwrap(originalReviews.first?.id),
                                          name: "Changed candidate that must not enter the cache"))
            XCTAssertEqual(library.persistenceWork.namedReviewEncoding.calls, 1)
            XCTAssertEqual(library.persistenceWork.backupWrite.calls, 1)
            XCTAssertEqual(library.persistenceWork.backupWrite.succeeded, failsBackup ? 0 : 1)
            XCTAssertEqual(library.persistenceWork.primaryWrite.calls, failsBackup ? 0 : 1)
            XCTAssertEqual(library.persistenceWork.primaryWrite.succeeded, 0)
            XCTAssertEqual(library.savedReviews, originalReviews)
            XCTAssertEqual(library.autosavedReview?.state, state)
            XCTAssertEqual(library.status, "Save failed. Check device storage.")
            XCTAssertEqual(try Data(contentsOf: failsBackup ? url : heldFile), originalBytes)
            try FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: heldFile, to: target)
            library.resetPersistenceWorkForTesting()
            XCTAssertTrue(library.autosave(replacing(state, playhead: 1)))
            XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 1,
                           "Failed write must retain the old lastGoodData range and source reviews")
            XCTAssertEqual(library.persistenceWork.namedReviewEncoding.calls, 0)
            XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("backup")), originalBytes)
            try assertIndependentEncoding(library, at: url)
        }
    }

    func testEqualStateStillRejectsNonfiniteDateAndChangedInvalidKey() throws {
        let url = try temporaryURL()
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.catalogue, fileURL: url)
        let mark = CoachMark(kind: .arc, start: .zero, end: .init(x: 4, z: 8),
                             curve: .init(bend: 2, lift: 1), label: "Valid").recordingPose(at: 0)
        let state = replacing(ReplayStore().makeSavedReviewState(), playhead: 0, marks: [mark])
        XCTAssertTrue(library.autosave(state))
        let bytes = try Data(contentsOf: url)
        for time in [Double.nan, Double.infinity, -Double.infinity] {
            library.resetPersistenceWorkForTesting()
            XCTAssertFalse(library.autosave(state, now: Date(timeIntervalSince1970: time)))
            XCTAssertEqual(library.persistenceWork.unchangedAutosaveSkips, 0)
            XCTAssertEqual(library.persistenceWork.documentEncoding.calls, 0)
            XCTAssertEqual(library.status, "Autosave could not be completed")
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
        var invalid = mark
        invalid.keyframes?[0].time = -1
        library.resetPersistenceWorkForTesting()
        XCTAssertFalse(library.autosave(replacing(state, playhead: 0, marks: [invalid])))
        XCTAssertEqual(library.persistenceWork.stateValidation.calls, 1)
        XCTAssertEqual(library.persistenceWork.stateValidation.succeeded, 0)
        XCTAssertEqual(library.persistenceWork.documentEncoding.calls, 0)
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 0)
        XCTAssertEqual(library.autosavedReview?.state, state)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testFutureSchemaStaysReadOnlyAndDoesNotPrimeEncodingCache() throws {
        let url = try temporaryURL()
        let bytes = Data("{\"version\":4,\"unknown\":true}".utf8)
        try bytes.write(to: url, options: .atomic)
        let library = ReplayReviewLibrary(scenarios: DemoScenarios.catalogue, fileURL: url)
        let state = ReplayStore().makeSavedReviewState()
        library.resetPersistenceWorkForTesting()
        XCTAssertTrue(library.isReadOnly)
        XCTAssertFalse(library.autosave(state))
        XCTAssertFalse(library.save(named: "Cannot replace newer document", state: state))
        XCTAssertEqual(library.persistenceWork.documentEncoding.calls, 0)
        XCTAssertEqual(library.persistenceWork.namedReviewFragmentReuses, 0)
        XCTAssertEqual(library.persistenceWork.backupWrite.calls, 0)
        XCTAssertEqual(library.persistenceWork.primaryWrite.calls, 0)
        XCTAssertEqual(library.status, "Saves need a newer app version")
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    private func assertIndependentEncoding(_ library: ReplayReviewLibrary, at url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let independent = try encoder.encode(FixtureDocument(savedReviews: library.savedReviews,
                                                              autosavedReview: library.autosavedReview))
        XCTAssertEqual(try Data(contentsOf: url), independent,
                       "Fragment assembly must remain byte-identical to ordinary schema-v1 JSONEncoder")
    }

    private func assertOneWrite(_ work: ReplayReviewLibrary.PersistenceWork, previousBytes: Int, currentBytes: Int) {
        XCTAssertEqual(work.stateValidation.calls, 1)
        XCTAssertEqual(work.stateValidation.succeeded, 1)
        XCTAssertEqual(work.documentEncoding.calls, 1)
        XCTAssertEqual(work.documentEncoding.succeeded, 1)
        XCTAssertEqual(work.documentEncoding.bytes, currentBytes)
        XCTAssertEqual(work.backupWrite.calls, 1)
        XCTAssertEqual(work.backupWrite.succeeded, 1)
        XCTAssertEqual(work.backupWrite.bytes, previousBytes)
        XCTAssertEqual(work.primaryWrite.calls, 1)
        XCTAssertEqual(work.primaryWrite.succeeded, 1)
        XCTAssertEqual(work.primaryWrite.bytes, currentBytes)
    }

    private func temporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayPersistenceWork-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directories.append(directory)
        return directory.appendingPathComponent("reviews.json")
    }

    private func makeNearCapacityFixture(at url: URL) throws -> Data {
        let store = ReplayStore()
        let base = store.makeSavedReviewState()
        let prototype = CoachMark(kind: .arc, start: .init(x: 0, z: 0), end: .init(x: 8, z: 10),
                                  curve: .init(bend: 2, lift: 1), label: "Keyframe-heavy saved run")
        let frames = (0..<CoachMark.maximumKeyframes).map {
            CoachMarkKeyframe(time: Double($0) * store.selectedScenario.duration / 63, mark: prototype)
        }
        let marks = (0..<ReplayStore.maximumSharedCoachMarks).map { _ in
            CoachMark(kind: .arc, start: prototype.start, end: prototype.end,
                      curve: prototype.curve, label: prototype.label, keyframes: frames)
        }
        let heavy = replacing(base, playhead: 0, marks: marks)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let autosave = SavedReplayReview(id: UUID(), name: "Last session", savedAt: now, state: heavy)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let targetBytes = ReplayReviewLibrary.maximumFileBytes * 96 / 100
        var reviews: [SavedReplayReview] = []
        var data = try encoder.encode(FixtureDocument(savedReviews: reviews, autosavedReview: autosave))
        while reviews.count < ReplayReviewLibrary.maximumSavedReviews - 1 {
            let review = SavedReplayReview(id: UUID(), name: "Retained keyed review", savedAt: now, state: heavy)
            let candidate = try encoder.encode(FixtureDocument(savedReviews: reviews + [review], autosavedReview: autosave))
            guard candidate.count <= targetBytes else { break }
            reviews.append(review)
            data = candidate
        }
        // Fill the remaining space with a bounded partial review, avoiding a
        // size assumption tied to today's Float/JSON formatting or clip length.
        let partialID = UUID()
        var low = 0, high = marks.count
        while low <= high {
            let count = (low + high) / 2
            let partial = SavedReplayReview(id: partialID, name: "Partial keyed review", savedAt: now,
                                           state: replacing(heavy, playhead: 0, marks: Array(marks.prefix(count))))
            let candidate = try encoder.encode(FixtureDocument(savedReviews: reviews + [partial], autosavedReview: autosave))
            if candidate.count <= targetBytes { data = candidate; low = count + 1 }
            else { high = count - 1 }
        }
        try data.write(to: url, options: .atomic)
        return data
    }

    private func replacing(_ state: SavedReplayState, playhead: TimeInterval, marks: [CoachMark]? = nil) -> SavedReplayState {
        var scenarios = state.marksByScenario
        if let marks { scenarios[state.scenarioID] = marks }
        return SavedReplayState(scenarioID: state.scenarioID, playhead: playhead,
                                playbackRate: state.playbackRate, viewMode: state.viewMode,
                                perspectiveID: state.perspectiveID, showsLaneLens: state.showsLaneLens,
                                shapeFocusStage: state.shapeFocusStage, marksByScenario: scenarios)
    }
}
