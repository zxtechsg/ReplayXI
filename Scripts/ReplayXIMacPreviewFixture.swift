import Foundation
import Network

// UI QA only. This Bonjour server sends sample state, not headset state.
@MainActor
final class ReplayXIMacPreviewFixture {
    private var listener: NWListener?
    private var peer: ReplayXIWireConnection?

    func start() throws {
        let listener = try NWListener(using: .tcp)
        listener.service = .init(name: "Replay XI Fixture", type: ReplayXIWire.serviceType)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.peer?.close()
                let peer = ReplayXIWireConnection(connection)
                self.peer = peer
                peer.onMessage = { message in
                    if message.type == "pair", message.pin == "123456" {
                        peer.send(.init(type: "result", id: message.id, ok: true, detail: "Fixture paired"))
                        peer.send(.init(type: "state", state: Self.sampleState))
                    } else if message.type == "command" {
                        peer.send(.init(type: "result", id: message.id, ok: false,
                            detail: "Fixture is read only"))
                    }
                }
                peer.start()
            }
        }
        listener.start(queue: .main)
        self.listener = listener
        print("Replay XI fixture ready. Pair with PIN 123456. This is sample UI data only.")
    }

    private static var sampleState: ReplayXIWireState {
        let arc = ReplayXIWireMark(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            kind: "arc", start: .init(x: -20, z: -28), end: .init(x: 8, z: 18),
            startHeight: 0.5, endHeight: 1.2, label: "Curved overlap", showAt: 7,
            hideAt: 20, keyframes: [7, 12, 18], authored: false,
            controlPoint: .init(x: -23, y: 3.2, z: 4), encodedMark: Data("{}".utf8))
        let pass = ReplayXIWireMark(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            kind: "pass", start: .init(x: 10, z: -3), end: .init(x: 22, z: 14),
            startHeight: 0, endHeight: 0, label: "Release the lane", showAt: 11,
            hideAt: 17, keyframes: [], authored: true,
            controlPoint: nil, encodedMark: Data("{}".utf8))
        return ReplayXIWireState(revision: 1, scenarioID: "preview", playhead: 12,
            playing: false, rate: 1, viewMode: "tacticalTable", perspectiveID: "p7",
            duration: 36, scenarios: [.init(id: "preview", title: "Fixture · Counterattack", duration: 36)],
            players: [
                .init(id: "p7", name: "Left winger", number: 7, team: "home", position: .init(x: -18, z: -20)),
                .init(id: "p9", name: "Striker", number: 9, team: "home", position: .init(x: 4, z: 5)),
                .init(id: "p4", name: "Defender", number: 4, team: "away", position: .init(x: 16, z: 12))
            ], ball: .init(x: 2, y: 0.11, z: 1), marks: [arc, pass],
            canUndo: true, canRedo: false, canSave: true, canEdit: true,
            status: "Fixture data · UI preview only")
    }
}

@main
struct ReplayXIMacPreviewFixtureMain {
    @MainActor static func main() throws {
        let server = ReplayXIMacPreviewFixture()
        try server.start()
        RunLoop.main.run()
    }
}
