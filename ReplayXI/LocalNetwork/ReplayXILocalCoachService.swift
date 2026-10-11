import Foundation
import Network
import Observation
import simd

/// One paired Mac may control this local review. The PIN is single-use;
/// rejected attempts close the socket. No account or external relay exists.
@MainActor
@Observable
final class ReplayXILocalCoachService {
    private(set) var pin = String(format: "%06d", Int.random(in: 0...999_999))
    private(set) var status = "Mac link off"
    var isRunning: Bool { listener != nil }
    private(set) var isPaired = false
    private let store: ReplayStore
    private var listener: NWListener?
    private var peer: ReplayXIWireConnection?
    private var publishTask: Task<Void, Never>?
    private var revision: UInt64 = 0
    private var lastState: ReplayXIWireState?
    private var encodedMarks: [UUID: (mark: CoachMark, bytes: Data)] = [:]
    private var commandTimes: [ContinuousClock.Instant] = []
    private var failedPairings = 0

    init(store: ReplayStore) { self.store = store }

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = false
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(name: "Replay XI", type: ReplayXIWire.serviceType)
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor [weak self, weak listener] in
                    guard let self, let listener, self.listener === listener else { return }
                    switch state {
                    case .ready: self.status = self.isPaired ? "Mac connected" : "Mac link ready · PIN \(self.pin)"
                    case .failed(let error): self.status = "Mac link unavailable: \(error.localizedDescription)"
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self, weak listener] connection in
                Task { @MainActor [weak self, weak listener] in
                    guard let self, let listener, self.listener === listener else {
                        connection.cancel()
                        return
                    }
                    self.accept(connection, from: listener)
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            publishTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(350))
                    self?.publishStateIfChanged()
                }
            }
        } catch {
            status = "Mac link unavailable: \(error.localizedDescription)"
        }
    }

    func stop() {
        publishTask?.cancel(); publishTask = nil
        peer?.close(); peer = nil
        listener?.cancel(); listener = nil
        isPaired = false
        encodedMarks.removeAll()
        failedPairings = 0
        rotatePin()
        status = "Mac link off"
    }

    func resetPairing() {
        peer?.close(); peer = nil
        isPaired = false
        failedPairings = 0
        rotatePin()
        status = "Mac link ready · PIN \(pin)"
    }

    private func rotatePin() {
        let previous = pin
        repeat { pin = String(format: "%06d", Int.random(in: 0...999_999)) }
        while pin == previous
    }

    private func accept(_ connection: NWConnection, from listener: NWListener) {
        guard self.listener === listener, peer == nil, failedPairings < 5,
              Self.isLANEndpoint(connection.endpoint) else {
            if failedPairings >= 5 { status = "Pairing locked · choose New PIN" }
            connection.cancel()
            return
        }
        let peer = ReplayXIWireConnection(connection, receivesStates: false)
        self.peer = peer
        peer.onClose = { [weak self, weak peer] in
            guard let self, self.peer === peer else { return }
            self.peer = nil
            self.isPaired = false
            self.lastState = nil
            self.status = self.failedPairings >= 5
                ? "Pairing locked · choose New PIN"
                : "Mac disconnected · PIN \(self.pin)"
        }
        peer.onMessage = { [weak self] message in self?.receive(message, from: peer) }
        peer.start()
        Task { [weak self, weak peer] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, let peer, self.peer === peer, !self.isPaired else { return }
            peer.close()
        }
    }

    private static func isLANEndpoint(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        var address = String(describing: host).lowercased()
        address = address.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if address.hasPrefix("::ffff:") { address = String(address.dropFirst(7)) }
        if address == "::1" || address.hasPrefix("fe80:")
            || (address.contains(":") && (address.hasPrefix("fc") || address.hasPrefix("fd"))) { return true }
        let octets = address.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 10 || octets[0] == 127
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 169 && octets[1] == 254)
    }

    private func receive(_ message: ReplayXIWireMessage, from peer: ReplayXIWireConnection) {
        guard self.peer === peer else { return }
        if !isPaired {
            guard message.type == "pair", message.pin == pin, failedPairings < 5 else {
                failedPairings += 1
                peer.send(.init(type: "result", id: message.id, ok: false, detail: "Pairing failed"))
                peer.closeAfterFlush()
                return
            }
            isPaired = true
            failedPairings = 0
            rotatePin() // The code visible during pairing cannot authorize a later session.
            status = "Mac connected"
            peer.send(.init(type: "result", id: message.id, ok: true, detail: "Paired"))
            lastState = nil
            publishStateIfChanged()
            return
        }
        guard message.type == "command", let command = message.command,
              let encoded = try? ReplayXIWire.encoder.encode(message),
              encoded.count <= ReplayXIWire.maximumCommandBytes,
              admitCommand() else {
            peer.send(.init(type: "result", id: message.id, ok: false, detail: "Invalid or rate limited request"))
            return
        }
        // Catch a headset-side seek/edit that occurred since the last pulse.
        publishStateIfChanged()
        let result = apply(command)
        peer.send(.init(type: "result", id: message.id, ok: result, detail: store.statusMessage))
        lastState = nil
        publishStateIfChanged()
    }

    private func admitCommand() -> Bool {
        let clock = ContinuousClock()
        let now = clock.now
        commandTimes.removeAll { $0.duration(to: now) > .seconds(1) }
        guard commandTimes.count < 20 else { return false }
        commandTimes.append(now)
        return true
    }

    func apply(_ command: ReplayXIWireCommand) -> Bool {
        // Existing store gates remain authoritative, including SharePlay role,
        // drafts, active drags, authored overlays and physical placement.
        guard store.pendingAnnotationTimingEditID == nil else {
            store.statusMessage = "Finish the headset timing edit first"
            return false
        }
        let editCommands: Set<String> = ["create", "labelPlayer", "geometry", "height", "arcControl", "window",
            "captureKey", "deleteKey", "retimeKey", "label", "delete", "clear", "undo", "redo", "save"]
        if editCommands.contains(command.name) {
            guard !store.isPlaying,
                  let editTime = command.time,
                  editTime.isFinite,
                  abs(editTime - store.playhead) < 0.001 else {
                store.statusMessage = "Pause the replay before editing on Mac"
                return false
            }
            guard command.expectedRevision == revision,
                  command.expectedScenarioID == store.selectedScenarioID else {
                store.statusMessage = "Mac state changed. Try the edit again."
                return false
            }
        }
        switch command.name {
        case "scenario":
            guard let id = command.scenarioID, store.scenarios.contains(where: { $0.id == id }) else { return false }
            store.selectScenario(id: id); return store.selectedScenarioID == id
        case "play":
            guard let value = command.value else { return false }
            store.setPlaying(value); return store.isPlaying == value
        case "seek":
            guard let time = command.time, time.isFinite, (0...store.selectedScenario.duration).contains(time) else { return false }
            store.seek(to: time); return abs(store.playhead - time) < 0.001
        case "rate":
            guard let rate = command.rate, rate.isFinite, (0.25...4).contains(rate) else { return false }
            store.setPlaybackRate(rate); return store.playbackRate == rate
        case "view":
            guard let raw = command.viewMode, let mode = ReplayViewMode(rawValue: raw) else { return false }
            store.setViewMode(mode); return store.viewMode == mode
        case "pov":
            guard let id = command.playerID, store.selectedScenario.player(id: id) != nil else { return false }
            store.broadcastPerspective(id); return store.coachFocusPerspectiveID == id
        case "create":
            guard let kindRaw = command.kind, let kind = CoachMarkKind(rawValue: kindRaw), kind.requiresTwoPitchPoints,
                  let start = command.start?.pitchPoint, let end = command.end?.pitchPoint,
                  let startHeight = command.startHeight, let endHeight = command.endHeight,
                  startHeight.isFinite, endHeight.isFinite,
                  let label = command.label, label.count <= ReplayStore.maximumCoachMarkLabelLength else { return false }
            return store.addMacCoachMark(kind: kind, start: start, end: end,
                startElevation: startHeight, endElevation: endHeight, label: label) != nil
        case "labelPlayer":
            guard let id = command.playerID, store.selectedScenario.player(id: id) != nil else { return false }
            return store.labelPlayer(id) != nil
        case "geometry":
            guard let id = command.markID, let start = command.start?.pitchPoint,
                  let end = command.end?.pitchPoint,
                  let startHeight = command.startHeight, let endHeight = command.endHeight,
                  startHeight.isFinite, endHeight.isFinite else { return false }
            let control = command.controlPoint.map { SIMD3($0.x, $0.y, $0.z) }
            return store.setMacCoachMarkPose(id: id, start: start, end: end,
                startElevation: startHeight, endElevation: endHeight, controlPoint: control)
        case "height":
            guard let id = command.markID, let target = command.kind,
                  let delta = command.startHeight, delta.isFinite else { return false }
            let endpoint: CoachMarkElevationTarget
            switch target {
            case "start": endpoint = .start
            case "end": endpoint = .end
            case "both": endpoint = .both
            default: return false
            }
            return store.nudgeCoachMarkElevation(id: id, target: endpoint, by: delta)
        case "arcControl":
            guard let id = command.markID, let p = command.controlPoint,
                  p.x.isFinite, p.y.isFinite, p.z.isFinite else { return false }
            return store.updateCoachMarkArcControlPoint(id: id, point: SIMD3(p.x, p.y, p.z))
        case "window":
            guard let id = command.markID, let start = command.showAt, start.isFinite,
                  command.hideAt?.isFinite ?? true else { return false }
            return store.setCoachMarkWindow(id: id, start: start, end: command.hideAt)
        case "captureKey":
            guard let id = command.markID else { return false }
            return store.captureCoachMarkKeyframe(id: id)
        case "deleteKey":
            guard let id = command.markID, let time = command.keyframeAt, time.isFinite else { return false }
            return store.removeCoachMarkKeyframe(id: id, at: time)
        case "retimeKey":
            guard let id = command.markID, let from = command.keyframeAt, let to = command.keyframeTo,
                  from.isFinite, to.isFinite else { return false }
            return store.retimeCoachMarkKeyframe(id: id, from: from, to: to)
        case "label":
            guard let id = command.markID, let label = command.label,
                  label.count <= ReplayStore.maximumCoachMarkLabelLength else { return false }
            return store.updateCoachMarkLabel(id: id, label: label)
        case "delete":
            guard let id = command.markID else { return false }
            return store.removeCoachMark(id: id)
        case "clear":
            let oldCount = store.marks.count
            store.clearMarks()
            return store.marks.count < oldCount
        case "undo": return store.undoAnnotationEdit()
        case "redo": return store.redoAnnotationEdit()
        case "save":
            guard let name = command.saveName, !name.isEmpty, name.count <= 80 else { return false }
            return store.saveReview(named: name)
        default: return false
        }
    }

    private func publishStateIfChanged() {
        guard isPaired, let peer else { return }
        let snapshot = store.makeSnapshot()
        let scenario = store.selectedScenario
        let players = scenario.players.map { player in
            let p = store.presentedPlayerPose(for: player, at: store.playhead).position
            return ReplayXIWirePlayer(id: player.id, name: player.displayName,
                number: player.shirtNumber, team: player.team.rawValue,
                position: .init(x: p.x, z: p.z))
        }
        let authoredBall = scenario.ball.pose(at: store.playhead)
        let ballPosition: SIMD3<Float>
        if let sample = store.macRenderedBallSample,
           sample.scenarioID == scenario.id,
           abs(sample.time - store.playhead) < 0.05,
           sample.position.x.isFinite, sample.position.y.isFinite,
           sample.position.z.isFinite {
            ballPosition = sample.position
        } else {
            ballPosition = SIMD3(authoredBall.position.x, authoredBall.height,
                authoredBall.position.z)
        }
        let authoredIDs = Set(scenario.coachMarks.map(\.id))
        let marks: [ReplayXIWireMark] = snapshot.marks.compactMap { mark in
            let encoded: Data
            if let cached = encodedMarks[mark.id], cached.mark == mark {
                encoded = cached.bytes
            } else {
                guard let bytes = try? ReplayXIWire.encoder.encode(mark) else { return nil }
                encodedMarks[mark.id] = (mark, bytes)
                encoded = bytes
            }
            let posed = mark.sampled(at: store.playhead)
            let presented = store.presentedCoachMarkGeometry(mark, at: store.playhead)
            let displayedPose = CoachMark(id: posed.id, kind: posed.kind,
                start: presented.start, end: presented.end,
                startElevation: posed.startElevation, endElevation: posed.endElevation,
                curve: posed.curve, label: posed.label, revealTime: posed.revealTime,
                hideTime: posed.hideTime, author: posed.author)
            return ReplayXIWireMark(id: mark.id, kind: mark.kind.rawValue,
                start: .init(x: presented.start.x, z: presented.start.z),
                end: .init(x: presented.end.x, z: presented.end.z),
                startHeight: posed.resolvedStartElevation,
                endHeight: posed.resolvedEndElevation,
                label: mark.label, showAt: mark.revealTime, hideAt: mark.hideTime,
                keyframes: mark.keyframes?.map(\.time) ?? [], authored: authoredIDs.contains(mark.id),
                controlPoint: mark.kind == .arc ? {
                    let p = displayedPose.resolvedCurve.controlPoint(for: displayedPose)
                    return ReplayXIWirePoint3(x: p.x, y: p.y, z: p.z)
                }() : nil, encodedMark: encoded)
        }
        let retainedIDs = Set(snapshot.marks.map(\.id))
        encodedMarks = encodedMarks.filter { retainedIDs.contains($0.key) }
        let state = ReplayXIWireState(revision: 0, scenarioID: scenario.id,
            playhead: store.playhead, playing: store.isPlaying, rate: store.playbackRate,
            viewMode: store.viewMode.rawValue, perspectiveID: store.activePerspectiveID,
            duration: scenario.duration,
            scenarios: store.scenarios.map { .init(id: $0.id, title: $0.title, duration: $0.duration) },
            players: players,
            ball: .init(x: ballPosition.x, y: ballPosition.y, z: ballPosition.z),
            marks: marks, canUndo: store.canUndoAnnotationEdit,
            canRedo: store.canRedoAnnotationEdit, canSave: store.canSaveReview,
            canEdit: !store.isPlaying && store.pendingAnnotationTimingEditID == nil
                && store.localRole == .coach && store.canChangePlaybackView
                && !store.isDrawing && !store.hasActiveTimelineScrub
                && !store.hasActiveCoachMarkGeometryPreview && store.triangleLockMode != .place,
            status: store.statusMessage)
        guard state != lastState else { return }
        lastState = state
        revision &+= 1
        var updated = state
        updated.revision = revision
        guard peer.send(.init(type: "state", state: updated)) else {
            status = "Mac state exceeds 4 MB limit"
            peer.send(.init(type: "result", ok: false, detail: status))
            return
        }
    }
}

private extension ReplayXIWirePoint {
    var pitchPoint: PitchPoint { PitchPoint(x: x, z: z) }
}
