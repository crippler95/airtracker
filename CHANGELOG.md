# Changelog

All notable changes to AirTracker are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
