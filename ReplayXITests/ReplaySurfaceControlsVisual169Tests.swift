import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

/// Native UIKit captures of the actual controls. These validate layout only;
/// no surface discovery, ARKit permission, placement or headset claim is made.
@MainActor
final class ReplaySurfaceControlsVisual169Tests: XCTestCase {
    func testSurfaceControlsFitRegularHUD169() throws {
        let width = PlaybackViewHUDLayout.resolve(preset: .standard,
            usesAccessibilityText: false).attachmentWidth
        try captureStates(width: width, largest: false, label: "regular-HUD")
    }

    func testSurfaceControlsFitLargestTextHUD169() throws {
        let width = PlaybackViewHUDLayout.resolve(preset: .standard,
            usesAccessibilityText: true).attachmentWidth
        try captureStates(width: width, largest: true, label: "AX5-HUD")
    }

    func testSurfaceControlsFitNarrowLargestTextPanel169() throws {
        try captureStates(width: 340, largest: true, label: "AX5-narrow")
    }

    private struct State {
        let name: String
        let target: String?
        let busy: Bool
        let scanning: Bool
        let placed: Bool
        let status: String
    }

    private func captureStates(width: CGFloat, largest: Bool, label: String) throws {
        let states = [
            State(name: "find", target: nil, busy: false, scanning: false, placed: false,
                  status: "Look at a floor or table near you."),
            State(name: "place-on-table", target: "Table", busy: false, scanning: true, placed: true,
                  status: "Table found · 65% size. Tap Place to confirm."),
            State(name: "busy-cancel", target: nil, busy: true, scanning: true, placed: true,
                  status: "Look at a clear floor or table. Only surfaces that fit the pitch are offered."),
            State(name: "ready-no-fitting-surface", target: nil, busy: false, scanning: true, placed: false,
                  status: "Look at a clear floor or table. Only surfaces that fit the pitch are offered.")
        ]
        var metrics: [[String: Any]] = []
        for state in states {
            var invokedActions: [String] = []
            let content = ReplaySurfacePlacementControls(targetLabel: state.target,
                statusText: state.status, isBusy: state.busy,
                isScanning: state.scanning, hasPlacement: state.placed,
                canEdit: true, findSurface: { invokedActions.append("find") },
                place: { invokedActions.append("place") }, reset: { invokedActions.append("reset") },
                cancel: { invokedActions.append("cancel") })
                .environment(\.colorScheme, .dark)
                .dynamicTypeSize(largest ? .accessibility5 : .large)
                .controlSize(.large)
                // Match PlaybackViewOverlayHUD's inset, without spatial glass.
                .padding(11)
                .fixedSize(horizontal: false, vertical: true)
            let fittingHost = UIHostingController(rootView: content)
            let fitting = fittingHost.sizeThatFits(in: CGSize(width: width, height: 2000))
            XCTAssertTrue(fitting.width.isFinite && fitting.height.isFinite)
            XCTAssertLessThanOrEqual(fitting.width, width + 0.5,
                                     "\(state.name): controls must not demand a wider panel")
            XCTAssertGreaterThan(fitting.height, 80)
            XCTAssertLessThan(fitting.height, largest ? 900 : 400,
                              "\(state.name): the full control group must remain bounded")

            // A visible gutter lets the pixel check catch drawing outside the
            // proposed panel width, beyond a small native button-shadow margin.
            let gutter: CGFloat = 16
            let canvas = CGSize(width: width + gutter * 2, height: ceil(fitting.height) + gutter * 2)
            let view = content.frame(width: width, alignment: .topLeading)
                .padding(gutter)
                .background(Color(red: 0.04, green: 0.06, blue: 0.08))
            let host = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(origin: .zero, size: canvas))
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            host.view.frame = window.bounds
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: canvas).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            XCTAssertEqual(image.size.width, canvas.width, accuracy: 0.5)
            XCTAssertEqual(image.size.height, canvas.height, accuracy: 0.5)
            let pixels = try pixelMetrics(image, outerGutterPoints: gutter / 2)
            XCTAssertGreaterThan(pixels.bright, 500, "A blank capture is not layout evidence")
            XCTAssertEqual(pixels.overflow, 0,
                           "\(state.name): control content overflows the proposed panel width")
            XCTAssertTrue(invokedActions.isEmpty, "Rendering controls must never start a scan or move the pitch")

            let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
            attachment.name = "ReplayXI-SurfaceControls169-\(label)-\(state.name).png"
            attachment.lifetime = .keepAlways
            add(attachment)
            metrics.append([
                "state": state.name,
                "panelWidthPoints": width,
                "controlsWidthPoints": width - 22,
                "fittingWidthPoints": fitting.width,
                "fittingHeightPoints": fitting.height,
                "captureSizePoints": [canvas.width, canvas.height],
                "brightPixels": pixels.bright,
                "horizontalOverflowPixels": pixels.overflow,
                "busy": state.busy,
                "scanning": state.scanning,
                "hasPlacement": state.placed,
                "status": state.status
            ])
        }
        let report: [String: Any] = [
            "scope": "Native layout snapshots only. Fitting width and overflow are checked; PNGs remain the evidence for text truncation and button readability.",
            "dynamicType": largest ? "accessibility5" : "large",
            "states": metrics
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-SurfaceControls169-\(label)-layout.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pixelMetrics(_ image: UIImage, outerGutterPoints: CGFloat) throws
        -> (bright: Int, overflow: Int) {
        let source = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
                width: source.width, height: source.height, bitsPerComponent: 8,
                bytesPerRow: source.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        }
        let gutterPixels = Int(outerGutterPoints * CGFloat(source.width) / image.size.width)
        var bright = 0, overflow = 0
        for y in 0..<source.height {
            for x in 0..<source.width {
                let index = (y * source.width + x) * 4
                if max(bytes[index], max(bytes[index + 1], bytes[index + 2])) > 100 {
                    bright += 1
                    if x < gutterPixels || x >= source.width - gutterPixels { overflow += 1 }
                }
            }
        }
        return (bright, overflow)
    }
}
