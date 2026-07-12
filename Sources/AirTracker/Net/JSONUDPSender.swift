import Foundation

/// Streams the sony-parity JSON schema, one object per sample.
final class JSONUDPSender: UDPSender, @unchecked Sendable {
    func send(frame: TrackingFrame) {
        send(frame.jsonData())
    }
}
