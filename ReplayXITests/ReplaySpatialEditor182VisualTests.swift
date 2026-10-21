import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

/// Native captures of the actual inline editor; no immersive glass or mocked marks.
@MainActor
final class ReplaySpatialEditor182VisualTests: XCTestCase {
    func testEndpointAndTimelineSymbolsExist() {
        for name in ["list.bullet.rectangle", "minus.circle", "diamond",
                     "circle.lefthalf.filled", "circle.righthalf.filled", "slider.horizontal.3"] {
            XCTAssertNotNil(UIImage(systemName: name), "Missing SF Symbol: \(name)")
        }
    }

    func testKeyedEditorAndThreeTracksRenderAtAttachmentWidth() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let first = try addMark(.arc, at: 2, start: .init(x: 0, z: 0),
                                end: .init(x: 8, z: 10), to: store)
        XCTAssertTrue(store.captureCoachMarkKeyframe(id: first.id))
        store.seek(to: 5, broadcast: false)
        XCTAssertTrue(store.updateCoachMarkGeometry(id: first.id,
            start: .init(x: 2, z: 1), end: .init(x: 10, z: 11)))
        let second = try addMark(.run, at: 3, start: .init(x: -5, z: -9),
                        end: .init(x: 1, z: -3), to: store)
        let third = try addMark(.pass, at: 4, start: .init(x: 5, z: 5),
                        end: .init(x: 13, z: 10), to: store)
        let keyed = try XCTUnwrap(store.marks.first { $0.id == first.id })
        XCTAssertGreaterThanOrEqual(keyed.keyframes?.count ?? 0, 2)
        let createdIDs: Set<UUID> = [first.id, second.id, third.id]
        let createdMarks = store.marks.filter { createdIDs.contains($0.id) }
        XCTAssertEqual(createdMarks.count, 3)

        let width = PlaybackControlDeckLayout.resolve(preset: .standard,
            usesAccessibilityText: false).contentWidth
        let editor = SpatialAnnotationEditor(mark: keyed, onTimeline: {}, onAdjust: {},
            onActions: {}, onClose: {})
            .environment(store)
        try capture(editor, width: width, name: "spatial-editor-keyed-182")

        let tracks = SpatialAnnotationTracks(marks: createdMarks, onSelect: { _ in }, onClose: {})
            .environment(store)
        try capture(tracks, width: width, name: "spatial-tracks-three-182")
    }

    private func addMark(_ kind: CoachMarkKind, at time: TimeInterval, start: PitchPoint,
                         end: PitchPoint, to store: ReplayStore) throws -> CoachMark {
        store.seek(to: time, broadcast: false)
        store.beginDrawing(kind)
        _ = store.registerPitchTap(start)
        return try XCTUnwrap(store.registerPitchTap(end))
    }

    private func capture<Content: View>(_ content: Content, width: CGFloat,
                                        name: String) throws {
        let view = content
            .environment(\.colorScheme, .dark)
            .padding(20)
            .frame(width: width, alignment: .topLeading)
            .background(ReplayTheme.navy)
        let host = UIHostingController(rootView: view)
        let fitting = host.sizeThatFits(in: CGSize(width: width, height: 2_000))
        XCTAssertTrue(fitting.height.isFinite)
        XCTAssertGreaterThan(fitting.height, 100)
        XCTAssertLessThan(fitting.height, 1_000)
        let size = CGSize(width: width, height: ceil(fitting.height))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(try brightPixels(image), 1_000, "Rendered editor must not be blank")
        let data = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(data.count, 4_096)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func brightPixels(_ image: UIImage) throws -> Int {
        let source = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: source.width,
                height: source.height, bitsPerComponent: 8, bytesPerRow: source.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo:
                CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        }
        return stride(from: 0, to: bytes.count, by: 4).reduce(0) {
            $0 + (max(bytes[$1], bytes[$1 + 1], bytes[$1 + 2]) > 120 ? 1 : 0)
        }
    }
}
