import Foundation
import SwiftUI
import CoreMotion
import ServiceManagement
import AppKit
import Carbon.HIToolbox
import os
import AirTrackerCore

let log = Logger(subsystem: "com.szilard.airtracker", category: "core")

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// Single source of truth for user config; persisted and applied on every change.
    @Published var settings: TrackerSettings { didSet { onSettingsChanged() } }

    // Fixed local ports.
    let jsonPort: UInt16 = 4243
    let httpPort: UInt16 = 4244
    let wsPort: UInt16 = 4245

    // Runtime status.
    @Published var airPodsConnected = false
    @Published var packetsPerSecond = 0
    @Published var motionDenied = false
    @Published var paused = false { didSet { pausedUnsafe = paused } }
    @Published var secondsSinceSample = 0.0
    @Published var launchAtLogin = false { didSet { applyLaunchAtLogin() } }

    private let motion = HeadphoneMotionSource()
    private let pipeline = OrientationPipeline()
    private let openTrackSender: OpenTrackUDPSender
    private let jsonSender: JSONUDPSender
    private let http: HTTPServer
    private let ws: WebSocketServer
    private var recenterHotkey: GlobalHotkey?
    private var pauseHotkey: GlobalHotkey?
    private var watchdog: Timer?
    private var uiTimer: Timer?

    private var lastUIUpdate: TimeInterval = 0
    private var started = false

    init() {
        let loaded = SettingsStore.load()
        settings = loaded
        openTrackSender = OpenTrackUDPSender(host: loaded.openTrackHost, port: UInt16(loaded.openTrackPort))
        jsonSender = JSONUDPSender(host: "127.0.0.1", port: 4243)
        http = HTTPServer(port: 4244, wsPort: 4245)
        ws = WebSocketServer(port: 4245)
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    var motionAvailable: Bool { HeadphoneMotionSource.isAvailable }
    var webViewerURL: URL { URL(string: "http://localhost:\(httpPort)")! }
    var backendName: String { "CoreMotion" }

    var menuBarSymbol: String {
        if paused { return "pause.circle" }
        return airPodsConnected ? "airpods" : "airpods.gen3"
    }

    func start() {
        guard !started else { return }
        started = true

        motion.onConnect = { [weak self] in
            log.info("AirPods connected")
            Task { @MainActor in
                guard let self else { return }
                self.airPodsConnected = true
                if self.settings.recenterOnConnect { self.recenter() }
            }
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
            if !self.pausedUnsafe {
                self.openTrackSender.send(frame: frame)
                self.jsonSender.send(frame: frame)
            }
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

        applySettings()
        openTrackSender.start()
        jsonSender.start()
        http.start()
        ws.start()

        recenterHotkey = GlobalHotkey { [weak self] in
            Task { @MainActor in self?.recenter() }
        }
        recenterHotkey?.register()
        pauseHotkey = GlobalHotkey(keyCode: UInt32(kVK_ANSI_P)) { [weak self] in
            Task { @MainActor in self?.togglePause() }
        }
        pauseHotkey?.register()

        motion.start()
        startTimers()
        updateAuthState()
        log.info("Started. available=\(self.motionAvailable) auth=\(HeadphoneMotionSource.authorizationStatus.rawValue) opentrack=\(self.settings.openTrackHost):\(self.settings.openTrackPort)")
    }

    // MARK: Actions

    func recenter() { pipeline.recenter() }

    func togglePause() { paused.toggle() }

    func openWebViewer() { NSWorkspace.shared.open(webViewerURL) }

    func openMotionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Motion") {
            NSWorkspace.shared.open(url)
        }
    }

    func resetCalibration() {
        settings.axis = AxisConfig()
        recenter()
    }

    func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "airtracker-config.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? SettingsStore.encode(settings).write(to: url)
    }

    func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let loaded = SettingsStore.decode(data) else { return }
        settings = loaded
    }

    func exportDiagnostics() {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let bundle: [String: Any] = [
            "app": "AirTracker", "version": CLI.version,
            "os": "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "motionAvailable": motionAvailable,
            "authorization": HeadphoneMotionSource.authorizationStatus.rawValue,
            "airPodsConnected": airPodsConnected,
            "packetsPerSecond": packetsPerSecond,
            "settings": (try? JSONSerialization.jsonObject(with: SettingsStore.encode(settings))) ?? [:],
        ]
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "airtracker-diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? JSONSerialization.data(withJSONObject: bundle, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url)
    }

    // MARK: Web-viewer commands

    private func handleCommand(_ cmd: String, _ obj: [String: Any]) {
        switch cmd {
        case "recenter": recenter()
        case "pause": togglePause()
        case "setSmoothing":
            if let v = obj["value"] as? Double { settings.smoothing = min(0.9, max(0, v)) }
        case "setInvert":
            guard let axis = obj["axis"] as? String, let v = obj["value"] as? Bool else { return }
            switch axis {
            case "yaw": settings.axis.invertYaw = v
            case "pitch": settings.axis.invertPitch = v
            case "roll": settings.axis.invertRoll = v
            default: break
            }
        case "setSource":
            guard let axis = obj["axis"] as? String, let src = (obj["value"] as? String).flatMap(SourceAxis.init) else { return }
            switch axis {
            case "yaw": settings.axis.yawSource = src
            case "pitch": settings.axis.pitchSource = src
            case "roll": settings.axis.rollSource = src
            default: break
            }
        case "setScale":
            guard let axis = obj["axis"] as? String, let v = obj["value"] as? Double else { return }
            switch axis {
            case "yaw": settings.axis.scaleYaw = v
            case "pitch": settings.axis.scalePitch = v
            case "roll": settings.axis.scaleRoll = v
            default: break
            }
        case "setDeadzone":
            if let v = obj["value"] as? Double { settings.axis.deadzone = min(10, max(0, v)) }
        case "setExpo":
            if let v = obj["value"] as? Double { settings.axis.expo = min(1, max(0, v)) }
        case "setDrift":
            if let v = obj["value"] as? Double { settings.driftCompensation = min(10, max(0, v)) }
        default: break
        }
    }

    // MARK: Internals

    /// Read from the pipeline callback thread; a stale read only skips/sends one frame.
    private var pausedUnsafe = false

    private func onSettingsChanged() {
        SettingsStore.save(settings)
        applySettings()
    }

    private func applySettings() {
        openTrackSender.updateEndpoint(host: settings.openTrackHost, port: UInt16(settings.openTrackPort))
        pipeline.setSmoothing(settings.smoothing)
        pipeline.setAxisConfig(settings.axis)
        pipeline.setDriftCompensation(settings.driftCompensation)
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            log.error("launch-at-login failed: \(error.localizedDescription)")
        }
    }

    private func startTimers() {
        // Reconnect watchdog: if updates should be flowing but samples stalled, restart them.
        watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkWatchdog() }
        }
        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateSampleAge() }
        }
    }

    private func checkWatchdog() {
        guard motion.isActive, motion.lastSampleTime > 0 else { return }
        let age = Date().timeIntervalSince1970 - motion.lastSampleTime
        if age > 5 {
            log.info("watchdog: samples stalled \(String(format: "%.1f", age))s, restarting motion updates")
            motion.restart()
        }
    }

    private func updateSampleAge() {
        guard motion.lastSampleTime > 0 else { secondsSinceSample = 0; return }
        secondsSinceSample = Date().timeIntervalSince1970 - motion.lastSampleTime
        if secondsSinceSample > 1.5 { packetsPerSecond = 0 }
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
