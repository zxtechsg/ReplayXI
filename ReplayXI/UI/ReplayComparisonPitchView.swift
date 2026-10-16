import RealityKit
import SwiftUI

/// A genuine, read-only instance of the same replay scene used in the room.
/// The containing window removes this view before opening the immersive scene.
struct ReplayComparisonPitchView: View {
    let capture: ReplayConversionPreviewSession.Capture
    let playhead: TimeInterval
    var framing: ReplayComparisonPitchFraming = .play
    @AppStorage(ReplayPlayerDetail.storageKey) private var playerDetailRawValue =
        ReplayPlayerDetail.defaultSelection.rawValue
    @State private var recording: ReplayNativeBallPhysics.Recording?
    @State private var isReady = false
    @State private var playFocus: ReplayComparisonPitchFocus?
    @State private var preparationError: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if isReady {
                GeometryReader3D { geometry in
                    RealityView { content in
                        let root = PitchSceneFactory.makeMatchRoot(for: capture.scenario,
                                                                  nativeRecording: recording)
                        content.add(root)
                        update(root, bounds: content.convert(geometry.frame(in: .local),
                                                            from: .local, to: .scene))
                    } update: { content in
                        guard let root = content.entities.first else { return }
                        update(root, bounds: content.convert(geometry.frame(in: .local),
                                                            from: .local, to: .scene))
                    }
                    // Selection and drawing happen in the full spatial room.
                    .allowsHitTesting(false)
                    .clipped()
                    .accessibilityLabel("Three-dimensional authored replay of \(capture.scenario.title)")
                }
            } else if let preparationError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(preparationError).multilineTextAlignment(.center)
                    Button("Retry 3D") { retry += 1 }.buttonStyle(.bordered)
                }
                .padding(24)
            } else {
                ProgressView("Preparing 3D replay…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: retry) { await prepare() }
    }

    @MainActor
    private func prepare() async {
        isReady = false
        preparationError = nil
        playFocus = ReplayComparisonPitchFocus(scenario: capture.scenario)
        do {
            try await ReplayRoomLauncher.prepareVisuals(for: [capture.scenario])
            try Task.checkCancellation()
            if FootballReferenceScenarios.contains(capture.scenario) {
                let prepared = try await ReplayNativeBallPhysics.prewarm(
                    track: capture.scenario.ball, players: capture.scenario.players,
                    plannedTouches: FootballReferenceScenarios.touches(for: capture.scenario))
                try Task.checkCancellation()
                guard NativeReplaySceneAdmission.isUsable(prepared) else {
                    throw ReplayNativeBallPhysics.Failure.invalidInput
                }
                recording = prepared
            }
            try Task.checkCancellation()
            isReady = true
        } catch is CancellationError {
            // Closing the preview or entering the room is not a preparation error.
        } catch {
            guard !Task.isCancelled else { return }
            preparationError = "3D replay could not prepare."
        }
    }

    @MainActor
    private func update(_ root: Entity, bounds: BoundingBox) {
        PitchSceneFactory.update(root: root, scenario: capture.scenario, time: playhead,
            viewMode: .tacticalTable, perspectiveID: capture.perspectiveID, marks: capture.marks,
            showsLaneLens: false, isDrawing: false, positionalOriginTransform: nil,
            playerDetail: ReplayPlayerDetail.resolved(playerDetailRawValue))
        // The factory's room coordinates are intentionally overridden only for
        // this miniature. No track, ball/contact or annotation data is changed.
        let focus = framing == .play ? playFocus : nil
        let layout = ReplayComparisonPitchLayout(width: bounds.extents.x, height: bounds.extents.y,
                                                 focus: focus)
        root.scale = SIMD3<Float>(repeating: layout.scale)
        root.orientation = simd_quatf(angle: layout.tilt, axis: [1, 0, 0])
            * simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        let centre = focus?.centre ?? .zero
        let offset = root.orientation.act(SIMD3<Float>(centre.x, 0, centre.z) * layout.scale)
        root.position = bounds.center + SIMD3<Float>(0, -0.012, -layout.depthOffset) - offset
    }
}

enum ReplayComparisonPitchFraming: String, CaseIterable, Identifiable {
    case play = "Play"
    case wholePitch = "Whole pitch"
    var id: String { rawValue }
}

/// Fixed bounds over the complete play, never a head- or ball-following camera.
/// A long counter stays wide enough to include its first pass; short combinations
/// use a closer attacking-third view. Whole pitch remains one tap away.
struct ReplayComparisonPitchFocus: Equatable {
    let centre: PitchPoint
    let width: Float
    let length: Float

    init(scenario: ReplayScenario) {
        let points = scenario.ball.keyframes.map(\.position).filter { $0.x.isFinite && $0.z.isFinite }
        let minX = max(-38, (points.map(\.x).min() ?? -22) - 14)
        let maxX = min(38, (points.map(\.x).max() ?? 22) + 14)
        let minZ = max(-57, (points.map(\.z).min() ?? 10) - 10)
        let maxZ = min(57, (points.map(\.z).max() ?? 47) + 7)
        centre = PitchPoint(x: (minX + maxX) / 2, z: (minZ + maxZ) / 2)
        width = max(44, maxX - minX)
        length = max(36, maxZ - minZ)
    }
}

struct ReplayComparisonPitchLayout: Equatable {
    let scale: Float
    let tilt: Float
    let depthOffset: Float

    init(width: Float, height: Float, focus: ReplayComparisonPitchFocus? = nil) {
        let safeWidth = width.isFinite ? max(width, 0.01) : 0.01
        let safeHeight = height.isFinite ? max(height, 0.01) : 0.01
        // Includes goal depth, shirt labels and breathing room around the pitch.
        let resolvedTilt: Float = focus == nil ? .pi * 0.36 : .pi * 0.28
        tilt = resolvedTilt
        let projectedWidth = focus.map { $0.length + 8 } ?? 120
        let projectedHeight = focus.map { $0.width * sin(resolvedTilt) + 12 } ?? 88
        scale = min(safeWidth / projectedWidth, safeHeight / projectedHeight)
        depthOffset = (focus.map { $0.width * cos(resolvedTilt) / 2 + 5 } ?? 42) * scale
    }
}
