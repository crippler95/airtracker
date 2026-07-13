import Foundation
import SwiftUI
import CoreMotion
import os

let log = Logger(subsystem: "com.szilard.airtracker", category: "core")

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Persisted settings. Plain @Published (not @AppStorage) so didSet fires on binding
    // writes from the menu — @AppStorage's setter bypasses didSet, which silently dropped
    // every settings change. Persistence is handled manually in each didSet.
    @Published var openTrackHost: String { didSet { defaults.set(openTrackHost, forKey: "openTrackHost"); applyEndpoints() } }
    @Published var openTrackPort: Int { didSet { defaults.set(openTrackPort, forKey: "openTrackPort"); applyEndpoints() } }
    @Published var smoothing: Double { didSet { defaults.set(smoothing, forKey: "smoothing"); pipeline.setSmoothing(smoothing) } }
    @Published var invertYaw: Bool { didSet { defaults.set(invertYaw, forKey: "invertYaw"); applyInversion() } }
    @Published var invertPitch: Bool { didSet { defaults.set(invertPitch, forKey: "invertPitch"); applyInversion() } }
    @Published var invertRoll: Bool { didSet { defaults.set(invertRoll, forKey: "invertRoll"); applyInversion() } }

    private let defaults = UserDefaults.standard

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
        let d = UserDefaults.standard
        // Defaults reflect the AirPods body frame: pitch reads inverted vs opentrack's
        // "up = positive", so invertPitch defaults on. The user can flip any axis live.
        d.register(defaults: ["openTrackHost": "127.0.0.1", "openTrackPort": 4242,
                              "smoothing": 0.18, "invertYaw": false,
                              "invertPitch": true, "invertRoll": false])
        let host = d.string(forKey: "openTrackHost") ?? "127.0.0.1"
        let port = d.integer(forKey: "openTrackPort")

        // Create sinks first so the settings' didSet observers have valid targets.
        openTrackSender = OpenTrackUDPSender(host: host, port: UInt16(port))
        jsonSender = JSONUDPSender(host: "127.0.0.1", port: jsonPort)
        http = HTTPServer(port: httpPort, wsPort: wsPort)
        ws = WebSocketServer(port: wsPort)

        openTrackHost = host
        openTrackPort = port
        smoothing = d.double(forKey: "smoothing")
        invertYaw = d.bool(forKey: "invertYaw")
        invertPitch = d.bool(forKey: "invertPitch")
        invertRoll = d.bool(forKey: "invertRoll")
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
            self.ws.broadcast(frame.webViewerData())
            self.throttledUIUpdate(frame)
        }

        ws.onCommand = { [weak self] text in
            guard let self,
                  let data = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cmd = obj["cmd"] as? String else { return }
            Task { @MainActor in self.handleCommand(cmd, obj) }
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
        log.info("Started. motionAvailable=\(self.motionAvailable) auth=\(HeadphoneMotionSource.authorizationStatus.rawValue) invert(y/p/r)=\(self.invertYaw)/\(self.invertPitch)/\(self.invertRoll) smoothing=\(self.smoothing) opentrack=\(self.openTrackHost):\(self.openTrackPort)")
    }

    func recenter() {
        pipeline.recenter()
    }

    /// Commands from the web viewer. Writing the @Published settings persists them and
    /// applies them via didSet, and keeps the menu UI in sync automatically.
    private func handleCommand(_ cmd: String, _ obj: [String: Any]) {
        switch cmd {
        case "recenter":
            recenter()
        case "setSmoothing":
            if let v = obj["value"] as? Double { smoothing = min(0.9, max(0, v)) }
        case "setInvert":
            guard let axis = obj["axis"] as? String, let v = obj["value"] as? Bool else { return }
            switch axis {
            case "yaw": invertYaw = v
            case "pitch": invertPitch = v
            case "roll": invertRoll = v
            default: break
            }
        default:
            break
        }
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
