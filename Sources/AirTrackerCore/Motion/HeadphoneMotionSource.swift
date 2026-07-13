import Foundation
import CoreMotion
import simd

/// A single motion sample forwarded from CoreMotion, decoupled from CMDeviceMotion
/// so the rest of the pipeline never imports CoreMotion types.
public struct MotionSample: Sendable {
    public var quaternion: simd_quatd
    public var rotationRate: SIMD3<Double>       // rad/s
    public var userAcceleration: SIMD3<Double>   // g
    public init(quaternion: simd_quatd, rotationRate: SIMD3<Double>, userAcceleration: SIMD3<Double>) {
        self.quaternion = quaternion
        self.rotationRate = rotationRate
        self.userAcceleration = userAcceleration
    }
}

/// Wraps CMHeadphoneMotionManager and forwards samples + connection events.
/// The first call to startDeviceMotionUpdates on a signed .app triggers the Motion TCC prompt.
public final class HeadphoneMotionSource: NSObject, CMHeadphoneMotionManagerDelegate, @unchecked Sendable {
    private let manager = CMHeadphoneMotionManager()
    private let queue = OperationQueue()

    public var onSample: ((MotionSample) -> Void)?
    public var onConnect: (() -> Void)?
    public var onDisconnect: (() -> Void)?

    /// Wall-clock time of the last delivered sample; used by the reconnect watchdog.
    public private(set) var lastSampleTime: TimeInterval = 0

    public override init() {
        super.init()
        queue.name = "com.szilard.airtracker.motion"
        queue.maxConcurrentOperationCount = 1
        manager.delegate = self
    }

    public static var isAvailable: Bool {
        CMHeadphoneMotionManager().isDeviceMotionAvailable
    }

    public static var authorizationStatus: CMAuthorizationStatus {
        CMHeadphoneMotionManager.authorizationStatus()
    }

    public func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let q = m.attitude.quaternion
            self.lastSampleTime = Date().timeIntervalSince1970
            let sample = MotionSample(
                quaternion: simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w),
                rotationRate: SIMD3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z),
                userAcceleration: SIMD3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z)
            )
            self.onSample?(sample)
        }
    }

    public func stop() {
        manager.stopDeviceMotionUpdates()
    }

    /// Stop and restart updates — used by the watchdog when samples stall.
    public func restart() {
        manager.stopDeviceMotionUpdates()
        start()
    }

    public var isActive: Bool { manager.isDeviceMotionActive }

    // MARK: CMHeadphoneMotionManagerDelegate

    public func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        onConnect?()
    }

    public func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        onDisconnect?()
    }
}
