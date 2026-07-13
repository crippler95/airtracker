import Foundation
import CoreMotion

/// Headless command-line interface. The executable dispatches here when launched with a
/// recognized subcommand; otherwise it starts the menu-bar GUI. Reuses the same core.
public enum CLI {
    public static let version = "1.1.0"

    private static let commands: Set<String> = [
        "probe", "bridge", "dump", "diagnostics", "version", "--version", "-v", "help", "--help", "-h",
    ]

    public static func isCommand(_ arg: String) -> Bool { commands.contains(arg) }

    public static func run(_ args: [String]) -> Int32 {
        guard let cmd = args.first else { return usage() }
        let rest = Array(args.dropFirst())
        switch cmd {
        case "probe": return probe()
        case "bridge": return bridge(rest)
        case "dump": return dump(rest)
        case "diagnostics": return diagnostics()
        case "version", "--version", "-v": print("AirTracker \(version)"); return 0
        default: return usage()
        }
    }

    // MARK: Commands

    private static func probe() -> Int32 {
        let available = HeadphoneMotionSource.isAvailable
        let status = HeadphoneMotionSource.authorizationStatus
        print("AirTracker \(version) — probe")
        print("  headphone motion available: \(available ? "yes" : "no")")
        print("  authorization: \(authName(status))")
        if !available {
            print("  → This Mac cannot read headphone motion (needs macOS 14+ and supported hardware).")
            return 2
        }
        switch status {
        case .authorized:
            print("  → Ready. Run `AirTracker bridge` or launch the app.")
            return 0
        case .notDetermined:
            print("  → Permission not requested yet. Launch AirTracker.app once and grant Motion & Fitness.")
            return 2
        default:
            print("  → Permission denied. System Settings → Privacy & Security → Motion & Fitness.")
            return 2
        }
    }

    private static func bridge(_ args: [String]) -> Int32 {
        var settings = SettingsStore.load()
        let opts = parse(args)
        if let h = opts["host"] { settings.openTrackHost = h }
        if let p = opts["port"].flatMap({ Int($0) }) { settings.openTrackPort = p }
        if let s = opts["smoothing"].flatMap({ Double($0) }) { settings.smoothing = s }
        let jsonPort = UInt16(opts["json-port"].flatMap { Int($0) } ?? 4243)
        let noJSON = args.contains("--no-json")
        let seconds = opts["seconds"].flatMap { Double($0) }

        if HeadphoneMotionSource.authorizationStatus != .authorized {
            FileHandle.standardError.write(Data("warning: Motion not authorized — launch AirTracker.app once to grant it.\n".utf8))
        }

        let motion = HeadphoneMotionSource()
        let pipeline = OrientationPipeline()
        let opentrack = OpenTrackUDPSender(host: settings.openTrackHost, port: UInt16(settings.openTrackPort))
        let json = JSONUDPSender(host: "127.0.0.1", port: jsonPort)
        pipeline.setSmoothing(settings.smoothing)
        pipeline.setAxisConfig(settings.axis)

        FileHandle.standardError.write(Data("AirTracker \(version) bridge → opentrack \(settings.openTrackHost):\(settings.openTrackPort)\(noJSON ? "" : ", json 127.0.0.1:\(jsonPort)")\n".utf8))

        pipeline.onFrame = { frame in
            opentrack.send(frame: frame)
            if !noJSON { json.send(frame: frame) }
        }
        motion.onSample = { pipeline.ingest($0) }
        opentrack.start(); if !noJSON { json.start() }
        motion.start()

        runUntil(seconds: seconds, tick: nil)
        return 0
    }

    private static func dump(_ args: [String]) -> Int32 {
        let opts = parse(args)
        let seconds = opts["seconds"].flatMap { Double($0) }
        let motion = HeadphoneMotionSource()
        motion.onSample = { s in
            let q = s.quaternion
            print(String(format: "q=[% .4f % .4f % .4f % .4f] gyro=[% .3f % .3f % .3f] accel=[% .3f % .3f % .3f]",
                         q.real, q.imag.x, q.imag.y, q.imag.z,
                         s.rotationRate.x, s.rotationRate.y, s.rotationRate.z,
                         s.userAcceleration.x, s.userAcceleration.y, s.userAcceleration.z))
        }
        motion.start()
        runUntil(seconds: seconds, tick: nil)
        return 0
    }

    private static func diagnostics() -> Int32 {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let bundle: [String: Any] = [
            "app": "AirTracker",
            "version": version,
            "os": "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "arch": machineArch(),
            "motionAvailable": HeadphoneMotionSource.isAvailable,
            "authorization": authName(HeadphoneMotionSource.authorizationStatus),
            "settings": (try? JSONSerialization.jsonObject(with: SettingsStore.encode(SettingsStore.load()))) ?? [:],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: bundle, options: [.prettyPrinted, .sortedKeys]) {
            print(String(data: data, encoding: .utf8) ?? "{}")
        }
        return 0
    }

    // MARK: Helpers

    private static func usage() -> Int32 {
        print("""
        AirTracker \(version) — use your AirPods as a head tracker

        USAGE:
          AirTracker                 Launch the menu-bar app
          AirTracker probe           Check hardware & permission (exit 0 = ready)
          AirTracker bridge [opts]   Stream head tracking without the GUI
          AirTracker dump [opts]     Print raw motion samples
          AirTracker diagnostics     Print a redacted diagnostics bundle (JSON)
          AirTracker version
          AirTracker help

        BRIDGE OPTIONS:
          --host <ip>        OpenTrack target host (default from settings / 127.0.0.1)
          --port <n>         OpenTrack UDP port (default 4242)
          --json-port <n>    JSON UDP port (default 4243)
          --no-json          Disable the JSON stream
          --smoothing <0-0.9>
          --seconds <n>      Run for n seconds then exit (default: until Ctrl-C)
        """)
        return 0
    }

    private static func parse(_ args: [String]) -> [String: String] {
        var out: [String: String] = [:]
        var i = 0
        while i < args.count {
            let a = args[i]
            if a.hasPrefix("--"), !a.hasSuffix("json") {
                let key = String(a.dropFirst(2))
                if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                    out[key] = args[i + 1]; i += 2; continue
                }
            }
            i += 1
        }
        return out
    }

    private static func authName(_ s: CMAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    private static func machineArch() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafeBytes(of: &sysinfo.machine) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }

    /// Keep the process alive for CoreMotion callbacks; exit after `seconds` or on SIGINT.
    private static func runUntil(seconds: Double?, tick: (() -> Void)? = nil) {
        signal(SIGINT) { _ in exit(0) }
        signal(SIGTERM) { _ in exit(0) }
        if let seconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
        }
        if let tick {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler(handler: tick)
            timer.resume()
        }
        dispatchMain()
    }
}
