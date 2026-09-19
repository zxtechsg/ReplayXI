import Foundation
import Observation

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
    var usesDisk: Bool { fileURL != nil }

    private struct Document: Codable {
        let version: Int
        let savedReviews: [SavedReplayReview]
        let autosavedReview: SavedReplayReview?
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
        guard accepts(state), now.timeIntervalSince1970.isFinite else {
            status = "Autosave could not be completed"
            return false
        }
        guard autosavedReview?.state != state else { return true }
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

    private static func validName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maximumNameLength,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return name
    }

    private func decode(_ data: Data) throws -> Document {
        guard data.count <= Self.maximumFileBytes else { throw LibraryError.invalidDocument }
        // Read the version before decoding payloads that a future schema may
        // change. A downgrade must never erase a newer app's saves.
        struct Header: Decodable { let version: Int }
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        guard header.version <= 1 else { throw LibraryError.newerVersion }
        guard header.version == 1 else { throw LibraryError.invalidDocument }
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
    }

    private func persist(reviews: [SavedReplayReview], autosave: SavedReplayReview?, message: String) -> Bool {
        guard !isReadOnly else { return false }
        let document = Document(version: 1, savedReviews: reviews, autosavedReview: autosave)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(document)
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
                    try lastGoodData.write(to: fileURL.appendingPathExtension("backup"), options: .atomic)
                }
                try data.write(to: fileURL, options: .atomic)
            }
            adopt(document, data: data)
            status = message
            return true
        } catch {
            status = "Save failed. Check device storage."
            return false
        }
    }
}
