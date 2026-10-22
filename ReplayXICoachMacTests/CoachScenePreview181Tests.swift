import XCTest
import SceneKit
import simd
@testable import ReplayXICoachMac

final class CoachScenePreview181Tests: XCTestCase {
    @MainActor
    func testFramedCircularZoneSnapshotsAtWideAndNarrowSizes() throws {
        var state = fixtureState(revision: 7)
        let id = UUID()
        state.marks = [.init(id: id, kind: "space", start: .init(x: 0, z: 0), end: .init(x: 30, z: 0),
            startHeight: 0, endHeight: 0, label: "Press area", showAt: 0, hideAt: nil,
            keyframes: [], authored: false, controlPoint: nil, encodedMark: Data())]
        for width in [1000, 400] {
            let size = CGSize(width: width, height: 700)
            let view = CoachSceneView(frame: NSRect(origin: .zero, size: size))
            view.update(.init(state: state, selectedMarkID: id, drawingEnabled: false, drawStart: nil,
                resetRevision: 0, playerView: false, focusRevision: 1, select: { _ in }, onPlayer: { _ in },
                onPitchClick: { _ in }, onPose: { _, _, _, _ in }))
            let camera = try XCTUnwrap(view.pointOfView)
            let frame = CoachSceneGeometry.annotationFrame(state.marks[0], size: size, fieldOfView: 60)
            XCTAssertEqual(camera.simdPosition, frame.position)
            XCTAssertEqual(camera.camera?.zFar, frame.farPlane)
            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = view.scene; renderer.pointOfView = camera
            renderer.autoenablesDefaultLighting = true
            let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "Coach-Zone184-\(width)x700.png"; attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testNative3DEditorSnapshot() throws {
        var state = fixtureState(revision: 7)
        let id = UUID()
        state.marks = [.init(id: id, kind: "arc", start: .init(x: -20, z: -25), end: .init(x: 10, z: 25),
            startHeight: 0.2, endHeight: 1.2, label: "Overlap", showAt: 0, hideAt: nil, keyframes: [0, 4],
            authored: false, controlPoint: .init(x: -25, y: 8, z: 6), encodedMark: Data())]
        state.players = (0..<22).map { index in
            .init(id: "p\(index)", name: "Player", number: index % 11 + 1, team: index < 11 ? "home" : "away",
                position: .init(x: Float(index % 4) * 15 - 24, z: Float(index / 4) * 15 - 42), facingDegrees: Float(index * 15))
        }
        let view = CoachSceneView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        view.update(.init(state: state, selectedMarkID: id, drawingEnabled: false, drawStart: nil,
            resetRevision: 0, playerView: false, select: { _ in }, onPlayer: { _ in },
            onPitchClick: { _ in }, onPose: { _, _, _, _ in }))
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = view.scene; renderer.pointOfView = view.pointOfView
        renderer.autoenablesDefaultLighting = true
        let image = renderer.snapshot(atTime: 0, with: .init(width: 1000, height: 700), antialiasingMode: .multisampling4X)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000)
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "Coach-3D-Editor181.png"; attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testArcSamplesKeepExactEndsAndControlHeight() {
        let start = SIMD3<Float>(-12, 0.5, -20)
        let end = SIMD3<Float>(16, 1.2, 24)
        let control = SIMD3<Float>(-5, 4, 6)
        let first = CoachSceneGeometry.arcPoint(from: start, to: end, control: control, t: 0)
        let middle = CoachSceneGeometry.arcPoint(from: start, to: end, control: control, t: 0.5)
        let last = CoachSceneGeometry.arcPoint(from: start, to: end, control: control, t: 1)
        XCTAssertEqual(first, start)
        XCTAssertEqual(last, end)
        XCTAssertEqual(middle.x, -1.5, accuracy: 0.0001)
        XCTAssertEqual(middle.y, 2.425, accuracy: 0.0001)
        XCTAssertEqual(middle.z, 4, accuracy: 0.0001)
    }

    func testPitchRingGeometryLiesInXZPlane() {
        let ring = CoachSceneGeometry.pitchRing(radius: 9.15, pipeRadius: 0.08)
        XCTAssertTrue(ring.geometry is SCNTorus)
        let (minimum, maximum) = ring.boundingBox
        XCTAssertGreaterThan(maximum.x - minimum.x, 18)
        XCTAssertGreaterThan(maximum.z - minimum.z, 18)
        XCTAssertLessThan(maximum.y - minimum.y, 0.2)
        XCTAssertEqual(ring.eulerAngles.x, 0, accuracy: 0.0001)
    }

    func testPlayerPOVUsesPitchHeadingConvention() {
        let point = ReplayXIWirePoint(x: 3, z: -8)
        let north = CoachSceneGeometry.headingTarget(position: point, facingDegrees: 0)
        let east = CoachSceneGeometry.headingTarget(position: point, facingDegrees: 90)
        let south = CoachSceneGeometry.headingTarget(position: point, facingDegrees: 180)
        XCTAssertEqual(north.x, 3, accuracy: 0.0001)
        XCTAssertEqual(north.z, 2, accuracy: 0.0001)
        XCTAssertEqual(east.x, 13, accuracy: 0.0001)
        XCTAssertEqual(east.z, -8, accuracy: 0.0001)
        XCTAssertEqual(south.z, -18, accuracy: 0.0001)
    }

    func testOverviewFrustumFitsAllPitchCornersAtFourByThree() {
        let camera = CoachSceneGeometry.overviewPosition
        let forward = simd_normalize(CoachSceneGeometry.overviewTarget - camera)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        let verticalLimit = tan(Float(CoachSceneGeometry.overviewFieldOfView) * .pi / 360)
        let horizontalLimit = verticalLimit * 4 / 3
        for x: Float in [-34, 34] {
            for z: Float in [-52.5, 52.5] {
                let offset = SIMD3<Float>(x, 0, z) - camera
                let depth = simd_dot(offset, forward)
                XCTAssertGreaterThan(depth, 0)
                XCTAssertLessThan(abs(simd_dot(offset, right)) / depth, horizontalLimit)
                XCTAssertLessThan(abs(simd_dot(offset, up)) / depth, verticalLimit)
            }
        }
    }

    func testDragCommitRequiresCurrentRevisionScenarioAndSelection() {
        let id = UUID()
        let state = fixtureState(revision: 7)
        XCTAssertTrue(CoachSceneGeometry.canCommit(dragRevision: 7, dragScenarioID: "match-a",
            markID: id, state: state, selectedMarkID: id))
        XCTAssertFalse(CoachSceneGeometry.canCommit(dragRevision: 6, dragScenarioID: "match-a",
            markID: id, state: state, selectedMarkID: id))
        XCTAssertFalse(CoachSceneGeometry.canCommit(dragRevision: 7, dragScenarioID: "match-b",
            markID: id, state: state, selectedMarkID: id))
        XCTAssertFalse(CoachSceneGeometry.canCommit(dragRevision: 7, dragScenarioID: "match-a",
            markID: id, state: state, selectedMarkID: UUID()))
        var locked = state
        locked.canEdit = false
        XCTAssertFalse(CoachSceneGeometry.canCommit(dragRevision: 7, dragScenarioID: "match-a",
            markID: id, state: locked, selectedMarkID: id))
    }

    func testRayPlaneIntersectionRejectsParallelBehindAndNonfinite() {
        let hit = CoachSceneGeometry.planeIntersection(near: [0, 10, 0], far: [10, -10, 20], height: 0)
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.x ?? .nan, 5, accuracy: 0.0001)
        XCTAssertEqual(hit?.y ?? .nan, 0, accuracy: 0.0001)
        XCTAssertEqual(hit?.z ?? .nan, 10, accuracy: 0.0001)
        XCTAssertNil(CoachSceneGeometry.planeIntersection(near: [0, 1, 0], far: [1, 1, 1], height: 0))
        XCTAssertNil(CoachSceneGeometry.planeIntersection(near: [0, 1, 0], far: [1, 2, 1], height: 0))
        XCTAssertNil(CoachSceneGeometry.planeIntersection(near: [0, 1, 0], far: [1, -1, 1], height: .nan))
        XCTAssertNil(CoachSceneGeometry.planeIntersection(near: [.infinity, 1, 0], far: [1, -1, 1], height: 0))
    }

    @MainActor
    func testSceneKitReferenceProjectionHitsPitchPoint() {
        // SCNView.projectPoint([12, 0, 20]) from this camera and viewport
        // gives (493.7999, 268.2071). This sample also covers macOS's
        // bottom-left view coordinate convention without a rendered NSView.
        let camera = makeCamera(position: CoachSceneGeometry.overviewPosition,
            target: CoachSceneGeometry.overviewTarget)
        let hit = CoachSceneGeometry.pitchPoint(
            screen: .init(x: 493.7999, y: 268.2071), size: .init(width: 1000, height: 700),
            camera: camera, fieldOfView: CoachSceneGeometry.overviewFieldOfView,
            height: 0)
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.x ?? .nan, 12, accuracy: 0.1)
        XCTAssertEqual(hit?.z ?? .nan, 20, accuracy: 0.1)
    }

    @MainActor
    func testPitchPickUsesLiveCameraOrientationAfterOrbit() {
        let camera = makeCamera(position: [25, 40, 70], target: .zero)
        let hit = CoachSceneGeometry.pitchPoint(screen: .init(x: 480, y: 360),
            size: .init(width: 960, height: 720), camera: camera,
            fieldOfView: CoachSceneGeometry.overviewFieldOfView, height: 0)
        XCTAssertEqual(hit?.x ?? .nan, 0, accuracy: 0.1)
        XCTAssertEqual(hit?.z ?? .nan, 0, accuracy: 0.1)
    }

    @MainActor
    private func makeCamera(position: SIMD3<Float>, target: SIMD3<Float>) -> SCNNode {
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = CoachSceneGeometry.overviewFieldOfView
        camera.simdPosition = position
        camera.look(at: .init(target.x, target.y, target.z),
            up: .init(0, 1, 0), localFront: .init(0, 0, -1))
        return camera
    }

    private func fixtureState(revision: UInt64) -> ReplayXIWireState {
        .init(revision: revision, scenarioID: "match-a", playhead: 0, playing: false, rate: 1,
            viewMode: "tactical", perspectiveID: "", duration: 60, scenarios: [], players: [],
            ball: .init(x: 0, y: 0, z: 0), marks: [], canUndo: false, canRedo: false,
            canSave: false, canEdit: true, status: "")
    }
}
