import XCTest
@testable import ReplayXI

@MainActor
final class ReplayReviewReadFailureTests: XCTestCase {
    func testUnreadablePrimaryIsNotReplacedWithAnOlderBackup() throws {
        let files = FileManager.default
        let directory = files.temporaryDirectory
            .appendingPathComponent("ReplayReadFailure-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("reviews.json")
        defer {
            try? files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try? files.removeItem(at: directory)
        }

        let library = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        let state = ReplayStore().makeSavedReviewState()
        XCTAssertTrue(library.save(named: "Older review", state: state))
        XCTAssertTrue(library.save(named: "Latest review", state: state))
        let primary = try Data(contentsOf: url)
        let backupURL = url.appendingPathExtension("backup")
        let backup = try Data(contentsOf: backupURL)
        XCTAssertNotEqual(primary, backup)

        try files.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        if (try? Data(contentsOf: url)) != nil {
            throw XCTSkip("This test requires a filesystem that enforces read permissions")
        }

        let reopened = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        XCTAssertTrue(reopened.isReadOnly, "Do not accept writes over unreadable saved data")
        XCTAssertFalse(reopened.autosave(state))
        let children = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertFalse(children.contains { $0.lastPathComponent.hasPrefix("reviews-damaged-") })
        XCTAssertTrue(files.fileExists(atPath: url.path))

        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        XCTAssertEqual(try Data(contentsOf: url), primary, "A read error must not roll back the primary")
        XCTAssertEqual(try Data(contentsOf: backupURL), backup)
        let readable = ReplayReviewLibrary(scenarios: DemoScenarios.all, fileURL: url)
        XCTAssertFalse(readable.isReadOnly)
        XCTAssertEqual(Set(readable.savedReviews.map(\.name)), ["Older review", "Latest review"])
    }
}
