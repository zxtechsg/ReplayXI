import RealityKit
import XCTest
import simd
@testable import ReplayXI

@MainActor
final class ReplayArticulatedFarRuntimeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
    }
    override func tearDown() {
        ReplayArticulatedFarProvider.resetForTesting()
        ReplayFarAthleteHeadProvider.resetForTesting()
        ReplayAthleteHeadProvider.resetForTesting()
        super.tearDown()
    }
    private func scenario() throws -> ReplayScenario { try XCTUnwrap(DemoScenarios.scenario(for: .squadReplay)) }
    private func prepare() throws {
        try ReplayAthleteHeadProvider.prewarm()
        try ReplayFarAthleteHeadProvider.prewarm()
        try ReplayArticulatedFarProvider.prewarm()
    }

    func testColdAndFailedPreparationKeepTheExistingSevenModelFallback() throws {
        let match = try scenario()
        let player = try XCTUnwrap(match.player(id: "red-lw"))
        try ReplayAthleteFactory.prewarm(for: match.players, lods: [.far])
        let cold = try ReplayAthleteFactory.make(for: player, lod: .far)
        XCTAssertNil(cold.joints.articulatedFar)
        XCTAssertEqual(cold.metrics, .init(modelEntities: 7, verticesPerInstance: 399, trianglesPerInstance: 574))
        XCTAssertEqual(ReplayArticulatedFarProvider.preparationCount, 0)
        ReplayArticulatedFarProvider.resetForTesting(forceFailure: true)
        XCTAssertThrowsError(try ReplayArticulatedFarProvider.prewarm())
        XCTAssertThrowsError(try ReplayArticulatedFarProvider.prewarm())
        let fallback = try ReplayAthleteFactory.make(for: player, lod: .far)
        XCTAssertEqual(fallback.metrics, cold.metrics)
        XCTAssertNil(fallback.joints.articulatedFar)
        XCTAssertEqual(ReplayArticulatedFarProvider.preparationCount, 1)
    }

    func testBothTeamsUseIdenticalBodyGeometryAndTheUnchangedSevenDrawBudget() throws {
        let match = try scenario()
        try prepare()
        try ReplayAthleteFactory.prewarm(for: match.players, lods: [.far])
        var meshes: [String: MeshResource] = [:]
        for player in match.players {
            let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
            XCTAssertEqual(rig.root.scale, .one)
            XCTAssertEqual(rig.metrics, .init(modelEntities: 7, verticesPerInstance: 1_464, trianglesPerInstance: 2_495))
            XCTAssertTrue(rig.metrics.fits(ReplayAthleteLOD.far.budget))
            XCTAssertEqual(rig.joints.articulatedFar?.supportPointCount, 426)
            XCTAssertNil(rig.joints.farFloorSupport)
            for name in ["torso","shorts","left-leg","right-leg","left-arm","right-arm"] {
                let model = try XCTUnwrap(rig.root.findEntity(named: name) as? ModelEntity)
                let mesh = try XCTUnwrap(model.model).mesh
                if let first = meshes[name] { XCTAssertTrue(mesh === first, "Teams share shape, not just scale") }
                else { meshes[name] = mesh }
            }
        }
        XCTAssertEqual(ReplayArticulatedFarProvider.preparationCount, 1)
        XCTAssertEqual(ReplaySkinnedAthleteProvider.maximumConcurrentInstances, 4)
    }

    func testActualWeightedBootFloorAndAbsoluteTimeRewindWithArticulatedKnees() throws {
        let match = try scenario()
        try prepare()
        let times: [Double] = [0,1,10,11.6916667,12.1,13.6,14.15,17.5,23,26.54,32]
        for id in ["navy-rb","red-lw","navy-gk","red-rw"] {
            let player = try XCTUnwrap(match.player(id: id))
            let rig = try ReplayAthleteFactory.make(for: player, lod: .far)
            var snapshots: [Double: [Transform]] = [:]
            let limbs = try ["left-leg","right-leg","left-arm","right-arm"].map {
                try XCTUnwrap(rig.root.findEntity(named: $0) as? ModelEntity)
            }
            for time in times + times.reversed() {
                let ball = match.ball.pose(at: time)
                let target = SIMD3(ball.position.x,ball.height,ball.position.z)
                let authored = ReplayAthleteMotion.locomotionPose(for: player, at: time,
                    lookTargetWorldPosition: target, ballTrack: match.ball)
                ReplayAthleteMotion.update(rig, from: player, at: time,
                    lookTargetWorldPosition: target, ballTrack: match.ball)
                let y = try nativeLegMinimum(in: rig)
                XCTAssertGreaterThanOrEqual(y, -0.000_01, "\(id) @ \(time)")
                XCTAssertEqual(try XCTUnwrap(rig.joints.articulatedFar).minimumY(relativeTo: rig.root), y,
                               accuracy: 0.000_01, "Cached full-vertex support agrees with native skin data")
                XCTAssertEqual(rig.joints[.bodyRoot].position.x, authored.bodyPosition.x)
                XCTAssertEqual(rig.joints[.bodyRoot].position.z, authored.bodyPosition.z)
                XCTAssertGreaterThanOrEqual(rig.joints[.bodyRoot].position.y, authored.bodyPosition.y)
                for (model, joint) in zip(limbs, [ReplayAthleteJoint.leftKnee,.rightKnee,.leftElbow,.rightElbow]) {
                    XCTAssertEqual(model.jointTransforms[1], rig.joints[joint].transform)
                }
                let snapshot = [rig.joints[.bodyRoot].transform] + limbs.flatMap(\.jointTransforms)
                if let first = snapshots[time] { XCTAssertEqual(snapshot, first, "Exact rewind \(id) @ \(time)") }
                else { snapshots[time] = snapshot }
            }
        }
        XCTAssertEqual(ReplayArticulatedFarProvider.preparationCount, 1)
    }

    func testNearAndMidRemainUnchangedWhenTheFarFamilyWarms() throws {
        let player = try XCTUnwrap(try scenario().player(id: "red-rw"))
        let before = try [ReplayAthleteLOD.near,.mid].map { try ReplayAthleteFactory.make(for: player, lod: $0) }
        try ReplayArticulatedFarProvider.prewarm()
        for (index,lod) in [ReplayAthleteLOD.near,.mid].enumerated() {
            let after = try ReplayAthleteFactory.make(for: player, lod: lod)
            XCTAssertEqual(after.metrics, before[index].metrics)
            XCTAssertNil(after.joints.articulatedFar)
            for name in ["torso","shorts","left-thigh","left-shin","left-sleeve"] {
                let a = try XCTUnwrap(before[index].root.findEntity(named: name) as? ModelEntity)
                let b = try XCTUnwrap(after.root.findEntity(named: name) as? ModelEntity)
                XCTAssertTrue(try XCTUnwrap(a.model).mesh === XCTUnwrap(b.model).mesh)
            }
        }
    }

    /// Independent test-owned LBS from actual imported mesh weights/binds and
    /// the joint transforms read back from the live ModelEntity.
    private func nativeLegMinimum(in rig: ReplayAthleteInstance) throws -> Float {
        var minimum = Float.infinity
        for name in ["left-leg","right-leg"] {
            let model = try XCTUnwrap(rig.root.findEntity(named: name) as? ModelEntity)
            let contents = try XCTUnwrap(model.model).mesh.contents
            let skeleton = try XCTUnwrap(contents.skeletons.first)
            let part = try XCTUnwrap(contents.models.first?.parts.first)
            let joints = model.jointTransforms
            let matrices = [joints[0].matrix,joints[0].matrix*joints[1].matrix,
                            joints[0].matrix*joints[1].matrix*joints[2].matrix]
            let influences = try XCTUnwrap(part.jointInfluences).influences.elements
            let stride = influences.count / part.positions.count
            for (index,position) in part.positions.elements.enumerated() {
                var point = SIMD4<Float>.zero
                for influence in influences[(index*stride)..<((index+1)*stride)] {
                    point += (matrices[influence.jointIndex] * skeleton.joints[influence.jointIndex].inverseBindPoseMatrix
                              * SIMD4(position,1)) * influence.weight
                }
                let local = SIMD3(point.x,point.y,point.z)
                minimum = min(minimum, model.convert(position: local, to: rig.root).y)
            }
        }
        return minimum
    }
}
