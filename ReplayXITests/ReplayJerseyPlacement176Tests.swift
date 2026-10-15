import RealityKit
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayJerseyPlacement176Tests: XCTestCase {
    private struct Ink {
        let samples: [SIMD2<Float>]
        let aspect: Float
    }

    private struct Coverage {
        let points: [SIMD3<Float>]
        let sourceHoles: Int
    }

    override func tearDown() {
        ReplayTripoAthleteProvider.resetForTesting()
        super.tearDown()
    }

    func testOpaqueJerseyInkIsCentredBelowCollarOnBothBodiesAndDetails() throws {
        ReplayTripoAthleteProvider.resetForTesting()
        try ReplayTripoAthleteProvider.prewarm()
        let source = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay)?.player(id: "navy-rw"))
        var rows: [[String: Any]] = []
        for number in [1, 3, 7, 11, 26] {
            let ink = try opaqueInk(number: number)
            let track = PlayerTrack(id: "jersey-placement-\(number)", displayName: "Jersey audit",
                role: source.role, shirtNumber: number, team: source.team,
                isGoalkeeper: false, keyframes: source.keyframes)
            for diverse in [false, true] {
                for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                    let skin = try diverse
                        ? ReplayTripoAthleteProvider.makeDiverse(for: track, detail: detail)
                        : ReplayTripoAthleteProvider.make(for: track, detail: detail)
                    XCTAssertTrue(skin.numbersUseShirtSkin)
                    let rest = skin.motion.restPose.modelSpaceTransforms
                    let neck = rest[try XCTUnwrap(skin.motion.semanticJointIndices["neck"])].columns.3
                    let hips = rest[try XCTUnwrap(skin.motion.semanticJointIndices["hips"])].columns.3
                    for isFront in [true, false] {
                        let context = "\(diverse ? "A" : "B") \(detail) #\(number) \(isFront ? "front" : "back")"
                        let coverage = try restInkCoverage(ink.samples,
                            entity: isFront ? skin.front : skin.back, body: skin.model,
                            isFront: isFront, context: context)
                        let points = coverage.points
                        XCTAssertEqual(points.count + coverage.sourceHoles, ink.samples.count,
                            "Every available shirt surface must carry its ink: \(context)")
                        // The pinned Player A mesh has small genuine holes;
                        // direct USD/native triangle checks found up to 5.1%
                        // of these opaque samples lack cloth, mostly at low LOD.
                        XCTAssertGreaterThanOrEqual(Float(points.count) / Float(ink.samples.count), 0.94,
                            "Source holes must not consume more jersey ink: \(context)")
                        let minX = try XCTUnwrap(points.map(\.x).min())
                        let maxX = try XCTUnwrap(points.map(\.x).max())
                        let minY = try XCTUnwrap(points.map(\.y).min())
                        let maxY = try XCTUnwrap(points.map(\.y).max())
                        // Inspect actual opaque pixels on admitted cloth, not
                        // transparent mesh bounds or production anchor math.
                        XCTAssertEqual((minX + maxX) * 0.5, hips.x, accuracy: 0.008,
                            "The numeral must sit on the torso centre: \(context)")
                        XCTAssertLessThan(maxY, neck.y - 0.06,
                            "Ink must clear the collar: \(context)")
                        XCTAssertGreaterThan(minY, hips.y + 0.12,
                            "Ink must remain above the waist: \(context)")
                        XCTAssertEqual((maxX - minX) / (maxY - minY), ink.aspect, accuracy: 0.025,
                            "Projection must preserve the font's aspect: \(context)")
                        if number == 1 {
                            XCTAssertGreaterThan(maxX - minX, isFront ? 0.025 : 0.05,
                                "#1 must not collapse into a thin segment strip: \(context)")
                        }
                        rows.append(["body": diverse ? "A" : "B", "number": number,
                            "detail": detail == .near ? "near" : "low",
                            "side": isFront ? "front" : "back", "samples": points.count,
                            "sourceHoles": coverage.sourceHoles,
                            "inkMin": [minX, minY], "inkMax": [maxX, maxY],
                            "collarHeight": neck.y, "waistHeight": hips.y])
                    }
                }
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows,
            options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-JerseyPlacement176.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func opaqueInk(number: Int) throws -> Ink {
        let digit = try ReplayAthleteMeshLibrary.jerseyNumber(number).mesh
        let image = try ReplayTripoAthleteProvider.numberMaskImage(number: number, digit: digit)
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        var samples: [SIMD2<Float>] = []
        var extremes = [(x: 256, y: 256), (x: -1, y: -1), (x: 256, y: 256), (x: -1, y: -1)]
        func uv(_ x: Int, _ y: Int) -> SIMD2<Float> {
            [(Float(x) + 0.5) / Float(image.width), 1 - (Float(y) + 0.5) / Float(image.height)]
        }
        for y in 0..<image.height {
            for x in 0..<image.width where bytes[y * image.bytesPerRow + x * 4 + 3] > 230 {
                if x % 8 == 0, y % 8 == 0 { samples.append(uv(x, y)) }
                if x < extremes[0].x { extremes[0] = (x, y) }
                if x > extremes[1].x { extremes[1] = (x, y) }
                if y < extremes[2].y { extremes[2] = (x, y) }
                if y > extremes[3].y { extremes[3] = (x, y) }
            }
        }
        XCTAssertGreaterThan(samples.count, 16)
        samples.append(contentsOf: extremes.map { uv($0.x, $0.y) })
        return Ink(samples: samples, aspect: Float(extremes[1].x - extremes[0].x)
            / Float(extremes[3].y - extremes[2].y))
    }

    private func restInkCoverage(_ samples: [SIMD2<Float>], entity: ModelEntity,
                                body: ModelEntity, isFront: Bool, context: String) throws -> Coverage {
        let part = try XCTUnwrap(entity.model?.mesh.contents.models.first?.parts.first)
        let positions = part.positions.elements
        let uv = try XCTUnwrap(part.textureCoordinates).elements
        let indices = try XCTUnwrap(part.triangleIndices).elements
        let side: Float = isFront ? 1 : -1
        var sourceHoles = 0
        let points = try samples.compactMap { target -> SIMD3<Float>? in
            var selected: SIMD3<Float>?
            var projected: (point: SIMD3<Float>, area: Float)?
            for start in stride(from: 0, to: indices.count, by: 3) {
                let ia = Int(indices[start]), ib = Int(indices[start + 1]), ic = Int(indices[start + 2])
                let a = uv[ia], b = uv[ib], c = uv[ic]
                let denominator = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
                guard abs(denominator) > 0.000_000_1 else { continue }
                let wa = ((b.y - c.y) * (target.x - c.x) + (c.x - b.x) * (target.y - c.y)) / denominator
                let wb = ((c.y - a.y) * (target.x - c.x) + (a.x - c.x) * (target.y - c.y)) / denominator
                let wc = 1 - wa - wb
                let point = positions[ia] * wa + positions[ib] * wb + positions[ic] * wc
                // XY projection is affine over the canvas. A large triangle
                // gives a stable target even when a source cloth hole leaves
                // this UV outside every copied triangle.
                if projected == nil || abs(denominator) > projected!.area {
                    projected = (point, abs(denominator))
                }
                guard min(wa, wb, wc) >= -0.000_1 else { continue }
                if selected == nil || side * point.z > side * selected!.z { selected = point }
            }
            if selected == nil {
                let target = try XCTUnwrap(projected).point
                let hasCloth = try hasOutwardBodyTriangle(at: [target.x, target.y],
                    body: body, side: side)
                XCTAssertFalse(hasCloth, "Decal omitted an existing shirt surface: \(context), \(target)")
                if !hasCloth { sourceHoles += 1 }
            }
            return selected
        }
        return Coverage(points: points, sourceHoles: sourceHoles)
    }

    private func hasOutwardBodyTriangle(at target: SIMD2<Float>, body: ModelEntity,
                                        side: Float) throws -> Bool {
        let part = try XCTUnwrap(body.model?.mesh.contents.models.first?.parts.first)
        let positions = part.positions.elements
        let indices = try XCTUnwrap(part.triangleIndices).elements
        for start in stride(from: 0, to: indices.count, by: 3) {
            let a = positions[Int(indices[start])], b = positions[Int(indices[start + 1])]
            let c = positions[Int(indices[start + 2])]
            let denominator = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
            guard abs(denominator) > 0.000_000_1 else { continue }
            let wa = ((b.y - c.y) * (target.x - c.x) + (c.x - b.x) * (target.y - c.y)) / denominator
            let wb = ((c.y - a.y) * (target.x - c.x) + (a.x - c.x) * (target.y - c.y)) / denominator
            let wc = 1 - wa - wb
            if min(wa, wb, wc) >= -0.000_1, side * (a.z * wa + b.z * wb + c.z * wc) > 0 {
                return true
            }
        }
        return false
    }
}
