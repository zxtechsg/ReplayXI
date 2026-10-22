import SceneKit
import XCTest
@testable import ReplayXICoachMac

@MainActor
final class CoachSceneWork183Tests: XCTestCase {
    func testHiddenHistoryOwnsNoSceneNodesAndReverseSeekRestoresCurrentPose() throws {
        let cache = CoachSceneMarkCache()
        let parent = SCNNode()
        var marks = (0..<128).map { _ in mark(kind: "pass", start: 10, end: 20) }
        cache.update(marks, selectedID: nil, editable: true, time: 0, parent: parent)
        XCTAssertEqual(cache.count, 0)
        XCTAssertTrue(parent.childNodes.isEmpty)
        cache.update(marks, selectedID: marks[0].id, editable: true, time: 0, parent: parent)
        XCTAssertEqual(cache.count, 1, "A hidden selection still needs its editing handles")
        XCTAssertEqual(try XCTUnwrap(cache[marks[0].id]).root.opacity, 0.25)
        cache.update(marks, selectedID: nil, editable: true, time: 15, parent: parent)
        XCTAssertEqual(cache.count, 128)
        XCTAssertTrue(marks.allSatisfy { cache[$0.id]?.segmentCount == 1 })
        cache.update(marks, selectedID: nil, editable: true, time: 25, parent: parent)
        XCTAssertEqual(cache.count, 0)
        XCTAssertTrue(parent.childNodes.isEmpty)
        marks[0].end = .init(x: 12, z: 15)
        cache.update(marks, selectedID: marks[0].id, editable: true, time: 15, parent: parent)
        let tip = try XCTUnwrap(cache[marks[0].id]?.root.childNodes.first { $0.geometry is SCNCone })
        XCTAssertEqual(tip.simdPosition, [12, 0.12, 15])
    }

    func testPathGeometryScalesWithKindAndIsReusedUntilKindChanges() throws {
        let node = CoachSceneMark()
        var model = mark(kind: "pass")
        node.update(model, selected: true, editable: true, visible: true)
        XCTAssertEqual(node.segmentCount, 1)
        let original = try XCTUnwrap(node.root.childNode(withName: "path-segment-0", recursively: false))
        node.update(model, selected: false, editable: true, visible: true)
        XCTAssertTrue(node.root.childNodes.contains { $0 === original })
        model.kind = "arc"
        model.controlPoint = .init(x: 2, y: 5, z: 1)
        node.update(model, selected: true, editable: true, visible: true)
        XCTAssertEqual(node.segmentCount, 32, "Keep the existing curve resolution")
        model.kind = "space"
        node.update(model, selected: true, editable: true, visible: true)
        XCTAssertEqual(node.segmentCount, 0)
        XCTAssertNil(original.parent)
        model.kind = "playerLabel"
        node.update(model, selected: true, editable: true, visible: true)
        XCTAssertEqual(node.segmentCount, 0)
    }

    func testSpaceMatchesAuthoredCentreAndCircularRadius() throws {
        let node = CoachSceneMark()
        var model = mark(kind: "space")
        model.start = .init(x: -4, z: 6)
        model.end = .init(x: -1, z: 10)
        node.update(model, selected: false, editable: true, visible: true)
        let ring = try XCTUnwrap(node.root.childNodes.first { $0.geometry is SCNTorus })
        XCTAssertEqual(ring.simdPosition, [-4, 0.12, 6])
        XCTAssertEqual(ring.simdScale, [5, 1, 5])
    }

    func testDeletingTheSelectedMarkRemovesItsGeometry() {
        let cache = CoachSceneMarkCache()
        let parent = SCNNode()
        let model = mark(kind: "arc")
        cache.update([model], selectedID: model.id, editable: true, time: 0, parent: parent)
        cache.update([], selectedID: model.id, editable: true, time: 0, parent: parent)
        XCTAssertEqual(cache.count, 0)
        XCTAssertTrue(parent.childNodes.isEmpty)
    }

    func testZoneMapUsesTheSameCentreAndRadiusAsTheScene() {
        let bounds = CoachWorkspace.zoneBounds(centre: .init(x: 100, y: 200),
            edge: .init(x: 130, y: 240), minimumRadius: 5)
        XCTAssertEqual(bounds, CGRect(x: 50, y: 150, width: 100, height: 100))
        XCTAssertEqual(CoachWorkspace.zoneRadius(start: .init(x: 0, z: 0),
            end: .init(x: 0, z: 0)), 1.1)
    }

    func testReusedPlayerIDRefreshesNumberAndTeamWithoutReplacingGeometry() throws {
        let node = CoachScenePlayer()
        var player = ReplayXIWirePlayer(id: "shared-id", name: "One", number: 7,
            team: "home", position: .init(x: 1, z: 2), facingDegrees: 90)
        node.update(player)
        let label = try XCTUnwrap(node.root.childNodes.compactMap { $0.geometry as? SCNText }.first)
        let body = try XCTUnwrap(node.root.childNodes.first { $0.geometry is SCNCapsule })
        XCTAssertEqual(label.string as? String, "7")
        XCTAssertEqual(body.geometry?.firstMaterial?.diffuse.contents as? NSColor, .systemBlue)
        player.number = 19
        player.team = "away"
        player.position = .init(x: -3, z: 8)
        player.facingDegrees = 0
        node.update(player)
        XCTAssertEqual(label.string as? String, "19")
        XCTAssertEqual(body.geometry?.firstMaterial?.diffuse.contents as? NSColor, .systemRed)
        XCTAssertEqual(node.root.simdPosition, [-3, 0, 8])
        XCTAssertEqual(node.root.eulerAngles.y, 0)
        XCTAssertTrue(node.root.childNodes.contains { $0 === body })
        node.update(player)
        XCTAssertEqual(label.string as? String, "19")
    }

    private func mark(kind: String, start: Double = 0, end: Double? = nil) -> ReplayXIWireMark {
        .init(id: UUID(), kind: kind, start: .init(x: 0, z: 0), end: .init(x: 4, z: 4),
            startHeight: 0, endHeight: 0, label: "Test", showAt: start, hideAt: end,
            keyframes: [], authored: false, controlPoint: nil, encodedMark: Data())
    }
}
