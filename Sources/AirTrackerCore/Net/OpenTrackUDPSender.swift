import Foundation

/// Streams opentrack's "UDP over network" format: six little-endian Float64
/// (x, y, z in cm, then yaw, pitch, roll in degrees). Translation is always 0.
public final class OpenTrackUDPSender: UDPSender, @unchecked Sendable {
    public func send(frame: TrackingFrame) {
        send(OpenTrackUDPSender.packet(yaw: frame.euler.yaw, pitch: frame.euler.pitch, roll: frame.euler.roll))
    }

    /// Pure packet builder, exercised by unit tests.
    public static func packet(yaw: Double, pitch: Double, roll: Double) -> Data {
        var data = Data(capacity: 48)
        let values: [Double] = [0, 0, 0, yaw, pitch, roll]
        for v in values {
            var le = v.bitPattern.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }
}
