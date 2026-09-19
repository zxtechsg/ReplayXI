import XCTest
@testable import ReplayXI

@MainActor
final class AnnotationCurveAdjustmentPrecisionTests: XCTestCase {
    func testFineAndCoarseStepsMatchTheirLabels() {
        let fine = AnnotationCurveAdjustmentPrecision(fine: true)
        let coarse = AnnotationCurveAdjustmentPrecision(fine: false)
        XCTAssertEqual(fine.distanceStep, 0.05)
        XCTAssertEqual(fine.angleStep, 1)
        XCTAssertEqual(coarse.distanceStep, 0.25)
        XCTAssertEqual(coarse.angleStep, 5)
        for precision in [fine, coarse] {
            XCTAssertEqual(precision.verticalStep(isAngle: false), precision.distanceStep)
            XCTAssertEqual(precision.verticalStep(isAngle: true), precision.angleStep)
        }
        XCTAssertEqual(fine.distanceHint, "Five-centimetre step")
        XCTAssertEqual(fine.angleHint, "One-degree step")
        XCTAssertEqual(coarse.distanceHint, "Quarter-metre step")
        XCTAssertEqual(coarse.angleHint, "Five-degree step")
    }

    func testSpokenPadHintMatchesModeAndPrecision() {
        let fine = AnnotationCurveAdjustmentPrecision(fine: true)
        let coarse = AnnotationCurveAdjustmentPrecision(fine: false)
        XCTAssertTrue(fine.padHint(isAngle: true).contains("Five-centimetre and one-degree steps"))
        XCTAssertTrue(coarse.padHint(isAngle: true).contains("Quarter-metre and five-degree steps"))
        XCTAssertTrue(fine.padHint(isAngle: false).contains("Five-centimetre steps"))
        XCTAssertTrue(coarse.padHint(isAngle: false).contains("Quarter-metre steps"))
        for precision in [fine, coarse] {
            XCTAssertFalse(precision.padHint(isAngle: false).contains("degree"))
            XCTAssertTrue(precision.padHint(isAngle: false).contains("rotation angle is preserved"))
        }
    }

    func testOneNotchDragMatchesAtomicActionAndSingleUndoInBothModes() throws {
        for fine in [false, true] {
            let precision = AnnotationCurveAdjustmentPrecision(fine: fine)
            for mode in AnnotationCurveAdjustmentController.Mode.allCases {
                for vertical in [false, true] {
                    for sign in [Float(-1), Float(1)] {
                        let (store, mark) = try fixture()
                        let baseline = store.marks
                        let controller = AnnotationCurveAdjustmentController()
                        let horizontalDelta = vertical ? 0 : sign * precision.distanceStep
                        let verticalDelta = vertical ? sign * precision.verticalStep(isAngle: mode == .shape) : 0
                        XCTAssertTrue(controller.adjust(in: store, markID: mark.id, mode: mode,
                                                        horizontal: horizontalDelta, vertical: verticalDelta))
                        let atomic = store.marks
                        let curve = try XCTUnwrap(atomic.first { $0.id == mark.id }).resolvedCurve
                        if mode == .shape {
                            XCTAssertEqual(curve.amount, mark.resolvedCurve.amount + horizontalDelta, accuracy: 0.000_01)
                            XCTAssertEqual(curve.rollDegrees, mark.resolvedCurve.rollDegrees + verticalDelta, accuracy: 0.000_01)
                        } else {
                            XCTAssertEqual(curve.bend, mark.resolvedCurve.bend + horizontalDelta, accuracy: 0.000_01)
                            XCTAssertEqual(curve.lift, mark.resolvedCurve.lift + verticalDelta, accuracy: 0.000_01)
                        }
                        XCTAssertTrue(store.undoAnnotationEdit())
                        XCTAssertEqual(store.marks, baseline, "Each +/- or VoiceOver action is one Undo")

                        // 16 pt is exactly one accepted notch, beyond the 12 pt dead zone.
                        let translation = CGSize(width: vertical ? 0 : CGFloat(sign) * 16,
                                                 height: vertical ? -CGFloat(sign) * 16 : 0)
                        XCTAssertTrue(controller.preview(in: store, markID: mark.id, translation: translation, mode: mode, fine: fine))
                        XCTAssertTrue(controller.finish(in: store, markID: mark.id, translation: translation, mode: mode, fine: fine))
                        XCTAssertEqual(store.marks, atomic, "Dragging and atomic actions must use identical precision")
                        XCTAssertFalse(store.hasActiveCoachMarkGeometryPreview)
                        XCTAssertTrue(store.undoAnnotationEdit())
                        XCTAssertEqual(store.marks, baseline, "Each completed drag is also one Undo")
                    }
                }
            }
        }
    }

    func testAllVoiceOverActionsAndVisibleButtonsUseSharedPrecision() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/Immersive/AnnotationCurveAdjustmentPad.swift"), encoding: .utf8)
        let actions = source.components(separatedBy: .newlines).filter { $0.contains(".accessibilityAction(named:") }
        XCTAssertEqual(actions.count, 8)
        for action in actions {
            XCTAssertTrue(action.contains(action.contains("Rotate arc") ? "precision.angleStep" : "precision.distanceStep"))
        }
        XCTAssertTrue(source.contains("horizontal: precision.distanceStep, vertical: 0"))
        XCTAssertTrue(source.contains("vertical: precision.verticalStep(isAngle: mode == .shape)"))
        XCTAssertTrue(source.contains("precision.padHint(isAngle: mode == .shape)"))
        XCTAssertTrue(source.contains("precision.angleHint : precision.distanceHint"))
    }

    private func fixture() throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 5, broadcast: false)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(.init(x: -20, z: -20))
        let created = try XCTUnwrap(store.registerPitchTap(.init(x: -16, z: -14)))
        let controller = AnnotationCurveAdjustmentController()
        // Leave space in both directions so negative actions are not clamped.
        XCTAssertTrue(controller.adjust(in: store, markID: created.id, mode: .offset, horizontal: 0, vertical: 1))
        XCTAssertTrue(controller.adjust(in: store, markID: created.id, mode: .shape, horizontal: 0, vertical: 20))
        return (store, try XCTUnwrap(store.marks.first { $0.id == created.id }))
    }
}
