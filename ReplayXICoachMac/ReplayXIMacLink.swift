import Foundation
import Network
import Observation

@MainActor
@Observable
final class ReplayXIMacLink {
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
    private var peer: ReplayXIWireConnection?
    private var pairTimeout: Task<Void, Never>?
    private var pairingID: UUID?
    private var pairingAccepted = false
    private let pairingTimeout: Duration
    private var seekTask: Task<Void, Never>?
    private var pendingSeek: (scenarioID: String, time: Double)?

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
            }
        }
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            Task { @MainActor [weak self, weak browser] in
                guard let self, let browser, self.browser === browser else { return }
                if case let .failed(error) = state {
                    self.status = "Discovery failed: \(error.localizedDescription)"
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
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
        peer.onReady = { [weak self, weak peer] in
            guard let self, self.peer === peer else { return }
            peer?.send(.init(type: "pair", id: requestID, pin: requestedPIN))
        }
        peer.start()
        let timeout = pairingTimeout
        pairTimeout = Task { [weak self, weak peer] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, let peer,
                  self.peer === peer, !self.connected else { return }
            self.lastAction = self.pairingAccepted
                ? "Paired, but no replay arrived. Restart Mac link and try again."
                : "Pairing timed out. Check Start Mac link and the PIN."
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
                lastAction = message.ok == true ? (message.detail ?? "Applied")
                    : "Rejected: \(message.detail ?? "invalid edit")"
                status = message.ok == true ? "Connected · local network" : lastAction
            }
        case "state":
            guard pairingAccepted, let next = message.state else { return }
            if let current = state, next.revision <= current.revision { return }
            state = next
            connected = true
            isConnecting = false
            pairTimeout?.cancel(); pairTimeout = nil
            status = "Connected · local network"
        default: break
        }
    }

    func send(_ command: ReplayXIWireCommand) {
        if command.name == "seek" || command.name == "scenario" || command.name == "play" {
            seekTask?.cancel(); seekTask = nil; pendingSeek = nil
        }
        transmit(command)
    }

    private func transmit(_ command: ReplayXIWireCommand) {
        guard connected, let state else { return }
        var command = command
        command.expectedRevision = state.revision
        command.expectedScenarioID = state.scenarioID
        if command.time == nil { command.time = state.playhead }
        if peer?.send(.init(type: "command", id: UUID(), command: command)) != true {
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
            transmit(.init(name: "seek", time: time))
            return
        }
        pendingSeek = (state.scenarioID, time)
        guard seekTask == nil else { return }
        transmit(.init(name: "seek", time: time))
        pendingSeek = nil
        seekTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(125))
                guard !Task.isCancelled, let self else { return }
                guard let next = self.pendingSeek else { self.seekTask = nil; return }
                self.pendingSeek = nil
                if self.state?.scenarioID == next.scenarioID {
                    self.transmit(.init(name: "seek", time: next.time))
                }
            }
        }
    }
}
