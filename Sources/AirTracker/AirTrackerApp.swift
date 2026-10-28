import SwiftUI
import AppKit
import Combine
import AirTrackerCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public static var shared: AppDelegate?
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var symbolObserver: AnyCancellable?
    private var lastSymbol = ""
    private var settingsWindow: NSWindow?
    private var settingsHostingController: NSHostingController<AnyView>?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        let state = AppState.shared
        state.start()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView().environmentObject(state)
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.target = self
        applySymbol(state.menuBarSymbol)

        symbolObserver = state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.applySymbol(state.menuBarSymbol) }
            }

        // Add Settings menu item for Cmd+, support
        setupSettingsMenuItem()
    }

    private func setupSettingsMenuItem() {
        guard let mainMenu = NSApp.mainMenu,
              let appMenu = mainMenu.items.first?.submenu else { return }

        // Find or create the Settings menu item
        if let existingSettingsItem = appMenu.items.first(where: { $0.action == #selector(showSettingsWindow(_:)) }) {
            // Already exists
        } else {
            let settingsItem = NSMenuItem(
                title: "Settings…",
                action: #selector(showSettingsWindow(_:)),
                keyEquivalent: ","
            )
            settingsItem.target = self
            settingsItem.keyEquivalentModifierMask = [.command]
            // Insert before the "Services" menu item or at the end of the section
            if let servicesIndex = appMenu.items.firstIndex(where: { $0.title == "Services" }) {
                appMenu.insertItem(settingsItem, at: servicesIndex)
            } else {
                appMenu.addItem(settingsItem)
            }
        }
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        if settingsWindow == nil {
            let state = AppState.shared
            let settingsView = AnyView(SettingsView().environmentObject(state))
            settingsHostingController = NSHostingController(rootView: settingsView)

            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "AirTracker Settings"
            settingsWindow?.contentViewController = settingsHostingController
            settingsWindow?.center()
            settingsWindow?.isReleasedWhenClosed = false
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applySymbol(_ name: String) {
        guard name != lastSymbol, let button = statusItem?.button else { return }
        lastSymbol = name
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "AirTracker")
        image?.isTemplate = true
        button.image = image
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// Settings window view - used for the custom settings window
struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Connection") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenTrack target").font(.headline)
                    HStack {
                        TextField("Host", text: $state.settings.openTrackHost)
                            .textFieldStyle(.roundedBorder)
                        TextField("Port", value: $state.settings.openTrackPort, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    Text("Use 127.0.0.1 for OpenTrack on this Mac, or your PC's LAN IP.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Smoothing & Filtering") {
                sliderRow("Smoothing", value: $state.settings.smoothing, range: 0...0.9, format: "%.2f")
                sliderRow("Deadzone", value: $state.settings.axis.deadzone, range: 0...10, format: "%.1f°")
                sliderRow("Expo curve", value: $state.settings.axis.expo, range: 0...1, format: "%.2f")
                sliderRow("Drift compensation", value: $state.settings.driftCompensation, range: 0...5, format: "%.1f°/s")
            }

            Section("Axis inversion") {
                HStack {
                    Text("Invert").font(.caption).foregroundStyle(.secondary)
                    Toggle("Yaw", isOn: $state.settings.axis.invertYaw)
                    Toggle("Pitch", isOn: $state.settings.axis.invertPitch)
                    Toggle("Roll", isOn: $state.settings.axis.invertRoll)
                }
                .toggleStyle(.checkbox)
            }

            Section("Advanced axis mapping") {
                axisRow("Yaw", source: $state.settings.axis.yawSource, scale: $state.settings.axis.scaleYaw)
                axisRow("Pitch", source: $state.settings.axis.pitchSource, scale: $state.settings.axis.scalePitch)
                axisRow("Roll", source: $state.settings.axis.rollSource, scale: $state.settings.axis.scaleRoll)
            }

            Section("Behavior") {
                Toggle("Recenter when AirPods connect", isOn: $state.settings.recenterOnConnect)
                Toggle("Launch at login", isOn: $state.launchAtLogin)
            }

            Section("Actions") {
                Button("Recenter now (⌃⌥C)") { state.recenter() }
                Button(state.paused ? "Resume (⌃⌥P)" : "Pause (⌃⌥P)") { state.togglePause() }
                Button("Open Web Viewer") { state.openWebViewer() }
            }

            Section("Data") {
                HStack {
                    Button("Import config…") { state.importConfig() }
                    Button("Export config…") { state.exportConfig() }
                    Button("Export diagnostics…") { state.exportDiagnostics() }
                }
                Button("Reset calibration") { state.resetCalibration() }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 480, minHeight: 500)
    }

    private func sliderRow(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func axisRow(_ name: String, source: Binding<SourceAxis>, scale: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Text(name).frame(width: 50, alignment: .leading)
            Picker("", selection: source) {
                ForEach(SourceAxis.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .labelsHidden().frame(width: 110)
            Text(String(format: "×%.1f", scale.wrappedValue))
                .font(.caption).foregroundStyle(.secondary).frame(width: 38)
            Slider(value: scale, in: 0.2...3.0)
        }
    }
}

struct AirTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Minimal scene - AppDelegate manages the menu bar and settings window
        // WindowGroup with a hidden view prevents any window from appearing at startup
        WindowGroup {
            EmptyView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 0, height: 0)
    }
}
