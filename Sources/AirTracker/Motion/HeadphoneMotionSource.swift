import Foundation
import CoreMotion
import simd

/// A single motion sample forwarded from CoreMotion, decoupled from CMDeviceMotion
/// so the rest of the pipeline never imports CoreMotion types.
struct MotionSample {
    var quaternion: simd_quatd
    var rotationRate: SIMD3<Double>       // rad/s
    var userAcceleration: SIMD3<Double>   // g
}

/// Wraps CMHeadphoneMotionManager and forwards samples + connection events.
/// The first call to startDeviceMotionUpdates on a signed .app triggers the Motion TCC prompt.
final class HeadphoneMotionSource: NSObject, CMHeadphoneMotionManagerDelegate, @unchecked Sendable {
    private let manager = CMHeadphoneMotionManager()
    private let queue = OperationQueue()

    var onSample: ((MotionSample) -> Void)?
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?

    override init() {
        super.init()
        queue.name = "com.szilard.airtracker.motion"
        queue.maxConcurrentOperationCount = 1
        manager.delegate = self
    }

    static var isAvailable: Bool {
        CMHeadphoneMotionManager().isDeviceMotionAvailable
    }

    static var authorizationStatus: CMAuthorizationStatus {
        CMHeadphoneMotionManager.authorizationStatus()
    }

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let q = m.attitude.quaternion
            let sample = MotionSample(
                quaternion: simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w),
                rotationRate: SIMD3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z),
                userAcceleration: SIMD3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z)
            )
            self.onSample?(sample)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    var isActive: Bool { manager.isDeviceMotionActive }

    // MARK: CMHeadphoneMotionManagerDelegate

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        onConnect?()
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        onDisconnect?()
    }
}
