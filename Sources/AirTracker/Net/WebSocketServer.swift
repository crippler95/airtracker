import Foundation
import Network

/// Broadcasts tracking frames as WebSocket text messages and receives commands
/// (currently {"cmd":"recenter"}) from the web viewer. The WebSocket upgrade and
/// framing are handled natively by NWProtocolWebSocket.
final class WebSocketServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.szilard.airtracker.ws")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let port: UInt16

    var onCommand: ((String) -> Void)?

    init(port: UInt16) {
        self.port = port
    }

    func start() {
        queue.async {
            do {
                let params = NWParameters.tcp
                let ws = NWProtocolWebSocket.Options()
                ws.autoReplyPing = true
                params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
                params.allowLocalEndpointReuse = true

                guard let nwPort = NWEndpoint.Port(rawValue: self.port) else { return }
                let listener = try NWListener(using: params, on: nwPort)
                listener.newConnectionHandler = { [weak self] conn in
                    self?.accept(conn)
                }
                listener.start(queue: self.queue)
                self.listener = listener
            } catch {
                NSLog("WebSocketServer failed to start on \(self.port): \(error)")
            }
        }
    }

    private func accept(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .cancelled, .failed:
                self.queue.async { self.connections[id] = nil }
            default:
                break
            }
        }
        connections[id] = conn
        conn.start(queue: queue)
        receive(on: conn)
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            if let data, let text = String(data: data, encoding: .utf8) {
                self?.onCommand?(text)
            }
            if error == nil {
                self?.receive(on: conn)
            }
        }
    }

    func broadcast(_ data: Data) {
        queue.async {
            guard !self.connections.isEmpty else { return }
            let meta = NWProtocolWebSocket.Metadata(opcode: .text)
            let ctx = NWConnection.ContentContext(identifier: "frame", metadata: [meta])
            for conn in self.connections.values {
                conn.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
            }
        }
    }
}
