import Foundation
import Network

/// Base UDP sender over Network.framework. Recreates the connection on endpoint
/// change or failure; drops sends until the connection is ready.
open class UDPSender: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.szilard.airtracker.udp")
    private var connection: NWConnection?
    private var host: String
    private var port: UInt16
    private var ready = false

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    public func start() {
        queue.async { self.reconnect() }
    }

    public func updateEndpoint(host: String, port: UInt16) {
        queue.async {
            guard host != self.host || port != self.port else { return }
            self.host = host
            self.port = port
            self.reconnect()
        }
    }

    public func stop() {
        queue.async {
            self.connection?.cancel()
            self.connection = nil
            self.ready = false
        }
    }

    private func reconnect() {
        connection?.cancel()
        ready = false
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.ready = true
            case .failed, .cancelled:
                self.ready = false
            default:
                break
            }
        }
        connection = conn
        conn.start(queue: queue)
    }

    /// Enqueue a datagram. Safe to call from any thread.
    public func send(_ data: Data) {
        queue.async {
            guard self.ready, let conn = self.connection else { return }
            conn.send(content: data, completion: .idempotent)
        }
    }
}
