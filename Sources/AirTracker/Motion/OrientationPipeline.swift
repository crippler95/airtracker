import Foundation
import simd

struct AxisInversion: Equatable {
    var yaw = false
    var pitch = false
    var roll = false
}

/// A processed tracking frame, ready to be serialized to any sink.
struct TrackingFrame {
    var quaternion: simd_quatd       // relative-to-reference, smoothed
    var euler: Euler                 // opentrack degrees (after inversion)
    var rotationRate: SIMD3<Double>
    var userAcceleration: SIMD3<Double>
    var packetsPerSecond: Int
    var smoothing: Double            // current settings, echoed to the web viewer
    var inversion: AxisInversion
}

/// Owns recenter reference, smoothing state, axis config, and the sample-rate counter.
/// All mutation is confined to a single serial queue; sinks are invoked on that queue.
final class OrientationPipeline: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.szilard.airtracker.pipeline")

    private var qRef = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
    private var qSmoothed: simd_quatd?
    private var smoothing: Double = 0.18
    private var inversion = AxisInversion()

    private var recenterPending = true          // recenter on first sample so output starts at identity
    private var lastRawQuaternion = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)

    // Rolling 1-second window for packets-per-second.
    private var sampleTimestamps: [TimeInterval] = []

    var onFrame: ((TrackingFrame) -> Void)?

    func ingest(_ sample: MotionSample) {
        queue.async { self.process(sample) }
    }

    func recenter() {
        queue.async { self.recenterPending = true }
    }

    func setSmoothing(_ value: Double) {
        queue.async { self.smoothing = min(0.9, max(0, value)) }
    }

    func setInversion(_ value: AxisInversion) {
        queue.async { self.inversion = value }
    }

    private func process(_ sample: MotionSample) {
        lastRawQuaternion = sample.quaternion

        if recenterPending {
            qRef = sample.quaternion
            qSmoothed = nil
            recenterPending = false
        }

        // Relative orientation in the reference body frame.
        let qRel = qRef.inverse * sample.quaternion

        // Exponential slerp low-pass.
        let target = simd_normalize(qRel)
        let smoothed: simd_quatd
        if let prev = qSmoothed, smoothing > 0 {
            smoothed = QuaternionMath.slerp(prev, target, 1.0 - smoothing)
        } else {
            smoothed = target
        }
        qSmoothed = smoothed

        var euler = QuaternionMath.opentrackEuler(smoothed)
        if inversion.yaw { euler.yaw = -euler.yaw }
        if inversion.pitch { euler.pitch = -euler.pitch }
        if inversion.roll { euler.roll = -euler.roll }

        let now = Date().timeIntervalSince1970
        sampleTimestamps.append(now)
        sampleTimestamps.removeAll { now - $0 > 1.0 }

        let frame = TrackingFrame(
            quaternion: smoothed,
            euler: euler,
            rotationRate: sample.rotationRate,
            userAcceleration: sample.userAcceleration,
            packetsPerSecond: sampleTimestamps.count,
            smoothing: smoothing,
            inversion: inversion
        )
        onFrame?(frame)
    }
}
