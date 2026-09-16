import RealityKit
import UIKit
import simd

/// Accounting returned with every original Replay XI mesh.  The factory uses
/// these values to enforce its per-LOD geometry budget without introspecting
/// private RealityKit buffers at runtime.
struct ReplayAthleteMeshMetrics: Equatable, Sendable {
    var vertices: Int
    var triangles: Int

    static let zero = ReplayAthleteMeshMetrics(vertices: 0, triangles: 0)

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            vertices: lhs.vertices + rhs.vertices,
            triangles: lhs.triangles + rhs.triangles
        )
    }
}

@MainActor
struct ReplayAthleteMeshAsset {
    let mesh: MeshResource
    let metrics: ReplayAthleteMeshMetrics
}

/// Original football anatomy. Smooth lofts are cached by part
/// and LOD, so every player shares immutable vertex/index buffers.  Compared
/// with scaled balls and boxes, the authored profiles preserve a shoulder,
/// waist, quadriceps, calf, jaw and boot silhouette under close Player POV.
/// Only integrated far limbs add height UVs for their small colour strips.
@MainActor
enum ReplayAthleteMeshLibrary {
    enum Part: String, Hashable, Sendable {
        case torso
        case shorts
        case neck
        case head
        case hair
        case thigh
        case shin
        case sleeve
        case upperArm
        case forearm
        case hand
        case wholeLeg
        case wholeArm
        case boot
        case nose
        case jerseyStripe
    }

    private struct CacheKey: Hashable {
        let part: Part
        let lod: ReplayAthleteLOD
    }

    private struct RingProfile {
        let y: Float
        let radiusX: Float
        let radiusZ: Float
        let centreZ: Float
    }

    private static var meshCache: [CacheKey: ReplayAthleteMeshAsset] = [:]
    private static var numberCache: [Int: ReplayAthleteMeshAsset] = [:]

    static func mesh(for part: Part, lod: ReplayAthleteLOD) throws -> ReplayAthleteMeshAsset {
        let key = CacheKey(part: part, lod: lod)
        if let cached = meshCache[key] {
            return cached
        }

        let radialSegments = switch lod {
        case .near: 14
        case .mid: 10
        case .far: 7
        }

        let generated: ReplayAthleteMeshAsset
        switch part {
        case .torso:
            generated = try loft(
                named: "replay-athlete-torso-\(lod.rawValue)",
                profiles: [
                    .init(y: -0.025, radiusX: 0.164, radiusZ: 0.104, centreZ: -0.004),
                    .init(y: 0.045, radiusX: 0.190, radiusZ: 0.119, centreZ: -0.003),
                    .init(y: 0.180, radiusX: 0.204, radiusZ: 0.130, centreZ: -0.006),
                    .init(y: 0.325, radiusX: 0.226, radiusZ: 0.140, centreZ: -0.001),
                    .init(y: 0.445, radiusX: 0.242, radiusZ: 0.144, centreZ: 0),
                    .init(y: 0.500, radiusX: 0.222, radiusZ: 0.135, centreZ: 0),
                    .init(y: 0.540, radiusX: 0.174, radiusZ: 0.113, centreZ: 0),
                    .init(y: 0.575, radiusX: 0.105, radiusZ: 0.082, centreZ: 0),
                ],
                segments: radialSegments,
                capped: true
            )
        case .shorts:
            generated = try loft(
                named: "replay-athlete-shorts-\(lod.rawValue)",
                profiles: [
                    .init(y: -0.135, radiusX: 0.168, radiusZ: 0.113, centreZ: 0),
                    .init(y: -0.078, radiusX: 0.205, radiusZ: 0.137, centreZ: -0.004),
                    .init(y: 0.020, radiusX: 0.216, radiusZ: 0.142, centreZ: -0.004),
                    .init(y: 0.100, radiusX: 0.188, radiusZ: 0.126, centreZ: 0),
                ],
                segments: radialSegments,
                capped: true
            )
        case .neck:
            generated = try loft(
                named: "replay-athlete-neck-\(lod.rawValue)",
                profiles: [
                    .init(y: -0.045, radiusX: 0.072, radiusZ: 0.067, centreZ: 0),
                    .init(y: 0.025, radiusX: 0.069, radiusZ: 0.065, centreZ: 0),
                    .init(y: 0.100, radiusX: 0.074, radiusZ: 0.069, centreZ: 0),
                ],
                segments: radialSegments,
                capped: true
            )
        case .head:
            generated = try loft(
                named: "replay-athlete-head-\(lod.rawValue)",
                profiles: [
                    .init(y: -0.155, radiusX: 0.050, radiusZ: 0.057, centreZ: 0.019),
                    .init(y: -0.120, radiusX: 0.092, radiusZ: 0.083, centreZ: 0.015),
                    .init(y: -0.055, radiusX: 0.123, radiusZ: 0.105, centreZ: 0.010),
                    .init(y: 0.035, radiusX: 0.137, radiusZ: 0.119, centreZ: 0.004),
                    .init(y: 0.105, radiusX: 0.123, radiusZ: 0.110, centreZ: -0.004),
                    .init(y: 0.150, radiusX: 0.084, radiusZ: 0.079, centreZ: -0.010),
                    .init(y: 0.173, radiusX: 0.034, radiusZ: 0.033, centreZ: -0.012),
                ],
                segments: radialSegments,
                capped: true
            )
        case .hair:
            generated = try loft(
                named: "replay-athlete-hair-\(lod.rawValue)",
                profiles: [
                    .init(y: 0.045, radiusX: 0.137, radiusZ: 0.116, centreZ: -0.008),
                    .init(y: 0.108, radiusX: 0.126, radiusZ: 0.112, centreZ: -0.008),
                    .init(y: 0.158, radiusX: 0.086, radiusZ: 0.082, centreZ: -0.012),
                    .init(y: 0.180, radiusX: 0.025, radiusZ: 0.025, centreZ: -0.013),
                ],
                segments: radialSegments,
                capped: true
            )
        case .thigh:
            generated = try loft(
                named: "replay-athlete-thigh-\(lod.rawValue)",
                profiles: [
                    .init(y: 0.020, radiusX: 0.090, radiusZ: 0.096, centreZ: 0),
                    .init(y: -0.085, radiusX: 0.108, radiusZ: 0.116, centreZ: -0.004),
                    .init(y: -0.205, radiusX: 0.101, radiusZ: 0.111, centreZ: -0.012),
                    .init(y: -0.330, radiusX: 0.082, radiusZ: 0.090, centreZ: -0.006),
                    .init(y: -0.390, radiusX: 0.072, radiusZ: 0.078, centreZ: 0),
                ],
                segments: radialSegments,
                capped: true
            )
        case .shin:
            generated = try loft(
                named: "replay-athlete-shin-\(lod.rawValue)",
                profiles: [
                    .init(y: 0.010, radiusX: 0.071, radiusZ: 0.077, centreZ: 0),
                    .init(y: -0.090, radiusX: 0.080, radiusZ: 0.092, centreZ: -0.013),
                    .init(y: -0.185, radiusX: 0.088, radiusZ: 0.098, centreZ: -0.024),
                    .init(y: -0.290, radiusX: 0.069, radiusZ: 0.075, centreZ: -0.008),
                    .init(y: -0.350, radiusX: 0.058, radiusZ: 0.063, centreZ: 0),
                ],
                segments: radialSegments,
                capped: true
            )
        case .sleeve:
            generated = try loft(
                named: "replay-athlete-sleeve-\(lod.rawValue)",
                profiles: [
                    // A small rounded crown hides the rotating joint instead
                    // of exposing the old broad, flat cap beside the torso.
                    .init(y: 0.075, radiusX: 0.052, radiusZ: 0.058, centreZ: 0),
                    .init(y: 0.035, radiusX: 0.096, radiusZ: 0.105, centreZ: 0),
                    .init(y: -0.025, radiusX: 0.108, radiusZ: 0.116, centreZ: 0),
                    .init(y: -0.095, radiusX: 0.090, radiusZ: 0.097, centreZ: 0),
                    .init(y: -0.160, radiusX: 0.075, radiusZ: 0.080, centreZ: 0),
                ],
                segments: radialSegments,
                capped: true
            )
        case .upperArm:
            generated = try loft(
                named: "replay-athlete-upper-arm-\(lod.rawValue)",
                profiles: [
                    .init(y: -0.095, radiusX: 0.067, radiusZ: 0.072, centreZ: 0),
                    .init(y: -0.190, radiusX: 0.070, radiusZ: 0.075, centreZ: 0),
                    .init(y: -0.310, radiusX: 0.058, radiusZ: 0.062, centreZ: 0),
                ],
                segments: radialSegments,
                capped: true
            )
        case .forearm:
            generated = try loft(
                named: "replay-athlete-forearm-\(lod.rawValue)",
                profiles: [
                    .init(y: 0.010, radiusX: 0.058, radiusZ: 0.061, centreZ: 0),
                    .init(y: -0.100, radiusX: 0.061, radiusZ: 0.065, centreZ: 0),
                    .init(y: -0.230, radiusX: 0.047, radiusZ: 0.050, centreZ: 0),
                    .init(y: -0.275, radiusX: 0.043, radiusZ: 0.046, centreZ: 0),
                ],
                segments: radialSegments,
                capped: true
            )
        case .hand:
            generated = try loft(
                named: "replay-athlete-hand-\(lod.rawValue)",
                profiles: [
                    .init(y: 0.008, radiusX: 0.043, radiusZ: 0.041, centreZ: 0),
                    .init(y: -0.045, radiusX: 0.056, radiusZ: 0.045, centreZ: 0.004),
                    .init(y: -0.095, radiusX: 0.036, radiusZ: 0.033, centreZ: 0.008),
                ],
                segments: radialSegments,
                capped: true
            )
        case .wholeLeg:
            generated = try loft(
                named: "replay-athlete-whole-leg-\(lod.rawValue)",
                profiles: [
                    .init(y: 0.020, radiusX: 0.096, radiusZ: 0.101, centreZ: 0),
                    .init(y: -0.170, radiusX: 0.101, radiusZ: 0.109, centreZ: -0.010),
                    .init(y: -0.385, radiusX: 0.070, radiusZ: 0.076, centreZ: 0),
                    .init(y: -0.540, radiusX: 0.082, radiusZ: 0.092, centreZ: -0.018),
                    .init(y: -0.750, radiusX: 0.058, radiusZ: 0.064, centreZ: 0),
                    // Far LOD folds a quiet boot silhouette into the same
                    // material/draw instead of spending two more squad draws.
                    .init(y: -0.820, radiusX: 0.069, radiusZ: 0.115, centreZ: 0.055),
                ],
                segments: radialSegments,
                capped: true,
                paletteLimb: lod == .far ? .leg : nil
            )
        case .wholeArm:
            generated = try loft(
                named: "replay-athlete-whole-arm-\(lod.rawValue)",
                profiles: [
                    .init(y: 0.020, radiusX: 0.089, radiusZ: 0.095, centreZ: 0),
                    .init(y: -0.150, radiusX: 0.069, radiusZ: 0.074, centreZ: 0),
                    .init(y: -0.310, radiusX: 0.057, radiusZ: 0.061, centreZ: 0),
                    .init(y: -0.485, radiusX: 0.049, radiusZ: 0.052, centreZ: 0),
                    .init(y: -0.580, radiusX: 0.041, radiusZ: 0.043, centreZ: 0),
                ],
                segments: radialSegments,
                capped: true,
                paletteLimb: lod == .far ? .arm : nil
            )
        case .boot:
            generated = try boot(named: "replay-athlete-boot-\(lod.rawValue)")
        case .nose:
            generated = try wedge(
                named: "replay-athlete-nose-\(lod.rawValue)",
                halfWidth: 0.020,
                height: 0.052,
                depth: 0.038
            )
        case .jerseyStripe:
            generated = try wedge(
                named: "replay-athlete-stripe-\(lod.rawValue)",
                halfWidth: 0.014,
                height: 0.335,
                depth: 0.010
            )
        }

        meshCache[key] = generated
        return generated
    }

    /// A bespoke seven-segment football number, extruded as one mesh per shirt
    /// number.  It is deterministic, license-free, cached, and performs no
    /// runtime font lookup or CoreText tessellation.
    static func jerseyNumber(_ number: Int) throws -> ReplayAthleteMeshAsset {
        let bounded = min(max(number, 0), 99)
        if let cached = numberCache[bounded] {
            return cached
        }

        let digits = String(bounded).compactMap { $0.wholeNumberValue }
        let digitWidth: Float = 0.56
        let digitGap: Float = 0.13
        let totalWidth = (Float(digits.count) * digitWidth)
            + (Float(max(digits.count - 1, 0)) * digitGap)
        var builder = TriangleMeshBuilder()

        for (index, digit) in digits.enumerated() {
            let left = (Float(index) * (digitWidth + digitGap)) - (totalWidth / 2)
            for segment in numberSegments[digit] ?? [] {
                let specification = segmentSpecification(segment)
                builder.appendChamferedPrism(
                    centre: SIMD2<Float>(
                        left + (digitWidth / 2) + specification.centre.x,
                        specification.centre.y - 0.5
                    ),
                    size: specification.size,
                    depth: 0.018,
                    chamfer: 0.028,
                    includesBackFace: false
                )
            }
        }

        let generated = try builder.makeAsset(named: "replay-athlete-number-\(bounded)")
        numberCache[bounded] = generated
        return generated
    }

    /// Build immutable geometry while the dashboard is still visible. Apple
    /// recommends avoiding resource generation during an active immersive/AR
    /// session; callers should await this synchronously on the main actor before
    /// opening the space, then all factory calls become cache hits.
    static func prewarm(lods: Set<ReplayAthleteLOD>, shirtNumbers: Set<Int>) throws {
        for lod in lods {
            for part in partsUsed(by: lod) {
                _ = try mesh(for: part, lod: lod)
            }
            if lod != .far {
                for number in shirtNumbers {
                    _ = try jerseyNumber(number)
                }
            }
        }
    }

    // MARK: - Original mesh generation

    private static func partsUsed(by lod: ReplayAthleteLOD) -> [Part] {
        switch lod {
        case .near:
            [
                .torso, .shorts, .neck, .head, .hair, .thigh, .shin,
                .sleeve, .upperArm, .forearm, .hand, .boot, .nose,
                .jerseyStripe,
            ]
        case .mid:
            [
                .torso, .shorts, .neck, .head, .hair, .thigh, .shin,
                .sleeve, .upperArm, .forearm, .boot,
            ]
        case .far:
            [.torso, .shorts, .head, .wholeLeg, .wholeArm]
        }
    }

    private static func loft(
        named name: String,
        profiles: [RingProfile],
        segments: Int,
        capped: Bool,
        paletteLimb: ReplayFarAthletePaletteProvider.Limb? = nil
    ) throws -> ReplayAthleteMeshAsset {
        precondition(profiles.count >= 2)
        precondition(segments >= 3)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(
            (profiles.count * segments) + (capped ? ((segments * 2) + 2) : 0)
        )
        normals.reserveCapacity(positions.capacity)
        indices.reserveCapacity(((profiles.count - 1) * segments * 6) + (capped ? segments * 6 : 0))
        // Torso rings ascend; limbs are authored from their joint downwards.
        // Both need outward-facing winding and normals. Treating a descending
        // limb as an ascending loft turned its surface inward and flattened its
        // longitudinal normal, producing dark seams and culled limb surfaces.
        let direction: Float = profiles.last!.y >= profiles.first!.y ? 1 : -1

        for ringIndex in profiles.indices {
            let profile = profiles[ringIndex]
            let previous = profiles[max(ringIndex - 1, profiles.startIndex)]
            let next = profiles[min(ringIndex + 1, profiles.index(before: profiles.endIndex))]
            let dy = direction * max(abs(next.y - previous.y), 0.000_1)
            let drx = next.radiusX - previous.radiusX
            let drz = next.radiusZ - previous.radiusZ
            let dCentreZ = next.centreZ - previous.centreZ

            for segmentIndex in 0..<segments {
                let angle = (Float(segmentIndex) / Float(segments)) * (.pi * 2)
                let cosine = cos(angle)
                let sine = sin(angle)
                positions.append([
                    cosine * profile.radiusX,
                    profile.y,
                    profile.centreZ + (sine * profile.radiusZ),
                ])

                let alongProfile = SIMD3<Float>(
                    cosine * drx,
                    dy,
                    dCentreZ + (sine * drz)
                )
                let aroundRing = SIMD3<Float>(
                    -sine * profile.radiusX,
                    0,
                    cosine * profile.radiusZ
                )
                let rawNormal = simd_cross(alongProfile, aroundRing) * direction
                normals.append(simd_length_squared(rawNormal) > 0.000_001
                    ? simd_normalize(rawNormal)
                    : SIMD3<Float>(cosine, 0, sine))
            }
        }

        for ringIndex in 0..<(profiles.count - 1) {
            for segmentIndex in 0..<segments {
                let nextSegment = (segmentIndex + 1) % segments
                let lower = UInt32((ringIndex * segments) + segmentIndex)
                let lowerNext = UInt32((ringIndex * segments) + nextSegment)
                let upper = UInt32(((ringIndex + 1) * segments) + segmentIndex)
                let upperNext = UInt32(((ringIndex + 1) * segments) + nextSegment)
                indices.append(contentsOf: direction > 0
                    ? [lower, upper, lowerNext, lowerNext, upper, upperNext]
                    : [lower, lowerNext, upper, lowerNext, upperNext, upper])
            }
        }

        if capped {
            let bottomCentre = UInt32(positions.count)
            positions.append([0, profiles[0].y, profiles[0].centreZ])
            normals.append([0, -direction, 0])
            let bottomRingStart = UInt32(positions.count)
            for segmentIndex in 0..<segments {
                let angle = (Float(segmentIndex) / Float(segments)) * (.pi * 2)
                let profile = profiles[0]
                positions.append([
                    cos(angle) * profile.radiusX,
                    profile.y,
                    profile.centreZ + (sin(angle) * profile.radiusZ),
                ])
                normals.append([0, -direction, 0])
            }

            let topProfile = profiles[profiles.count - 1]
            let topCentre = UInt32(positions.count)
            positions.append([0, topProfile.y, topProfile.centreZ])
            normals.append([0, direction, 0])
            let topRingStart = UInt32(positions.count)
            for segmentIndex in 0..<segments {
                let angle = (Float(segmentIndex) / Float(segments)) * (.pi * 2)
                positions.append([
                    cos(angle) * topProfile.radiusX,
                    topProfile.y,
                    topProfile.centreZ + (sin(angle) * topProfile.radiusZ),
                ])
                normals.append([0, direction, 0])
            }

            for segmentIndex in 0..<segments {
                let current = UInt32(segmentIndex)
                let next = UInt32((segmentIndex + 1) % segments)
                let firstCap: [UInt32] = [
                    bottomCentre,
                    bottomRingStart + current,
                    bottomRingStart + next,
                ]
                let lastCap: [UInt32] = [
                    topCentre,
                    topRingStart + next,
                    topRingStart + current,
                ]
                indices.append(contentsOf: direction > 0 ? firstCap : Array(firstCap.reversed()))
                indices.append(contentsOf: direction > 0 ? lastCap : Array(lastCap.reversed()))
            }
        }

        let coordinates = paletteLimb.map { limb in
            positions.map { ReplayFarAthletePaletteProvider.textureCoordinate(for: $0, limb: limb) }
        }
        return try makeAsset(name: name, positions: positions, normals: normals,
                             indices: indices, textureCoordinates: coordinates)
    }

    private static func boot(named name: String) throws -> ReplayAthleteMeshAsset {
        var builder = TriangleMeshBuilder()
        // A human-scale, six-stage football boot rather than a broad box at the
        // end of the ankle. The rising heel counter secures the silhouette to
        // the shin, the narrow midfoot opens into the ball of the foot, and the
        // final two sections lift and taper into a recognisable rocker toe.
        let sections: [(z: Float, bottom: Float, top: Float, halfWidth: Float)] = [
            (-0.075, -0.094, 0.040, 0.048),
            (-0.035, -0.100, 0.036, 0.055),
            (0.045, -0.100, 0.028, 0.052),
            (0.145, -0.097, 0.006, 0.061),
            (0.215, -0.085, -0.018, 0.058),
            (0.245, -0.066, -0.040, 0.032),
        ]
        builder.appendSectionedPrism(sections: sections)
        return try builder.makeAsset(named: name)
    }

    private static func wedge(
        named name: String,
        halfWidth: Float,
        height: Float,
        depth: Float
    ) throws -> ReplayAthleteMeshAsset {
        var builder = TriangleMeshBuilder()
        builder.appendChamferedPrism(
            centre: .zero,
            size: [halfWidth * 2, height],
            depth: depth,
            chamfer: min(halfWidth * 0.36, height * 0.08)
        )
        return try builder.makeAsset(named: name)
    }

    private static func makeAsset(
        name: String,
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        indices: [UInt32],
        textureCoordinates: [SIMD2<Float>]? = nil
    ) throws -> ReplayAthleteMeshAsset {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        if let textureCoordinates {
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(textureCoordinates)
        }
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])
        return ReplayAthleteMeshAsset(
            mesh: mesh,
            metrics: .init(vertices: positions.count, triangles: indices.count / 3)
        )
    }

    private enum NumberSegment: Hashable {
        case top
        case upperLeft
        case upperRight
        case middle
        case lowerLeft
        case lowerRight
        case bottom
    }

    // Arrays, rather than sets, make generated vertex/index ordering stable
    // across launches and toolchains.
    private static let numberSegments: [Int: [NumberSegment]] = [
        0: [.top, .upperLeft, .upperRight, .lowerLeft, .lowerRight, .bottom],
        1: [.upperRight, .lowerRight],
        2: [.top, .upperRight, .middle, .lowerLeft, .bottom],
        3: [.top, .upperRight, .middle, .lowerRight, .bottom],
        4: [.upperLeft, .upperRight, .middle, .lowerRight],
        5: [.top, .upperLeft, .middle, .lowerRight, .bottom],
        6: [.top, .upperLeft, .middle, .lowerLeft, .lowerRight, .bottom],
        7: [.top, .upperRight, .lowerRight],
        8: [.top, .upperLeft, .upperRight, .middle, .lowerLeft, .lowerRight, .bottom],
        9: [.top, .upperLeft, .upperRight, .middle, .lowerRight, .bottom],
    ]

    private static func segmentSpecification(
        _ segment: NumberSegment
    ) -> (centre: SIMD2<Float>, size: SIMD2<Float>) {
        switch segment {
        case .top: ([0, 0.94], [0.42, 0.105])
        case .middle: ([0, 0.50], [0.42, 0.105])
        case .bottom: ([0, 0.06], [0.42, 0.105])
        case .upperLeft: ([-0.235, 0.72], [0.105, 0.345])
        case .upperRight: ([0.235, 0.72], [0.105, 0.345])
        case .lowerLeft: ([-0.235, 0.28], [0.105, 0.345])
        case .lowerRight: ([0.235, 0.28], [0.105, 0.345])
        }
    }

    /// Small indexed builder used for flat-shaded wedges and glyph prisms.
    private struct TriangleMeshBuilder {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        mutating func appendChamferedPrism(
            centre: SIMD2<Float>,
            size: SIMD2<Float>,
            depth: Float,
            chamfer: Float,
            includesBackFace: Bool = true
        ) {
            let halfWidth = size.x / 2
            let halfHeight = size.y / 2
            let boundedChamfer = min(chamfer, min(halfWidth, halfHeight) * 0.48)
            let outline: [SIMD2<Float>] = [
                [-halfWidth + boundedChamfer, -halfHeight],
                [halfWidth - boundedChamfer, -halfHeight],
                [halfWidth, -halfHeight + boundedChamfer],
                [halfWidth, halfHeight - boundedChamfer],
                [halfWidth - boundedChamfer, halfHeight],
                [-halfWidth + boundedChamfer, halfHeight],
                [-halfWidth, halfHeight - boundedChamfer],
                [-halfWidth, -halfHeight + boundedChamfer],
            ].map { $0 + centre }
            appendExtrudedPolygon(outline, depth: depth, includesBackFace: includesBackFace)
        }

        mutating func appendExtrudedPolygon(
            _ outline: [SIMD2<Float>], depth: Float, includesBackFace: Bool
        ) {
            guard outline.count >= 3 else { return }
            let frontZ = depth / 2
            let backZ = -depth / 2

            // Duplicate vertices by face so the glyph edge remains crisp.
            let frontBase = UInt32(positions.count)
            for point in outline {
                positions.append([point.x, point.y, frontZ])
                normals.append([0, 0, 1])
            }
            for index in 1..<(outline.count - 1) {
                indices.append(contentsOf: [frontBase, frontBase + UInt32(index), frontBase + UInt32(index + 1)])
            }

            // Shirt digits face outwards and their backs are against opaque
            // fabric. Omit that invisible face while retaining crisp fronts
            // and all side walls; two #88 labels save 224 vertices / 168 tris.
            if includesBackFace {
                let backBase = UInt32(positions.count)
                for point in outline {
                    positions.append([point.x, point.y, backZ])
                    normals.append([0, 0, -1])
                }
                for index in 1..<(outline.count - 1) {
                    indices.append(contentsOf: [backBase, backBase + UInt32(index + 1), backBase + UInt32(index)])
                }
            }

            for index in outline.indices {
                let next = (index + 1) % outline.count
                let edge = outline[next] - outline[index]
                let normal2D = simd_normalize(SIMD2<Float>(edge.y, -edge.x))
                let base = UInt32(positions.count)
                positions.append([outline[index].x, outline[index].y, backZ])
                positions.append([outline[next].x, outline[next].y, backZ])
                positions.append([outline[next].x, outline[next].y, frontZ])
                positions.append([outline[index].x, outline[index].y, frontZ])
                normals.append(contentsOf: Array(
                    repeating: SIMD3<Float>(normal2D.x, normal2D.y, 0),
                    count: 4
                ))
                indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            }
        }

        mutating func appendSectionedPrism(
            sections: [(z: Float, bottom: Float, top: Float, halfWidth: Float)]
        ) {
            guard sections.count >= 2 else { return }
            let sectionPoints = sections.map { section in
                [
                    SIMD3<Float>(-section.halfWidth, section.bottom, section.z),
                    SIMD3<Float>(section.halfWidth, section.bottom, section.z),
                    SIMD3<Float>(section.halfWidth, section.top, section.z),
                    SIMD3<Float>(-section.halfWidth, section.top, section.z),
                ]
            }

            func appendQuad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) {
                // Section calls describe surfaces clockwise from outside; use
                // the reversed winding so RealityKit's back-face culling and
                // the authored flat normal both face outward.
                let rawNormal = simd_cross(c - a, b - a)
                let normal = simd_length_squared(rawNormal) > 0.000_001
                    ? simd_normalize(rawNormal)
                    : SIMD3<Float>(0, 1, 0)
                let base = UInt32(positions.count)
                positions.append(contentsOf: [a, b, c, d])
                normals.append(contentsOf: Array(repeating: normal, count: 4))
                indices.append(contentsOf: [base, base + 2, base + 1, base, base + 3, base + 2])
            }

            for index in 0..<(sectionPoints.count - 1) {
                let start = sectionPoints[index]
                let end = sectionPoints[index + 1]
                appendQuad(start[0], end[0], end[1], start[1])
                appendQuad(start[1], end[1], end[2], start[2])
                appendQuad(start[2], end[2], end[3], start[3])
                appendQuad(start[3], end[3], end[0], start[0])
            }
            let first = sectionPoints[0]
            let last = sectionPoints[sectionPoints.count - 1]
            appendQuad(first[0], first[1], first[2], first[3])
            appendQuad(last[3], last[2], last[1], last[0])
        }

        func makeAsset(named name: String) throws -> ReplayAthleteMeshAsset {
            try ReplayAthleteMeshLibrary.makeAsset(
                name: name,
                positions: positions,
                normals: normals,
                indices: indices
            )
        }
    }
}
