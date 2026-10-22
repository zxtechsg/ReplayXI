import SceneKit
import XCTest
@testable import ReplayXICoachMac

@MainActor
final class CoachSceneReview184Tests: XCTestCase {
    func testFramingKeepsTheWholeCircularZoneInsideWideAndNarrowViews() {
        var zone = mark(kind: "space")
        zone.start = .init(x: -12, z: 8)
        zone.end = .init(x: 18, z: 8)
        for size in [CGSize(width: 1000, height: 600), CGSize(width: 400, height: 700)] {
            let frame = CoachSceneGeometry.annotationFrame(zone, size: size, fieldOfView: 60)
            XCTAssertEqual(frame.target.x, zone.start.x)
            XCTAssertEqual(frame.target.z, zone.start.z)
            // Include the torus's outer edge, not just its centreline.
            for index in 0..<72 {
                let angle = Float(index) * .pi / 36
                let point = SIMD3<Float>(-12 + 33 * cos(angle), 0.12, 8 + 33 * sin(angle))
                assertInside(point, frame: frame, size: size)
            }
        }
    }

    func testFramingAlsoContainsAnElevatedArcAndItsControlHandle() {
        var arc = mark(kind: "arc")
        arc.controlPoint = .init(x: -24, y: 12, z: 30)
        arc.startHeight = 2
        arc.endHeight = 4
        let size = CGSize(width: 400, height: 700)
        let frame = CoachSceneGeometry.annotationFrame(arc, size: size, fieldOfView: 60)
        let a = SIMD3<Float>(arc.start.x, arc.startHeight, arc.start.z)
        let b = SIMD3<Float>(arc.end.x, arc.endHeight, arc.end.z)
        let c = SIMD3<Float>(-24, 12, 30)
        for index in 0...32 {
            assertInside(CoachSceneGeometry.arcPoint(from: a, to: b, control: c,
                t: Float(index) / 32), frame: frame, size: size)
        }
        assertInside(c, frame: frame, size: size)
    }

    func testFramingALargeZoneExtendsTheFarClipPlane() {
        var zone = mark(kind: "space")
        zone.start = .init(x: -34, z: -52.5)
        zone.end = .init(x: 34, z: 52.5)
        let size = CGSize(width: 400, height: 700)
        let frame = CoachSceneGeometry.annotationFrame(zone, size: size, fieldOfView: 60)
        XCTAssertGreaterThan(frame.farPlane, 500)
        let radius = hypot(Float(68), Float(105)) * 1.1
        for index in 0..<72 {
            let angle = Float(index) * .pi / 36
            assertInside([-34 + radius * cos(angle), 0.12, -52.5 + radius * sin(angle)],
                frame: frame, size: size)
        }
    }

    func testNonvisualWireChangesDoNotRewriteGeometry() {
        let node = CoachSceneMark()
        var model = mark(kind: "pass")
        node.update(model, selected: false, editable: true, visible: true)
        let count = node.geometryUpdateCount
        model.showAt = 1
        model.hideAt = 9
        model.keyframes = [1, 3, 8]
        model.encodedMark = Data(repeating: 42, count: 16_384)
        model.startPlayerID = "runner"
        node.update(model, selected: false, editable: true, visible: true)
        XCTAssertEqual(node.geometryUpdateCount, count)
        model.end = .init(x: 20, z: 30)
        node.update(model, selected: false, editable: true, visible: true)
        XCTAssertEqual(node.geometryUpdateCount, count + 1)
        let tip = node.root.childNodes.first { $0.geometry is SCNCone }
        XCTAssertEqual(tip?.simdPosition, [20, 0.12, 30])
        node.update(model, selected: true, editable: true, visible: false)
        XCTAssertEqual(node.geometryUpdateCount, count + 2)
        XCTAssertEqual(node.root.opacity, 0.25)
    }

    private func assertInside(_ point: SIMD3<Float>,
                              frame: CoachSceneGeometry.AnnotationFrame, size: CGSize,
                              file: StaticString = #filePath, line: UInt = #line) {
        let forward = simd_normalize(frame.target - frame.position)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        let offset = point - frame.position
        let depth = simd_dot(offset, forward)
        XCTAssertGreaterThan(depth, 0, file: file, line: line)
        XCTAssertLessThan(Double(depth), frame.farPlane, file: file, line: line)
        let vertical = tan(Float.pi / 6)
        XCTAssertLessThan(abs(simd_dot(offset, right)) / depth,
            vertical * Float(size.width / size.height), file: file, line: line)
        XCTAssertLessThan(abs(simd_dot(offset, up)) / depth, vertical, file: file, line: line)
    }

    private func mark(kind: String) -> ReplayXIWireMark {
        .init(id: UUID(), kind: kind, start: .init(x: -5, z: -10), end: .init(x: 10, z: 20),
            startHeight: 0, endHeight: 0, label: "Test", showAt: 0, hideAt: nil,
            keyframes: [], authored: false, controlPoint: nil, encodedMark: Data())
    }
}
