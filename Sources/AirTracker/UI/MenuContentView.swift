import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            statusRows

            Divider()

            targetSection

            Divider()

            smoothingSection

            invertSection

            Divider()

            actions
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack {
            Image(systemName: "airpods")
            Text("AirTracker").font(.headline)
            Spacer()
            Text("v1.0").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusRows: some View {
        if !state.motionAvailable {
            label("Headphone motion unavailable on this Mac", color: .red, symbol: "xmark.circle.fill")
        } else if state.motionDenied {
            VStack(alignment: .leading, spacing: 6) {
                label("Motion permission denied", color: .red, symbol: "xmark.circle.fill")
                Button("Open Motion settings…") { state.openMotionSettings() }
                    .font(.caption)
            }
        } else {
            HStack {
                Circle().fill(state.airPodsConnected ? .green : .gray).frame(width: 9, height: 9)
                Text(state.airPodsConnected ? "AirPods connected" : "Waiting for AirPods…")
                Spacer()
                if state.airPodsConnected {
                    Text("\(state.packetsPerSecond) Hz").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OpenTrack target").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Host", text: $state.openTrackHost)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", value: $state.openTrackPort, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
            }
            Text("Use 127.0.0.1 for OpenTrack on this Mac, or your PC's LAN IP.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var smoothingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Smoothing").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", state.smoothing)).font(.caption).foregroundStyle(.secondary)
            }
            Slider(value: $state.smoothing, in: 0...0.9)
        }
    }

    private var invertSection: some View {
        HStack(spacing: 12) {
            Text("Invert").font(.caption).foregroundStyle(.secondary)
            Toggle("Yaw", isOn: $state.invertYaw)
            Toggle("Pitch", isOn: $state.invertPitch)
            Toggle("Roll", isOn: $state.invertRoll)
        }
        .toggleStyle(.checkbox)
        .font(.caption)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                state.recenter()
            } label: {
                Label("Recenter (⌃⌥C)", systemImage: "scope").frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            HStack {
                Button("Open Web Viewer") { state.openWebViewer() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .font(.caption)
        }
    }

    private func label(_ text: String, color: Color, symbol: String) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text)
        }
    }
}
