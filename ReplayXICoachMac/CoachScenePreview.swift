import SwiftUI
import SceneKit
import simd

enum CoachSceneGeometry {
    static let overviewPosition = SIMD3<Float>(55, 88, 82)
    static let overviewTarget = SIMD3<Float>(0, 0, 0)
    static let overviewFieldOfView: CGFloat = 60

    static func pitchRing(radius: CGFloat, pipeRadius: CGFloat) -> SCNNode {
        SCNNode(geometry: SCNTorus(ringRadius: radius, pipeRadius: pipeRadius))
    }

    static func headingTarget(position: ReplayXIWirePoint, facingDegrees: Float) -> SIMD3<Float> {
        let yaw = facingDegrees * .pi / 180
        return [position.x + sin(yaw) * 10, 1.5, position.z + cos(yaw) * 10]
    }

    static func arcPoint(from a: SIMD3<Float>, to b: SIMD3<Float>, control c: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        (1 - t) * (1 - t) * a + 2 * (1 - t) * t * c + t * t * b
    }

    struct AnnotationFrame {
        let position: SIMD3<Float>
        let target: SIMD3<Float>
        let farPlane: Double
    }

    static func annotationFrame(_ mark: ReplayXIWireMark, size: CGSize,
                                fieldOfView: CGFloat) -> AnnotationFrame {
        let a = SIMD3<Float>(mark.start.x, mark.startHeight, mark.start.z)
        let b = SIMD3<Float>(mark.end.x, mark.endHeight, mark.end.z)
        let centre: SIMD3<Float>
        let radius: Float
        if mark.kind == "space" {
            centre = [a.x, (a.y + b.y) / 2, a.z]
            // The endpoint sets a radius, not a bounding-box corner. Include
            // the torus thickness and editing handles in the framed sphere.
            radius = max(5, CoachWorkspace.zoneRadius(start: mark.start, end: mark.end) * 1.1 + 0.8)
        } else {
            let c = mark.controlPoint.map { SIMD3<Float>($0.x, $0.y, $0.z) } ?? (a + b) / 2
            let minimum = simd_min(a, simd_min(b, c)), maximum = simd_max(a, simd_max(b, c))
            centre = (minimum + maximum) / 2
            radius = max(5, simd_distance(minimum, maximum) / 2 + 1.5)
        }
        let aspect = size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
            ? Float(size.width / size.height) : 1
        let fov = fieldOfView.isFinite && (1..<179).contains(fieldOfView)
            ? fieldOfView : overviewFieldOfView
        let vertical = Float(fov) * .pi / 360
        let halfAngle = min(vertical, atan(tan(vertical) * aspect))
        let distance = radius / sin(halfAngle) * 1.08
        return AnnotationFrame(position: centre + simd_normalize(SIMD3<Float>(0.55, 0.95, 1)) * distance,
            target: centre, farPlane: max(500, Double(distance + radius + 5)))
    }

    static func planeIntersection(near a: SIMD3<Float>, far b: SIMD3<Float>, height: Float) -> SIMD3<Float>? {
        let ray = b - a
        guard height.isFinite, abs(ray.y) > 0.0001 else { return nil }
        let t = (height - a.y) / ray.y
        guard t.isFinite, t >= 0 else { return nil }
        let point = a + ray * t
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { return nil }
        return point
    }

    /// SceneKit's unprojectPoint needs a rendered viewport. Derive the pick
    /// ray from the live camera instead, so the first drag works too.
    static func pitchPoint(screen: CGPoint, size: CGSize, camera: SCNNode,
                           fieldOfView: CGFloat, height: Float) -> SIMD3<Float>? {
        guard size.width > 0, size.height > 0, fieldOfView.isFinite,
              (1..<179).contains(fieldOfView) else { return nil }
        let tangent = Float(tan(fieldOfView * .pi / 360))
        let aspect = Float(size.width / size.height)
        let local = SIMD3<Float>(
            (Float(screen.x / size.width) * 2 - 1) * aspect * tangent,
            (Float(screen.y / size.height) * 2 - 1) * tangent, -1)
        let transform = camera.simdWorldTransform
        let rotation = simd_float3x3(columns: (
            SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)))
        let origin = camera.simdWorldPosition
        return planeIntersection(near: origin, far: origin + rotation * local, height: height)
    }

    static func canCommit(dragRevision: UInt64, dragScenarioID: String, markID: UUID,
                          state: ReplayXIWireState, selectedMarkID: UUID?) -> Bool {
        state.canEdit && state.revision == dragRevision && state.scenarioID == dragScenarioID &&
            selectedMarkID == markID
    }
}

/// A local, lightweight 3D editor, not a second football simulation. Every
/// player, ball and annotation position comes from the headset's wire state.
struct CoachScenePreview: View {
    let state: ReplayXIWireState
    let selectedMarkID: UUID?
    let drawingEnabled: Bool
    let drawStart: ReplayXIWirePoint?
    let resetRevision: Int
    let select: (UUID) -> Void
    let onPlayer: (String) -> Void
    let onPitchClick: (ReplayXIWirePoint) -> Void
    let onPose: (ReplayXIWireMark, ReplayXIWirePoint3, ReplayXIWirePoint3, ReplayXIWirePoint3?) -> Void
    @State private var playerView = false
    @State private var focusRevision = 0

    var body: some View {
        CoachSceneSurface(state: state, selectedMarkID: selectedMarkID,
            drawingEnabled: drawingEnabled, drawStart: drawStart,
            resetRevision: resetRevision, playerView: playerView, focusRevision: focusRevision,
            select: select, onPlayer: { id in playerView = true; onPlayer(id) },
            onPitchClick: onPitchClick, onPose: onPose)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                Picker("Camera", selection: $playerView) {
                    Text("Overview").tag(false)
                    Text("Player POV").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
                Button {
                    playerView = false; focusRevision += 1
                } label: { Image(systemName: "scope") }
                    .help("Frame selected annotation").accessibilityLabel("Frame selected annotation")
                    .disabled(selectedMarkID == nil)
                }.padding(10)
            }
            .overlay(alignment: .bottomLeading) {
                Text(drawingEnabled ? (drawStart == nil ? "Click origin" : "Click destination") :
                     playerView ? "Player POV · select a player to change view" :
                     "Drag: orbit · Scroll: zoom · Drag points: move · Shift-drag: height")
                    .font(.caption).padding(8).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .padding(10).allowsHitTesting(false)
            }
            .onChange(of: resetRevision) { _, _ in playerView = false }
    }
}

struct CoachSceneSurface: NSViewRepresentable {
    let state: ReplayXIWireState
    let selectedMarkID: UUID?
    let drawingEnabled: Bool
    let drawStart: ReplayXIWirePoint?
    let resetRevision: Int
    let playerView: Bool
    var focusRevision: Int = 0
    let select: (UUID) -> Void
    let onPlayer: (String) -> Void
    let onPitchClick: (ReplayXIWirePoint) -> Void
    let onPose: (ReplayXIWireMark, ReplayXIWirePoint3, ReplayXIWirePoint3, ReplayXIWirePoint3?) -> Void

    func makeNSView(context: Context) -> CoachSceneView { CoachSceneView(frame: .zero) }
    func updateNSView(_ view: CoachSceneView, context: Context) { view.update(self) }
}

final class CoachSceneView: SCNView {
    private let world = SCNScene()
    private let cameraNode = SCNNode()
    private let ballNode = SCNNode(geometry: SCNSphere(radius: 0.35))
    private let drawNode = SCNNode(geometry: SCNSphere(radius: 0.55))
    private var players: [String: CoachScenePlayer] = [:]
    private let marks = CoachSceneMarkCache()
    private var stalePlayerIDs: [String] = []
    private var configuration: CoachSceneSurface?
    private var resetRevision: Int?
    private var scenarioID: String?
    private var wasPlayerView = false
    private var focusRevision = 0
    private struct Drag {
        let mark: ReplayXIWireMark
        let handle: String
        let location: CGPoint
        let origin: SIMD3<Float>
        let vertical: Bool
        let revision: UInt64
        let scenarioID: String
        var point: SIMD3<Float>
    }
    private var drag: Drag?
    private var cameraDrag = false

    override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        scene = world
        backgroundColor = NSColor(calibratedWhite: 0.045, alpha: 1)
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 30
        rendersContinuously = false
        allowsCameraControl = true
        autoenablesDefaultLighting = true
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.05
        cameraNode.camera?.zFar = 500
        cameraNode.camera?.fieldOfView = CoachSceneGeometry.overviewFieldOfView
        world.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode
        let ground = SCNNode(geometry: SCNPlane(width: 68, height: 105))
        ground.eulerAngles.x = -.pi / 2
        ground.position.y = -0.03
        ground.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.07, green: 0.27, blue: 0.17, alpha: 1)
        world.rootNode.addChildNode(ground)
        for z in stride(from: -52.5, through: 52.5, by: 10.5) {
            let stripe = SCNNode(geometry: SCNPlane(width: 68, height: 5.25))
            stripe.eulerAngles.x = -.pi / 2; stripe.position = .init(0, -0.02, Float(z + 2.625))
            stripe.geometry?.firstMaterial?.diffuse.contents = NSColor.white.withAlphaComponent(0.025)
            world.rootNode.addChildNode(stripe)
        }
        func line(_ a: SIMD3<Float>, _ b: SIMD3<Float>) {
            world.rootNode.addChildNode(CoachSceneMark.segment(from: a, to: b, radius: 0.08, color: .white))
        }
        for z: Float in [-52.5, 52.5] { line([-34, 0, z], [34, 0, z]) }
        for x: Float in [-34, 34] { line([x, 0, -52.5], [x, 0, 52.5]) }
        line([-34, 0, 0], [34, 0, 0])
        let circle = CoachSceneGeometry.pitchRing(radius: 9.15, pipeRadius: 0.08)
        world.rootNode.addChildNode(circle)
        for side: Float in [-1, 1] {
            let z = side * 52.5, box = side * 36
            line([-20.16, 0, z], [-20.16, 0, box]); line([-20.16, 0, box], [20.16, 0, box])
            line([20.16, 0, box], [20.16, 0, z])
            line([-3.66, 0, z], [-3.66, 2.44, z]); line([-3.66, 2.44, z], [3.66, 2.44, z])
            line([3.66, 2.44, z], [3.66, 0, z])
        }
        ballNode.geometry?.firstMaterial?.diffuse.contents = NSColor.white
        world.rootNode.addChildNode(ballNode)
        drawNode.geometry?.firstMaterial?.diffuse.contents = NSColor.systemOrange
        world.rootNode.addChildNode(drawNode)
        overview()
        setAccessibilityLabel("Live 3D annotation editor")
        setAccessibilityHelp("Drag to orbit. Scroll to zoom. Drag yellow handles on the pitch, or Shift-drag to change height. Cyan adjusts the arc.")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ next: CoachSceneSurface) {
        let changedScene = scenarioID != next.state.scenarioID
        if let drag, drag.revision != next.state.revision || next.selectedMarkID != drag.mark.id || !next.state.canEdit {
            self.drag = nil
        }
        configuration = next
        if changedScene || resetRevision != next.resetRevision || (wasPlayerView && !next.playerView) {
            overview()
        }
        resetRevision = next.resetRevision; scenarioID = next.state.scenarioID; wasPlayerView = next.playerView
        if next.focusRevision != focusRevision,
           let mark = next.state.marks.first(where: { $0.id == next.selectedMarkID }) {
            focus(mark)
        }
        focusRevision = next.focusRevision
        allowsCameraControl = !next.playerView && drag == nil
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        for player in next.state.players {
            let node = players[player.id] ?? makePlayer(player)
            node.update(player)
        }
        stalePlayerIDs.removeAll(keepingCapacity: true)
        for id in players.keys where !next.state.players.contains(where: { $0.id == id }) {
            stalePlayerIDs.append(id)
        }
        for id in stalePlayerIDs { players.removeValue(forKey: id)?.root.removeFromParentNode() }
        ballNode.simdPosition = [next.state.ball.x, max(0.11, next.state.ball.y), next.state.ball.z]
        drawNode.isHidden = next.drawStart == nil
        if let start = next.drawStart { drawNode.simdPosition = [start.x, 0.1, start.z] }
        marks.update(next.state.marks, selectedID: next.selectedMarkID,
            editable: next.state.canEdit, time: next.state.playhead, parent: world.rootNode)
        if let drag { preview(drag) }
        if next.playerView, let player = next.state.players.first(where: { $0.id == next.state.perspectiveID }) {
            cameraNode.simdPosition = [player.position.x, 1.72, player.position.z]
            let target = CoachSceneGeometry.headingTarget(position: player.position,
                                                          facingDegrees: player.facingDegrees ?? 0)
            cameraNode.look(at: .init(target.x, target.y, target.z),
                            up: .init(0, 1, 0), localFront: .init(0, 0, -1))
            pointOfView = cameraNode
            for (id, node) in players { node.root.isHidden = id == player.id }
        } else { for node in players.values { node.root.isHidden = false } }
        SCNTransaction.commit()
        needsDisplay = true
    }

    private func overview() {
        cameraNode.simdPosition = CoachSceneGeometry.overviewPosition
        cameraNode.camera?.zFar = 500
        let target = CoachSceneGeometry.overviewTarget
        cameraNode.look(at: .init(target.x, target.y, target.z),
                        up: .init(0, 1, 0), localFront: .init(0, 0, -1))
        pointOfView = cameraNode
        defaultCameraController.target = .init(target.x, target.y, target.z)
        defaultCameraController.clearRoll()
    }

    private func focus(_ mark: ReplayXIWireMark) {
        let frame = CoachSceneGeometry.annotationFrame(mark, size: bounds.size,
            fieldOfView: cameraNode.camera?.fieldOfView ?? CoachSceneGeometry.overviewFieldOfView)
        let centre = frame.target
        cameraNode.simdPosition = frame.position
        cameraNode.camera?.zFar = frame.farPlane
        cameraNode.look(at: .init(centre.x, centre.y, centre.z),
                        up: .init(0, 1, 0), localFront: .init(0, 0, -1))
        pointOfView = cameraNode
        defaultCameraController.target = .init(centre.x, centre.y, centre.z)
        defaultCameraController.clearRoll()
    }

    private func makePlayer(_ player: ReplayXIWirePlayer) -> CoachScenePlayer {
        let result = CoachScenePlayer()
        players[player.id] = result
        world.rootNode.addChildNode(result.root)
        return result
    }

    override func mouseDown(with event: NSEvent) {
        guard let c = configuration else { return }
        let location = convert(event.locationInWindow, from: nil)
        let hits = hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
        if !c.drawingEnabled, c.state.canEdit, let id = c.selectedMarkID,
           let mark = c.state.marks.first(where: { $0.id == id && !$0.authored }),
           let hit = hits.first(where: { $0.node.name?.hasPrefix("handle:") == true }),
           let handle = hit.node.name?.split(separator: ":").last {
            let point = hit.node.simdWorldPosition
            drag = .init(mark: mark, handle: String(handle), location: location, origin: point,
                         vertical: event.modifierFlags.contains(.shift), revision: c.state.revision,
                         scenarioID: c.state.scenarioID, point: point)
            allowsCameraControl = false
            return
        }
        if c.drawingEnabled {
            if c.state.canEdit, let point = planePoint(location, height: 0),
               abs(point.x) <= 34, abs(point.z) <= 52.5 {
                c.onPitchClick(.init(x: point.x, z: point.z))
            }
            return
        }
        for hit in hits {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, name.hasPrefix("player:") {
                    c.onPlayer(String(name.dropFirst(7))); return
                }
                if let name = current.name, name.hasPrefix("mark:"), let id = UUID(uuidString: String(name.dropFirst(5))) {
                    c.select(id); return
                }
                node = current.parent
            }
        }
        cameraDrag = true; super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag else { if cameraDrag { super.mouseDragged(with: event) }; return }
        let location = convert(event.locationInWindow, from: nil)
        if drag.vertical {
            drag.point.y = min(max(0, drag.origin.y + Float(location.y - drag.location.y) * 0.035),
                               drag.handle == "control" ? 12 : 4)
        } else if let point = planePoint(location, height: drag.origin.y) {
            // Preserve the grab offset, instead of snapping a handle centre to
            // the cursor at the first drag sample.
            let initial = planePoint(drag.location, height: drag.origin.y) ?? drag.origin
            drag.point = drag.origin + point - initial
            drag.point.x = min(max(-34, drag.point.x), 34); drag.point.z = min(max(-52.5, drag.point.z), 52.5)
        }
        self.drag = drag; preview(drag); needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let drag, let c = configuration {
            self.drag = nil; allowsCameraControl = !c.playerView
            guard CoachSceneGeometry.canCommit(dragRevision: drag.revision,
                  dragScenarioID: drag.scenarioID, markID: drag.mark.id,
                  state: c.state, selectedMarkID: c.selectedMarkID) else { update(c); return }
            let pose = edited(drag)
            c.onPose(drag.mark, pose.start, pose.end, pose.control)
            // Drop the preview immediately; only acknowledged state is truth.
            update(c)
        } else if cameraDrag { super.mouseUp(with: event) }
        cameraDrag = false
    }

    override func cancelOperation(_ sender: Any?) {
        drag = nil; cameraDrag = false
        if let configuration { update(configuration) }
    }

    private func planePoint(_ location: CGPoint, height: Float) -> SIMD3<Float>? {
        CoachSceneGeometry.pitchPoint(screen: location, size: bounds.size,
            camera: cameraNode, fieldOfView: cameraNode.camera?.fieldOfView ?? 60,
            height: height)
    }

    private func edited(_ drag: Drag) -> (start: ReplayXIWirePoint3, end: ReplayXIWirePoint3, control: ReplayXIWirePoint3?) {
        let p = ReplayXIWirePoint3(x: drag.point.x, y: drag.point.y, z: drag.point.z)
        let m = drag.mark
        let zoneHeight = m.kind == "space" ? p.y : nil
        return (drag.handle == "start" ? p : .init(x: m.start.x, y: zoneHeight ?? m.startHeight, z: m.start.z),
                drag.handle == "end" ? p : .init(x: m.end.x, y: zoneHeight ?? m.endHeight, z: m.end.z),
                drag.handle == "control" ? p : m.controlPoint)
    }

    private func preview(_ drag: Drag) {
        let p = edited(drag)
        var mark = drag.mark
        mark.start = .init(x: p.start.x, z: p.start.z); mark.startHeight = p.start.y
        mark.end = .init(x: p.end.x, z: p.end.z); mark.endHeight = p.end.y
        if mark.kind == "space" { mark.endHeight = mark.startHeight }
        mark.controlPoint = p.control
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        marks[mark.id]?.update(mark, selected: true, editable: true, visible: true)
        SCNTransaction.commit()
    }
}

/// Lightweight preview geometry, with identity updates even when a study
/// reuses a player ID. Unchanged wire frames do not rewrite native properties.
final class CoachScenePlayer {
    let root = SCNNode()
    private let body = SCNNode(geometry: SCNCapsule(capRadius: 0.29, height: 1.25))
    private let number = SCNText(string: "", extrusionDepth: 0)
    private var previous: ReplayXIWirePlayer?

    init() {
        body.position.y = 0.8
        root.addChildNode(body)
        let head = SCNNode(geometry: SCNSphere(radius: 0.20))
        head.position.y = 1.63
        head.geometry?.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.7, alpha: 1)
        root.addChildNode(head)
        number.font = .monospacedDigitSystemFont(ofSize: 1.8, weight: .bold)
        number.flatness = 0.3
        number.firstMaterial?.diffuse.contents = NSColor.white
        let label = SCNNode(geometry: number)
        label.position = .init(-0.5, 2.05, 0)
        label.constraints = [SCNBillboardConstraint()]
        root.addChildNode(label)
    }

    func update(_ player: ReplayXIWirePlayer) {
        guard previous != player else { return }
        if previous?.id != player.id { root.name = "player:\(player.id)" }
        if previous?.team != player.team {
            body.geometry?.firstMaterial?.diffuse.contents = player.team == "home"
                ? NSColor.systemBlue : NSColor.systemRed
        }
        if previous?.number != player.number { number.string = "\(player.number)" }
        if previous?.position != player.position {
            root.simdPosition = [player.position.x, 0, player.position.z]
        }
        if previous == nil || previous?.facingDegrees != player.facingDegrees {
            root.eulerAngles.y = CGFloat((player.facingDegrees ?? 0) * .pi / 180)
        }
        previous = player
    }
}

/// Only displayed marks own SceneKit geometry. Seeking recreates a newly
/// visible mark from the current wire pose, never from a stale hidden frame.
final class CoachSceneMarkCache {
    private var nodes: [UUID: CoachSceneMark] = [:]

    subscript(id: UUID) -> CoachSceneMark? { nodes[id] }
    var count: Int { nodes.count }

    func update(_ marks: [ReplayXIWireMark], selectedID: UUID?, editable: Bool,
                time: TimeInterval, parent: SCNNode) {
        var retained = Set<UUID>()
        for mark in marks {
            let visible = CoachWorkspace.isVisible(mark, at: time)
            let selected = mark.id == selectedID
            guard visible || selected else { continue }
            retained.insert(mark.id)
            let node: CoachSceneMark
            if let existing = nodes[mark.id] {
                node = existing
            } else {
                node = CoachSceneMark()
                nodes[mark.id] = node
                parent.addChildNode(node.root)
            }
            node.update(mark, selected: selected, editable: editable && !mark.authored, visible: visible)
        }
        for id in Array(nodes.keys) where !retained.contains(id) {
            nodes.removeValue(forKey: id)?.root.removeFromParentNode()
        }
    }
}

final class CoachSceneMark {
    /// Wire timing, anchors and encoded edit history do not alter an already
    /// resolved pose. Compare only fields used by this renderer.
    private struct RenderInput: Equatable {
        let id: UUID
        let kind: String
        let start: ReplayXIWirePoint
        let end: ReplayXIWirePoint
        let startHeight: Float
        let endHeight: Float
        let control: ReplayXIWirePoint3?
        let label: String
        let authored: Bool
        let selected: Bool
        let editable: Bool
        let visible: Bool
    }

    let root = SCNNode()
    private var segments: [SCNNode] = []
    private let tip = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.65, height: 1.65))
    private let zone = CoachSceneGeometry.pitchRing(radius: 1, pipeRadius: 0.035)
    private var handles: [String: SCNNode] = [:]
    private var guides: [SCNNode] = []
    private let label = SCNNode()
    private var previous: RenderInput?
    var segmentCount: Int { segments.count }
    private(set) var geometryUpdateCount = 0

    init() {
        root.addChildNode(tip); root.addChildNode(zone)
        let text = SCNText(string: "", extrusionDepth: 0)
        text.font = .systemFont(ofSize: 1.1, weight: .semibold)
        text.flatness = 0.5; text.firstMaterial?.diffuse.contents = NSColor.white
        label.geometry = text; label.constraints = [SCNBillboardConstraint()]
        root.addChildNode(label)
        for _ in 0..<2 {
            let guide = Self.segment(from: .zero, to: [0, 1, 0], radius: 0.055, color: .systemCyan)
            guide.opacity = 0.35; guides.append(guide); root.addChildNode(guide)
        }
        for name in ["start", "end", "control"] {
            let node = SCNNode(geometry: SCNSphere(radius: name == "control" ? 0.8 : 0.7))
            node.name = "handle:\(name)"
            node.geometry?.firstMaterial?.diffuse.contents = name == "control" ? NSColor.systemCyan : NSColor.systemYellow
            handles[name] = node; root.addChildNode(node)
        }
    }

    func update(_ mark: ReplayXIWireMark, selected: Bool, editable: Bool, visible: Bool) {
        let input = RenderInput(id: mark.id, kind: mark.kind, start: mark.start, end: mark.end,
            startHeight: mark.startHeight, endHeight: mark.endHeight, control: mark.controlPoint,
            label: mark.label, authored: mark.authored, selected: selected, editable: editable, visible: visible)
        guard previous != input else { return }
        geometryUpdateCount &+= 1
        previous = input
        root.name = "mark:\(mark.id.uuidString)"
        root.isHidden = !visible && !selected
        root.opacity = visible ? 1 : 0.25
        let a = SIMD3<Float>(mark.start.x, mark.startHeight + 0.12, mark.start.z)
        let b = SIMD3<Float>(mark.end.x, mark.endHeight + 0.12, mark.end.z)
        let c = mark.controlPoint.map { SIMD3<Float>($0.x, $0.y + 0.12, $0.z) }
        label.isHidden = !(selected || mark.kind == "playerLabel")
        if let text = label.geometry as? SCNText, text.string as? String != mark.label {
            text.string = mark.label
            let bounds = label.boundingBox
            label.pivot = SCNMatrix4MakeTranslation((bounds.min.x + bounds.max.x) / 2, 0, 0)
        }
        label.simdPosition = mark.kind == "playerLabel" ? a + [0, 2.8, 0] : (a + b) / 2 + [0, 1.5, 0]
        for (index, guide) in guides.enumerated() {
            guide.isHidden = !selected || c == nil
            if let c { Self.place(guide, from: index == 0 ? a : b, to: c) }
        }
        let count = mark.kind == "space" || mark.kind == "playerLabel" ? 0
            : mark.kind == "arc" && c != nil ? 32 : 1
        while segments.count > count { segments.removeLast().removeFromParentNode() }
        while segments.count < count {
            let node = Self.segment(from: .zero, to: [0, 1, 0], radius: 0.16, color: .systemOrange)
            node.name = "path-segment-\(segments.count)"
            segments.append(node); root.addChildNode(node)
        }
        var last = a, direction = b - a
        let color: NSColor = selected ? .systemYellow : mark.authored ? .systemCyan : .systemOrange
        for (index, node) in segments.enumerated() {
            let t = Float(index + 1) / Float(count)
            let p = c.map { CoachSceneGeometry.arcPoint(from: a, to: b, control: $0, t: t) } ?? b
            direction = p - last; Self.place(node, from: last, to: p)
            node.geometry?.firstMaterial?.diffuse.contents = color; last = p
        }
        tip.isHidden = mark.kind == "space" || mark.kind == "danger" || mark.kind == "playerLabel"
        tip.simdPosition = b
        if simd_length_squared(direction) > 0.0001 { tip.simdOrientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(direction)) }
        tip.geometry?.firstMaterial?.diffuse.contents = color
        zone.isHidden = mark.kind != "space"
        zone.simdPosition = [a.x, (a.y + b.y) / 2, a.z]
        let radius = CoachWorkspace.zoneRadius(start: mark.start, end: mark.end)
        zone.simdScale = [radius, 1, radius]
        zone.geometry?.firstMaterial?.diffuse.contents = color
        for (name, node) in handles {
            node.isHidden = !selected || !editable || mark.kind == "playerLabel" || (name == "control" && c == nil)
            node.simdPosition = name == "start" ? a : name == "end" ? b : c ?? .zero
            // Handles sit at the true authored point, not at the line's small
            // anti-z-fighting offset; dragging never accumulates that offset.
            node.position.y -= 0.12
        }
    }

    static func segment(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: CGFloat, color: NSColor) -> SCNNode {
        let geometry = SCNCylinder(radius: radius, height: 1)
        geometry.radialSegmentCount = 6; geometry.firstMaterial?.diffuse.contents = color
        let node = SCNNode(geometry: geometry); place(node, from: a, to: b); return node
    }

    private static func place(_ node: SCNNode, from a: SIMD3<Float>, to b: SIMD3<Float>) {
        let vector = b - a, length = simd_length(vector)
        node.simdPosition = (a + b) / 2
        node.simdScale = [1, max(0.0001, length), 1]
        if length > 0.0001 { node.simdOrientation = simd_quatf(from: [0, 1, 0], to: vector / length) }
    }
}
