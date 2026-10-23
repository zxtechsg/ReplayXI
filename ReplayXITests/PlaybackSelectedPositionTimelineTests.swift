import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackSelectedPositionTimelineTests: XCTestCase {
    private func mark(times: [TimeInterval], id: UUID = UUID()) -> CoachMark {
        var mark = CoachMark(id: id, kind: .arc, start: .init(x: 0, z: 0), end: .init(x: 5, z: 5),
                             label: "Run", revealTime: 2, hideTime: 10)
        mark.keyframes = times.map { CoachMarkKeyframe(time: $0, mark: mark) }
        return mark
    }

    func testSelectionAddRemoveAndRetimeInvalidateOnlySelectedTimestampCache() {
        var cache = PlaybackSelectedPositionTimelineCache()
        var mark = mark(times: [2, 6])
        func update(_ mark: CoachMark?) -> Bool {
            cache.update(.init(mark: mark, duration: 20), railWidth: 300, leadingInset: 9)
        }
        XCTAssertTrue(update(mark))
        XCTAssertEqual(cache.keyCount, 2)
        XCTAssertFalse(update(mark))
        let addedFrame = CoachMarkKeyframe(time: 12, mark: mark)
        mark.keyframes?.append(addedFrame)
        XCTAssertTrue(update(mark))
        XCTAssertEqual(cache.keyCount, 3)
        mark.keyframes?[1].time = 8
        XCTAssertTrue(update(mark))
        XCTAssertEqual(cache.clusters.map(\.earliestTime), [2, 8, 12])
        mark.keyframes?.removeLast()
        XCTAssertTrue(update(mark))
        XCTAssertEqual(cache.keyCount, 2)
        XCTAssertTrue(update(self.mark(times: [2, 8])))
        XCTAssertTrue(update(nil))
        XCTAssertNil(cache.keyCount)
        XCTAssertTrue(cache.clusters.isEmpty)
    }

    func testGeometryLabelsAndVisibilityEditsDoNotReclusterPositionTimes() {
        let original = mark(times: [2, 6, 12])
        let changed = CoachMark(id: original.id, kind: original.kind, start: .init(x: 3, z: 3),
            end: .init(x: 8, z: 12), curve: .init(bend: 4, lift: 2, rollDegrees: 90),
            label: "Different label", revealTime: 0, hideTime: nil, keyframes: original.keyframes)
        let a = PlaybackSelectedPositionTimelineSnapshot(mark: original, duration: 20)
        let b = PlaybackSelectedPositionTimelineSnapshot(mark: changed, duration: 20)
        XCTAssertEqual(a, b)
        var cache = PlaybackSelectedPositionTimelineCache()
        XCTAssertTrue(cache.update(a, railWidth: 300, leadingInset: 9))
        let clusters = cache.clusters
        for _ in 0..<100 {
            XCTAssertFalse(cache.update(b, railWidth: 300, leadingInset: 9))
        }
        XCTAssertEqual(cache.clusters, clusters)
    }

    func testWidthDurationAndInsetChangesUpdateProjectedEndpoints() throws {
        let mark = mark(times: [0, 20])
        var cache = PlaybackSelectedPositionTimelineCache()
        XCTAssertTrue(cache.update(.init(mark: mark, duration: 20), railWidth: 200, leadingInset: 9))
        XCTAssertEqual(try XCTUnwrap(cache.clusters.first).x, 9)
        XCTAssertEqual(try XCTUnwrap(cache.clusters.last).x, 209)
        XCTAssertTrue(cache.update(.init(mark: mark, duration: 20), railWidth: 400, leadingInset: 12))
        XCTAssertEqual(try XCTUnwrap(cache.clusters.last).x, 412)
        XCTAssertTrue(cache.update(.init(mark: mark, duration: 40), railWidth: 400, leadingInset: 12))
        XCTAssertEqual(try XCTUnwrap(cache.clusters.last).x, 212, accuracy: 8)
        XCTAssertEqual(cache.keyCount, 2)
    }

    func testDensePositionsClusterWithoutDroppingCount() {
        let times = (0..<64).map { Double($0) / 1000 + 2 }
        var cache = PlaybackSelectedPositionTimelineCache()
        XCTAssertTrue(cache.update(.init(mark: mark(times: times), duration: 20),
                                   railWidth: 230, leadingInset: 9))
        XCTAssertEqual(cache.keyCount, 64)
        XCTAssertEqual(cache.clusters.count, 1)
        XCTAssertEqual(cache.clusters.reduce(0) { $0 + $1.eventCount }, 64)
        XCTAssertLessThanOrEqual(cache.clusters.count, CoachMark.maximumKeyframes)
    }

    func testMalformedInputsRemainFiniteAndBounded() {
        var cache = PlaybackSelectedPositionTimelineCache()
        let snapshot = PlaybackSelectedPositionTimelineSnapshot(
            mark: mark(times: [.nan, -.infinity, -1, 0, 20, 21]), duration: 20)
        XCTAssertEqual(snapshot.times, [0, 20])
        XCTAssertTrue(cache.update(snapshot, railWidth: .nan, leadingInset: .infinity))
        XCTAssertTrue(cache.clusters.allSatisfy { $0.x.isFinite })
        let tooMany = PlaybackSelectedPositionTimelineSnapshot(
            mark: mark(times: (0..<200).map { Double($0) / 20 }), duration: 20)
        XCTAssertEqual(tooMany.times.count, 64)
    }

    func testAccessibilityDistinguishesNoSelectionFromNoPositions() {
        XCTAssertEqual(PlaybackSelectedPositionTimelineCache.accessibilitySummary(keyCount: nil), "")
        XCTAssertEqual(PlaybackSelectedPositionTimelineCache.accessibilitySummary(keyCount: 0),
                       "; selected annotation, 0 saved positions")
        XCTAssertEqual(PlaybackSelectedPositionTimelineCache.accessibilitySummary(keyCount: 1),
                       "; selected annotation, 1 saved position")
        XCTAssertEqual(PlaybackSelectedPositionTimelineCache.accessibilitySummary(keyCount: 4),
                       "; selected annotation, 4 saved positions")
    }

    func testOverlayLeavesScrubOwnershipAndDoesNotObservePlaybackTime() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let overlay = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/PlaybackSelectedPositionTimeline.swift"), encoding: .utf8)
        XCTAssertTrue(overlay.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(overlay.contains(".accessibilityHidden(true)"))
        XCTAssertFalse(overlay.contains("store.playhead"))
        XCTAssertFalse(overlay.contains(".gesture("))
        XCTAssertFalse(overlay.contains("store.marks.map"))
        let immersive = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        XCTAssertFalse(immersive.contains("PlaybackSelectedPositionTimeline(annotationID: selectedAnnotationID"))
        XCTAssertFalse(immersive.contains("PlaybackSelectedPositionTimelineCache.accessibilitySummary"))
    }

    func testNativeOverlayUpdatesKeysWithoutChangingScrubPlayhead() throws {
        let store = ReplayStore()
        let duration = store.selectedScenario.duration
        store.seek(to: duration * 0.1)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: 0, z: 0))
        let mark = try XCTUnwrap(store.registerPitchTap(.init(x: 5, z: 5)))
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        store.seek(to: duration * 0.45)
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        var reportedCount: Int?
        let view = ZStack(alignment: .topLeading) {
            Capsule().fill(.white.opacity(0.25)).frame(width: 580, height: 4).position(x: 300, y: 8)
            PlaybackSelectedPositionTimeline(annotationID: mark.id, railWidth: 580, leadingInset: 10,
                keyCount: Binding(get: { reportedCount }, set: { reportedCount = $0 }))
        }.frame(width: 600, height: 40).padding(20)
            .background(ReplayTheme.navy).environment(store)
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 640, height: 80))
        window.rootViewController = host; window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        func settle() {
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        }
        settle()
        XCTAssertEqual(reportedCount, 2)
        let keyTime = store.playhead
        store.seek(to: duration * 0.8)
        settle()
        XCTAssertEqual(reportedCount, 2)
        XCTAssertEqual(store.playhead, duration * 0.8, accuracy: 0.000_001)
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: mark.id))
        settle()
        XCTAssertEqual(reportedCount, 3)
        XCTAssertTrue(store.retimeCoachMarkKeyframe(id: mark.id, from: keyTime, to: duration * 0.5))
        settle()
        XCTAssertEqual(reportedCount, 3)
        XCTAssertTrue(store.removeCoachMarkKeyframe(id: mark.id, at: duration * 0.1))
        settle()
        XCTAssertEqual(reportedCount, 2)
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
        attachment.name = "selected-position-timeline-diamonds"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
