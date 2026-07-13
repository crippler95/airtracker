import XCTest
import simd
@testable import AirTrackerCore

final class AirTrackerCoreTests: XCTestCase {

    // MARK: opentrack Euler conversion

    func testIdentityQuaternionIsZeroEuler() {
        let e = QuaternionMath.opentrackEuler(simd_quatd(ix: 0, iy: 0, iz: 0, r: 1))
        XCTAssertEqual(e.yaw, 0, accuracy: 1e-9)
        XCTAssertEqual(e.pitch, 0, accuracy: 1e-9)
        XCTAssertEqual(e.roll, 0, accuracy: 1e-9)
    }

    func testYawRotationAboutZ() {
        // +30° about the vertical (z) axis → yaw ≈ +30°.
        let angle = 30.0 * .pi / 180
        let q = simd_quatd(angle: angle, axis: SIMD3(0, 0, 1))
        let e = QuaternionMath.opentrackEuler(q)
        XCTAssertEqual(e.yaw, 30, accuracy: 1e-6)
        XCTAssertEqual(e.pitch, 0, accuracy: 1e-6)
        XCTAssertEqual(e.roll, 0, accuracy: 1e-6)
    }

    func testPitchRotationAboutX() {
        let angle = 20.0 * .pi / 180
        let q = simd_quatd(angle: angle, axis: SIMD3(1, 0, 0))
        let e = QuaternionMath.opentrackEuler(q)
        XCTAssertEqual(e.pitch, 20, accuracy: 1e-6)
        XCTAssertEqual(e.yaw, 0, accuracy: 1e-6)
        XCTAssertEqual(e.roll, 0, accuracy: 1e-6)
    }

    func testRollRotationAboutY() {
        let angle = 15.0 * .pi / 180
        let q = simd_quatd(angle: angle, axis: SIMD3(0, 1, 0))
        let e = QuaternionMath.opentrackEuler(q)
        XCTAssertEqual(e.roll, 15, accuracy: 1e-6)
        XCTAssertEqual(e.yaw, 0, accuracy: 1e-6)
        XCTAssertEqual(e.pitch, 0, accuracy: 1e-6)
    }

    // MARK: AxisConfig

    func testAxisConfigDefaultInvertsPitch() {
        let c = AxisConfig()
        let out = c.apply(to: Euler(yaw: 10, pitch: 20, roll: 30))
        XCTAssertEqual(out.yaw, 10)
        XCTAssertEqual(out.pitch, -20)   // invertPitch default on
        XCTAssertEqual(out.roll, 30)
    }

    func testAxisConfigRemapAndScale() {
        var c = AxisConfig()
        c.invertPitch = false
        c.yawSource = .roll          // yaw output reads the roll channel
        c.scaleYaw = 2.0
        let out = c.apply(to: Euler(yaw: 10, pitch: 20, roll: 30))
        XCTAssertEqual(out.yaw, 60)   // roll(30) * 2.0
        XCTAssertEqual(out.pitch, 20)
        XCTAssertEqual(out.roll, 30)
    }

    // MARK: opentrack packet

    func testOpenTrackPacketIsFortyEightLittleEndianBytes() {
        let data = OpenTrackUDPSender.packet(yaw: 1.5, pitch: -2.5, roll: 3.5)
        XCTAssertEqual(data.count, 48)
        let values = data.withUnsafeBytes { raw -> [Double] in
            (0..<6).map { i in
                let bits = raw.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self)
                return Double(bitPattern: UInt64(littleEndian: bits))
            }
        }
        XCTAssertEqual(values, [0, 0, 0, 1.5, -2.5, 3.5])
    }

    // MARK: JSON schema parity

    func testJSONHasSonyParityFields() throws {
        let frame = TrackingFrame(
            quaternion: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1),
            euler: Euler(yaw: 1, pitch: 2, roll: 3),
            rotationRate: SIMD3(0.1, 0.2, 0.3),
            userAcceleration: SIMD3(0.4, 0.5, 0.6),
            packetsPerSecond: 25,
            resetCounter: 4,
            axisConfig: AxisConfig(),
            smoothing: 0.18
        )
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: frame.jsonData()) as? [String: Any])
        for key in ["version", "device", "rotationVector", "quaternion", "yprDegrees",
                    "gyroscope", "accelerometer", "angularVelocity", "resetCounter",
                    "packetsPerSecond", "receiveLatencyMs"] {
            XCTAssertNotNil(obj[key], "missing \(key)")
        }
        XCTAssertEqual(obj["resetCounter"] as? Int, 4)
        XCTAssertEqual(obj["version"] as? Int, 2)
    }

    func testWebViewerDataHasSettings() throws {
        let frame = TrackingFrame(
            quaternion: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1),
            euler: Euler(yaw: 0, pitch: 0, roll: 0),
            rotationRate: .zero, userAcceleration: .zero,
            packetsPerSecond: 0, resetCounter: 0, axisConfig: AxisConfig(), smoothing: 0.18
        )
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: frame.webViewerData()) as? [String: Any])
        let settings = try XCTUnwrap(obj["settings"] as? [String: Any])
        XCTAssertEqual(settings["invertPitch"] as? Bool, true)
        XCTAssertNotNil(settings["yawSource"])
    }

    // MARK: TrackerSettings round-trip

    func testSettingsCodableRoundTrip() throws {
        var s = TrackerSettings()
        s.openTrackHost = "192.168.1.42"
        s.openTrackPort = 5005
        s.axis.rollSource = .yaw
        s.axis.scalePitch = 1.7
        let data = SettingsStore.encode(s)
        let back = try XCTUnwrap(SettingsStore.decode(data))
        XCTAssertEqual(s, back)
    }

    // MARK: slerp

    func testSlerpMidpoint() {
        let a = simd_quatd(angle: 0, axis: SIMD3(0, 0, 1))
        let b = simd_quatd(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        let mid = QuaternionMath.slerp(a, b, 0.5)
        let e = QuaternionMath.opentrackEuler(mid)
        XCTAssertEqual(e.yaw, 45, accuracy: 1e-6)
    }
}
