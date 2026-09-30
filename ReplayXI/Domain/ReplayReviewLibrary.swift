import Foundation
import Observation
#if DEBUG
import Dispatch
#endif

/// Local replay data only. Room identities, anchors, consent, in-progress
/// gestures and playback-running flags have no representation in this format.
struct SavedReplayState: Codable, Equatable, Sendable {
    let scenarioID: String
    let playhead: TimeInterval
    let playbackRate: Double
    let viewMode: ReplayViewMode
    let perspectiveID: String
    let showsLaneLens: Bool
    let shapeFocusStage: ShapeFocusStage
    let marksByScenario: [String: [CoachMark]]

    var marks: [CoachMark] { marksByScenario[scenarioID] ?? [] }
}

struct SavedReplayReview: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    let savedAt: Date
    let state: SavedReplayState
}

/// One bounded, atomically replaced document, with its previous valid version
/// retained for recovery. An unknown newer schema is kept read-only.
@MainActor
@Observable
final class ReplayReviewLibrary {
    static let maximumSavedReviews = 40
    static let maximumNameLength = 60
    static let maximumFileBytes = 8 * 1_024 * 1_024

    private(set) var savedReviews: [SavedReplayReview] = []
    private(set) var autosavedReview: SavedReplayReview?
    private(set) var status = "Saved on this device"
    private(set) var isReadOnly = false

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let scenarios: [ReplayScenario]
    @ObservationIgnored private var lastGoodData: Data?
    @ObservationIgnored private var namedReviewEncodingCache: NamedReviewEncodingCache?
    var usesDisk: Bool { fileURL != nil }

    #if DEBUG
    /// Instrumented synchronous stage time, not CPU time or a frame-rate
    /// guarantee. Byte counts include only successfully encoded/written data.
    struct StageWork: Codable, Equatable {
        var calls = 0
        var succeeded = 0
        var bytes = 0
        var elapsedNanoseconds: UInt64 = 0
    }

    struct PersistenceWork: Codable, Equatable {
        var stateValidation = StageWork()
        var documentEncoding = StageWork()
        var backupWrite = StageWork()
        var primaryWrite = StageWork()
        var unchangedAutosaveSkips = 0
        var namedReviewEncoding = StageWork()
        var namedReviewFragmentReuses = 0
        var reusedNamedReviewBytes = 0
    }

    @ObservationIgnored private(set) var persistenceWork = PersistenceWork()

    func resetPersistenceWorkForTesting() { persistenceWork = PersistenceWork() }
    #endif

    private struct Document: Codable {
        let version: Int
        let savedReviews: [SavedReplayReview]
        let autosavedReview: SavedReplayReview?
    }

    /// The fragment lives inside lastGoodData, already retained for recovery.
    /// Keeping a byte range avoids another near-8-MiB resident JSON buffer.
    /// It is installed only after the corresponding primary write succeeds.
    private struct NamedReviewEncodingCache {
        let reviews: [SavedReplayReview]
        let range: Range<Int>
        let hasFramedCurves: Bool
    }

    private struct EncodedDocument {
        let data: Data
        let namedReviewRange: Range<Int>
    }

    private enum LibraryError: Error {
        case invalidDocument
        case newerVersion
    }

    /// Nil means memory-only. Tests must provide their own temporary URL when
    /// exercising disk persistence; the app alone opts into Application Support.
    init(scenarios: [ReplayScenario], fileURL: URL? = nil) {
        self.scenarios = scenarios
        self.fileURL = fileURL
        if fileURL == nil { status = "Demo session" }
        load()
    }

    static func persistent(scenarios: [ReplayScenario]) -> ReplayReviewLibrary {
        let directory = URL.applicationSupportDirectory
            .appendingPathComponent("ReplayXI", isDirectory: true)
        return ReplayReviewLibrary(
            scenarios: scenarios,
            fileURL: directory.appendingPathComponent("reviews-v1.json")
        )
    }

    func accepts(_ state: SavedReplayState) -> Bool {
        #if DEBUG
        let started = DispatchTime.now().uptimeNanoseconds
        persistenceWork.stateValidation.calls &+= 1
        defer {
            persistenceWork.stateValidation.elapsedNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- started
        }
        #endif
        let accepted = validateState(state)
        #if DEBUG
        if accepted { persistenceWork.stateValidation.succeeded &+= 1 }
        #endif
        return accepted
    }

    private func validateState(_ state: SavedReplayState) -> Bool {
        guard let scenario = scenarios.first(where: { $0.id == state.scenarioID }),
              state.playhead.isFinite,
              (0...scenario.duration).contains(state.playhead),
              state.playbackRate.isFinite,
              (0.25...4).contains(state.playbackRate),
              scenario.player(id: state.perspectiveID) != nil,
              state.marksByScenario[state.scenarioID] != nil,
              state.marksByScenario.count <= scenarios.count else { return false }
        return state.marksByScenario.allSatisfy { id, marks in
            guard let scenario = scenarios.first(where: { $0.id == id }),
                  marks.count <= ReplayStore.maximumSharedCoachMarks,
                  Set(marks.map(\.id)).count == marks.count else { return false }
            return marks.allSatisfy { ReplayStore.isValidReviewMark($0, for: scenario) }
        }
    }

    @discardableResult
    func save(named name: String, state: SavedReplayState, now: Date = .now) -> Bool {
        guard let name = Self.validName(name), accepts(state), now.timeIntervalSince1970.isFinite else {
            status = "Review could not be saved"
            return false
        }
        guard savedReviews.count < Self.maximumSavedReviews else {
            status = "40 saves reached. Delete a save first."
            return false
        }
        let review = SavedReplayReview(id: UUID(), name: name, savedAt: now, state: state)
        return persist(reviews: [review] + savedReviews, autosave: autosavedReview, message: "Review saved")
    }

    @discardableResult
    func autosave(_ state: SavedReplayState, now: Date = .now) -> Bool {
        guard now.timeIntervalSince1970.isFinite else {
            status = "Autosave could not be completed"
            return false
        }
        // Equality with the private, previously accepted state cannot admit a
        // new malformed value. Keep the date guard before this no-op path.
        guard autosavedReview?.state != state else {
            #if DEBUG
            persistenceWork.unchangedAutosaveSkips &+= 1
            #endif
            return true
        }
        guard accepts(state) else {
            status = "Autosave could not be completed"
            return false
        }
        let review = SavedReplayReview(
            id: autosavedReview?.id ?? UUID(), name: "Last session", savedAt: now, state: state
        )
        return persist(reviews: savedReviews, autosave: review, message: "Session saved")
    }

    @discardableResult
    func rename(id: UUID, name: String) -> Bool {
        guard let name = Self.validName(name) else {
            status = "Use 1–60 characters without line breaks"
            return false
        }
        guard let index = savedReviews.firstIndex(where: { $0.id == id }) else {
            status = "This saved review is no longer available"
            return false
        }
        var reviews = savedReviews
        reviews[index].name = name
        return persist(reviews: reviews, autosave: autosavedReview, message: "Review renamed")
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        guard savedReviews.contains(where: { $0.id == id }) else { return false }
        return persist(
            reviews: savedReviews.filter { $0.id != id },
            autosave: autosavedReview,
            message: "Review deleted"
        )
    }

    /// Shared by inline editing and persistence: do not silently truncate a
    /// pasted name or enable a Save button for input the library will reject.
    static func nameValidationMessage(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Enter a review name." }
        if name.count > maximumNameLength { return "Use \(maximumNameLength) characters or fewer." }
        if name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            return "Remove line breaks and control characters."
        }
        return nil
    }

    private static func validName(_ raw: String) -> String? {
        guard nameValidationMessage(raw) == nil else { return nil }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decode(_ data: Data) throws -> Document {
        guard data.count <= Self.maximumFileBytes else { throw LibraryError.invalidDocument }
        // Read the version before decoding payloads that a future schema may
        // change. A downgrade must never erase a newer app's saves.
        struct Header: Decodable { let version: Int }
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        guard header.version <= 2 else { throw LibraryError.newerVersion }
        guard header.version == 1 || header.version == 2 else { throw LibraryError.invalidDocument }
        let document = try decoder.decode(Document.self, from: data)
        let reviews = document.savedReviews + (document.autosavedReview.map { [$0] } ?? [])
        guard document.savedReviews.count <= Self.maximumSavedReviews,
              Set(document.savedReviews.map(\.id)).count == document.savedReviews.count,
              reviews.allSatisfy({
                  Self.validName($0.name) != nil
                      && $0.savedAt.timeIntervalSince1970.isFinite
                      && accepts($0.state)
              }) else { throw LibraryError.invalidDocument }
        return document
    }

    private func read(_ url: URL) throws -> (Document, Data) {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maximumFileBytes else { throw LibraryError.invalidDocument }
        let data = try Data(contentsOf: url)
        return (try decode(data), data)
    }

    private func load() {
        guard let fileURL else { return }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let backupURL = fileURL.appendingPathExtension("backup")
            guard FileManager.default.fileExists(atPath: backupURL.path) else { return }
            do {
                let (document, data) = try read(backupURL)
                try data.write(to: fileURL, options: .atomic)
                adopt(document, data: data)
                status = "Recovered the previous save"
            } catch LibraryError.newerVersion {
                isReadOnly = true
                status = "Saves need a newer app version"
            } catch {
                isReadOnly = true
                status = "Saves could not be opened"
            }
            return
        }
        do {
            let (document, data) = try read(fileURL)
            adopt(document, data: data)
        } catch LibraryError.newerVersion {
            isReadOnly = true
            status = "Saves need a newer app version"
        } catch is DecodingError {
            recoverDamagedPrimary(fileURL)
        } catch LibraryError.invalidDocument {
            recoverDamagedPrimary(fileURL)
        } catch {
            // Permission, file-protection and other I/O errors do not prove
            // corruption. Keep the primary in place and block writes so an
            // older backup cannot silently replace a merely unreadable review.
            isReadOnly = true
            status = "Saves could not be read. Try reopening the app."
        }
    }

    private func recoverDamagedPrimary(_ fileURL: URL) {
        do {
            let quarantine = fileURL.deletingLastPathComponent()
                .appendingPathComponent("reviews-damaged-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: fileURL, to: quarantine)
            let backupURL = fileURL.appendingPathExtension("backup")
            guard FileManager.default.fileExists(atPath: backupURL.path) else {
                status = "Damaged save kept aside. A new library is ready."
                return
            }
            let (document, data) = try read(backupURL)
            try data.write(to: fileURL, options: .atomic)
            adopt(document, data: data)
            status = "Recovered the previous save"
        } catch LibraryError.newerVersion {
            isReadOnly = true
            status = "Saves need a newer app version"
        } catch {
            isReadOnly = true
            status = "Saves could not be opened"
        }
    }

    private func adopt(_ document: Document, data: Data) {
        savedReviews = document.savedReviews.sorted { $0.savedAt > $1.savedAt }
        autosavedReview = document.autosavedReview
        lastGoodData = data
        namedReviewEncodingCache = nil
    }

    private func persist(reviews: [SavedReplayReview], autosave: SavedReplayReview?, message: String) -> Bool {
        guard !isReadOnly else { return false }
        let namedHasFrames: Bool
        if let cache = namedReviewEncodingCache, cache.reviews == reviews {
            namedHasFrames = cache.hasFramedCurves
        } else {
            namedHasFrames = reviews.contains { Self.hasFramedCurves(in: $0.state) }
        }
        let needsVersion2 = namedHasFrames || autosave.map { Self.hasFramedCurves(in: $0.state) } == true
        let document = Document(version: needsVersion2 ? 2 : 1, savedReviews: reviews, autosavedReview: autosave)
        do {
            let encoded = try encode(document)
            let data = encoded.data
            guard data.count <= Self.maximumFileBytes else {
                // This is the app's bounded library, not proof that the device
                // is out of disk space. Never replace the last valid document.
                status = "Review library full. Delete a saved review or reduce annotations."
                return false
            }
            if let fileURL {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                if let lastGoodData {
                    try writePersistedData(lastGoodData, to: fileURL.appendingPathExtension("backup"), isBackup: true)
                }
                try writePersistedData(data, to: fileURL, isBackup: false)
            }
            adopt(document, data: data)
            namedReviewEncodingCache = NamedReviewEncodingCache(
                reviews: document.savedReviews, range: encoded.namedReviewRange, hasFramedCurves: namedHasFrames
            )
            status = message
            return true
        } catch {
            status = "Save failed. Check device storage."
            return false
        }
    }

    private static func hasFramedCurves(in state: SavedReplayState) -> Bool {
        state.marksByScenario.values.contains { marks in
            marks.contains { mark in
                mark.curve?.bendBearingDegrees != nil
                    || mark.keyframes?.contains { $0.curve?.bendBearingDegrees != nil } == true
            }
        }
    }

    private func encode(_ document: Document) throws -> EncodedDocument {
        #if DEBUG
        let started = DispatchTime.now().uptimeNanoseconds
        persistenceWork.documentEncoding.calls &+= 1
        defer {
            persistenceWork.documentEncoding.elapsedNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- started
        }
        #endif
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let namedReviews: Data
        if let cache = namedReviewEncodingCache, let lastGoodData,
           cache.reviews == document.savedReviews,
           cache.range.lowerBound >= 0, cache.range.upperBound <= lastGoodData.count {
            namedReviews = lastGoodData[cache.range]
            #if DEBUG
            persistenceWork.namedReviewFragmentReuses &+= 1
            persistenceWork.reusedNamedReviewBytes &+= namedReviews.count
            #endif
        } else {
            namedReviews = try encodeNamedReviews(document.savedReviews, using: encoder)
        }
        let autosave = try document.autosavedReview.map { try encoder.encode($0) }
        var data = Data()
        data.reserveCapacity(namedReviews.count + (autosave?.count ?? 0) + 64)
        // Shared schema-v1/v2 field names in JSONEncoder.sortedKeys order. Every
        // dynamic value is an independently encoded JSON fragment; strings,
        // escaping, Float/Date formats and nested key ordering stay native.
        data.append(contentsOf: "{".utf8)
        if let autosave {
            data.append(contentsOf: "\"autosavedReview\":".utf8)
            data.append(autosave)
            data.append(contentsOf: ",".utf8)
        }
        data.append(contentsOf: "\"savedReviews\":".utf8)
        let start = data.count
        data.append(namedReviews)
        let end = data.count
        data.append(contentsOf: ",\"version\":".utf8)
        data.append(contentsOf: String(document.version).utf8)
        data.append(contentsOf: "}".utf8)
        #if DEBUG
        persistenceWork.documentEncoding.succeeded &+= 1
        persistenceWork.documentEncoding.bytes &+= data.count
        #endif
        return EncodedDocument(data: data, namedReviewRange: start..<end)
    }

    private func encodeNamedReviews(_ reviews: [SavedReplayReview], using encoder: JSONEncoder) throws -> Data {
        #if DEBUG
        let started = DispatchTime.now().uptimeNanoseconds
        persistenceWork.namedReviewEncoding.calls &+= 1
        defer {
            persistenceWork.namedReviewEncoding.elapsedNanoseconds &+= DispatchTime.now().uptimeNanoseconds &- started
        }
        #endif
        let data = try encoder.encode(reviews)
        #if DEBUG
        persistenceWork.namedReviewEncoding.succeeded &+= 1
        persistenceWork.namedReviewEncoding.bytes &+= data.count
        #endif
        return data
    }

    private func writePersistedData(_ data: Data, to url: URL, isBackup: Bool) throws {
        #if DEBUG
        let started = DispatchTime.now().uptimeNanoseconds
        if isBackup { persistenceWork.backupWrite.calls &+= 1 }
        else { persistenceWork.primaryWrite.calls &+= 1 }
        defer {
            let elapsed = DispatchTime.now().uptimeNanoseconds &- started
            if isBackup { persistenceWork.backupWrite.elapsedNanoseconds &+= elapsed }
            else { persistenceWork.primaryWrite.elapsedNanoseconds &+= elapsed }
        }
        #endif
        try data.write(to: url, options: .atomic)
        #if DEBUG
        if isBackup {
            persistenceWork.backupWrite.succeeded &+= 1
            persistenceWork.backupWrite.bytes &+= data.count
        } else {
            persistenceWork.primaryWrite.succeeded &+= 1
            persistenceWork.primaryWrite.bytes &+= data.count
        }
        #endif
    }
}
