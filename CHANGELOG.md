# Changelog

All notable changes to AirTracker are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] — 2026-07-14

### Added

- Yaw drift compensation: an adjustable rate (deg/s) that continuously pulls yaw back to
  center, absorbing the slow sensor drift AirPods accumulate over a session. Off by default.
- Deadzone (degrees): ignores tiny head motion around center, subtractively so there is no
  jump at the edge.
- Expo response curve: softens small motions while leaving 90° turns unchanged (0 = linear,
  1 = quadratic near center).
- Recenter automatically when AirPods (re)connect, so a stale reference never survives
  taking the AirPods off. On by default; can be disabled under Advanced.
- All of the above in the menu bar, the web viewer (live mirrored sliders), and the CLI
  (`bridge --deadzone --expo --drift`).
- Settings and exported configs from older versions load unchanged (new fields default off).

### Fixed

- Menu bar panel would not open on click under newer macOS: replaced the `MenuBarExtra(.window)`
  scene with an `NSStatusItem` + `NSPopover` host for the same SwiftUI view.

## [1.1.0] — 2026-07-13

### Added

- CLI mode with `probe`, `bridge`, `dump`, `diagnostics`, `version`, and `help` subcommands.
- Axis-order remapping with per-axis source, invert, and scale.
- Full JSON parity: `angularVelocity`, `resetCounter`, and smoothed gyroscope / accelerometer fields.
- Config import / export.
- Diagnostics export.
- Auto-reconnect watchdog.
- Richer menu UI showing packet age and an advanced section, plus a live orientation graph in the web viewer.
- Pause / resume with a hotkey.
- Launch at login.
- Panda app icon.
- Unit tests and GitHub Actions CI.
- Universal (arm64 + x86_64) downloadable release.

## [1.0.0] — 2026-07-12

### Added

- Initial release.
- AirPods head tracking via `CMHeadphoneMotionManager`.
- OpenTrack UDP output (port 4242) and JSON UDP output (port 4243).
- Menu-bar app.
- Three.js web viewer.
- Recenter hotkey.
- Smoothing.
- Per-axis inversion.
