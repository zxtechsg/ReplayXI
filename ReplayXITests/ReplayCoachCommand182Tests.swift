import Network
import XCTest
@testable import ReplayXI

@MainActor
final class ReplayCoachCommand182Tests: XCTestCase {
    func testUnchangedRequestsPreserveRevisionAndStaleEditExplainsFailure() async throws {
        #if targetEnvironment(simulator)
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.setPlaying(false)
        let service = ReplayXILocalCoachService(store: store)
        service.simulatorPortOverrideForTesting = 0
        let pin = service.pin
        service.start()
        defer { service.stop() }

        let port = try await readyPort(service)
        let client = ReplayXIWireConnection(NWConnection(host: .ipv4(.loopback), port: port, using: .tcp))
        defer { client.close() }
        let pairID = UUID(), noOpID = UUID(), rejectedID = UUID(), seekID = UUID(), staleID = UUID()
        let seekStateReceived = expectation(description: "only the real seek advances the wire revision")
        let staleResultReceived = expectation(description: "stale edit explains its rejection")
        var initialRevision: UInt64?
        var scenarioID: String?
        var stage = 0

        client.onReady = { [weak client] in
            _ = client?.send(.init(type: "pair", id: pairID, pin: pin))
        }
        client.onMessage = { [weak client] message in
            if message.type == "state", let state = message.state {
                if stage == 0 {
                    initialRevision = state.revision
                    scenarioID = state.scenarioID
                    stage = 1
                    _ = client?.send(.init(type: "command", id: noOpID,
                        command: .init(name: "seek", time: state.playhead)))
                } else if stage < 3 {
                    XCTFail("No-op or rejected command published an unchanged state")
                } else if stage == 3, state.playhead == 2 {
                    XCTAssertEqual(state.revision, initialRevision.map { $0 + 1 })
                    stage = 4
                    seekStateReceived.fulfill()
                } else if stage == 3 {
                    XCTFail("No-op or rejected command published an unchanged state")
                }
            } else if message.type == "result", message.id == noOpID {
                XCTAssertEqual(message.ok, true)
                XCTAssertEqual(message.stateRevision, initialRevision)
                stage = 2
                _ = client?.send(.init(type: "command", id: rejectedID,
                    command: .init(name: "unsupported-command")))
            } else if message.type == "result", message.id == rejectedID {
                XCTAssertEqual(message.ok, false)
                XCTAssertEqual(message.stateRevision, initialRevision)
                stage = 3
                _ = client?.send(.init(type: "command", id: seekID,
                    command: .init(name: "seek", time: 2)))
            } else if message.type == "result", message.id == seekID {
                XCTAssertEqual(message.ok, true)
                XCTAssertEqual(message.stateRevision, initialRevision.map { $0 + 1 })
                var stale = ReplayXIWireCommand(name: "create")
                stale.expectedRevision = initialRevision
                stale.expectedScenarioID = scenarioID
                stale.time = 2
                _ = client?.send(.init(type: "command", id: staleID, command: stale))
            } else if message.type == "result", message.id == staleID {
                XCTAssertEqual(message.ok, false)
                XCTAssertTrue(message.detail?.contains("Mac state changed") == true)
                XCTAssertGreaterThanOrEqual(message.stateRevision ?? 0, initialRevision.map { $0 + 1 } ?? 0)
                staleResultReceived.fulfill()
            }
        }
        client.start()
        await fulfillment(of: [seekStateReceived, staleResultReceived], timeout: 5)
        XCTAssertEqual(store.playhead, 2)
        #endif
    }

    private func readyPort(_ service: ReplayXILocalCoachService) async throws -> NWEndpoint.Port {
        for _ in 0..<100 {
            if let raw = service.listeningPort, let port = NWEndpoint.Port(rawValue: raw) { return port }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTFail("Listener did not become ready: \(service.status)")
        return try XCTUnwrap(service.listeningPort.flatMap(NWEndpoint.Port.init(rawValue:)))
    }
}
