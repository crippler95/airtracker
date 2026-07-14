import SwiftUI
import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var symbolObserver: AnyCancellable?
    private var lastSymbol = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
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

struct AirTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
