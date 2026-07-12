import Foundation
import Network

/// Minimal static file server for the web viewer. Serves index.html and the
/// vendored Three.js module from the app's resource bundle. Listens on all
/// interfaces so a browser on another LAN machine can also open the viewer.
final class HTTPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.szilard.airtracker.http")
    private var listener: NWListener?
    private let port: UInt16
    private let wsPort: UInt16

    init(port: UInt16, wsPort: UInt16) {
        self.port = port
        self.wsPort = wsPort
    }

    func start() {
        queue.async {
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                guard let nwPort = NWEndpoint.Port(rawValue: self.port) else { return }
                let listener = try NWListener(using: params, on: nwPort)
                listener.newConnectionHandler = { [weak self] conn in
                    self?.handle(conn)
                }
                listener.start(queue: self.queue)
                self.listener = listener
            } catch {
                NSLog("HTTPServer failed to start on \(self.port): \(error)")
            }
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { conn.cancel(); return }
            let path = self.parsePath(data)
            let (body, contentType) = self.resource(for: path)
            self.respond(conn, status: body == nil ? "404 Not Found" : "200 OK",
                         body: body ?? Data("Not Found".utf8), contentType: contentType)
        }
    }

    private func parsePath(_ data: Data?) -> String {
        guard let data, let line = String(data: data, encoding: .utf8)?
            .split(separator: "\r\n").first else { return "/" }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        return String(parts[1])
    }

    private func resource(for path: String) -> (Data?, String) {
        let webDir = Bundle.module.url(forResource: "Web", withExtension: nil)
        switch path {
        case "/", "/index.html":
            let url = webDir?.appendingPathComponent("index.html")
            var html = url.flatMap { try? Data(contentsOf: $0) }
            // Inject the WebSocket port so the page needs no build step.
            if let data = html, var str = String(data: data, encoding: .utf8) {
                str = str.replacingOccurrences(of: "__WS_PORT__", with: String(wsPort))
                html = Data(str.utf8)
            }
            return (html, "text/html; charset=utf-8")
        case "/vendor/three.module.min.js":
            let url = webDir?.appendingPathComponent("three.module.min.js")
            return (url.flatMap { try? Data(contentsOf: $0) }, "text/javascript; charset=utf-8")
        default:
            return (nil, "text/plain; charset=utf-8")
        }
    }

    private func respond(_ conn: NWConnection, status: String, body: Data, contentType: String) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Connection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }
}
