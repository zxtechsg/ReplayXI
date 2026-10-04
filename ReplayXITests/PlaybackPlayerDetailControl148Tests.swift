import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class PlaybackPlayerDetailControl148Tests: XCTestCase {
    @MainActor private final class Preference {
        var value: String
        var writes = 0
        init(_ value: String? = nil) {
            self.value = value ?? ReplayPlayerDetail.defaultSelection.rawValue
        }
        var binding: Binding<String> {
            Binding(get: { self.value }, set: { self.value = $0; self.writes += 1 })
        }
    }

    func testActualChoicePausesWithoutChangingReplayOrAnnotationHistory() throws {
        let store = try makeStore()
        let preference = Preference()
        store.beginDrawing(.arc)
        XCTAssertNil(store.registerPitchTap(.init(x: -20, z: -20)))
        XCTAssertNotNil(store.registerPitchTap(.init(x: -16, z: -14)))
        XCTAssertTrue(store.saveReview(named: "Before player detail"))
        store.setPlaying(true, broadcast: false)
        let before = store.makeSavedReviewState()
        let history = [store.annotationUndoTitle, store.annotationRedoTitle]
        let savedReviews = store.reviewLibrary.savedReviews
        XCTAssertTrue(PlaybackPlayerDetailControl.select(.fullSquad, rawValue: preference.binding, store: store))
        XCTAssertEqual(preference.value, ReplayPlayerDetail.fullSquad.rawValue)
        XCTAssertEqual(preference.writes, 1)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.makeSavedReviewState(), before)
        XCTAssertEqual([store.annotationUndoTitle, store.annotationRedoTitle], history)
        XCTAssertEqual(store.reviewLibrary.savedReviews, savedReviews)
        store.setPlaying(true, broadcast: false)
        XCTAssertTrue(PlaybackPlayerDetailControl.select(.balanced, rawValue: preference.binding, store: store))
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(preference.writes, 2)
        XCTAssertEqual(store.makeSavedReviewState(), before)
    }

    func testReselectAndUnknownStoredFallbackAreExactNoOpsDuringPlayback() throws {
        for raw in [ReplayPlayerDetail.balanced.rawValue, ReplayPlayerDetail.fullSquad.rawValue, "unknown-future-detail"] {
            let store = try makeStore()
            let preference = Preference(raw)
            store.setPlaying(true, broadcast: false)
            let before = store.makeSavedReviewState()
            XCTAssertFalse(PlaybackPlayerDetailControl.select(.resolved(raw), rawValue: preference.binding, store: store))
            XCTAssertTrue(store.isPlaying)
            XCTAssertEqual(preference.value, raw)
            XCTAssertEqual(preference.writes, 0)
            XCTAssertEqual(store.makeSavedReviewState(), before)
        }
    }

    func testDrawingScrubAndGeometryOwnersRejectAStaleEnabledAction() throws {
        for owner in ["drawing", "timeline", "geometry", "joystick", "curve"] {
            let store = try makeStore()
            let preference = Preference()
            if owner == "drawing" {
                store.beginDrawing(.arc)
                _ = store.registerPitchTap(.init(x: -20, z: -20))
            } else if owner == "timeline" {
                store.setPlaying(true, broadcast: false)
                XCTAssertTrue(store.beginTimelineScrub())
                XCTAssertTrue(store.previewTimelineScrub(to: 2))
            } else {
                store.beginDrawing(.arc)
                _ = store.registerPitchTap(.init(x: -20, z: -20))
                let mark = try XCTUnwrap(store.registerPitchTap(.init(x: -16, z: -14)))
                if owner == "joystick" {
                    XCTAssertNotNil(store.previewCoachMarkEndpoint(id: mark.id, endpoint: .end,
                        gestureID: UUID(), cumulativeDelta: .init(x: 1, z: 0)))
                } else if owner == "curve" {
                    XCTAssertTrue(store.previewCoachMarkCurve(id: mark.id, gestureID: UUID(),
                        curve: mark.resolvedCurve.adjusting(amountDelta: 0.5, angleDelta: 5)))
                } else {
                    XCTAssertTrue(store.updateCoachMarkGeometry(id: mark.id, start: mark.start,
                        end: .init(x: -14, z: -14), broadcast: false))
                }
            }
            XCTAssertFalse(store.canChangePlaybackView)
            let before = store.makeSavedReviewState()
            let previewMarks = store.marks
            let pendingPoint = store.pendingDrawStart
            let playing = store.isPlaying
            XCTAssertFalse(PlaybackPlayerDetailControl.select(.fullSquad, rawValue: preference.binding, store: store))
            XCTAssertEqual(preference.writes, 0)
            XCTAssertEqual(store.makeSavedReviewState(), before)
            XCTAssertEqual(store.marks, previewMarks)
            XCTAssertEqual(store.pendingDrawStart, pendingPoint)
            XCTAssertEqual(store.isPlaying, playing)
            XCTAssertFalse(store.canChangePlaybackView)
        }
    }

    func testShapeLabRejectsTheHiddenChoiceWithoutPausing() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .shapeLab))
        let store = ReplayStore(scenarios: [scenario])
        store.prepareForLocalExperience()
        store.setPlaying(true, broadcast: false)
        let preference = Preference()
        let before = store.makeSavedReviewState()
        let playing = store.isPlaying
        XCTAssertFalse(PlaybackPlayerDetailControl.select(.fullSquad, rawValue: preference.binding, store: store))
        XCTAssertEqual(preference.writes, 0)
        XCTAssertEqual(store.isPlaying, playing)
        XCTAssertEqual(store.makeSavedReviewState(), before)
    }

    func testPreferenceWiresBothSceneUpdatesAndOnlyTheSettingsShelf() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("@AppStorage(ReplayPlayerDetail.storageKey)"))
        XCTAssertTrue(source.contains("ReplayPlayerDetail.defaultSelection.rawValue"))
        // Creation and updates share one path; both must reach the detail choice.
        XCTAssertEqual(source.components(separatedBy: "updateMatchRoot(root)").count - 1, 2)
        XCTAssertEqual(source.components(separatedBy: "playerDetail: playerDetail").count - 1, 1)
        XCTAssertTrue(source.contains("playerDetailRawValue: $playerDetailRawValue"))
        let shelfStart = try XCTUnwrap(source.range(of: "private var playbackSettingsShelf:"))
        let shelfEnd = try XCTUnwrap(source.range(of: "private var speedShelfHeader:", range: shelfStart.upperBound..<source.endIndex))
        let shelf = String(source[shelfStart.lowerBound..<shelfEnd.lowerBound])
        XCTAssertTrue(shelf.contains("if store.selectedScenario.kind != .shapeLab"))
        XCTAssertTrue(shelf.contains("PlaybackPlayerDetailControl(rawValue: $playerDetailRawValue)"))
        XCTAssertEqual(source.components(separatedBy: "PlaybackPlayerDetailControl(").count - 1, 1)
        let control = try String(contentsOf: root.appendingPathComponent("ReplayXI/Immersive/PlaybackPlayerDetailControl.swift"), encoding: .utf8)
        XCTAssertFalse(control.contains("Menu(")); XCTAssertFalse(control.contains(".popover"))
        XCTAssertTrue(control.contains("PlaybackControlDeckPresentation.minimumSpatialHitTarget"))
        XCTAssertTrue(control.contains(".accessibilityAddTraits(selected ? .isSelected : [])"))
        XCTAssertTrue(control.contains(".accessibilityHint(selected ? \"Selected\""))
        XCTAssertTrue(control.contains(".disabled(!store.canChangePlaybackView)"))
        XCTAssertTrue(control.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(control.contains(".tint(selected ? ReplayTheme.cyan : .white.opacity(0.10))"))
        XCTAssertTrue(control.contains(".foregroundStyle(selected ? Color.black : Color.white)"))
        XCTAssertTrue(control.contains("Full squad: more detail, more processing."))
        XCTAssertGreaterThanOrEqual(PlaybackControlDeckPresentation.minimumSpatialHitTarget, 60)
    }

    func testDetailChoicesRenderAtRegularAndLargestText() throws {
        let cases: [(name: String, large: Bool, width: CGFloat, height: CGFloat)] = [
            ("regular-balanced", false, 1200, 220),
            ("AX5-full-squad", true, 1380, 420),
            ("narrow-balanced", false, 560, 280),
            ("AX5-narrow-full-squad", true, 560, 620)
        ]
        for fixture in cases {
            let store = try makeStore()
            let width = fixture.width, height = fixture.height
            let view = PlaybackPlayerDetailControl(rawValue: .constant(fixture.large ? "fullSquad" : "balanced"))
                .environment(store).environment(\.colorScheme, .dark)
                .dynamicTypeSize(fixture.large ? .accessibility5 : .large)
                .controlSize(.extraLarge)
                .padding(24).frame(width: width, height: height, alignment: .topLeading)
                .background(Color(red: 0.04, green: 0.06, blue: 0.08))
            let host = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
            window.rootViewController = host; window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            host.view.frame = window.bounds
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
            }
            let data = try XCTUnwrap(image.pngData())
            XCTAssertGreaterThan(data.count, 2_048)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "PlayerDetail148-\(fixture.name)"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    private func makeStore() throws -> ReplayStore {
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        let store = ReplayStore(scenarios: [scenario])
        store.prepareForLocalExperience()
        store.seek(to: 1, broadcast: false)
        return store
    }
}
