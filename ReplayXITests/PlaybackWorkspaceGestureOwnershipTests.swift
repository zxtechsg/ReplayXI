import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackWorkspaceGestureOwnershipTests: XCTestCase {
    func testPresetCallbackChecksPlacementAdmissionBeforeWritingTheSavedPreset() throws {
        let source = try immersiveSource()
        let start = try XCTUnwrap(source.range(of: "private func controlDeckChoice(")?.lowerBound)
        let end = try XCTUnwrap(source.range(of: "private var annotationEditShelf:")?.lowerBound)
        let preset = source[start..<end]
        let admission = preset.range(of: "guard canChangeControlPlacement else { return }")?.lowerBound
        let mutation = try XCTUnwrap(preset.range(of: "controlDeckPresetRawValue = preset.rawValue")?.lowerBound)
        XCTAssertNotNil(admission, "A queued preset callback must not move controls beneath the held timeline")
        if let admission { XCTAssertLessThan(admission, mutation) }
        XCTAssertTrue(preset.contains(".disabled(!canChangeControlPlacement)"))
    }

    func testPresetAvailabilityUsesTheExistingWorkspaceGesturePolicy() throws {
        let source = try immersiveSource()
        let start = try XCTUnwrap(source.range(of: "private var canChangeControlPlacement: Bool")?.lowerBound)
        let end = try XCTUnwrap(source.range(of: "private var compactSpeedControlButton:", range: start..<source.endIndex)?.lowerBound)
        let policy = source[start..<end]
        XCTAssertTrue(policy.contains("PlaybackAttachmentPlacement.canRecenter("))
        XCTAssertTrue(policy.contains("isDrawing: store.isDrawing || isPinchDrawing"))
        XCTAssertTrue(policy.contains("isScrubbing: store.hasActiveTimelineScrub"))
        XCTAssertTrue(policy.contains("isEditingGeometry: store.hasActiveCoachMarkGeometryPreview"))
    }

    func testHeldTimelineActuallyOwnsPlacementWithoutLosingItsPreviewOrCommit() {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 5, broadcast: false)
        store.setPlaying(true, broadcast: false)
        XCTAssertTrue(store.beginTimelineScrub())
        XCTAssertTrue(store.previewTimelineScrub(to: 13))

        XCTAssertFalse(PlaybackAttachmentPlacement.canRecenter(
            isDrawing: store.isDrawing,
            isScrubbing: store.hasActiveTimelineScrub,
            isEditingGeometry: store.hasActiveCoachMarkGeometryPreview
        ))
        XCTAssertEqual(store.playhead, 13)
        XCTAssertTrue(store.hasActiveTimelineScrub)
        XCTAssertTrue(store.commitTimelineScrub(to: 14))
        XCTAssertEqual(store.playhead, 14)
        XCTAssertTrue(store.isPlaying)
        XCTAssertTrue(PlaybackAttachmentPlacement.canRecenter(
            isDrawing: store.isDrawing,
            isScrubbing: store.hasActiveTimelineScrub,
            isEditingGeometry: store.hasActiveCoachMarkGeometryPreview
        ))
    }

    private func immersiveSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("ReplayXI/Immersive/FootballImmersiveView.swift"),
            encoding: .utf8
        )
    }
}
