import RealityKit
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayTripoAthleteRuntimeTests: XCTestCase {
    private var maskSamplesByNumber: [Int: [SIMD2<Float>]] = [:]
    override func setUp() {
        super.setUp()
        ReplayTripoAthleteProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
    }

    override func tearDown() {
        ReplayTripoAthleteProvider.resetForTesting()
        ReplaySkinnedAthleteProvider.resetForTesting()
        super.tearDown()
    }

    private func player(_ id: String = "navy-rw") throws -> PlayerTrack {
        try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay)?.player(id: id))
    }

    private func locomotion(_ player: PlayerTrack, time: Double, speed: Float, turn: Float = 0)
        -> PlayerLocomotionSample {
        .init(motion: player.locomotion(at: time).motion, speedMetresPerSecond: speed,
              accelerationMetresPerSecondSquared: 0, turnRateDegreesPerSecond: turn,
              state: PlayerLocomotionSample.classify(speedMetresPerSecond: speed,
                                                    turnRateDegreesPerSecond: turn))
    }

    func testCPUJerseyMaskHasSolidInk() throws {
        let digit = try ReplayAthleteMeshLibrary.jerseyNumber(3).mesh
        let image = try ReplayTripoAthleteProvider.numberMaskImage(number: 3, digit: digit)
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = "ReplayXI-CPU-JerseyMask-3.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        var solid = 0, minX = 256, maxX = 0, minY = 256, maxY = 0
        for y in 0..<256 {
            for x in 0..<256 where bytes[y * image.bytesPerRow + x * 4 + 3] > 230 {
                solid += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThan(solid, 3_500, "The bold numeral needs a substantial solid interior")
        XCTAssertLessThan(solid, 30_000, "The background must remain mostly clear")
        XCTAssertGreaterThanOrEqual(max(maxX - minX, maxY - minY), 205,
            "Actual glyph ink should fill the shirt decal box, not only its font line box")
        XCTAssertGreaterThanOrEqual(minX, 8); XCTAssertLessThanOrEqual(maxX, 247)
        XCTAssertGreaterThanOrEqual(minY, 8); XCTAssertLessThanOrEqual(maxY, 247)
        XCTAssertEqual(bytes[3], 0, "The outside corner must remain transparent")
    }

    private func visibleNumberUVs(_ number: Int, digit: MeshResource) throws -> [SIMD2<Float>] {
        if let cached = maskSamplesByNumber[number] { return cached }
        let image = try ReplayTripoAthleteProvider.numberMaskImage(number: number, digit: digit)
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        var samples: [SIMD2<Float>] = []
        for y in stride(from: 12, to: 244, by: 12) {
            for x in stride(from: 12, to: 244, by: 12)
                where bytes[y * image.bytesPerRow + x * 4 + 3] > 230 {
                samples.append([(Float(x) + 0.5) / 256, 1 - (Float(y) + 0.5) / 256])
            }
        }
        XCTAssertGreaterThan(samples.count, 12, "Visible mask pixels must exist across the numeral")
        let step = max(samples.count / 24, 1)
        let selected = stride(from: 0, to: samples.count, by: step).map { samples[$0] }
        maskSamplesByNumber[number] = selected
        return selected
    }

    func testNativeShirtNumberDepthDiagnostic() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let source = try player()
        var rows: [[String: Any]] = []
        for geometry in ["base", "diverse"] {
            for number in [1, 7, 11, 26] {
                let track = PlayerTrack(id: "number-depth-\(geometry)-\(number)",
                    displayName: source.displayName, role: source.role, shirtNumber: number,
                    team: source.team, isGoalkeeper: false, keyframes: source.keyframes)
                for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                    let skin = try geometry == "diverse"
                        ? ReplayTripoAthleteProvider.makeDiverse(for: track, detail: detail)
                        : ReplayTripoAthleteProvider.make(for: track, detail: detail)
                    for time in [1.25, 13.6, 1.25] {
                        let speed: Float = time < 2 ? 0 : 3.6
                        XCTAssertTrue(skin.update(at: time, track: track,
                            locomotion: locomotion(track, time: time, speed: speed),
                            lookTarget: nil, ballAction: nil,
                            stationaryPose: speed == 0 ? track.presentationPose(at: time) : nil,
                            allowsOffBallPose: false))
                        for isFront in [true, false] {
                            XCTAssertTrue(skin.numbersUseShirtSkin,
                                "Missing skinned digit: \(geometry) #\(number) \(detail) \(isFront ? "front" : "back")")
                            guard skin.numbersUseShirtSkin else { continue }
                            let clearances = try numberClearances(skin, number: number, isFront: isFront)
                            XCTAssertGreaterThanOrEqual(clearances.count, 3)
                            XCTAssertGreaterThanOrEqual(clearances.min() ?? -1, 0.002)
                            XCTAssertLessThanOrEqual(clearances.max() ?? 1, 0.012)
                            rows.append(["geometry": geometry, "number": number,
                                "detail": detail == .near ? "near" : "low", "time": time,
                                "side": isFront ? "front" : "back", "witnesses": clearances.count,
                                "minimumClearanceMetres": clearances.min() ?? -1,
                                "maximumClearanceMetres": clearances.max() ?? -1])
                        }
                    }
                }
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows,
            options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-NumberDepth-Diagnostic.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Independent check from the imported triangle/weight buffer. The low
    /// mesh can have no shirt vertex inside a narrow #1, so vertex-only depth
    /// tests cannot verify that number's actual fabric surface.
    func testSparseNumberHasIndependentWeightedTriangleWitness() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let source = try player()
        var rows: [[String: Any]] = []
        for geometry in ["base", "diverse"] {
            let track = PlayerTrack(id: "triangle-number-\(geometry)", displayName: source.displayName,
                role: source.role, shirtNumber: 1, team: source.team,
                isGoalkeeper: false, keyframes: source.keyframes)
            for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
                let skin = try geometry == "diverse"
                    ? ReplayTripoAthleteProvider.makeDiverse(for: track, detail: detail)
                    : ReplayTripoAthleteProvider.make(for: track, detail: detail)
                for time in [1.25, 13.6] {
                    let speed: Float = time < 2 ? 0 : 3.6
                    XCTAssertTrue(skin.update(at: time, track: track,
                        locomotion: locomotion(track, time: time, speed: speed),
                        lookTarget: nil, ballAction: nil,
                        stationaryPose: speed == 0 ? track.presentationPose(at: time) : nil,
                        allowsOffBallPose: false))
                    for isFront in [true, false] {
                        XCTAssertTrue(skin.numbersUseShirtSkin,
                            "Missing skinned digit: \(geometry) #1 \(detail) \(isFront ? "front" : "back")")
                        guard skin.numbersUseShirtSkin else { continue }
                        let clearances = try numberClearances(skin, number: 1, isFront: isFront)
                        XCTAssertGreaterThanOrEqual(clearances.count, 3,
                            "Visible #1 ink samples need imported torso triangles")
                        XCTAssertGreaterThanOrEqual(clearances.min() ?? -1, 0.002)
                        XCTAssertLessThanOrEqual(clearances.max() ?? 1, 0.012)
                        rows.append(["geometry": geometry, "detail": detail == .near ? "near" : "low",
                            "time": time, "side": isFront ? "front" : "back",
                            "witnesses": clearances.count,
                            "minimumClearanceMetres": clearances.min() ?? -1,
                            "maximumClearanceMetres": clearances.max() ?? -1])
                    }
                }
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows,
            options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-IndependentNumberTriangle-Witness.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func numberClearances(_ skin: ReplaySkinnedAthleteInstance, number: Int,
                                  isFront: Bool) throws -> [Float] {
        let digit = isFront ? skin.front : skin.back
        let contents = try XCTUnwrap(digit.model).mesh.contents
        let part = try XCTUnwrap(contents.models.first?.parts.first)
        let skeleton = try XCTUnwrap(contents.skeletons.first)
        let weights = try XCTUnwrap(part.jointInfluences).influences.elements
        let indices = try XCTUnwrap(part.triangleIndices).elements
        let inkMesh = try ReplayAthleteMeshLibrary.jerseyNumber(number).mesh
        let visibleUVs = try visibleNumberUVs(number, digit: inkMesh)
        XCTAssertEqual(digit.jointTransforms, skin.model.jointTransforms)
        let chestIndex = skin.motion.numberAnchors.jointIndex
        let chest = skin.pose.modelSpaceTransforms[chestIndex]
        let rest = skin.motion.restPose.modelSpaceTransforms[chestIndex]
        let frontNormal = simd_quatf(chest).act(simd_quatf(rest).inverse.act([0, 0, 1]))
        let outward = isFront ? frontNormal : -frontNormal
        let positions = part.positions.elements
        let textureCoordinates = try XCTUnwrap(part.textureCoordinates).elements
        let side: Float = isFront ? 1 : -1
        var clearances: [Float] = []
        for uv in visibleUVs {
            // These UVs are opaque in the generated mask; transparent cloth
            // decal corners are not counted as visible-number evidence. Read
            // UV placement from the mesh, independently of its anchor formula.
            var selected: (corners: [Int], barycentric: SIMD3<Float>, point: SIMD3<Float>)?
            for decalBase in stride(from: 0, to: indices.count, by: 3) {
                let ids = (0..<3).map { Int(indices[decalBase + $0]) }
                let p = ids.map { textureCoordinates[$0] }
                let denominator = (p[1].y - p[2].y) * (p[0].x - p[2].x)
                    + (p[2].x - p[1].x) * (p[0].y - p[2].y)
                guard abs(denominator) > 0.000_000_1 else { continue }
                let wa = ((p[1].y - p[2].y) * (uv.x - p[2].x)
                    + (p[2].x - p[1].x) * (uv.y - p[2].y)) / denominator
                let wb = ((p[2].y - p[0].y) * (uv.x - p[2].x)
                    + (p[0].x - p[2].x) * (uv.y - p[2].y)) / denominator
                let wc = 1 - wa - wb
                guard min(wa, wb, wc) >= -0.000_1 else { continue }
                let point = positions[ids[0]] * wa + positions[ids[1]] * wb + positions[ids[2]] * wc
                if selected == nil || side * point.z > side * selected!.point.z {
                    selected = (ids, [wa, wb, wc], point)
                }
            }
            guard let selected, let shirt = try rawShirtTriangleWitness(skin, isFront: isFront,
                restPoint: [selected.point.x, selected.point.y]) else { continue }
            var ink = SIMD3<Float>.zero
            for (corner, index) in selected.corners.enumerated() {
                var posed = SIMD4<Float>.zero
                for influence in weights[(index * 4)..<(index * 4 + 4)] where influence.weight > 0 {
                    posed += skin.pose.modelSpaceTransforms[influence.jointIndex]
                        * skeleton.joints[influence.jointIndex].inverseBindPoseMatrix
                        * SIMD4(positions[index], 1) * influence.weight
                }
                ink += SIMD3(posed.x, posed.y, posed.z) * selected.barycentric[corner]
            }
            clearances.append(simd_dot(ink - shirt, outward))
        }
        return clearances
    }

    private func rawShirtTriangleWitness(_ skin: ReplaySkinnedAthleteInstance, isFront: Bool,
                                         restPoint target: SIMD2<Float>) throws -> SIMD3<Float>? {
        let contents = try XCTUnwrap(skin.model.model).mesh.contents
        let part = try XCTUnwrap(contents.models.first?.parts.first)
        let skeleton = try XCTUnwrap(contents.skeletons.first)
        let weights = try XCTUnwrap(part.jointInfluences).influences.elements
        let indices = try XCTUnwrap(part.triangleIndices).elements
        let positions = part.positions.elements
        var chosen: (indices: [Int], weights: SIMD3<Float>, depth: Float)?
        for base in stride(from: 0, to: indices.count, by: 3) {
            let vertexIDs = [Int(indices[base]), Int(indices[base + 1]), Int(indices[base + 2])]
            let a = positions[vertexIDs[0]], b = positions[vertexIDs[1]], c = positions[vertexIDs[2]]
            let denominator = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
            guard abs(denominator) > 0.000_000_1 else { continue }
            let wa = ((b.y - c.y) * (target.x - c.x) + (c.x - b.x) * (target.y - c.y)) / denominator
            let wb = ((c.y - a.y) * (target.x - c.x) + (a.x - c.x) * (target.y - c.y)) / denominator
            let wc = 1 - wa - wb
            guard min(wa, wb, wc) >= -0.000_1 else { continue }
            let depth = a.z * wa + b.z * wb + c.z * wc
            guard (isFront ? depth : -depth) > 0.04 else { continue }
            if chosen == nil || (isFront ? depth > chosen!.depth : depth < chosen!.depth) {
                chosen = (vertexIDs, [wa, wb, wc], depth)
            }
        }
        guard let chosen else { return nil }
        var result = SIMD3<Float>.zero
        for (corner, index) in chosen.indices.enumerated() {
            var posed = SIMD4<Float>.zero
            for influence in weights[(index * 4)..<(index * 4 + 4)] where influence.weight > 0 {
                posed += skin.pose.modelSpaceTransforms[influence.jointIndex]
                    * skeleton.joints[influence.jointIndex].inverseBindPoseMatrix
                    * SIMD4(positions[index], 1) * influence.weight
            }
            result += SIMD3(posed.x, posed.y, posed.z) * chosen.weights[corner]
        }
        return result
    }

    func testNewRigHasSharedMeshesIndependentPosesAndEqualTeamScale() throws {
        try ReplayTripoAthleteProvider.prewarm()
        XCTAssertTrue(ReplayTripoAthleteProvider.isPrewarmed)
        XCTAssertFalse(ReplaySkinnedAthleteProvider.isPrewarmed, "Do not decode both asset families")
        let home = try player(), away = try player("red-lb")
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let first = try ReplayTripoAthleteProvider.make(for: home, detail: detail)
            let second = try ReplayTripoAthleteProvider.make(for: away, detail: detail)
            let maskBytes = ReplayTripoAthleteProvider.loadedNumberMaskBaseBytes
            let sameNumber = try ReplayTripoAthleteProvider.make(for: home, detail: detail)
            XCTAssertTrue(first.front.model?.mesh === sameNumber.front.model?.mesh)
            XCTAssertTrue(first.back.model?.mesh === sameNumber.back.model?.mesh)
            XCTAssertEqual(ReplayTripoAthleteProvider.loadedNumberMaskBaseBytes, maskBytes)
            XCTAssertEqual(first.motion.rigProfile, .tripo52)
            XCTAssertEqual(first.model.jointNames.count, 52)
            XCTAssertEqual(first.model.jointNames, first.motion.jointNames)
            XCTAssertEqual(first.model.model?.materials.count, 1)
            XCTAssertEqual(first.root.scale, second.root.scale)
            XCTAssertEqual(first.root.scale, SIMD3<Float>(repeating: 1))
            XCTAssertEqual(first.motion.geometry.nominalHeight, 1.82, accuracy: 0.0001)
            XCTAssertTrue(first.model.model?.mesh === second.model.model?.mesh)
            XCTAssertFalse(first.model === second.model)
            XCTAssertEqual(first.bootMarkers?.markers.count, 2)
            XCTAssertEqual(first.contactSurface.headerProbeCount, 96)
            XCTAssertNotNil(ReplaySkinnedAthleteFootballPose(motion: first.motion, bootMarkers: first.bootMarkers))
            XCTAssertNotNil(ReplaySkinnedAthleteImpactPose(motion: first.motion, contactSurface: first.contactSurface))
            let component = try XCTUnwrap(first.model.model)
            let part = try XCTUnwrap(component.mesh.contents.models.first?.parts.first)
            let sourceVertices = detail == .near ? ReplayTripoAthleteProvider.skinVertices
                : ReplayTripoAthleteProvider.lowSkinVertices
            let importedVertices = detail == .near ? ReplayTripoAthleteProvider.importedSkinVertices
                : ReplayTripoAthleteProvider.lowImportedSkinVertices
            XCTAssertEqual(sourceVertices, detail == .near ? 9_075 : 3_269)
            XCTAssertEqual(importedVertices, detail == .near ? 9_075 : 3_267)
            XCTAssertEqual(part.positions.count, importedVertices)
            XCTAssertEqual(part.normals?.rate, .vertex)
            XCTAssertEqual(part.normals?.count, importedVertices)
            XCTAssertEqual(part.textureCoordinates?.rate, .vertex)
            XCTAssertEqual(part.textureCoordinates?.count, importedVertices)
            XCTAssertEqual(part.jointInfluences?.influences.count, importedVertices * 4)
            XCTAssertEqual(part.triangleIndices?.count, (detail == .near ? 7_685 : 1_964) * 3)
            XCTAssertTrue(first.update(at: 1.25, track: home,
                locomotion: locomotion(home, time: 1.25, speed: 3.6), lookTarget: nil, ballAction: nil))
            XCTAssertNotEqual(first.model.jointTransforms, second.model.jointTransforms)
            XCTAssertEqual(first.front.name, "skinned-chest-number")
            XCTAssertEqual(first.back.name, "skinned-shirt-number")
        }
        XCTAssertEqual(ReplayTripoAthleteProvider.materialDrawsPerInstance, 3)
        XCTAssertEqual(ReplayTripoAthleteProvider.diverseMaterialDrawsPerInstance, 4)
        XCTAssertEqual(ReplayTripoAthleteProvider.decodedTextureBytes, 50_331_648)
    }

    func testImportedTriangleCornersRetainPinnedSourceGeometryUVAndSkin() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let track = try player()
        // Old-v5 and welded-v6 RealityKit readbacks had identical ordered
        // corners (zero position, UV and weight delta). No source path needed.
        for (detail, expected) in [
            (ReplaySkinnedAthleteProvider.Detail.near, UInt64(0x536e60d398cdadf1)),
            (.lowDetail, UInt64(0xb24f17241abc4d6b)),
        ] {
            let skin = try ReplayTripoAthleteProvider.make(for: track, detail: detail)
            XCTAssertEqual(skin.model.jointNames, skin.motion.jointNames)
            let part = try XCTUnwrap(skin.model.model?.mesh.contents.models.first?.parts.first)
            XCTAssertEqual(part.textureCoordinates?.rate, .vertex)
            let positions = part.positions.elements
            let uv = try XCTUnwrap(part.textureCoordinates).elements
            let indices = try XCTUnwrap(part.triangleIndices).elements
            let influences = try XCTUnwrap(part.jointInfluences).influences.elements
            XCTAssertEqual(positions.count, uv.count)
            XCTAssertEqual(influences.count, positions.count * 4)
            XCTAssertEqual(indices.count, detail == .near ? 23_055 : 5_892)
            XCTAssertEqual(cornerSignature(part), expected,
                           "Imported triangle-corner geometry, UV, or skin changed")
        }
    }

    private func cornerSignature(_ part: MeshResource.Part) -> UInt64 {
        let positions = part.positions.elements
        let uv = part.textureCoordinates!.elements
        let indices = part.triangleIndices!.elements
        let influences = part.jointInfluences!.influences.elements
        var hash: UInt64 = 14_695_981_039_346_656_037
        func feed(_ value: Float) {
            let quantized = Int64((Double(value) * 100_000).rounded(.toNearestOrEven))
            let bits = UInt64(bitPattern: quantized)
            for shift in stride(from: 0, through: 56, by: 8) {
                let byte = UInt8(truncatingIfNeeded: bits >> shift)
                hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
            }
        }
        for rawIndex in indices {
            let index = Int(rawIndex)
            let point = positions[index], coord = uv[index]
            feed(point.x); feed(point.y); feed(point.z)
            feed(coord.x); feed(coord.y)
            let start = index * 4
            for slot in 0..<4 { feed(Float(influences[start + slot].jointIndex)) }
            for slot in 0..<4 { feed(influences[start + slot].weight) }
        }
        return hash
    }

    func testSeeksTouchesAndImpactsAreDeterministicForBothDetails() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let track = try player(), scenario = try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay))
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplayTripoAthleteProvider.make(for: track, detail: detail)
            func seek(_ time: Double, impact: PlayerRagdollPlayback.Sample? = nil) {
                XCTAssertTrue(skin.update(at: time, track: track,
                    locomotion: locomotion(track, time: time, speed: 3.6), lookTarget: [9, 0.2, 20],
                    ballAction: ReplayAthleteMotion.ballActionPose(for: track, ballTrack: scenario.ball, at: time),
                    impact: impact))
            }
            seek(13.6)
            let expected = skin.model.jointTransforms, front = skin.front.transform, back = skin.back.transform
            let cue = PlayerRagdollCue(playerID: track.id, impactTime: 12.6)
            seek(13.6, impact: try XCTUnwrap(PlayerRagdollPlayback.sample(for: cue, at: 13.6)))
            XCTAssertNotEqual(skin.model.jointTransforms, expected)
            for time in [2.0, 17, 3, 13.6] { seek(time) }
            XCTAssertEqual(skin.model.jointTransforms, expected)
            XCTAssertEqual(skin.front.transform, front)
            XCTAssertEqual(skin.back.transform, back)
            XCTAssertTrue(skin.numbersUseShirtSkin, "Missing skinned #7 digit at \(detail)")
            XCTAssertEqual(skin.front.jointTransforms, skin.model.jointTransforms)
            XCTAssertEqual(skin.back.jointTransforms, skin.model.jointTransforms)
            XCTAssertEqual(skin.front.jointNames, skin.model.jointNames)
            XCTAssertEqual(skin.back.jointNames, skin.model.jointNames)
        }
    }

    func testActualWeightedVerticesStayFiniteAndAbovePitchAcrossMotion() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let track = try player()
        for detail in [ReplaySkinnedAthleteProvider.Detail.near, .lowDetail] {
            let skin = try ReplayTripoAthleteProvider.make(for: track, detail: detail)
            let contents = try XCTUnwrap(skin.model.model).mesh.contents
            let skeleton = try XCTUnwrap(contents.skeletons.first)
            let part = try XCTUnwrap(contents.models.first?.parts.first)
            let weights = try XCTUnwrap(part.jointInfluences).influences.elements
            XCTAssertEqual(weights.count, part.positions.count * 4)
            let bindings = part.positions.elements.enumerated().map { index, point in
                weights[(index * 4)..<(index * 4 + 4)].map {
                    (joint: $0.jointIndex, point: skeleton.joints[$0.jointIndex].inverseBindPoseMatrix
                        * SIMD4(point, 1), weight: $0.weight)
                }
            }
            for (speed, turn) in [(Float(0), Float(0)), (1.1, 0), (3.6, 0), (3, 150)] {
                for time in stride(from: 0.0, through: 1.0, by: 0.2) {
                    XCTAssertTrue(skin.update(at: time, track: track,
                        locomotion: locomotion(track, time: time, speed: speed, turn: turn),
                        lookTarget: [10, 0.2, 25], ballAction: nil))
                    var minimum = Float.infinity
                    for influences in bindings {
                        var point = SIMD4<Float>.zero
                        for influence in influences where influence.weight > 0 {
                            point += skin.pose.modelSpaceTransforms[influence.joint] * influence.point * influence.weight
                        }
                        XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite)
                        XCTAssertLessThan(simd_length(SIMD3(point.x, point.y, point.z)), 4)
                        minimum = min(minimum, point.y - skin.motion.geometry.restMinY)
                    }
                    XCTAssertGreaterThanOrEqual(minimum, -0.005, "Actual mesh, not only the contact sample")
                    XCTAssertLessThan(minimum, 0.08, "Do not float above the pitch")
                }
            }
        }
    }

    func testMissingNewAssetsFailAtomicallyAndOldRigRemainsAvailable() throws {
        XCTAssertThrowsError(try ReplayTripoAthleteProvider.prewarm(in: Bundle(for: Self.self)))
        XCTAssertFalse(ReplayTripoAthleteProvider.isPrewarmed)
        XCTAssertNil(ReplayTripoAthleteProvider.motion)
        try ReplaySkinnedAthleteProvider.prewarm()
        let fallback = try ReplayTripoAthleteProvider.makePreferred(for: player(), detail: .near)
        XCTAssertEqual(fallback.motion.rigProfile, .rocketbox)
        XCTAssertEqual(fallback.model.jointNames.count, 80)
    }

    func testMotionBlendBoundariesDoNotSnapTheNewRig() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let track = try player(), skin = try ReplayTripoAthleteProvider.make(for: track)
        for (speed, turn) in [(Float(0.22), Float(0)), (1.65, 0), (3.8, 0), (2.8, 70)] {
            var previous: [Transform]?
            for offset: Float in [-0.001, 0.001] {
                XCTAssertTrue(skin.update(at: 12, track: track,
                    locomotion: locomotion(track, time: 12, speed: speed + offset, turn: turn + offset),
                    lookTarget: nil, ballAction: nil))
                if let previous {
                    for (a, b) in zip(previous, skin.model.jointTransforms) {
                        XCTAssertLessThan(simd_distance(a.translation, b.translation), 0.004)
                        XCTAssertGreaterThan(abs(simd_dot(a.rotation.vector, b.rotation.vector)), 0.999)
                    }
                }
                previous = skin.model.jointTransforms
            }
        }
    }

    func testImportedNormalsAreUnitAndMatchNativeGeometryCount() throws {
        try ReplayTripoAthleteProvider.prewarm()
        let skin = try ReplayTripoAthleteProvider.make(for: player())
        let part = try XCTUnwrap(skin.model.model?.mesh.contents.models.first?.parts.first)
        let normals = try XCTUnwrap(part.normals).elements
        XCTAssertEqual(normals.count, part.positions.count)
        for normal in normals { XCTAssertEqual(simd_length(normal), 1, accuracy: 0.0001) }
        let points = part.positions.elements.map { [$0.x, $0.y, $0.z] }
        let vectors = normals.map { [$0.x, $0.y, $0.z] }
        let indices = try XCTUnwrap(part.triangleIndices).elements.map(Int.init)
        let data = try JSONSerialization.data(withJSONObject: ["positions": points,
            "normals": vectors, "indices": indices, "assetSHA256": ReplayTripoAthleteProvider.assetSHA256])
        XCTAssertLessThan(data.count, 2 * 1_024 * 1_024)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ReplayXI-Tripo-Native-Normals.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testBothTeamsUseNewRigWithoutChangingAnnotationsOrBallRecording() async throws {
        try ReplayTripoAthleteProvider.prewarm()
        let scenario = try XCTUnwrap(FootballReferenceScenarios.all.first { $0.id == "final-108-rebound-v2" })
        try ReplayAthleteFactory.prewarm(for: scenario.players, lods: [.near, .far])
        let recording = try await ReplayNativeBallPhysics.prewarm(track: scenario.ball, players: scenario.players,
            plannedTouches: FootballReferenceScenarios.touches(for: scenario))
        let root = PitchSceneFactory.makeMatchRoot(for: scenario, nativeRecording: recording)
        let mark = CoachMark(kind: .run, start: .zero, end: PitchPoint(x: 8, z: 32), label: "New rig check")
        for detail in [ReplayPlayerDetail.balanced, .fullSquad, .balanced] {
            PitchSceneFactory.update(root: root, scenario: scenario, time: 0.3, viewMode: .tacticalTable,
                perspectiveID: "arg-23", marks: [mark], showsLaneLens: false, isDrawing: false,
                positionalOriginTransform: nil, playerDetail: detail)
            let skins = PitchSceneFactory.skinnedAthletesForTesting(in: root)
            XCTAssertEqual(skins.count, detail == .balanced ? 4 : 22)
            XCTAssertTrue(skins.values.allSatisfy { $0.motion.rigProfile == .tripo52 && $0.root.isEnabled })
            if detail == .fullSquad {
                for player in scenario.players { XCTAssertNotNil(skins[player.id], player.id) }
            }
            XCTAssertNotNil(root.findEntity(named: "mark-\(mark.id.uuidString)"))
            XCTAssertTrue(PitchSceneFactory.nativeBallRecordingForTesting(in: root) === recording)
        }
        // Selected first-person avatar is hidden; the other 21 retain the
        // same player IDs, so annotations and tap-to-switch keep ownership.
        PitchSceneFactory.update(root: root, scenario: scenario, time: 0.3, viewMode: .firstPerson,
            perspectiveID: "arg-23", marks: [mark], showsLaneLens: false, isDrawing: false,
            positionalOriginTransform: nil, playerDetail: .fullSquad)
        let firstPerson = PitchSceneFactory.skinnedAthletesForTesting(in: root)
        XCTAssertEqual(firstPerson.count, 21)
        XCTAssertNil(firstPerson["arg-23"])
        XCTAssertTrue(firstPerson.values.allSatisfy { $0.motion.rigProfile == .tripo52 })
        let target = try XCTUnwrap(root.findEntity(named: "player-arg-13")?.findEntity(named: "interaction-target"))
        XCTAssertTrue(target.isEnabledInHierarchy)
        XCTAssertNotNil(target.components[InputTargetComponent.self])
    }
}
