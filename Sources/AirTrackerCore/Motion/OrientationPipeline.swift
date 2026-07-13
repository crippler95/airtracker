import Foundation
import simd

/// A processed tracking frame, ready to be serialized to any sink.
public struct TrackingFrame: Sendable {
    public var quaternion: simd_quatd       // relative-to-reference, smoothed
    public var euler: Euler                 // opentrack degrees (after axis config)
    public var rotationRate: SIMD3<Double>  // smoothed gyroscope, rad/s
    public var userAcceleration: SIMD3<Double> // smoothed accelerometer, g
    public var packetsPerSecond: Int
    public var resetCounter: Int
    public var axisConfig: AxisConfig
    public var smoothing: Double
}

/// Owns recenter reference, smoothing state, axis config, and the sample-rate counter.
/// All mutation is confined to a single serial queue; sinks are invoked on that queue.
public final class OrientationPipeline: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.szilard.airtracker.pipeline")

    private var qRef = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
    private var qSmoothed: simd_quatd?
    private var gyroSmoothed: SIMD3<Double>?
    private var accelSmoothed: SIMD3<Double>?
    private var smoothing: Double = 0.18
    private var axisConfig = AxisConfig()

    private var recenterPending = true          // recenter on first sample so output starts at identity
    private var resetCounter = 0

    // Rolling 1-second window for packets-per-second.
    private var sampleTimestamps: [TimeInterval] = []

    public var onFrame: ((TrackingFrame) -> Void)?

    public init() {}

    public func ingest(_ sample: MotionSample) {
        queue.async { self.process(sample) }
    }

    public func recenter() {
        queue.async {
            self.recenterPending = true
            self.resetCounter += 1
        }
    }

    public func setSmoothing(_ value: Double) {
        queue.async { self.smoothing = min(0.9, max(0, value)) }
    }

    public func setAxisConfig(_ value: AxisConfig) {
        queue.async { self.axisConfig = value }
    }

    /// Pure transform used by both the pipeline and unit tests.
    public static func euler(from q: simd_quatd, config: AxisConfig) -> Euler {
        config.apply(to: QuaternionMath.opentrackEuler(q))
    }

    private func process(_ sample: MotionSample) {
        if recenterPending {
            qRef = sample.quaternion
            qSmoothed = nil
            gyroSmoothed = nil
            accelSmoothed = nil
            recenterPending = false
        }

        // Relative orientation in the reference body frame.
        let qRel = simd_normalize(qRef.inverse * sample.quaternion)

        // Exponential slerp low-pass on orientation, matching linear lerp on the vectors.
        let smoothed: simd_quatd
        if let prev = qSmoothed, smoothing > 0 {
            smoothed = QuaternionMath.slerp(prev, qRel, 1.0 - smoothing)
        } else {
            smoothed = qRel
        }
        qSmoothed = smoothed

        let gyro = lowpass(&gyroSmoothed, sample.rotationRate)
        let accel = lowpass(&accelSmoothed, sample.userAcceleration)

        let euler = OrientationPipeline.euler(from: smoothed, config: axisConfig)

        let now = Date().timeIntervalSince1970
        sampleTimestamps.append(now)
        sampleTimestamps.removeAll { now - $0 > 1.0 }

        let frame = TrackingFrame(
            quaternion: smoothed,
            euler: euler,
            rotationRate: gyro,
            userAcceleration: accel,
            packetsPerSecond: sampleTimestamps.count,
            resetCounter: resetCounter,
            axisConfig: axisConfig,
            smoothing: smoothing
        )
        onFrame?(frame)
    }

    private func lowpass(_ state: inout SIMD3<Double>?, _ value: SIMD3<Double>) -> SIMD3<Double> {
        guard smoothing > 0, let prev = state else { state = value; return value }
        let out = prev + (value - prev) * (1.0 - smoothing)
        state = out
        return out
    }
}
