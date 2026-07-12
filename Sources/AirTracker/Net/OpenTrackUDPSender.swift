import Foundation

/// Streams opentrack's "UDP over network" format: six little-endian Float64
/// (x, y, z in cm, then yaw, pitch, roll in degrees). Translation is always 0.
final class OpenTrackUDPSender: UDPSender, @unchecked Sendable {
    func send(frame: TrackingFrame) {
        var data = Data(capacity: 48)
        let values: [Double] = [0, 0, 0, frame.euler.yaw, frame.euler.pitch, frame.euler.roll]
        for v in values {
            var le = v.bitPattern.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        send(data)
    }
}
