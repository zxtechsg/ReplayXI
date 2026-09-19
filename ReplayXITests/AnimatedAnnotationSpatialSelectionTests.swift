import RealityKit
import XCTest
@testable import ReplayXI

@MainActor
final class AnimatedAnnotationSpatialSelectionTests: XCTestCase {
    func testExplicitReviewRetainsRevealJumpButSpatialSelectionKeepsTheHitPose() throws {
        let fixture = try Fixture()
        let mark = try fixture.mark()
        // Baseline: both spatial and AX selection formerly called this review
        // action, moving a hit at key 6 back to In 2 before the next edit.
        fixture.store.seek(to: 6, broadcast: false)
        PlaybackAccessibilityActivationRouter.reviewAnnotation(mark, in: fixture.store)
        XCTAssertEqual(fixture.store.playhead, 2, "Explicit review still starts at In")

        let original = fixture.store.marks
        for time in [6.0, 4.0, 2.0] {
            fixture.selectedAnnotationID = nil
            fixture.store.seek(to: time, broadcast: false)
            fixture.store.setPlaying(true, broadcast: false)
            fixture.render()
            let body = try fixture.body()
            XCTAssertTrue(body.isEnabledInHierarchy)
            let ax = try XCTUnwrap(body.components[AccessibilityComponent.self])
            XCTAssertTrue(ax.isAccessibilityElement)
            XCTAssertTrue(ax.systemActions.contains(.activate))
            try fixture.assertRenderedPose()

            fixture.activate(body)

            XCTAssertEqual(fixture.selectedAnnotationID, mark.id)
            XCTAssertEqual(fixture.playheadWhenSelected, time)
            XCTAssertEqual(fixture.store.playhead, time)
            XCTAssertFalse(fixture.store.isPlaying)
            XCTAssertEqual(fixture.store.marks, original, "Selection never writes a key")
            fixture.render()
            try fixture.assertSelectedEndpoints()
        }
    }

    func testBodySegmentAndLabelMapToTheCurrentAnimatedMarkInBothSeekDirections() throws {
        let fixture = try Fixture()
        for time in [2.0, 6.0, 4.0] {
            for useLabel in [false, true] {
                fixture.selectedAnnotationID = nil
                fixture.store.seek(to: time, broadcast: false)
                fixture.render()
                let entity = try fixture.markEntity()
                let target = try XCTUnwrap(useLabel
                    ? entity.findEntity(named: AnnotationSceneAffordance.labelTargetName)
                    : entity.findEntity(named: "annotation-arc-body-target-7"))
                XCTAssertEqual(AnnotationSceneAffordance.targetAncestor(of: target),
                               .init(markID: fixture.markID, role: .body))
                XCTAssertTrue(target.isEnabledInHierarchy)
                XCTAssertNotNil(target.components[InputTargetComponent.self])
                XCTAssertNotNil(target.components[CollisionComponent.self])
                try fixture.assertRenderedPose()

                fixture.activate(target)

                XCTAssertEqual(fixture.store.playhead, time)
                XCTAssertEqual(fixture.selectedAnnotationID, fixture.markID)
            }
        }
    }

    func testEditingAfterSelectionUpdatesCurrentKeyOrAddsInterpolatedKeyWithOneUndo() throws {
        let fixture = try Fixture()
        let baseline = fixture.store.marks
        let original = try fixture.mark()
        for time in [6.0, 4.0, 2.0] {
            fixture.selectedAnnotationID = nil
            fixture.store.seek(to: time, broadcast: false)
            fixture.render()
            fixture.activate(try fixture.body())
            XCTAssertTrue(fixture.store.nudgeCoachMarkEndpoint(
                id: fixture.markID, endpoint: .end, by: .init(x: 1, z: 0.5)))

            let edited = try fixture.mark()
            let before = original.sampled(at: time)
            let after = edited.sampled(at: time)
            XCTAssertEqual(fixture.store.playhead, time)
            XCTAssertEqual(after.end.x, before.end.x + 1, accuracy: 0.0001)
            XCTAssertEqual(after.end.z, before.end.z + 0.5, accuracy: 0.0001)
            XCTAssertEqual(edited.keyframes?.map(\.time), time == 4 ? [2, 4, 6] : [2, 6])
            for key in original.keyframes ?? [] where key.time != time {
                XCTAssertEqual(edited.keyframes?.first { $0.time == key.time }, key)
            }
            fixture.render()
            try fixture.assertRenderedPose()
            try fixture.assertSelectedEndpoints()
            XCTAssertTrue(fixture.store.flushReviewAutosave())
            XCTAssertEqual(fixture.store.autosavedReview?.state.playhead, time)
            XCTAssertEqual(fixture.store.autosavedReview?.state.marks, fixture.store.marks)
            XCTAssertTrue(fixture.store.undoAnnotationEdit())
            XCTAssertEqual(fixture.store.marks, baseline, "One Undo restores the whole keyed edit")
            XCTAssertEqual(fixture.store.playhead, time)
        }
    }

    func testEraseAndUndoKeepTimeAndRestoreAnimatedGeometryWithoutStaleActivation() throws {
        let fixture = try Fixture()
        for time in [6.0, 4.0] {
            fixture.selectedAnnotationID = nil
            fixture.store.seek(to: time, broadcast: false)
            fixture.render()
            let retainedTarget = try fixture.body()
            fixture.activate(retainedTarget)
            let original = fixture.store.marks
            XCTAssertTrue(fixture.store.removeCoachMark(id: fixture.markID))
            fixture.selectedAnnotationID = nil
            // Queued AX input can still carry the enabled previous-frame body.
            fixture.activate(retainedTarget)
            XCTAssertNil(fixture.selectedAnnotationID)
            XCTAssertFalse(fixture.store.marks.contains { $0.id == fixture.markID })
            XCTAssertEqual(fixture.store.playhead, time)

            fixture.render()
            XCTAssertNil(fixture.root.findEntity(named: "mark-\(fixture.markID.uuidString)"))
            XCTAssertTrue(fixture.store.undoAnnotationEdit())
            XCTAssertEqual(fixture.store.marks, original)
            XCTAssertEqual(fixture.store.playhead, time)
            fixture.render()
            try fixture.assertRenderedPose()
            fixture.activate(try fixture.body())
            XCTAssertEqual(fixture.selectedAnnotationID, fixture.markID)
            XCTAssertEqual(fixture.store.playhead, time)
        }
    }

    func testUnselectedTargetsRespectInclusiveInAndExclusiveOut() throws {
        let fixture = try Fixture()
        for (time, visible) in [(1.99, false), (2.0, true), (9.99, true), (10.0, false)] {
            fixture.selectedAnnotationID = nil
            fixture.store.seek(to: time, broadcast: false)
            fixture.store.setPlaying(true, broadcast: false)
            fixture.render()
            let body = try fixture.body()
            let label = try XCTUnwrap(try fixture.markEntity().findEntity(
                named: AnnotationSceneAffordance.labelTargetName))
            XCTAssertEqual(body.isEnabledInHierarchy, visible)
            XCTAssertEqual(label.isEnabledInHierarchy, visible)
            fixture.activate(body)
            fixture.activate(label)
            XCTAssertEqual(fixture.selectedAnnotationID, visible ? fixture.markID : nil)
            XCTAssertEqual(fixture.store.playhead, time)
            XCTAssertEqual(fixture.store.isPlaying, !visible)
        }
    }

    func testSelectedEditHandlesOutsideInOutKeepPreviewTimeAndSampledPose() throws {
        let fixture = try Fixture()
        fixture.selectedAnnotationID = fixture.markID
        let original = fixture.store.marks
        for time in [1.99, 10.0, 4.0] {
            fixture.store.seek(to: time, broadcast: false)
            fixture.render()
            try fixture.assertSelectedEndpoints()
            for endpoint in ["start", "end"] {
                let handle = try fixture.handle(endpoint)
                XCTAssertTrue(handle.isEnabledInHierarchy)
                let ax = try XCTUnwrap(handle.components[AccessibilityComponent.self])
                XCTAssertTrue(ax.systemActions.contains(.activate))
                fixture.activate(handle)
                XCTAssertEqual(fixture.store.playhead, time)
            }
        }
        XCTAssertEqual(fixture.store.marks, original)
    }

    func testTrackedCoachMarkAlsoKeepsThePlayerPoseWhileStaticMarksRetainReview() throws {
        let fixture = try Fixture(keyed: false)
        let plain = try fixture.mark()
        fixture.store.seek(to: 6, broadcast: false)
        PlaybackAccessibilityActivationRouter.selectSpatialAnnotation(plain, in: fixture.store)
        XCTAssertEqual(fixture.store.playhead, 2, "Static marks retain their previous review action")
        XCTAssertTrue(fixture.store.setCoachMarkTracking(id: fixture.markID, playerID: "red-lb"))
        let tracked = try fixture.mark()
        XCTAssertTrue(tracked.followsPlayerTracks)
        XCTAssertFalse(tracked.hasKeyframes)
        for time in [6.0, 4.0] {
            fixture.selectedAnnotationID = nil
            fixture.store.seek(to: time, broadcast: false)
            fixture.render()
            try fixture.assertRenderedPose()
            fixture.activate(try fixture.body())
            XCTAssertEqual(fixture.store.playhead, time)
            XCTAssertEqual(try fixture.mark(), tracked)
            fixture.render()
            try fixture.assertSelectedEndpoints()
        }
    }

    func testSelectionResolvesCurrentMarkAndCannotInterruptAnotherEditOrSelectDeletedData() throws {
        let fixture = try Fixture()
        var stale = try fixture.mark()
        stale.keyframes = nil
        fixture.store.seek(to: 6, broadcast: false)
        PlaybackAccessibilityActivationRouter.selectSpatialAnnotation(stale, in: fixture.store)
        XCTAssertEqual(fixture.store.playhead, 6, "Use current animation state, not a stale static value")

        XCTAssertTrue(fixture.store.beginTimelineScrub())
        XCTAssertTrue(fixture.store.previewTimelineScrub(to: 7))
        let owner = fixture.store.activeTimelineScrubID
        PlaybackAccessibilityActivationRouter.selectSpatialAnnotation(stale, in: fixture.store)
        XCTAssertEqual(fixture.store.playhead, 7)
        XCTAssertEqual(fixture.store.activeTimelineScrubID, owner)
        fixture.store.cancelTimelineScrub()
        fixture.store.beginDrawing(.arc)
        PlaybackAccessibilityActivationRouter.selectSpatialAnnotation(stale, in: fixture.store)
        XCTAssertTrue(fixture.store.isDrawing)
        XCTAssertEqual(fixture.store.playhead, 6)
        fixture.store.cancelDrawing()

        XCTAssertTrue(fixture.store.removeCoachMark(id: fixture.markID))
        fixture.store.setPlaying(true, broadcast: false)
        PlaybackAccessibilityActivationRouter.selectSpatialAnnotation(stale, in: fixture.store)
        XCTAssertTrue(fixture.store.isPlaying)
        XCTAssertEqual(fixture.store.playhead, 6)
    }

    func testSpatialTapRecoveredTapAndAccessibilityShareSelectionNotEventReview() throws {
        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let scene = try String(contentsOf: project.appendingPathComponent(
            "ReplayXI/Immersive/FootballImmersiveView.swift"), encoding: .utf8)
        let router = try String(contentsOf: project.appendingPathComponent(
            "ReplayXI/Immersive/PlaybackAccessibilityActivationRouter.swift"), encoding: .utf8)
        let spatial = try XCTUnwrap(scene.components(separatedBy: "private func handleSpatialTap(").last)
        XCTAssertTrue(spatial.components(separatedBy: "private func ").first?.contains(
            "reviewSpatialAnnotation(mark)") == true)
        let recovery = try XCTUnwrap(scene.components(separatedBy: "private func recoverTapIntentFromShortDrag(").last)
        XCTAssertTrue(recovery.components(separatedBy: "private func ").first?.contains(
            "reviewSpatialAnnotation(mark)") == true)
        XCTAssertTrue(scene.contains("PlaybackAccessibilityActivationRouter.selectSpatialAnnotation(mark, in: store)"))
        XCTAssertTrue(router.contains("selectAnnotation(annotationTarget.markID)\n            selectSpatialAnnotation(mark, in: store)"))
        let jump = try XCTUnwrap(scene.components(separatedBy: "private func jump(to mark: CoachMark)").last)
        XCTAssertTrue(jump.components(separatedBy: "private func ").first?.contains(
            "store.seek(to: mark.revealTime, broadcast: store.localRole == .coach)") == true)
    }

    @MainActor
    private final class Fixture {
        let store: ReplayStore
        let root: Entity
        let markID: UUID
        let roomPresentationID: UUID
        var selectedAnnotationID: UUID?
        var playheadWhenSelected: TimeInterval?

        init(keyed: Bool = true) throws {
            let store = ReplayStore()
            store.prepareForLocalExperience()
            store.seek(to: 2, broadcast: false)
            store.beginDrawing(.arc)
            XCTAssertNil(store.registerPitchTap(.init(x: -20, z: -20)))
            let created = try XCTUnwrap(store.registerPitchTap(.init(x: -16, z: -14)))
            if created.followsPlayerTracks {
                XCTAssertTrue(store.setCoachMarkTracking(id: created.id, playerID: nil))
            }
            if store.marks.last?.hideTime != 10 {
                XCTAssertTrue(store.setCoachMarkWindow(id: created.id, start: 2, end: 10))
            }
            if keyed {
                XCTAssertTrue(store.captureCoachMarkKeyframe(id: created.id))
                store.seek(to: 6, broadcast: false)
                XCTAssertTrue(store.updateCoachMarkGeometry(id: created.id,
                    start: .init(x: -12, z: -18), end: .init(x: -7, z: -10),
                    curve: .init(bend: 3, lift: 1, rollDegrees: 25)))
            }
            let request = try XCTUnwrap(store.beginImmersiveOpen())
            XCTAssertTrue(store.completeImmersiveOpen(request, opened: true))
            XCTAssertEqual(store.immersiveRoomDidAppear(request), request)
            self.store = store
            markID = created.id
            roomPresentationID = request
            root = PitchSceneFactory.makeMatchRoot(for: store.selectedScenario)
            render()
        }

        func mark() throws -> CoachMark {
            try XCTUnwrap(store.marks.first { $0.id == markID })
        }

        func markEntity() throws -> Entity {
            try XCTUnwrap(root.findEntity(named: "mark-\(markID.uuidString)"))
        }

        func body() throws -> Entity {
            try XCTUnwrap(try markEntity().findEntity(named: AnnotationSceneAffordance.bodyTargetName))
        }

        func handle(_ endpoint: String) throws -> Entity {
            try XCTUnwrap(root.findEntity(named: "annotation-target-\(endpoint)-\(markID.uuidString)"))
        }

        func presentedMark() throws -> CoachMark {
            let poses = Dictionary(uniqueKeysWithValues: store.selectedScenario.players.map {
                ($0.id, store.presentedPlayerPose(for: $0, at: store.playhead))
            })
            return try mark().resolvingTrackGeometry(in: store.selectedScenario,
                at: store.playhead, presentedPlayerPoses: poses)
        }

        func assertRenderedPose(file: StaticString = #filePath, line: UInt = #line) throws {
            let mark = try presentedMark()
            let entity = try markEntity()
            let arrow = try XCTUnwrap(entity.findEntity(named: "annotation-mark-arrow"))
            XCTAssertEqual(arrow.position.x, mark.end.x, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(arrow.position.z, mark.end.z, accuracy: 0.0001, file: file, line: line)
            let segment = try XCTUnwrap(entity.findEntity(named: "annotation-arc-body-target-7"))
            let a = mark.resolvedCurve.point(at: 7.0 / 16, for: mark, baseY: 0.17)
            let b = mark.resolvedCurve.point(at: 8.0 / 16, for: mark, baseY: 0.17)
            XCTAssertEqual(segment.position.x, (a.x + b.x) / 2, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(segment.position.y, (a.y + b.y) / 2, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(segment.position.z, (a.z + b.z) / 2, accuracy: 0.0001, file: file, line: line)
        }

        func assertSelectedEndpoints(file: StaticString = #filePath, line: UInt = #line) throws {
            let mark = try presentedMark()
            for (name, point, role) in [("start", mark.start, AnnotationSceneTargetRole.start),
                                        ("end", mark.end, AnnotationSceneTargetRole.end)] {
                let handle = try handle(name)
                XCTAssertTrue(handle.isEnabledInHierarchy, file: file, line: line)
                XCTAssertEqual(AnnotationSceneAffordance.targetAncestor(of: handle),
                               .init(markID: markID, role: role), file: file, line: line)
                XCTAssertEqual(handle.position.x, point.x, accuracy: 0.0001, file: file, line: line)
                XCTAssertEqual(handle.position.z, point.z, accuracy: 0.0001, file: file, line: line)
            }
        }

        func activate(_ entity: Entity) {
            PlaybackAccessibilityActivationRouter.handle(
                AccessibilityEvents.Activate(entity: entity), store: store,
                roomPresentationID: roomPresentationID, hasActiveDrawingStroke: false
            ) { id in
                selectedAnnotationID = id
                playheadWhenSelected = store.playhead
            }
        }

        func render() {
            PitchSceneFactory.update(root: root, scenario: store.selectedScenario,
                time: store.playhead, viewMode: store.viewMode,
                perspectiveID: store.activePerspectiveID, marks: store.marks,
                selectedAnnotationID: selectedAnnotationID,
                selectedAnnotationIsEditable: selectedAnnotationID == markID,
                showsLaneLens: false, isDrawing: store.isDrawing,
                positionalOriginTransform: nil)
        }
    }
}
