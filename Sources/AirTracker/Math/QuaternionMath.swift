import Foundation
import simd

struct Euler {
    var yaw: Double
    var pitch: Double
    var roll: Double
}

enum QuaternionMath {
    static func clamp(_ v: Double, _ lo: Double = -1, _ hi: Double = 1) -> Double {
        min(hi, max(lo, v))
    }

    /// Decompose a quaternion into opentrack's Euler convention (degrees):
    /// yaw+ = look left, pitch+ = look up, roll+ = tilt head right.
    /// Assumes the AirPods body frame x=right, y=forward, z=up (verified via the M1 axis probe).
    /// Intrinsic Z-X'-Y'' order, derived from R = Rz(yaw)·Rx(pitch)·Ry(roll).
    static func opentrackEuler(_ q: simd_quatd) -> Euler {
        let w = q.real, x = q.imag.x, y = q.imag.y, z = q.imag.z
        let sinPitch = 2 * (y * z + w * x)
        let pitch = asin(clamp(sinPitch))
        let yaw = atan2(2 * (w * z - x * y), 1 - 2 * (x * x + z * z))
        let roll = atan2(2 * (w * y - x * z), 1 - 2 * (x * x + y * y))
        let d = 180.0 / .pi
        return Euler(yaw: yaw * d, pitch: pitch * d, roll: roll * d)
    }

    /// Shortest-path slerp with sign normalization to avoid long-way-around jumps.
    static func slerp(_ a: simd_quatd, _ b: simd_quatd, _ t: Double) -> simd_quatd {
        var b2 = b
        if simd_dot(a.vector, b.vector) < 0 {
            b2 = simd_quatd(vector: -b.vector)
        }
        return simd_slerp(a, b2, t)
    }
}
