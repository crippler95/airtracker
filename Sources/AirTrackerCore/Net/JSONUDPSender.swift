import Foundation

/// Streams the sony-parity JSON schema, one object per sample.
public final class JSONUDPSender: UDPSender, @unchecked Sendable {
    public func send(frame: TrackingFrame) {
        send(frame.jsonData())
    }
}
