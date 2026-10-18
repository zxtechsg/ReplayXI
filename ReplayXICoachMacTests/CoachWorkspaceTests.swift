import XCTest
@testable import ReplayXICoachMac

final class CoachWorkspaceTests: XCTestCase {
    func testTimelineKeysJumpStrictlyInEitherDirectionWithoutWrapping() {
        XCTAssertEqual(CoachWorkspace.adjacentKey(in: [6, 2, 4], at: 4, forward: true), 6)
        XCTAssertEqual(CoachWorkspace.adjacentKey(in: [6, 2, 4], at: 4, forward: false), 2)
        XCTAssertNil(CoachWorkspace.adjacentKey(in: [2, 4, 6], at: 6, forward: true))
        XCTAssertNil(CoachWorkspace.adjacentKey(in: [2, 4, 6], at: 2, forward: false))
        XCTAssertEqual(CoachWorkspace.adjacentKey(in: [.nan, 4], at: 3, forward: true), 4)
    }

    func testTimelineScrubClampsToClipAndRejectsInvalidSizes() {
        XCTAssertEqual(CoachWorkspace.timelineTime(x: 50, width: 100, duration: 60), 30)
        XCTAssertEqual(CoachWorkspace.timelineTime(x: -5, width: 100, duration: 60), 0)
        XCTAssertEqual(CoachWorkspace.timelineTime(x: 200, width: 100, duration: 60), 60)
        XCTAssertEqual(CoachWorkspace.timelineTime(x: 50, width: 0, duration: 60), 0)
        XCTAssertEqual(CoachWorkspace.timelineTime(x: .infinity, width: 100, duration: 60), 0)
    }

    func testVisibilityMatchesInclusiveStartExclusiveEnd() {
        var mark = fixture
        XCTAssertFalse(CoachWorkspace.isVisible(mark, at: 6.999))
        XCTAssertTrue(CoachWorkspace.isVisible(mark, at: 7))
        XCTAssertTrue(CoachWorkspace.isVisible(mark, at: 19.999))
        XCTAssertFalse(CoachWorkspace.isVisible(mark, at: 20))
        mark.hideAt = nil
        XCTAssertTrue(CoachWorkspace.isVisible(mark, at: 60))
    }

    func testSearchCombinesNameNumberAndTeamWithoutCaseOrAccentSensitivity() {
        let values = ["José Left winger", "#7", "home"]
        XCTAssertTrue(CoachWorkspace.matches("  JOSE 7 home  ", values: values))
        XCTAssertTrue(CoachWorkspace.matches(" ", values: values))
        XCTAssertFalse(CoachWorkspace.matches("7 away", values: values))
        XCTAssertFalse(CoachWorkspace.matches("#9", values: values))
    }

    func testVisibilityWindowRejectsInvalidOrInvertedTimes() {
        XCTAssertTrue(CoachWorkspace.validWindow(show: 0, hide: 30, duration: 60))
        XCTAssertFalse(CoachWorkspace.validWindow(show: 0, hide: 60, duration: 60))
        XCTAssertFalse(CoachWorkspace.validWindow(show: 7, hide: 7.4, duration: 60))
        XCTAssertTrue(CoachWorkspace.validWindow(show: 7, hide: nil, duration: 60))
        for (show, hide, duration) in [(7.0, 7.0, 60.0), (7, 6, 60), (-1, 7, 60),
            (7, 61, 60), (61, 62, 60), (0, 1, -1), (Double.nan, 8, 60),
            (7, Double.infinity, 60), (7, 8, Double.infinity)] {
            XCTAssertFalse(CoachWorkspace.validWindow(show: show, hide: hide, duration: duration))
        }
    }

    func testClockCarriesRoundingAcrossMinuteBoundary() {
        XCTAssertEqual(CoachWorkspace.clock(0), "00:00.0")
        XCTAssertEqual(CoachWorkspace.clock(59.96), "01:00.0")
        XCTAssertEqual(CoachWorkspace.clock(75.2), "01:15.2")
        XCTAssertEqual(CoachWorkspace.clock(-2), "00:00.0")
        XCTAssertEqual(CoachWorkspace.clock(.nan), "—")
        XCTAssertEqual(CoachWorkspace.clock(.greatestFiniteMagnitude), "—")
        XCTAssertEqual(CoachWorkspace.clock(-Double.greatestFiniteMagnitude), "00:00.0")
    }

    func testRenameAcknowledgementPreservesUnsavedHeightAndTiming() {
        let base = CoachInspectorDraft(fixture, duration: 60)
        var local = base
        local.label = "Overlap"
        local.startHeight = 2
        local.hideAt = 25
        var remote = base
        remote.label = "Overlap"
        let merged = CoachInspectorDraft.merge(base: base, local: local, remote: remote)
        XCTAssertFalse(merged.conflict)
        XCTAssertEqual(merged.draft.label, "Overlap")
        XCTAssertEqual(merged.draft.startHeight, 2)
        XCTAssertEqual(merged.draft.hideAt, 25)
    }

    func testInspectorMergeUpdatesCleanFieldsAndDetectsActualConflicts() {
        let base = CoachInspectorDraft(fixture, duration: 60)
        var local = base
        local.label = "My label"
        var remote = base
        remote.endHeight = 3
        let merged = CoachInspectorDraft.merge(base: base, local: local, remote: remote)
        XCTAssertFalse(merged.conflict)
        XCTAssertEqual(merged.draft.endHeight, 3)
        XCTAssertEqual(merged.draft.label, "My label")
        remote.label = "Other label"
        let conflict = CoachInspectorDraft.merge(base: base, local: local, remote: remote)
        XCTAssertTrue(conflict.conflict)
        XCTAssertEqual(conflict.draft.label, "My label", "Never silently discard local typing")
    }

    func testHeightAcknowledgementDoesNotConflictOnWireRounding() {
        let base = CoachInspectorDraft(fixture, duration: 60)
        var local = base
        local.startHeight = 0.2
        local.endHeight = 1.1
        local.controlHeight = 3.3
        var remote = local
        remote.startHeight = Double(Float(local.startHeight))
        remote.endHeight = Double(Float(local.endHeight))
        remote.controlHeight = Double(Float(local.controlHeight))
        XCTAssertFalse(CoachInspectorDraft.merge(base: base, local: local, remote: remote).conflict)
        remote.controlHeight = 4
        XCTAssertTrue(CoachInspectorDraft.merge(base: base, local: local, remote: remote).conflict)
    }

    private var fixture: ReplayXIWireMark {
        .init(id: UUID(), kind: "arc", start: .init(x: -20, z: -28), end: .init(x: 8, z: 18),
            startHeight: 0.5, endHeight: 1.2, label: "Curved overlap", showAt: 7, hideAt: 20,
            keyframes: [7, 12, 18], authored: false, controlPoint: .init(x: -23, y: 3.2, z: 4),
            encodedMark: Data("{}".utf8))
    }
}
