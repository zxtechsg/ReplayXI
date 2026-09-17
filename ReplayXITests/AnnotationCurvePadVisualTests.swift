import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

/// Actual SwiftUI arc-pad captures on the native simulator. This is not a
/// screenshot of the full immersive deck, spatial glass or headset comfort.
@MainActor
final class AnnotationCurvePadVisualTests: XCTestCase {
    func testNativeParametricPadAtDefaultAndLargestTextSizes() throws {
        for (name, size) in [("default", DynamicTypeSize.large), ("accessibility5", .accessibility5)] {
            let (store, mark) = try makeArc()
            let layout = PlaybackControlDeckLayout.resolve(preset: .standard,
                usesAccessibilityText: size.isAccessibilitySize)
            try capture(store: store, mark: mark, width: layout.contentWidth - 64,
                        size: size, name: "arc-pad-\(name)")
        }
    }

    func testNativeParametricPadShowsPitchLimitForDownwardRotation() throws {
        let (store, mark) = try makeArc()
        let controller = AnnotationCurveAdjustmentController()
        XCTAssertTrue(controller.adjust(in: store, markID: mark.id, mode: .shape,
                                        horizontal: 0, vertical: -45))
        let rotated = try XCTUnwrap(store.marks.first { $0.id == mark.id })
        XCTAssertTrue(rotated.resolvedCurve.isLimitedByPitch(for: rotated))
        let layout = PlaybackControlDeckLayout.resolve(preset: .standard, usesAccessibilityText: false)
        try capture(store: store, mark: rotated, width: layout.contentWidth - 64,
                    size: .large, name: "arc-pad-negative-angle-pitch-limit")
    }

    private func capture(store: ReplayStore, mark: CoachMark, width: CGFloat,
                         size: DynamicTypeSize, name: String) throws {
        let view = AnnotationCurveAdjustmentPad(markID: mark.id, color: ReplayTheme.cyan, onCommit: {})
            .environment(store)
            .environment(\.dynamicTypeSize, size)
            .environment(\.colorScheme, .dark)
            .padding(24)
            .frame(width: width, alignment: .leading)
            .background(Color(red: 0.04, green: 0.06, blue: 0.08))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        let image = try XCTUnwrap(renderer.uiImage, "Native SwiftUI arc-pad render")
        XCTAssertEqual(image.size.width, width, accuracy: 1)
        XCTAssertGreaterThanOrEqual(image.size.height, 188)
        let data = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(data.count, 2_048, "Capture must contain UI, not an empty tiny image")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeArc() throws -> (ReplayStore, CoachMark) {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.seek(to: 5, broadcast: false)
        store.beginDrawing(.arc)
        _ = store.registerPitchTap(PitchPoint(x: -20, z: -20))
        let mark = try XCTUnwrap(store.registerPitchTap(PitchPoint(x: -16, z: -14)))
        return (store, mark)
    }
}
