import Foundation

extension TrackingFrame {
    /// Sony-head-tracker v2 parity schema, shared by the JSON UDP sink and the web viewer.
    func jsonData() -> Data {
        let q = quaternion
        let obj: [String: Any] = [
            "version": 2,
            "device": "AirPods (CoreMotion)",
            "rotationVector": [q.imag.x, q.imag.y, q.imag.z],
            "quaternion": [q.real, q.imag.x, q.imag.y, q.imag.z],
            "yprDegrees": [euler.yaw, euler.pitch, euler.roll],
            "gyroscope": [rotationRate.x, rotationRate.y, rotationRate.z],
            "accelerometer": [userAcceleration.x, userAcceleration.y, userAcceleration.z],
            "packetsPerSecond": packetsPerSecond,
            "receiveLatencyMs": -1.0,
        ]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    /// Extends the sony schema with the live control settings so the web viewer can
    /// drive the head from the (inverted) Euler and mirror the menu's toggles.
    func webViewerData() -> Data {
        let q = quaternion
        let obj: [String: Any] = [
            "quaternion": [q.real, q.imag.x, q.imag.y, q.imag.z],
            "yprDegrees": [euler.yaw, euler.pitch, euler.roll],
            "packetsPerSecond": packetsPerSecond,
            "settings": [
                "smoothing": smoothing,
                "invertYaw": inversion.yaw,
                "invertPitch": inversion.pitch,
                "invertRoll": inversion.roll,
            ],
        ]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }
}
