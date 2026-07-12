import Foundation
import SwiftUI
import CoreMotion
import os

let log = Logger(subsystem: "com.szilard.airtracker", category: "core")

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Persisted settings.
    @AppStorage("openTrackHost") var openTrackHost: String = "127.0.0.1" { didSet { applyEndpoints() } }
    @AppStorage("openTrackPort") var openTrackPort: Int = 4242 { didSet { applyEndpoints() } }
    @AppStorage("smoothing") var smoothing: Double = 0.18 { didSet { pipeline.setSmoothing(smoothing) } }
    @AppStorage("invertYaw") var invertYaw: Bool = false { didSet { applyInversion() } }
    @AppStorage("invertPitch") var invertPitch: Bool = false { didSet { applyInversion() } }
    @AppStorage("invertRoll") var invertRoll: Bool = false { didSet { applyInversion() } }

    // Fixed local ports.
    let jsonPort: UInt16 = 4243
    let httpPort: UInt16 = 4244
    let wsPort: UInt16 = 4245

    // Runtime status.
    @Published var airPodsConnected = false
    @Published var packetsPerSecond = 0
    @Published var motionDenied = false

    private let motion = HeadphoneMotionSource()
    private let pipeline = OrientationPipeline()
    private let openTrackSender: OpenTrackUDPSender
    private let jsonSender: JSONUDPSender
    private let http: HTTPServer
    private let ws: WebSocketServer
    private var hotkey: GlobalHotkey?

    private var lastUIUpdate: TimeInterval = 0
    private var started = false

    init() {
        openTrackSender = OpenTrackUDPSender(host: "127.0.0.1", port: 4242)
        jsonSender = JSONUDPSender(host: "127.0.0.1", port: jsonPort)
        http = HTTPServer(port: httpPort, wsPort: wsPort)
        ws = WebSocketServer(port: wsPort)
    }

    var motionAvailable: Bool { HeadphoneMotionSource.isAvailable }

    var webViewerURL: URL { URL(string: "http://localhost:\(httpPort)")! }

    func start() {
        guard !started else { return }
        started = true

        motion.onConnect = { [weak self] in
            log.info("AirPods connected")
            Task { @MainActor in self?.airPodsConnected = true }
        }
        motion.onDisconnect = { [weak self] in
            log.info("AirPods disconnected")
            Task { @MainActor in
                self?.airPodsConnected = false
                self?.packetsPerSecond = 0
            }
        }
        motion.onSample = { [weak self] sample in
            self?.pipeline.ingest(sample)
        }

        pipeline.onFrame = { [weak self] frame in
            guard let self else { return }
            self.openTrackSender.send(frame: frame)
            self.jsonSender.send(frame: frame)
            self.ws.broadcast(frame.jsonData())
            self.throttledUIUpdate(frame)
        }

        ws.onCommand = { [weak self] text in
            if text.contains("recenter") {
                self?.pipeline.recenter()
            }
        }

        pipeline.setSmoothing(smoothing)
        applyInversion()
        applyEndpoints()

        openTrackSender.start()
        jsonSender.start()
        http.start()
        ws.start()

        hotkey = GlobalHotkey { [weak self] in
            Task { @MainActor in self?.recenter() }
        }
        hotkey?.register()

        motion.start()

        updateAuthState()
        log.info("Started. motionAvailable=\(self.motionAvailable) auth=\(HeadphoneMotionSource.authorizationStatus.rawValue) http=\(self.httpPort) ws=\(self.wsPort) opentrack=\(self.openTrackHost):\(self.openTrackPort)")
    }

    func recenter() {
        pipeline.recenter()
    }

    func openWebViewer() {
        NSWorkspace.shared.open(webViewerURL)
    }

    func openMotionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Motion") {
            NSWorkspace.shared.open(url)
        }
    }

    private func applyEndpoints() {
        openTrackSender.updateEndpoint(host: openTrackHost, port: UInt16(openTrackPort))
    }

    private func applyInversion() {
        pipeline.setInversion(AxisInversion(yaw: invertYaw, pitch: invertPitch, roll: invertRoll))
    }

    private func updateAuthState() {
        let status = HeadphoneMotionSource.authorizationStatus
        motionDenied = (status == .denied || status == .restricted)
    }

    private func throttledUIUpdate(_ frame: TrackingFrame) {
        let now = Date().timeIntervalSince1970
        guard now - lastUIUpdate > 0.1 else { return }
        lastUIUpdate = now
        let pps = frame.packetsPerSecond
        Task { @MainActor in
            self.packetsPerSecond = pps
            self.updateAuthState()
        }
    }
}
