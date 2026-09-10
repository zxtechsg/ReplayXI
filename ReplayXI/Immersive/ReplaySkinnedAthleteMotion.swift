import Foundation
import simd

/// Immutable, validated animation data. Decode once; every replay seek fills a
/// reusable pose directly from absolute time and travelled gait phase.
struct ReplaySkinnedAthleteMotion: Sendable {
    static let expectedJointCount = 80
    static let maximumPayloadBytes = 4 * 1_024 * 1_024

    enum ClipID: String, CaseIterable, Sendable { case idle, run }
    enum DecodeError: Error, Equatable { case invalid(String) }

    struct Joint: Sendable {
        let name: String
        let sourceName: String
        let parentIndex: Int
        let localRightAxis: SIMD3<Float>
        let localUpAxis: SIMD3<Float>
        let localForwardAxis: SIMD3<Float>
    }

    struct Pose: Sendable {
        var translations: [SIMD3<Float>]
        var rotations: [simd_quatf]
        var scales: [SIMD3<Float>]
        var modelSpaceTransforms: [simd_float4x4]
    }

    struct NumberAnchors: Sendable {
        let jointIndex: Int
        let front: SIMD3<Float>
        let back: SIMD3<Float>
    }

    struct FootContact: Sendable {
        let footJointIndex: Int
        let toeJointIndex: Int
        let solePoint: SIMD3<Float>
        let restSoleWorld: SIMD3<Float>
    }

    struct Geometry: Sendable {
        let nominalHeight: Float
        let restMinY: Float
        var soleOffsetMetres: Float { max(-restMinY, 0) }
    }

    private struct Frame: Sendable {
        let time: TimeInterval
        let translations: [SIMD3<Float>]
        let rotations: [simd_quatf]
        let scales: [SIMD3<Float>]
    }

    private struct Clip: Sendable {
        let duration: TimeInterval
        let frames: [Frame]
    }

    private struct SampleSpan {
        let lower: Int
        let upper: Int
        let weight: Float
    }

    let sourceCommit: String
    let joints: [Joint]
    let jointNames: [String]
    let semanticJointIndices: [String: Int]
    let numberAnchors: NumberAnchors
    let footContacts: [String: FootContact]
    let geometry: Geometry
    let restPose: Pose

    private let idle: Clip
    private let run: Clip

    init(data: Data) throws {
        guard data.count <= Self.maximumPayloadBytes else {
            throw DecodeError.invalid("Motion payload exceeds 4 MB")
        }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1 else { throw DecodeError.invalid("Unsupported motion version") }
        guard document.joints.count == Self.expectedJointCount,
              document.geometry.jointCount == Self.expectedJointCount else {
            throw DecodeError.invalid("Expected 80 joints")
        }
        guard !document.sourceCommit.isEmpty, document.sourceCommit.count <= 80 else {
            throw DecodeError.invalid("Invalid source identity")
        }

        var decodedJoints: [Joint] = []
        var indices: [String: Int] = [:]
        var sourceNames = Set<String>()
        var translations: [SIMD3<Float>] = []
        var rotations: [simd_quatf] = []
        var scales: [SIMD3<Float>] = []
        for (index, joint) in document.joints.enumerated() {
            guard !joint.name.isEmpty, joint.name.count <= 512,
                  !joint.sourceName.isEmpty, joint.sourceName.count <= 96,
                  indices[joint.name] == nil, sourceNames.insert(joint.sourceName).inserted else {
                throw DecodeError.invalid("Duplicate or invalid joint identity")
            }
            if index == 0 {
                guard joint.parentIndex == -1, !joint.name.contains("/") else {
                    throw DecodeError.invalid("The first joint must be the single root")
                }
            } else {
                guard (0..<index).contains(joint.parentIndex),
                      joint.name.split(separator: "/").dropLast().joined(separator: "/")
                        == document.joints[joint.parentIndex].name else {
                    throw DecodeError.invalid("Joint hierarchy is not parent-first")
                }
            }
            let right = try Self.axis(joint.localRightAxis)
            let up = try Self.axis(joint.localUpAxis)
            let forward = try Self.axis(joint.localForwardAxis)
            guard abs(simd_dot(right, up)) < 0.01,
                  abs(simd_dot(right, forward)) < 0.01,
                  abs(simd_dot(up, forward)) < 0.01,
                  simd_dot(simd_cross(right, up), forward) > 0.99 else {
                throw DecodeError.invalid("Joint axes must form an orthonormal basis")
            }
            indices[joint.name] = index
            decodedJoints.append(Joint(
                name: joint.name, sourceName: joint.sourceName, parentIndex: joint.parentIndex,
                localRightAxis: right, localUpAxis: up, localForwardAxis: forward
            ))
            translations.append(try Self.vector(joint.translation, bound: 5))
            rotations.append(try Self.quaternion(joint.rotation))
            scales.append(try Self.scale(joint.scale))
        }
        let requiredSemantics: Set<String> = [
            "hips", "spine", "chest", "neck", "head", "leftHip", "rightHip",
            "leftKnee", "rightKnee", "leftAnkle", "rightAnkle", "leftToe", "rightToe",
            "leftShoulder", "rightShoulder", "leftElbow", "rightElbow", "leftWrist", "rightWrist"
        ]
        guard requiredSemantics.isSubset(of: Set(document.semanticJoints.keys)),
              document.semanticJoints.count <= Self.expectedJointCount else {
            throw DecodeError.invalid("Missing semantic joints")
        }
        var semantics: [String: Int] = [:]
        for (semantic, name) in document.semanticJoints {
            guard let index = indices[name] else { throw DecodeError.invalid("Unknown semantic joint") }
            semantics[semantic] = index
        }
        guard semantics["hips"] == 0,
              Set(requiredSemantics.compactMap { semantics[$0] }).count == requiredSemantics.count,
              let numberIndex = indices[document.numberAnchors.joint],
              numberIndex == semantics["chest"] else {
            throw DecodeError.invalid("Invalid semantic or jersey binding")
        }
        guard document.geometry.nominalHeight.isFinite,
              (1...2.5).contains(document.geometry.nominalHeight),
              document.geometry.restMinY.isFinite,
              (-0.5...0.5).contains(document.geometry.restMinY) else {
            throw DecodeError.invalid("Invalid athlete dimensions")
        }
        var contacts: [String: FootContact] = [:]
        for (side, contact) in document.footContacts ?? [:] {
            guard ["left", "right"].contains(side),
                  let foot = indices[contact.footJoint], let toe = indices[contact.toeJoint],
                  foot == semantics[side + "Ankle"], toe == semantics[side + "Toe"] else {
                throw DecodeError.invalid("Invalid foot contact binding")
            }
            contacts[side] = FootContact(
                footJointIndex: foot, toeJointIndex: toe,
                solePoint: try Self.vector(contact.solePoint, bound: 1),
                restSoleWorld: try Self.vector(contact.restSoleWorld, bound: 5)
            )
        }
        guard document.clips.count == ClipID.allCases.count,
              Set(document.clips.map(\.id)) == Set(ClipID.allCases.map(\.rawValue)) else {
            throw DecodeError.invalid("Expected one idle clip and one run clip")
        }
        let decodedClips = try document.clips.map { raw -> (String, Clip) in
            guard raw.durationSeconds.isFinite, (0.05...20).contains(raw.durationSeconds),
                  raw.fps.isFinite, (1...120).contains(raw.fps),
                  (2...2_401).contains(raw.frames.count),
                  abs(raw.frames[0].time) <= 0.000_001,
                  abs(raw.frames[raw.frames.count - 1].time - raw.durationSeconds) <= 0.000_01 else {
                throw DecodeError.invalid("Invalid clip timing")
            }
            var previousTime = -Double.infinity
            var frames: [Frame] = []
            frames.reserveCapacity(raw.frames.count)
            for frame in raw.frames {
                guard frame.time.isFinite, frame.time >= 0,
                      frame.time <= raw.durationSeconds + 0.000_01,
                      frame.time > previousTime,
                      frame.translations.count == Self.expectedJointCount,
                      frame.rotations.count == Self.expectedJointCount,
                      frame.scales.count == Self.expectedJointCount else {
                    throw DecodeError.invalid("Invalid frame order or joint count")
                }
                let translations = try frame.translations.map { try Self.vector($0, bound: 5) }
                guard abs(translations[0].x) < 0.001, abs(translations[0].z) < 0.001 else {
                    throw DecodeError.invalid("Source root travel must be removed")
                }
                frames.append(Frame(
                    time: frame.time,
                    translations: translations,
                    rotations: try frame.rotations.map { try Self.quaternion($0) },
                    scales: try frame.scales.map { try Self.scale($0) }
                ))
                previousTime = frame.time
            }
            return (raw.id, Clip(duration: raw.durationSeconds, frames: frames))
        }
        let clips = Dictionary(uniqueKeysWithValues: decodedClips)
        guard let idle = clips[ClipID.idle.rawValue], let run = clips[ClipID.run.rawValue] else {
            throw DecodeError.invalid("Missing clip")
        }
        self.sourceCommit = document.sourceCommit
        self.joints = decodedJoints
        self.jointNames = decodedJoints.map(\.name)
        self.semanticJointIndices = semantics
        self.geometry = Geometry(nominalHeight: document.geometry.nominalHeight, restMinY: document.geometry.restMinY)
        self.numberAnchors = NumberAnchors(
            jointIndex: numberIndex,
            front: try Self.vector(document.numberAnchors.front, bound: 1),
            back: try Self.vector(document.numberAnchors.back, bound: 1)
        )
        self.footContacts = contacts
        self.idle = idle
        self.run = run
        var pose = Pose(translations: translations, rotations: rotations, scales: scales,
                        modelSpaceTransforms: Array(repeating: matrix_identity_float4x4, count: decodedJoints.count))
        Self.rebuildHierarchy(joints: decodedJoints, pose: &pose)
        self.restPose = pose
    }

    func duration(of clip: ClipID) -> TimeInterval { clip == .idle ? idle.duration : run.duration }

    /// The first write owns each array through copy-on-write. Reusing the same
    /// buffer thereafter avoids per-frame decoding and pose-array allocation.
    func makePoseBuffer() -> Pose { restPose }

    func sample(
        clip: ClipID, at time: TimeInterval, looping: Bool = true,
        rebuildingModelSpace: Bool = true, into pose: inout Pose
    ) {
        ensureBuffer(&pose)
        let selected = clip == .idle ? idle : run
        let span = Self.span(in: selected, time: time, looping: looping)
        let first = selected.frames[span.lower]
        let second = selected.frames[span.upper]
        for index in joints.indices {
            pose.translations[index] = Self.lerp(first.translations[index], second.translations[index], span.weight)
            pose.rotations[index] = Self.shortestSlerp(first.rotations[index], second.rotations[index], span.weight)
            pose.scales[index] = Self.lerp(first.scales[index], second.scales[index], span.weight)
        }
        if rebuildingModelSpace { Self.rebuildHierarchy(joints: joints, pose: &pose) }
    }

    /// Gait phase is radians from the player's track. It controls the run cycle
    /// even when seeking backwards; playback speed never advances a hidden clock.
    func sample(
        time: TimeInterval, locomotionEffort: Float, gaitPhase: Float,
        rebuildingModelSpace: Bool = true, into pose: inout Pose
    ) {
        ensureBuffer(&pose)
        let effort = locomotionEffort.isFinite ? min(max(locomotionEffort, 0), 1) : 0
        let linearWeight = min(max((effort - 0.02) / 0.20, 0), 1)
        let runWeight = linearWeight * linearWeight * (3 - 2 * linearWeight)
        let phase = gaitPhase.isFinite ? Double(gaitPhase) : 0
        let runTime = Self.wrapped(phase, duration: 2 * .pi) / (2 * .pi) * run.duration
        // Most athletes are fully idle or running. Avoid sampling a second clip
        // at these endpoints and keep a full run exactly independent of idle time.
        if runWeight <= 0 {
            sample(clip: .idle, at: time, rebuildingModelSpace: rebuildingModelSpace, into: &pose)
            return
        }
        if runWeight >= 1 {
            sample(clip: .run, at: runTime, rebuildingModelSpace: rebuildingModelSpace, into: &pose)
            return
        }
        let idleSpan = Self.span(in: idle, time: time, looping: true)
        let runSpan = Self.span(in: run, time: runTime, looping: true)
        let idleStart = idle.frames[idleSpan.lower], idleEnd = idle.frames[idleSpan.upper]
        let runStart = run.frames[runSpan.lower], runEnd = run.frames[runSpan.upper]
        for index in joints.indices {
            let idleTranslation = Self.lerp(idleStart.translations[index], idleEnd.translations[index], idleSpan.weight)
            let runTranslation = Self.lerp(runStart.translations[index], runEnd.translations[index], runSpan.weight)
            let idleRotation = Self.shortestSlerp(idleStart.rotations[index], idleEnd.rotations[index], idleSpan.weight)
            let runRotation = Self.shortestSlerp(runStart.rotations[index], runEnd.rotations[index], runSpan.weight)
            let idleScale = Self.lerp(idleStart.scales[index], idleEnd.scales[index], idleSpan.weight)
            let runScale = Self.lerp(runStart.scales[index], runEnd.scales[index], runSpan.weight)
            pose.translations[index] = Self.lerp(idleTranslation, runTranslation, runWeight)
            pose.rotations[index] = Self.shortestSlerp(idleRotation, runRotation, runWeight)
            pose.scales[index] = Self.lerp(idleScale, runScale, runWeight)
        }
        if rebuildingModelSpace { Self.rebuildHierarchy(joints: joints, pose: &pose) }
    }

    /// Call after applying local head/neck adjustments. Parent-first traversal
    /// gives jersey and sole anchors the exact same pose as the skinned mesh.
    func rebuildModelSpaceTransforms(in pose: inout Pose) {
        ensureBuffer(&pose)
        Self.rebuildHierarchy(joints: joints, pose: &pose)
    }

    private func ensureBuffer(_ pose: inout Pose) {
        if pose.translations.count != joints.count || pose.rotations.count != joints.count
            || pose.scales.count != joints.count || pose.modelSpaceTransforms.count != joints.count {
            pose = makePoseBuffer()
        }
    }

    private static func rebuildHierarchy(joints: [Joint], pose: inout Pose) {
        for index in joints.indices {
            var local = simd_float4x4(pose.rotations[index])
            local.columns.0 *= pose.scales[index].x
            local.columns.1 *= pose.scales[index].y
            local.columns.2 *= pose.scales[index].z
            local.columns.3 = SIMD4<Float>(pose.translations[index], 1)
            let parent = joints[index].parentIndex
            pose.modelSpaceTransforms[index] = parent < 0 ? local : pose.modelSpaceTransforms[parent] * local
        }
    }

    private static func span(in clip: Clip, time: TimeInterval, looping: Bool) -> SampleSpan {
        let safeTime = time.isFinite ? time : 0
        let time = looping ? wrapped(safeTime, duration: clip.duration) : min(max(safeTime, 0), clip.duration)
        if time <= clip.frames[0].time { return SampleSpan(lower: 0, upper: 0, weight: 0) }
        let last = clip.frames.count - 1
        if time >= clip.frames[last].time { return SampleSpan(lower: last, upper: last, weight: 0) }
        var lower = 0, upper = clip.frames.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if clip.frames[middle].time <= time { lower = middle + 1 } else { upper = middle }
        }
        let start = lower - 1, end = lower
        let weight = Float((time - clip.frames[start].time) / (clip.frames[end].time - clip.frames[start].time))
        return SampleSpan(lower: start, upper: end, weight: min(max(weight, 0), 1))
    }

    private static func wrapped(_ value: Double, duration: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: duration)
        return remainder < 0 ? remainder + duration : remainder
    }

    private static func lerp(_ start: SIMD3<Float>, _ end: SIMD3<Float>, _ weight: Float) -> SIMD3<Float> {
        start + (end - start) * weight
    }

    private static func shortestSlerp(_ start: simd_quatf, _ end: simd_quatf, _ weight: Float) -> simd_quatf {
        let target = simd_dot(start.vector, end.vector) < 0 ? simd_quatf(vector: -end.vector) : end
        return simd_normalize(simd_slerp(start, target, weight))
    }

    private static func vector(_ values: [Float], bound: Float) throws -> SIMD3<Float> {
        guard values.count == 3, values.allSatisfy({ $0.isFinite && abs($0) <= bound }) else {
            throw DecodeError.invalid("Invalid three-component vector")
        }
        return SIMD3(values[0], values[1], values[2])
    }

    private static func axis(_ values: [Float]) throws -> SIMD3<Float> {
        let axis = try vector(values, bound: 1.01)
        guard abs(simd_length_squared(axis) - 1) < 0.01 else { throw DecodeError.invalid("Invalid local axis") }
        return simd_normalize(axis)
    }

    private static func scale(_ values: [Float]) throws -> SIMD3<Float> {
        let scale = try vector(values, bound: 10)
        guard scale.x >= 0.001, scale.y >= 0.001, scale.z >= 0.001 else {
            throw DecodeError.invalid("Joint scale must be positive")
        }
        return scale
    }

    private static func quaternion(_ values: [Float]) throws -> simd_quatf {
        guard values.count == 4, values.allSatisfy(\.isFinite) else {
            throw DecodeError.invalid("Invalid quaternion")
        }
        let vector = SIMD4<Float>(values[0], values[1], values[2], values[3])
        guard abs(simd_length_squared(vector) - 1) < 0.01 else {
            throw DecodeError.invalid("Quaternion is not unit length")
        }
        return simd_normalize(simd_quatf(vector: vector))
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let sourceCommit: String
        let joints: [RawJoint]
        let semanticJoints: [String: String]
        let clips: [RawClip]
        let geometry: RawGeometry
        let numberAnchors: RawNumberAnchors
        let footContacts: [String: RawFootContact]?
    }
    private struct RawJoint: Decodable {
        let name: String
        let sourceName: String
        let parentIndex: Int
        let translation: [Float]
        let rotation: [Float]
        let scale: [Float]
        let localRightAxis: [Float]
        let localUpAxis: [Float]
        let localForwardAxis: [Float]
    }
    private struct RawClip: Decodable {
        let id: String
        let durationSeconds: Double
        let fps: Double
        let frames: [RawFrame]
    }
    private struct RawFrame: Decodable {
        let time: Double
        let translations: [[Float]]
        let rotations: [[Float]]
        let scales: [[Float]]
    }
    private struct RawGeometry: Decodable {
        let jointCount: Int
        let nominalHeight: Float
        let restMinY: Float
    }
    private struct RawNumberAnchors: Decodable {
        let joint: String
        let front: [Float]
        let back: [Float]
    }
    private struct RawFootContact: Decodable {
        let footJoint: String
        let toeJoint: String
        let solePoint: [Float]
        let restSoleWorld: [Float]
    }
}
