import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayFlatPitch169Tests: XCTestCase {
    func testTacticalTableKeepsPitchAndDrawingPlaneHorizontal169() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        update(root, scenario: scenario, mode: .tacticalTable)

        assertHorizontal(root)
        let drawingSurface = try XCTUnwrap(root.findEntity(named: "annotation-surface"))
        let origin = drawingSurface.convert(position: .zero, to: nil)
        for corner: SIMD3<Float> in [[-34, 0, -52.5], [34, 0, -52.5],
                                    [34, 0, 52.5], [-34, 0, 52.5]] {
            XCTAssertEqual(drawingSurface.convert(position: corner, to: nil).y, origin.y,
                           accuracy: 0.000_01, "Drawing targets must lie on the flat pitch plane")
        }
    }

    func testReturningFromPOVAndTouchlineRestoresFlatPitchFrame169() throws {
        let scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario)
        let mark = CoachMark(kind: .run, start: PitchPoint(x: -20, z: -25),
                             end: PitchPoint(x: 17, z: 31), label: "Flat pitch run", revealTime: 0)
        update(root, scenario: scenario, mode: .tacticalTable, marks: [mark])
        let tableTransform = root.transform
        let markRoot = try XCTUnwrap(root.findEntity(named: "mark-\(mark.id.uuidString)"))
        let rail = try XCTUnwrap(markRoot.findEntity(named: "annotation-mark-segment-0"))
        let drawingSurface = try XCTUnwrap(root.findEntity(named: "annotation-surface"))
        let localRailPosition = rail.position(relativeTo: root)
        let tableRailPosition = rail.position(relativeTo: nil)
        let surfaceTransform = drawingSurface.transform
        XCTAssertEqual(localRailPosition.x, (mark.start.x + mark.end.x) / 2, accuracy: 0.000_1)
        XCTAssertEqual(localRailPosition.z, (mark.start.z + mark.end.z) / 2, accuracy: 0.000_1)

        for mode in [ReplayViewMode.firstPerson, .touchline, .firstPerson] {
            update(root, scenario: scenario, mode: mode, marks: [mark])
            assertVector(rail.position(relativeTo: root), equals: localRailPosition)
            assertVector(rail.position(relativeTo: nil),
                         equals: root.convert(position: localRailPosition, to: nil))
            XCTAssertEqual(drawingSurface.transform, surfaceTransform,
                           "Changing views must keep the drawing plane in pitch coordinates")

            update(root, scenario: scenario, mode: .tacticalTable, marks: [mark])
            assertHorizontal(root)
            XCTAssertEqual(root.transform, tableTransform)
            XCTAssertTrue(rail === markRoot.findEntity(named: "annotation-mark-segment-0"))
            XCTAssertTrue(drawingSurface === root.findEntity(named: "annotation-surface"))
            assertVector(rail.position(relativeTo: nil), equals: tableRailPosition)
            assertVector(root.convert(position: tableRailPosition, from: nil), equals: localRailPosition)
        }
    }

    private func assertHorizontal(_ root: Entity, file: StaticString = #filePath, line: UInt = #line) {
        assertVector(root.orientation.act([0, 1, 0]), equals: [0, 1, 0], file: file, line: line)
        let centre = root.convert(position: .zero, to: nil)
        for corner: SIMD3<Float> in [[-34, 0, -52.5], [34, 0, -52.5],
                                    [34, 0, 52.5], [-34, 0, 52.5]] {
            XCTAssertEqual(root.convert(position: corner, to: nil).y, centre.y,
                           accuracy: 0.000_01, file: file, line: line)
        }
    }

    private func assertVector(_ actual: SIMD3<Float>, equals expected: SIMD3<Float>,
                              file: StaticString = #filePath, line: UInt = #line) {
        for axis in 0..<3 {
            XCTAssertEqual(actual[axis], expected[axis], accuracy: 0.000_1, file: file, line: line)
        }
    }

    private func update(_ root: Entity, scenario: ReplayScenario, mode: ReplayViewMode,
                        marks: [CoachMark] = []) {
        PitchSceneFactory.update(root: root, scenario: scenario, time: 8, viewMode: mode,
                                 perspectiveID: scenario.defaultPerspectiveID, marks: marks,
                                 showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil)
    }
}
