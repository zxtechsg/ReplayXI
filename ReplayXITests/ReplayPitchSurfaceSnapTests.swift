import Foundation
import simd
import XCTest
@testable import ReplayXI

final class ReplayPitchSurfaceSnapTests: XCTestCase {
    private func rectangle(_ min: SIMD2<Float>, _ max: SIMD2<Float>) -> [ReplayPitchSurfaceSnap.Triangle] {
        [.init(a: min, b: [max.x, min.y], c: max),
         .init(a: min, b: max, c: [min.x, max.y])]
    }

    private func surface(id: UUID = UUID(), kind: ReplayPitchSurfaceSnap.Kind = .table,
                         centre: SIMD3<Float> = [0, 0.75, -1.5], extent: SIMD2<Float> = [3, 4],
                         yaw: Float = 0, triangles: [ReplayPitchSurfaceSnap.Triangle]? = nil) -> ReplayPitchSurfaceSnap.Surface {
        var transform = simd_float4x4(simd_quatf(angle: yaw, axis: [0, 1, 0]))
        transform.columns.3 = SIMD4(centre, 1)
        return .init(id: id, kind: kind, worldFromExtent: transform, extent: extent,
                     triangles: triangles ?? rectangle(-extent * 0.5, extent * 0.5))
    }

    func testWholeBoardRimFitsLevelAndUndersideClearsMeasuredSurface() throws {
        let table = surface()
        let placement = try XCTUnwrap(ReplayPitchSurfaceSnap.placement(on: [table], near: [0, 0.92, -1.5], yawRadians: 0))
        XCTAssertEqual(ReplayPitchSurfaceSnap.defaultFootprint.x, 1.8666, accuracy: 0.000001)
        XCTAssertEqual(ReplayPitchSurfaceSnap.defaultFootprint.y, 2.8611, accuracy: 0.000001)
        XCTAssertEqual(placement.surfaceID, table.id)
        XCTAssertEqual(placement.surfaceKind, .table)
        XCTAssertEqual(placement.scaleFactor, 1)
        XCTAssertEqual(placement.worldTransform.columns.1, SIMD4<Float>(0, 1, 0, 0))
        XCTAssertEqual(placement.worldTransform.columns.3.y - 0.56 * 0.0255, 0.752, accuracy: 0.000001)
        XCTAssertEqual(placement.surfaceWorldPosition.y, 0.75)
    }

    func testSmallTableScalesUniformlyAndRotatedBoardCannotOverhang() throws {
        let table = surface(extent: [1.15, 1.8], yaw: 0.37)
        for yaw in stride(from: -Float.pi, through: Float.pi, by: 0.15) {
            let placement = try XCTUnwrap(ReplayPitchSurfaceSnap.placement(on: [table],
                near: [0.9, 0.9, -1.0], yawRadians: yaw))
            XCTAssertLessThan(placement.scaleFactor, 1)
            XCTAssertGreaterThanOrEqual(placement.scaleFactor, 0.25)
            let half = ReplayPitchSurfaceSnap.defaultFootprint * placement.scaleFactor * 0.5
            for x: Float in [-1, 1] {
                for z: Float in [-1, 1] {
                    let corner = table.worldFromExtent.inverse * placement.worldTransform * SIMD4<Float>(x * half.x, 0, z * half.y, 1)
                    XCTAssertLessThan(abs(corner.x), table.extent.x * 0.5 - 0.014)
                    XCTAssertLessThan(abs(corner.z), table.extent.y * 0.5 - 0.014)
                }
            }
            XCTAssertLessThan(simd_distance(placement.worldTransform.columns.1, SIMD4<Float>(0, 1, 0, 0)), 0.000001)
        }
    }

    func testEdgesClampButMeshHolesNeverCountAsSupportedArea() throws {
        let table = surface(centre: .zero, extent: [4, 4])
        let edge = try XCTUnwrap(ReplayPitchSurfaceSnap.placement(on: [table], near: [2, 0, 0],
            yawRadians: 0, footprint: [1, 1], bottomOffset: 0))
        XCTAssertEqual(edge.surfaceWorldPosition.x, 1.485, accuracy: 0.000001)
        let ring = rectangle([-2, -2], [-0.7, 2]) + rectangle([0.7, -2], [2, 2])
            + rectangle([-0.7, -2], [0.7, -0.7]) + rectangle([-0.7, 0.7], [0.7, 2])
        let hole = surface(centre: .zero, extent: [4, 4], triangles: ring)
        XCTAssertNil(ReplayPitchSurfaceSnap.placement(on: [hole], near: .zero, yawRadians: 0,
            footprint: [1, 1], bottomOffset: 0), "A bounding extent does not prove mesh support inside a hole")
        let halfSurface = surface(centre: .zero, extent: [4, 4], triangles: [
            .init(a: [-2, -2], b: [2, -2], c: [-2, 2])
        ])
        XCTAssertNil(ReplayPitchSurfaceSnap.placement(on: [halfSurface], near: .zero, yawRadians: 0,
            footprint: [1, 1], minimumScaleFactor: 1), "Cut corners must reject unsupported board area")
    }

    func testNearestValidSurfaceAndExplicitChoiceKeepSourceIdentity() throws {
        let floor = surface(kind: .floor, centre: [0, 0, -1.5], extent: [5, 5])
        let table = surface()
        let near: SIMD3<Float> = [0, 0.9, -1.5]
        let nearest = try XCTUnwrap(ReplayPitchSurfaceSnap.placement(on: [floor, table], near: near, yawRadians: 0))
        XCTAssertEqual(nearest.surfaceID, table.id)
        let selected = try XCTUnwrap(ReplayPitchSurfaceSnap.placement(on: [table, floor], near: near,
            yawRadians: 0, preferredSurfaceID: floor.id))
        XCTAssertEqual(selected.surfaceID, floor.id)
        XCTAssertEqual(selected.surfaceKind, .floor)
        XCTAssertNil(ReplayPitchSurfaceSnap.placement(on: [table], near: near, yawRadians: 0,
            preferredSurfaceID: floor.id), "Removed or stale IDs cannot switch silently to a different surface")
        XCTAssertEqual(ReplayPitchSurfaceSnap.placement(on: [table, floor], near: near, yawRadians: 0), nearest)
    }

    func testInvalidDistantTinyOrVerticalSurfacesFailWithoutInventingFloor() {
        XCTAssertNil(ReplayPitchSurfaceSnap.placement(on: [], near: .zero, yawRadians: 0))
        XCTAssertNil(ReplayPitchSurfaceSnap.placement(on: [surface()], near: [.nan, 0, 0], yawRadians: 0))
        XCTAssertNil(ReplayPitchSurfaceSnap.placement(on: [surface()], near: .zero, yawRadians: .infinity))
        XCTAssertNil(ReplayPitchSurfaceSnap.placement(on: [surface(centre: [10, 0, 10])], near: .zero, yawRadians: 0))
        XCTAssertNil(ReplayPitchSurfaceSnap.placement(on: [surface(extent: [0.1, 0.1])], near: .zero, yawRadians: 0))
        XCTAssertNil(ReplayPitchSurfaceSnap.placement(on: [surface(triangles: [])], near: .zero, yawRadians: 0))
        let good = surface(centre: .zero)
        let wall = ReplayPitchSurfaceSnap.Surface(id: good.id, kind: .surface,
            worldFromExtent: simd_float4x4(simd_quatf(angle: .pi / 2, axis: [1, 0, 0])),
            extent: good.extent, triangles: good.triangles)
        XCTAssertNil(ReplayPitchSurfaceSnap.placement(on: [wall], near: .zero, yawRadians: 0))
    }
}
