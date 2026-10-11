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
    var pin = ""
    private var browser: NWBrowser?
    private var peer: ReplayXIWireConnection?
    private var pairTimeout: Task<Void, Never>?

    func startDiscovery() {
        guard browser == nil else { return }
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
        browser?.cancel()
        browser = nil
        devices = []
        status = "Looking for Replay XI on this network…"
        startDiscovery()
    }

    func connect(to device: Device) {
        disconnect()
        guard pin.count == 6, pin.allSatisfy(\.isNumber) else {
            status = "Enter the six digit PIN shown in Replay XI"
            return
        }
        status = "Connecting to \(device.name)…"
        lastAction = ""
        let connection = NWConnection(to: device.endpoint, using: .tcp)
        let peer = ReplayXIWireConnection(connection)
        self.peer = peer
        peer.onClose = { [weak self, weak peer] in
            guard let self, self.peer === peer else { return }
            self.pairTimeout?.cancel(); self.pairTimeout = nil
            self.peer = nil
            self.connected = false
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
            peer?.send(.init(type: "pair", id: UUID(), pin: self.pin))
        }
        peer.start()
        pairTimeout = Task { [weak self, weak peer] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, let peer,
                  self.peer === peer, !self.connected else { return }
            self.lastAction = "Pairing timed out. Check the headset link and PIN."
            peer.close()
        }
    }

    func disconnect() {
        pairTimeout?.cancel(); pairTimeout = nil
        let oldPeer = peer
        peer = nil
        oldPeer?.close()
        connected = false
        state = nil
        lastAction = ""
        status = "Disconnected · pair again with the headset's new PIN"
    }

    private func receive(_ message: ReplayXIWireMessage) {
        switch message.type {
        case "result":
            if !connected {
                connected = message.ok == true
                if connected {
                    pairTimeout?.cancel(); pairTimeout = nil
                    status = "Connected · local network"
                } else {
                    lastAction = message.detail ?? "Pairing failed"
                    status = lastAction
                }
            } else {
                lastAction = message.ok == true ? (message.detail ?? "Applied")
                    : "Rejected: \(message.detail ?? "invalid edit")"
                status = message.ok == true ? "Connected · local network" : lastAction
            }
        case "state":
            guard let next = message.state else { return }
            if let current = state, next.revision <= current.revision { return }
            state = next
            connected = true
            status = "Connected · local network"
        default: break
        }
    }

    func send(_ command: ReplayXIWireCommand) {
        guard connected, let state else { return }
        var command = command
        command.expectedRevision = state.revision
        command.expectedScenarioID = state.scenarioID
        if command.time == nil { command.time = state.playhead }
        if peer?.send(.init(type: "command", id: UUID(), command: command)) != true {
            lastAction = "Command exceeds transfer limit"
        }
    }
}
