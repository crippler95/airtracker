import Foundation
import AirTrackerCore

// A recognized subcommand runs headless and exits; otherwise launch the menu-bar GUI.
let arguments = Array(CommandLine.arguments.dropFirst())
if let first = arguments.first, CLI.isCommand(first) {
    exit(CLI.run(arguments))
} else {
    AirTrackerApp.main()
}
