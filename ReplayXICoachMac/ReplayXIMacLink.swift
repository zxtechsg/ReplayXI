import Foundation
import Network
import Observation

@MainActor
@Observable
final class ReplayXIMacLink {
    static let connectionTargetKey = "ReplayXI.coachConnectionTarget.v2"
    static let defaultConnectionTarget = "headset"

    struct Device: Identifiable {
        let id: String
        let name: String
        let endpoint: NWEndpoint
    }

    private(set) var devices: [Device] = []
    private(set) var state: ReplayXIWireState?
    private(set) var status = "Looking for Replay XI on this network…"
    private(set) var lastAction = ""
    private(set) var connected = false
    private(set) var isConnecting = false
    var pin = ""
    private var browser: NWBrowser?
    private var discoveryHintTask: Task<Void, Never>?
    private var peer: ReplayXIWireConnection?
    private var pairTimeout: Task<Void, Never>?
    private var pairingID: UUID?
    private var pairingAccepted = false
    private let pairingTimeout: Duration
    private var seekTask: Task<Void, Never>?
    private var pendingSeek: (scenarioID: String, time: Double)?
    private struct QueuedCommand {
        let command: ReplayXIWireCommand
        let scenarioID: String
        let playhead: Double
        let previewSeek: Bool
    }
    private var commandQueue: [QueuedCommand] = []
    private var inFlightCommandID: UUID?
    private var inFlightCommandName: String?
    private var awaitingStateRevision: UInt64?
    private var awaitingContextStateRevision: UInt64?
    private var revisionWaitTask: Task<Void, Never>?
    private var protocolSyncLost = false
    private static let editCommands: Set<String> = ["create", "labelPlayer", "geometry", "height",
        "arcControl", "window", "captureKey", "deleteKey", "retimeKey", "freezeKeys",
        "trackEndpoint", "label", "delete", "clear", "undo", "redo", "save"]

    private static let contextCommands: Set<String> = ["seek", "scenario", "play"]

    var playbackContextPending: Bool {
        inFlightCommandName.map { Self.contextCommands.contains($0) } == true
            || awaitingContextStateRevision != nil
            || commandQueue.contains(where: { Self.contextCommands.contains($0.command.name) })
            || pendingSeek != nil || seekTask != nil
    }

    init(pairingTimeout: Duration = .seconds(15)) {
        self.pairingTimeout = pairingTimeout
    }

    /// Vision Pro Simulator shares the host's loopback network. This is the
    /// same single-use PIN protocol as a headset, not a development bypass.
    func connectToSimulator(port: UInt16 = ReplayXIWire.simulatorPort) {
        guard port > 0, let endpointPort = NWEndpoint.Port(rawValue: port) else {
            status = "Invalid Simulator port"
            return
        }
        connect(to: Device(id: "local-simulator", name: "Simulator on this Mac",
            endpoint: .hostPort(host: .ipv4(.loopback), port: endpointPort)))
    }

    func stopDiscovery() {
        discoveryHintTask?.cancel(); discoveryHintTask = nil
        browser?.cancel()
        browser = nil
        devices = []
        if !connected, peer == nil { status = "Start Mac link in Vision Pro Simulator" }
    }

    func startDiscovery() {
        guard browser == nil else { return }
        if !connected, !isConnecting { status = "Looking for Replay XI on this network…" }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: ReplayXIWire.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            Task { @MainActor [weak self, weak browser] in
                guard let self, let browser, self.browser === browser else { return }
                self.devices = results.map { result in
                    let name: String
                    if case let .service(serviceName, _, _, _) = result.endpoint { name = serviceName }
                    else { name = "Replay XI" }
                    return Device(id: String(describing: result.endpoint), name: name, endpoint: result.endpoint)
                }.sorted { $0.name < $1.name }
                if !self.connected, !self.isConnecting, !self.devices.isEmpty {
                    self.status = "Headset found · select it and enter its PIN"
                }
            }
        }
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            Task { @MainActor [weak self, weak browser] in
                guard let self, let browser, self.browser === browser else { return }
                switch state {
                case .waiting(let error), .failed(let error):
                    if !self.connected, !self.isConnecting {
                        self.status = Self.discoveryFailure(error)
                    }
                    self.discoveryHintTask?.cancel()
                default: break
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        discoveryHintTask = Task { [weak self, weak browser] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, let browser, self.browser === browser,
                  self.devices.isEmpty, !self.connected, !self.isConnecting else { return }
            self.status = "No headset found · start Mac link, check Local Network permission and Wi-Fi, then Rescan"
        }
    }

    static func discoveryFailure(_ error: NWError) -> String {
        if case .dns(-65570) = error {
            return "Local Network blocked · allow Replay XI Coach in System Settings → Privacy & Security → Local Network, then Rescan"
        }
        return "Discovery unavailable: \(error.localizedDescription) · check Wi-Fi and Local Network permission, then Rescan"
    }

    func retryDiscovery() {
        stopDiscovery()
        status = "Looking for Replay XI on this network…"
        startDiscovery()
    }

    func connect(to device: Device) {
        guard !isConnecting else { return }
        disconnect()
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else {
            status = "Enter the six digit PIN shown in Replay XI"
            return
        }
        status = "Connecting to \(device.name)…"
        isConnecting = true
        lastAction = ""
        let requestedPIN = pin
        let requestID = UUID()
        pairingID = requestID
        let connection = NWConnection(to: device.endpoint, using: .tcp)
        let peer = ReplayXIWireConnection(connection)
        self.peer = peer
        peer.onClose = { [weak self, weak peer] in
            guard let self, self.peer === peer else { return }
            self.pairTimeout?.cancel(); self.pairTimeout = nil
            self.peer = nil
            self.connected = false
            self.isConnecting = false
            self.pairingAccepted = false
            self.pairingID = nil
            self.state = nil
            self.commandQueue.removeAll()
            self.inFlightCommandID = nil
            self.inFlightCommandName = nil
            self.awaitingStateRevision = nil
            self.awaitingContextStateRevision = nil
            self.revisionWaitTask?.cancel(); self.revisionWaitTask = nil
            self.seekTask?.cancel(); self.seekTask = nil; self.pendingSeek = nil
            self.protocolSyncLost = false
            self.status = self.lastAction.isEmpty ? "Disconnected · pair again with the headset's new PIN" : self.lastAction
        }
        peer.onMessage = { [weak self, weak peer] message in
            guard let self, self.peer === peer else { return }
            self.receive(message)
        }
        peer.onProtocolError = { [weak self, weak peer] detail in
            guard let self, self.peer === peer else { return }
            self.lastAction = detail
            self.status = detail
        }
        peer.onTransportError = { [weak self, weak peer] detail in
            guard let self, self.peer === peer else { return }
            self.lastAction = "Connection failed: \(detail)"
            self.status = self.lastAction
        }
        peer.onWaiting = { [weak self, weak peer] detail in
            guard let self, self.peer === peer else { return }
            self.lastAction = detail
            self.status = detail
        }
        peer.onReady = { [weak self, weak peer] in
            guard let self, self.peer === peer else { return }
            self.lastAction = ""
            self.status = "Connected to device · checking PIN…"
            peer?.send(.init(type: "pair", id: requestID, pin: requestedPIN))
        }
        peer.start()
        let timeout = pairingTimeout
        pairTimeout = Task { [weak self, weak peer] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, let peer,
                  self.peer === peer, !self.connected else { return }
            if self.lastAction.isEmpty {
                self.lastAction = self.pairingAccepted
                    ? "Paired, but no replay arrived. Restart Mac link and try again."
                    : "Pairing timed out. Check Start Mac link and the PIN."
            }
            peer.close()
        }
    }

    func disconnect() {
        seekTask?.cancel(); seekTask = nil; pendingSeek = nil
        pairTimeout?.cancel(); pairTimeout = nil
        let oldPeer = peer
        peer = nil
        oldPeer?.close()
        connected = false
        isConnecting = false
        pairingAccepted = false
        pairingID = nil
        state = nil
        commandQueue.removeAll()
        inFlightCommandID = nil
        inFlightCommandName = nil
        awaitingStateRevision = nil
        awaitingContextStateRevision = nil
        revisionWaitTask?.cancel(); revisionWaitTask = nil
        protocolSyncLost = false
        lastAction = ""
        status = "Disconnected · pair again with the headset's new PIN"
    }

    private func receive(_ message: ReplayXIWireMessage) {
        switch message.type {
        case "result":
            if !pairingAccepted {
                guard isConnecting, message.id == pairingID else { return }
                pairingAccepted = message.ok == true
                if pairingAccepted {
                    status = "Paired · loading replay…"
                } else {
                    lastAction = message.detail ?? "Pairing failed"
                    status = lastAction
                    peer?.close()
                }
            } else {
                guard message.id == inFlightCommandID else { return }
                let wasContextChange = inFlightCommandName.map { Self.contextCommands.contains($0) } == true
                inFlightCommandID = nil
                inFlightCommandName = nil
                lastAction = message.ok == true ? (message.detail ?? "Applied")
                    : "Rejected: \(message.detail ?? "invalid edit")"
                status = message.ok == true ? "Connected · local network" : lastAction
                guard let revision = message.stateRevision else {
                    // Older peers cannot prove which state an ack refers to.
                    commandQueue.removeAll()
                    protocolSyncLost = true
                    lastAction = "Replay XI update needed before more edits"
                    status = lastAction
                    return
                }
                if (state?.revision ?? 0) < revision {
                    awaitingStateRevision = revision
                    if wasContextChange { awaitingContextStateRevision = revision }
                    revisionWaitTask?.cancel()
                    revisionWaitTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled, let self,
                              self.awaitingStateRevision == revision else { return }
                        self.commandQueue.removeAll()
                        self.awaitingStateRevision = nil
                        self.awaitingContextStateRevision = nil
                        self.protocolSyncLost = true
                        self.lastAction = "Replay state did not arrive. Reconnect to edit."
                        self.status = self.lastAction
                    }
                } else {
                    if wasContextChange { awaitingContextStateRevision = nil }
                    transmitNext()
                }
            }
        case "state":
            guard pairingAccepted, let next = message.state else { return }
            if let current = state, next.revision <= current.revision { return }
            state = next
            if let waiting = awaitingStateRevision, next.revision >= waiting {
                awaitingStateRevision = nil
                awaitingContextStateRevision = nil
                revisionWaitTask?.cancel(); revisionWaitTask = nil
                transmitNext()
            }
            connected = true
            isConnecting = false
            pairTimeout?.cancel(); pairTimeout = nil
            status = lastAction.hasPrefix("Rejected:") ? lastAction : "Connected · local network"
        default: break
        }
    }

    func send(_ command: ReplayXIWireCommand) {
        if command.name == "seek" || command.name == "scenario" || command.name == "play" {
            seekTask?.cancel(); seekTask = nil; pendingSeek = nil
        }
        enqueue(command)
    }

    private func enqueue(_ command: ReplayXIWireCommand, previewSeek: Bool = false) {
        guard connected, let state else { return }
        guard !protocolSyncLost else {
            lastAction = "Replay XI update needed before more edits"
            status = lastAction
            return
        }
        guard !Self.editCommands.contains(command.name) || !playbackContextPending else {
            lastAction = "Wait for replay state to update before editing"
            status = lastAction
            return
        }
        if ["seek", "scenario", "play"].contains(command.name) {
            // The playhead/scenario may change before queued edits are sent.
            commandQueue.removeAll()
        } else if previewSeek {
            commandQueue.removeAll { $0.previewSeek }
        }
        commandQueue.append(.init(command: command, scenarioID: state.scenarioID,
                                  playhead: state.playhead, previewSeek: previewSeek))
        transmitNext()
    }

    private func transmitNext() {
        guard connected, !protocolSyncLost, inFlightCommandID == nil,
              awaitingStateRevision == nil, let state else { return }
        while !commandQueue.isEmpty {
            let queued = commandQueue.removeFirst()
            guard queued.scenarioID == state.scenarioID else { continue }
            var command = queued.command
            command.expectedRevision = state.revision
            command.expectedScenarioID = state.scenarioID
            if command.time == nil { command.time = queued.playhead }
            let id = UUID()
            if peer?.send(.init(type: "command", id: id, command: command)) == true {
                inFlightCommandID = id
                inFlightCommandName = command.name
                return
            }
            lastAction = "Command exceeds transfer limit"
        }
    }

    /// Eight previews/second, latest wins. Release sends the exact end time;
    /// no queued seek can arrive later and pull the playhead backwards.
    func seek(to time: Double, final: Bool) {
        guard let state, connected, time.isFinite else { return }
        let time = min(max(0, time), state.duration)
        if final {
            seekTask?.cancel(); seekTask = nil; pendingSeek = nil
            enqueue(.init(name: "seek", time: time))
            return
        }
        pendingSeek = (state.scenarioID, time)
        guard seekTask == nil else { return }
        enqueue(.init(name: "seek", time: time), previewSeek: true)
        pendingSeek = nil
        seekTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(125))
                guard !Task.isCancelled, let self else { return }
                guard let next = self.pendingSeek else { self.seekTask = nil; return }
                self.pendingSeek = nil
                if self.state?.scenarioID == next.scenarioID {
                    self.enqueue(.init(name: "seek", time: next.time), previewSeek: true)
                }
            }
        }
    }
}
