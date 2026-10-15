import XCTest
import Network
@testable import ReplayXI

@MainActor
final class ReplayXILocalCoachServiceTests: XCTestCase {
    func testStoppingLinkRotatesPairingPINAndIgnoresQueuedListenerStatus() async {
        let service = ReplayXILocalCoachService(store: ReplayStore())
        service.simulatorPortOverrideForTesting = 0
        let first = service.pin
        service.start()
        service.stop()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertNotEqual(service.pin, first)
        XCTAssertFalse(service.isRunning)
        XCTAssertEqual(service.status, "Mac link off")
    }

    func testSimulatorListenerBindsOnlyLoopbackWithoutBonjour() throws {
        let parameters = ReplayXILocalCoachService.listenerParameters(simulatorOnly: true)
        XCTAssertEqual(parameters.requiredInterfaceType, .loopback)
        XCTAssertFalse(parameters.includePeerToPeer)
        XCTAssertEqual(parameters.requiredLocalEndpoint,
            .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: ReplayXIWire.simulatorPort)!))
        XCTAssertNil(ReplayXILocalCoachService.advertisedService(simulatorOnly: true))
        XCTAssertTrue((49_152...65_535).contains(Int(ReplayXIWire.simulatorPort)))
        let device = ReplayXILocalCoachService.listenerParameters(simulatorOnly: false)
        XCTAssertNil(device.requiredLocalEndpoint)
        XCTAssertNotEqual(device.requiredInterfaceType, .loopback)
        XCTAssertFalse(device.includePeerToPeer)
        XCTAssertEqual(ReplayXILocalCoachService.advertisedService(simulatorOnly: false)?.type,
                       ReplayXIWire.serviceType)
    }

    func testSimulatorPortConflictExplainsHowToRecover() {
        let message = ReplayXILocalCoachService.failureMessage(.posix(.EADDRINUSE), simulatorOnly: true)
        XCTAssertTrue(message.contains("Stop Mac link in the other Replay XI Simulator"))
        XCTAssertTrue(message.contains("retry"))
    }

    func testOccupiedSimulatorPortStopsCleanlyAndCanBeRetried() async throws {
        #if targetEnvironment(simulator)
        let first = ReplayXILocalCoachService(store: ReplayStore())
        first.simulatorPortOverrideForTesting = 0
        first.start()
        defer { first.stop() }
        let occupied = try await readyPort(first)
        let second = ReplayXILocalCoachService(store: ReplayStore())
        second.simulatorPortOverrideForTesting = occupied.rawValue
        second.start()
        defer { second.stop() }
        for _ in 0..<100 {
            if !second.isRunning { break }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertFalse(second.isRunning, "A busy port must expose Start/Retry, not a stuck running link")
        XCTAssertNil(second.listeningPort)
        XCTAssertTrue(second.status.contains("Stop Mac link in the other Replay XI Simulator"), second.status)
        first.stop()
        try await Task.sleep(for: .milliseconds(100))
        second.start()
        let retried = try await readyPort(second)
        XCTAssertEqual(retried, occupied)
        XCTAssertTrue(second.isRunning)
        #endif
    }

    func testSimulatorPairsAndSeeksOverPINProtectedLoopback() async throws {
        #if targetEnvironment(simulator)
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.setPlaying(false)
        let service = ReplayXILocalCoachService(store: store)
        service.simulatorPortOverrideForTesting = 0
        XCTAssertNil(service.listeningPort)
        XCTAssertFalse(service.isRunning)
        let pin = service.pin
        service.start()
        defer { service.stop() }
        let port = try await readyPort(service)
        let paired = expectation(description: "PIN accepted")
        let sought = expectation(description: "Exact replay state returned after seek")
        let pairID = UUID(), seekID = UUID()
        let client = ReplayXIWireConnection(NWConnection(host: .ipv4(.loopback), port: port, using: .tcp))
        defer { client.close() }
        client.onReady = { [weak client] in client?.send(.init(type: "pair", id: pairID, pin: pin)) }
        var receivedSeekState = false
        client.onMessage = { [weak client] message in
            if message.type == "result", message.id == pairID {
                XCTAssertEqual(message.ok, true)
                paired.fulfill()
                client?.send(.init(type: "command", id: seekID, command: .init(name: "seek", time: 2)))
            } else if message.type == "state", message.state?.playhead == 2, !receivedSeekState {
                receivedSeekState = true
                sought.fulfill()
            }
        }
        client.start()
        await fulfillment(of: [paired, sought], timeout: 5)
        XCTAssertTrue(service.isPaired)
        XCTAssertNotEqual(service.pin, pin, "The visible pairing PIN remains single-use on loopback")
        XCTAssertEqual(store.playhead, 2)
        service.stop()
        XCTAssertNil(service.listeningPort)
        XCTAssertFalse(service.isRunning)
        #endif
    }

    func testSimulatorRejectsCommandsWithoutThePIN() async throws {
        #if targetEnvironment(simulator)
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.setPlaying(false)
        let service = ReplayXILocalCoachService(store: store)
        service.simulatorPortOverrideForTesting = 0
        service.start()
        defer { service.stop() }
        let port = try await readyPort(service)
        let rejected = expectation(description: "Unauthenticated command rejected")
        let closed = expectation(description: "Unauthenticated connection closed")
        let client = ReplayXIWireConnection(NWConnection(host: .ipv4(.loopback), port: port, using: .tcp))
        defer { client.close() }
        client.onReady = { [weak client] in
            client?.send(.init(type: "command", id: UUID(), command: .init(name: "seek", time: 2)))
        }
        client.onMessage = { message in
            if message.type == "result" {
                XCTAssertEqual(message.ok, false)
                rejected.fulfill()
            }
        }
        client.onClose = { closed.fulfill() }
        client.start()
        await fulfillment(of: [rejected, closed], timeout: 5)
        XCTAssertFalse(service.isPaired)
        XCTAssertEqual(store.playhead, 0)
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

    func testServiceStaysOffUntilStartedAndRejectsStaleOrPlayingEdits() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let service = ReplayXILocalCoachService(store: store)
        XCTAssertFalse(service.isRunning)
        var create = edit("create", store: store)
        create.kind = "run"
        create.start = .init(x: 0, z: 0)
        create.end = .init(x: 5, z: 5)
        create.startHeight = 0
        create.endHeight = 0
        create.label = "Mac run"

        store.setPlaying(true)
        XCTAssertFalse(service.apply(create))
        store.setPlaying(false)
        store.seek(to: 3)
        XCTAssertFalse(service.apply(create)) // wrong time
        create.time = store.playhead
        create.expectedRevision = 1
        XCTAssertFalse(service.apply(create)) // wrong revision
        create.expectedRevision = 0
        XCTAssertTrue(service.apply(create))
        let mark = try XCTUnwrap(store.marks.first { $0.label == "Mac run" })

        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: true))
        XCTAssertFalse(service.apply(.init(name: "play", value: true)))
        XCTAssertFalse(store.isPlaying)
        XCTAssertTrue(store.setAnnotationTimingDraftPending(id: mark.id, isPending: false))

        let clear = edit("clear", store: store)
        XCTAssertTrue(service.apply(clear))
        XCTAssertFalse(store.marks.contains { $0.id == mark.id })
        XCTAssertEqual(store.marks.map(\.id), store.selectedScenario.coachMarks.map(\.id))
    }

    func testPlayerLabelUsesStoreAndKeepsAuthoredOverlays() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        let service = ReplayXILocalCoachService(store: store)
        let player = try XCTUnwrap(store.selectedScenario.players.first)
        var command = edit("labelPlayer", store: store)
        command.playerID = player.id
        XCTAssertTrue(service.apply(command))
        XCTAssertTrue(store.marks.contains { $0.kind == .playerLabel && $0.playerID == player.id })
        XCTAssertTrue(service.apply(edit("clear", store: store)))
        XCTAssertEqual(store.marks.map(\.id), store.selectedScenario.coachMarks.map(\.id))
    }

    private func edit(_ name: String, store: ReplayStore) -> ReplayXIWireCommand {
        var command = ReplayXIWireCommand(name: name)
        command.expectedRevision = 0
        command.expectedScenarioID = store.selectedScenarioID
        command.time = store.playhead
        return command
    }
}
