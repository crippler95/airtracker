import Foundation
import simd

public struct Euler: Equatable, Sendable {
    public var yaw: Double
    public var pitch: Double
    public var roll: Double
    public init(yaw: Double, pitch: Double, roll: Double) {
        self.yaw = yaw; self.pitch = pitch; self.roll = roll
    }
}

public enum SourceAxis: String, Codable, Sendable, CaseIterable {
    case yaw, pitch, roll
}

/// Full axis calibration: for each output channel choose which computed axis feeds it,
/// whether to invert it, and a sensitivity multiplier. Subsumes simple inversion and
/// covers the "two axes are swapped" case that a sign flip alone can't fix.
public struct AxisConfig: Codable, Equatable, Sendable {
    public var yawSource: SourceAxis = .yaw
    public var pitchSource: SourceAxis = .pitch
    public var rollSource: SourceAxis = .roll
    public var invertYaw = false
    public var invertPitch = true       // AirPods body frame reads pitch inverted vs opentrack
    public var invertRoll = false
    public var scaleYaw = 1.0
    public var scalePitch = 1.0
    public var scaleRoll = 1.0
    public init() {}

    public func apply(to e: Euler) -> Euler {
        func pick(_ a: SourceAxis) -> Double {
            switch a { case .yaw: return e.yaw; case .pitch: return e.pitch; case .roll: return e.roll }
        }
        return Euler(
            yaw: pick(yawSource) * (invertYaw ? -1 : 1) * scaleYaw,
            pitch: pick(pitchSource) * (invertPitch ? -1 : 1) * scalePitch,
            roll: pick(rollSource) * (invertRoll ? -1 : 1) * scaleRoll
        )
    }
}

public enum QuaternionMath {
    public static func clamp(_ v: Double, _ lo: Double = -1, _ hi: Double = 1) -> Double {
        min(hi, max(lo, v))
    }

    /// Decompose a quaternion into opentrack's Euler convention (degrees):
    /// yaw+ = look left, pitch+ = look up, roll+ = tilt head right.
    /// Assumes the AirPods body frame x=right, y=forward, z=up.
    /// Intrinsic Z-X'-Y'' order, derived from R = Rz(yaw)·Rx(pitch)·Ry(roll).
    public static func opentrackEuler(_ q: simd_quatd) -> Euler {
        let w = q.real, x = q.imag.x, y = q.imag.y, z = q.imag.z
        let sinPitch = 2 * (y * z + w * x)
        let pitch = asin(clamp(sinPitch))
        let yaw = atan2(2 * (w * z - x * y), 1 - 2 * (x * x + z * z))
        let roll = atan2(2 * (w * y - x * z), 1 - 2 * (x * x + y * y))
        let d = 180.0 / .pi
        return Euler(yaw: yaw * d, pitch: pitch * d, roll: roll * d)
    }

    /// Shortest-path slerp with sign normalization to avoid long-way-around jumps.
    public static func slerp(_ a: simd_quatd, _ b: simd_quatd, _ t: Double) -> simd_quatd {
        var b2 = b
        if simd_dot(a.vector, b.vector) < 0 {
            b2 = simd_quatd(vector: -b.vector)
        }
        return simd_slerp(a, b2, t)
    }
}
