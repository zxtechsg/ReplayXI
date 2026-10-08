import Foundation
import Network

// Shared by the visionOS service and the separate macOS app. A line is one
// bounded JSON message; the full encoded CoachMark is carried without loss.
enum ReplayXIWire {
    static let serviceType = "_replayxi-coach._tcp"
    static let maximumMessageBytes = 4 * 1024 * 1024
    static let maximumCommandBytes = 8 * 1024
    static let protocolVersion = 1
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    static let decoder = JSONDecoder()
}

struct ReplayXIWirePoint: Codable, Equatable {
    var x: Float
    var z: Float
}

struct ReplayXIWirePoint3: Codable, Equatable {
    var x: Float
    var y: Float
    var z: Float
}

struct ReplayXIWirePlayer: Codable, Identifiable {
    var id: String
    var name: String
    var number: Int
    var team: String
    var position: ReplayXIWirePoint
}

struct ReplayXIWireScenario: Codable, Identifiable {
    var id: String
    var title: String
    var duration: Double
}

struct ReplayXIWireMark: Codable, Identifiable {
    var id: UUID
    var kind: String
    var start: ReplayXIWirePoint
    var end: ReplayXIWirePoint
    var startHeight: Float
    var endHeight: Float
    var label: String
    var showAt: Double
    var hideAt: Double?
    var keyframes: [Double]
    var authored: Bool
    var controlPoint: ReplayXIWirePoint3?
    /// Exact CoachMark Codable bytes, including anchors, curves and keyframes.
    var encodedMark: Data
}

struct ReplayXIWireState: Codable {
    var revision: UInt64
    var scenarioID: String
    var playhead: Double
    var playing: Bool
    var rate: Double
    var viewMode: String
    var perspectiveID: String
    var duration: Double
    var scenarios: [ReplayXIWireScenario]
    var players: [ReplayXIWirePlayer]
    var ball: ReplayXIWirePoint3
    var marks: [ReplayXIWireMark]
    var canUndo: Bool
    var canRedo: Bool
    var canSave: Bool
    var canEdit: Bool
    var status: String
}

struct ReplayXIWireCommand: Codable {
    var name: String
    var expectedRevision: UInt64? = nil
    var expectedScenarioID: String? = nil
    var scenarioID: String? = nil
    var time: Double? = nil
    var rate: Double? = nil
    var value: Bool? = nil
    var viewMode: String? = nil
    var playerID: String? = nil
    var markID: UUID? = nil
    var kind: String? = nil
    var start: ReplayXIWirePoint? = nil
    var end: ReplayXIWirePoint? = nil
    var startHeight: Float? = nil
    var endHeight: Float? = nil
    var controlPoint: ReplayXIWirePoint3? = nil
    var label: String? = nil
    var showAt: Double? = nil
    var hideAt: Double? = nil
    var keyframeAt: Double? = nil
    var keyframeTo: Double? = nil
    var saveName: String? = nil
}

struct ReplayXIWireMessage: Codable {
    var version: Int = ReplayXIWire.protocolVersion
    var type: String
    var id: UUID? = nil
    var pin: String? = nil
    var command: ReplayXIWireCommand? = nil
    var state: ReplayXIWireState? = nil
    var ok: Bool? = nil
    var detail: String? = nil
}

enum ReplayXIWireError: Error, Equatable {
    case oversized
    case invalid
    case version

    var detail: String {
        switch self {
        case .oversized: "Replay XI message exceeds 4 MB limit"
        case .invalid: "Invalid Replay XI message"
        case .version: "Replay XI versions differ"
        }
    }
}

struct ReplayXIWireParser {
    private var input = Data()

    mutating func append(_ bytes: Data) throws -> [ReplayXIWireMessage] {
        guard input.count + bytes.count <= ReplayXIWire.maximumMessageBytes + 1 else {
            throw ReplayXIWireError.oversized
        }
        input.append(bytes)
        var messages: [ReplayXIWireMessage] = []
        while let newline = input.firstIndex(of: 0x0A) {
            let line = input.prefix(upTo: newline)
            input.removeSubrange(...newline)
            guard line.count <= ReplayXIWire.maximumMessageBytes,
                  let message = try? ReplayXIWire.decoder.decode(ReplayXIWireMessage.self, from: line) else {
                throw ReplayXIWireError.invalid
            }
            guard message.version == ReplayXIWire.protocolVersion else {
                throw ReplayXIWireError.version
            }
            messages.append(message)
        }
        return messages
    }
}

@MainActor
final class ReplayXIWireConnection {
    let connection: NWConnection
    var onMessage: ((ReplayXIWireMessage) -> Void)?
    var onClose: (() -> Void)?
    var onReady: (() -> Void)?
    var onProtocolError: ((String) -> Void)?
    private var parser = ReplayXIWireParser()
    private var closed = false
    private var closingAfterFlush = false
    private var sending = false
    private var pendingCritical: [Data] = []
    private var pendingState: Data?

    init(_ connection: NWConnection) { self.connection = connection }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .ready = state { self.onReady?() }
                if case .failed = state { self.close() }
                if case .cancelled = state { self.close() }
            }
        }
        connection.start(queue: .main)
        receive()
    }

    @discardableResult
    func send(_ message: ReplayXIWireMessage) -> Bool {
        guard !closed, let bytes = try? ReplayXIWire.encoder.encode(message),
              bytes.count <= ReplayXIWire.maximumMessageBytes else { return false }
        var line = bytes; line.append(0x0A)
        if message.type == "state" {
            pendingState = line
        } else {
            guard pendingCritical.count < 16 else { close(); return false }
            pendingCritical.append(line)
        }
        drain()
        return true
    }

    func closeAfterFlush() {
        closingAfterFlush = true
        drain()
    }

    private func drain() {
        guard !sending, !closed else { return }
        let line: Data
        if !pendingCritical.isEmpty { line = pendingCritical.removeFirst() }
        else if let state = pendingState { line = state; pendingState = nil }
        else {
            if closingAfterFlush { close() }
            return
        }
        sending = true
        connection.send(content: line, completion: .contentProcessed { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sending = false
                if error != nil { self.close() } else { self.drain() }
            }
        })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] bytes, _, done, error in
            Task { @MainActor [weak self] in
                guard let self, !self.closed, !self.closingAfterFlush else { return }
                do {
                    let messages = try self.parser.append(bytes ?? Data())
                    for message in messages {
                        self.onMessage?(message)
                        if self.closed { return }
                    }
                } catch let wireError as ReplayXIWireError {
                    self.onProtocolError?(wireError.detail)
                    self.close()
                    return
                } catch {
                    self.onProtocolError?("Invalid Replay XI message")
                    self.close()
                    return
                }
                if error != nil || done { self.close() } else { self.receive() }
            }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClose?()
    }
}
