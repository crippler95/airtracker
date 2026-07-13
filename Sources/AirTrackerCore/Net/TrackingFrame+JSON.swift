import Foundation

extension TrackingFrame {
    /// Sony-head-tracker v2 parity schema, shared by the JSON UDP sink and the web viewer.
    public func jsonData() -> Data {
        (try? JSONSerialization.data(withJSONObject: jsonObject())) ?? Data()
    }

    public func jsonObject() -> [String: Any] {
        let q = quaternion
        return [
            "version": 2,
            "device": "AirPods (CoreMotion)",
            "rotationVector": [q.imag.x, q.imag.y, q.imag.z],
            "quaternion": [q.real, q.imag.x, q.imag.y, q.imag.z],
            "yprDegrees": [euler.yaw, euler.pitch, euler.roll],
            "gyroscope": [rotationRate.x, rotationRate.y, rotationRate.z],
            "accelerometer": [userAcceleration.x, userAcceleration.y, userAcceleration.z],
            "angularVelocity": [rotationRate.x, rotationRate.y, rotationRate.z],
            "resetCounter": resetCounter,
            "packetsPerSecond": packetsPerSecond,
            "receiveLatencyMs": -1.0,
        ]
    }

    /// Extends the sony schema with the live axis config so the web viewer can drive the
    /// head from the remapped Euler and mirror the menu's calibration controls.
    public func webViewerData() -> Data {
        var obj = jsonObject()
        let c = axisConfig
        obj["settings"] = [
            "smoothing": smoothing,
            "yawSource": c.yawSource.rawValue,
            "pitchSource": c.pitchSource.rawValue,
            "rollSource": c.rollSource.rawValue,
            "invertYaw": c.invertYaw,
            "invertPitch": c.invertPitch,
            "invertRoll": c.invertRoll,
            "scaleYaw": c.scaleYaw,
            "scalePitch": c.scalePitch,
            "scaleRoll": c.scaleRoll,
        ]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }
}
