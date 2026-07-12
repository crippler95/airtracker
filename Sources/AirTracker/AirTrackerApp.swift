import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.start()
    }
}

@main
struct AirTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("AirTracker", systemImage: "airpods") {
            MenuContentView()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)
    }
}
