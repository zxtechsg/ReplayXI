import XCTest
import Network
import SwiftUI
import AppKit
@testable import ReplayXICoachMac

@MainActor
final class ReplayXIWireLoopbackTests: XCTestCase {
    func testPairCommandStateAndDisconnectOverTCP() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "listener ready")
        let paired = expectation(description: "paired")
        let commanded = expectation(description: "commanded")
        let receivedState = expectation(description: "state received")
        let disconnected = expectation(description: "disconnected")
        var serverPeer: ReplayXIWireConnection?
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let peer = ReplayXIWireConnection(connection)
                serverPeer = peer
                peer.onMessage = { message in
                    if message.type == "pair", message.pin == "123456" {
                        paired.fulfill()
                        peer.send(.init(type: "result", id: message.id, ok: true))
                    } else if message.type == "command", message.command?.name == "seek",
                              message.command?.time == 12 {
                        commanded.fulfill()
                        peer.send(.init(type: "state", state: Self.sampleState))
                    }
                }
                peer.start()
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [ready], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        let client = ReplayXIWireConnection(NWConnection(host: "127.0.0.1", port: port, using: .tcp))
        client.onReady = { client.send(.init(type: "pair", id: UUID(), pin: "123456")) }
        client.onMessage = { message in
            if message.type == "result", message.ok == true {
                client.send(.init(type: "command", id: UUID(),
                    command: .init(name: "seek", time: 12)))
            } else if message.type == "state", message.state?.playhead == 12 {
                receivedState.fulfill()
                client.close()
            }
        }
        client.onClose = { disconnected.fulfill() }
        client.start()
        await fulfillment(of: [paired, commanded, receivedState, disconnected], timeout: 5)
        serverPeer?.close()
        listener.cancel()
    }

    func testFullMarkPayloadIsLossless() throws {
        let original = Data("{\"curve\":{\"controlOffset\":[1,2,3]},\"anchors\":[\"A\"]}".utf8)
        let mark = ReplayXIWireMark(id: UUID(), kind: "arc", start: .init(x: -2, z: 3),
            end: .init(x: 5, z: 7), startHeight: 0.5, endHeight: 1.2,
            label: "Curved run", showAt: 2, hideAt: 8, keyframes: [2, 5], authored: false,
            controlPoint: .init(x: 1, y: 2, z: 4), encodedMark: original)
        let decoded = try ReplayXIWire.decoder.decode(ReplayXIWireMark.self,
            from: ReplayXIWire.encoder.encode(mark))
        XCTAssertEqual(decoded.encodedMark, original)
        XCTAssertEqual(decoded.controlPoint, mark.controlPoint)
    }

    func testCanonicalEncodingAndBoundedParser() throws {
        let encoded = try ReplayXIWire.encoder.encode(["z": 1, "a": 2])
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "{\"a\":2,\"z\":1}")
        var parser = ReplayXIWireParser()
        let valid = try ReplayXIWire.encoder.encode(ReplayXIWireMessage(type: "pair", pin: "123456"))
        XCTAssertTrue(try parser.append(valid.prefix(4)).isEmpty)
        XCTAssertEqual(try parser.append(valid.dropFirst(4) + Data([0x0A])).first?.pin, "123456")
        var wrong = ReplayXIWireMessage(type: "pair")
        wrong.version = 99
        var versionParser = ReplayXIWireParser()
        XCTAssertThrowsError(try versionParser.append(ReplayXIWire.encoder.encode(wrong) + Data([0x0A]))) {
            XCTAssertEqual($0 as? ReplayXIWireError, .version)
        }
        var oversizedParser = ReplayXIWireParser()
        XCTAssertThrowsError(try oversizedParser.append(Data(repeating: 65,
            count: ReplayXIWire.maximumMessageBytes + 2))) {
            XCTAssertEqual($0 as? ReplayXIWireError, .oversized)
        }
    }

    func testPairedCoachWindowRendersAtDesktopAndMinimumSizes() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "fixture listener ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        var serverPeer: ReplayXIWireConnection?
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let peer = ReplayXIWireConnection(connection)
                serverPeer = peer
                peer.onMessage = { message in
                    if message.type == "pair", message.pin == "123456" {
                        peer.send(.init(type: "result", id: message.id, ok: true))
                        peer.send(.init(type: "state", state: Self.previewState))
                    }
                }
                peer.start()
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [ready], timeout: 5)

        let link = ReplayXIMacLink()
        link.pin = "123456"
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: try XCTUnwrap(listener.port))
        link.connect(to: .init(id: "loopback", name: "UI fixture", endpoint: endpoint))
        let paired = expectation(description: "paired view state")
        Task { @MainActor in
            for _ in 0..<150 {
                if link.state != nil { paired.fulfill(); return }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        await fulfillment(of: [paired], timeout: 5)
        XCTAssertEqual(link.state?.marks.count, 2)
        XCTAssertEqual(link.state?.players.count, 3)

        let output = URL(fileURLWithPath: "/private/tmp/replayxi-mac-qa", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (width, height) in [(1360, 840), (1060, 700)] {
            let view = CoachWindow().environment(link)
                .frame(width: CGFloat(width), height: CGFloat(height))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: CGFloat(height))
            let image = try XCTUnwrap(renderer.nsImage)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
            XCTAssertEqual(bitmap.pixelsWide, width)
            XCTAssertEqual(bitmap.pixelsHigh, height)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 10_000)
            try png.write(to: output.appendingPathComponent("replayxi-coach-\(width)x\(height).png"))

            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let hosted = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: hosted)
            let hostedPNG = try XCTUnwrap(hosted.representation(using: .png, properties: [:]))
            try hostedPNG.write(to: output.appendingPathComponent("replayxi-coach-host-\(width)x\(height).png"))
        }
        link.disconnect()
        serverPeer?.close()
        listener.cancel()
    }

    private static var sampleState: ReplayXIWireState {
        .init(revision: 1, scenarioID: "test", playhead: 12, playing: false,
            rate: 1, viewMode: "tacticalTable", perspectiveID: "player", duration: 60,
            scenarios: [.init(id: "test", title: "Test", duration: 60)], players: [],
            ball: .init(x: 0, y: 0.11, z: 0), marks: [],
            canUndo: false, canRedo: false, canSave: true, canEdit: true, status: "Ready")
    }

    private static var previewState: ReplayXIWireState {
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
            duration: 36, scenarios: [.init(id: "preview", title: "Counterattack", duration: 36)],
            players: [
                .init(id: "p7", name: "Left winger", number: 7, team: "home", position: .init(x: -18, z: -20)),
                .init(id: "p9", name: "Striker", number: 9, team: "home", position: .init(x: 4, z: 5)),
                .init(id: "p4", name: "Defender", number: 4, team: "away", position: .init(x: 16, z: 12))
            ], ball: .init(x: 2, y: 0.11, z: 1), marks: [arc, pass],
            canUndo: true, canRedo: false, canSave: true, canEdit: true,
            status: "Sample UI state")
    }
}
