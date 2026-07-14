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

    // MARK: Response shaping

    func testDeadzoneRemovesSmallMotionContinuously() {
        var c = AxisConfig()
        c.deadzone = 2
        XCTAssertEqual(c.shape(1.5), 0)
        XCTAssertEqual(c.shape(-1.5), 0)
        XCTAssertEqual(c.shape(2), 0)          // no jump at the edge
        XCTAssertEqual(c.shape(5), 3)          // subtractive, not a cliff
        XCTAssertEqual(c.shape(-5), -3)
    }

    func testExpoSoftensSmallAndPreserves90() {
        var c = AxisConfig()
        c.expo = 1.0
        XCTAssertEqual(c.shape(90), 90, accuracy: 1e-9)     // 90° invariant
        XCTAssertEqual(c.shape(-90), -90, accuracy: 1e-9)
        XCTAssertEqual(c.shape(9), 0.9, accuracy: 1e-9)     // quadratic near center
        c.expo = 0.5
        XCTAssertEqual(c.shape(9), 4.5 + 0.45, accuracy: 1e-9)  // linear/quadratic blend
        XCTAssertEqual(c.shape(0), 0)
    }

    func testShapingAppliesBeforeInvertAndScale() {
        var c = AxisConfig()
        c.invertPitch = false
        c.deadzone = 1
        c.scaleYaw = 2
        c.invertYaw = true
        let out = c.apply(to: Euler(yaw: 3, pitch: 0.5, roll: 0))
        XCTAssertEqual(out.yaw, -4)     // (3-1) * 2, inverted
        XCTAssertEqual(out.pitch, 0)    // inside deadzone
    }

    // MARK: Drift compensation

    func testDriftStepIsCappedByRate() {
        // Far from center: the accumulator moves at most rate·dt per step.
        let d = OrientationPipeline.stepDrift(0, towards: 30, rate: 1.0, dt: 0.04)
        XCTAssertEqual(d, 0.04, accuracy: 1e-12)
    }

    func testDriftConvergesToHeldYaw() {
        // Holding 5° for long enough pulls the output (yaw - drift) back to 0.
        var drift = 0.0
        for _ in 0..<200 {
            drift = OrientationPipeline.stepDrift(drift, towards: 5, rate: 1.0, dt: 0.04)
        }
        XCTAssertEqual(drift, 5, accuracy: 1e-9)
    }

    func testDriftFollowsSignChanges() {
        var drift = OrientationPipeline.stepDrift(0, towards: -10, rate: 2.0, dt: 0.1)
        XCTAssertEqual(drift, -0.2, accuracy: 1e-12)
        drift = OrientationPipeline.stepDrift(drift, towards: drift, rate: 2.0, dt: 0.1)
        XCTAssertEqual(drift, -0.2, accuracy: 1e-12)   // at target → no movement
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
            smoothing: 0.18,
            driftCompensation: 0
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
            packetsPerSecond: 0, resetCounter: 0, axisConfig: AxisConfig(), smoothing: 0.18,
            driftCompensation: 0
        )
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: frame.webViewerData()) as? [String: Any])
        let settings = try XCTUnwrap(obj["settings"] as? [String: Any])
        XCTAssertEqual(settings["invertPitch"] as? Bool, true)
        XCTAssertNotNil(settings["yawSource"])
        XCTAssertNotNil(settings["deadzone"])
        XCTAssertNotNil(settings["expo"])
        XCTAssertNotNil(settings["driftCompensation"])
    }

    // MARK: TrackerSettings round-trip

    func testSettingsCodableRoundTrip() throws {
        var s = TrackerSettings()
        s.openTrackHost = "192.168.1.42"
        s.openTrackPort = 5005
        s.axis.rollSource = .yaw
        s.axis.scalePitch = 1.7
        s.axis.deadzone = 2.5
        s.axis.expo = 0.4
        s.driftCompensation = 1.5
        s.recenterOnConnect = false
        let data = SettingsStore.encode(s)
        let back = try XCTUnwrap(SettingsStore.decode(data))
        XCTAssertEqual(s, back)
    }

    func testSettingsFromOlderVersionStillDecode() throws {
        // A 1.1.0 config has none of the 1.2.0 keys; it must load with defaults.
        let old = """
        {"openTrackHost":"10.0.0.7","openTrackPort":4242,"smoothing":0.3,
         "axis":{"yawSource":"yaw","pitchSource":"pitch","rollSource":"roll",
                 "invertYaw":false,"invertPitch":true,"invertRoll":false,
                 "scaleYaw":1,"scalePitch":1,"scaleRoll":1}}
        """
        let s = try XCTUnwrap(SettingsStore.decode(Data(old.utf8)))
        XCTAssertEqual(s.openTrackHost, "10.0.0.7")
        XCTAssertEqual(s.smoothing, 0.3)
        XCTAssertEqual(s.axis.deadzone, 0)
        XCTAssertEqual(s.axis.expo, 0)
        XCTAssertEqual(s.driftCompensation, 0)
        XCTAssertTrue(s.recenterOnConnect)
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
