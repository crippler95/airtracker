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
/// Also owns the response shaping shared by all axes: a subtractive deadzone (degrees)
/// and an expo curve that softens small motions without capping the range.
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
    public var deadzone = 0.0           // degrees removed around center, per axis
    public var expo = 0.0               // 0 = linear, 1 = fully quadratic below 90°
    public init() {}

    public init(from decoder: Decoder) throws {
        // decodeIfPresent everywhere so configs saved by older versions keep loading.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        yawSource = try c.decodeIfPresent(SourceAxis.self, forKey: .yawSource) ?? .yaw
        pitchSource = try c.decodeIfPresent(SourceAxis.self, forKey: .pitchSource) ?? .pitch
        rollSource = try c.decodeIfPresent(SourceAxis.self, forKey: .rollSource) ?? .roll
        invertYaw = try c.decodeIfPresent(Bool.self, forKey: .invertYaw) ?? false
        invertPitch = try c.decodeIfPresent(Bool.self, forKey: .invertPitch) ?? true
        invertRoll = try c.decodeIfPresent(Bool.self, forKey: .invertRoll) ?? false
        scaleYaw = try c.decodeIfPresent(Double.self, forKey: .scaleYaw) ?? 1.0
        scalePitch = try c.decodeIfPresent(Double.self, forKey: .scalePitch) ?? 1.0
        scaleRoll = try c.decodeIfPresent(Double.self, forKey: .scaleRoll) ?? 1.0
        deadzone = try c.decodeIfPresent(Double.self, forKey: .deadzone) ?? 0.0
        expo = try c.decodeIfPresent(Double.self, forKey: .expo) ?? 0.0
    }

    /// Deadzone then expo, both odd-symmetric and continuous. The expo blend is
    /// linear·(1−expo) + quadratic·expo, normalized so 90° maps to 90° at any expo.
    public func shape(_ v: Double) -> Double {
        var m = Swift.max(0, abs(v) - Swift.max(0, deadzone))
        if expo > 0 {
            m = m * (1 - expo) + (m * m / 90.0) * expo
        }
        return v < 0 ? -m : m
    }

    public func apply(to e: Euler) -> Euler {
        func pick(_ a: SourceAxis) -> Double {
            switch a { case .yaw: return e.yaw; case .pitch: return e.pitch; case .roll: return e.roll }
        }
        return Euler(
            yaw: shape(pick(yawSource)) * (invertYaw ? -1 : 1) * scaleYaw,
            pitch: shape(pick(pitchSource)) * (invertPitch ? -1 : 1) * scalePitch,
            roll: shape(pick(rollSource)) * (invertRoll ? -1 : 1) * scaleRoll
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
