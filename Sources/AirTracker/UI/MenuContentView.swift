import SwiftUI
import AirTrackerCore

struct MenuContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                statusRows
                Divider()
                targetSection
                smoothingSection
                calibrationSection
                Divider()
                advancedDisclosure
                Divider()
                actions
            }
            .padding(14)
        }
        .frame(width: 320)
        .frame(maxHeight: 640)
    }

    private var header: some View {
        HStack {
            Image(systemName: "airpods")
            Text("AirTracker").font(.headline)
            Spacer()
            Text("v\(CLI.version)").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusRows: some View {
        if !state.motionAvailable {
            labelRow("Headphone motion unavailable on this Mac", color: .red, symbol: "xmark.circle.fill")
        } else if state.motionDenied {
            VStack(alignment: .leading, spacing: 6) {
                labelRow("Motion permission denied", color: .red, symbol: "xmark.circle.fill")
                Button("Open Motion settings…") { state.openMotionSettings() }.font(.caption)
            }
        } else {
            HStack {
                Circle().fill(statusColor).frame(width: 9, height: 9)
                Text(statusText)
                Spacer()
                if state.airPodsConnected {
                    Text("\(state.packetsPerSecond) Hz").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Backend").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(state.backendName).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Last sample").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(sampleAgeText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var statusColor: Color {
        if state.paused { return .orange }
        return state.airPodsConnected ? .green : .gray
    }
    private var statusText: String {
        if state.paused { return "Paused" }
        return state.airPodsConnected ? "AirPods connected" : "Waiting for AirPods…"
    }
    private var sampleAgeText: String {
        guard state.airPodsConnected else { return "—" }
        let a = state.secondsSinceSample
        return a < 1 ? "just now" : String(format: "%.0fs ago", a)
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OpenTrack target").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Host", text: $state.settings.openTrackHost).textFieldStyle(.roundedBorder)
                TextField("Port", value: $state.settings.openTrackPort, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 64)
            }
            Text("127.0.0.1 for OpenTrack on this Mac, or your PC's LAN IP.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var smoothingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Smoothing").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", state.settings.smoothing)).font(.caption).foregroundStyle(.secondary)
            }
            Slider(value: $state.settings.smoothing, in: 0...0.9)
        }
    }

    private var calibrationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Invert").font(.caption).foregroundStyle(.secondary)
                Toggle("Yaw", isOn: $state.settings.axis.invertYaw)
                Toggle("Pitch", isOn: $state.settings.axis.invertPitch)
                Toggle("Roll", isOn: $state.settings.axis.invertRoll)
            }
            .toggleStyle(.checkbox).font(.caption)
        }
    }

    private var advancedDisclosure: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 10) {
                axisRow("Yaw", source: $state.settings.axis.yawSource, scale: $state.settings.axis.scaleYaw)
                axisRow("Pitch", source: $state.settings.axis.pitchSource, scale: $state.settings.axis.scalePitch)
                axisRow("Roll", source: $state.settings.axis.rollSource, scale: $state.settings.axis.scaleRoll)
                Button("Reset calibration") { state.resetCalibration() }.font(.caption)

                Divider()
                Toggle("Launch at login", isOn: $state.launchAtLogin).font(.caption)
                HStack {
                    Button("Import…") { state.importConfig() }
                    Button("Export…") { state.exportConfig() }
                    Button("Diagnostics…") { state.exportDiagnostics() }
                }.font(.caption)
            }
            .padding(.top, 6)
        } label: {
            Text("Advanced").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func axisRow(_ name: String, source: Binding<SourceAxis>, scale: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(name).font(.caption).frame(width: 40, alignment: .leading)
            Picker("", selection: source) {
                ForEach(SourceAxis.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .labelsHidden().frame(width: 92)
            Text(String(format: "×%.1f", scale.wrappedValue)).font(.caption2).foregroundStyle(.secondary).frame(width: 34)
            Slider(value: scale, in: 0.2...3.0)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { state.recenter() } label: {
                    Label("Recenter (⌃⌥C)", systemImage: "scope").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                Button { state.togglePause() } label: {
                    Image(systemName: state.paused ? "play.fill" : "pause.fill")
                }
                .controlSize(.large)
                .help(state.paused ? "Resume (⌃⌥P)" : "Pause (⌃⌥P)")
            }
            HStack {
                Button("Open Web Viewer") { state.openWebViewer() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .font(.caption)
        }
    }

    private func labelRow(_ text: String, color: Color, symbol: String) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text)
        }
    }
}
