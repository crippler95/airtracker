# macOS Setup & Troubleshooting

AirTracker is a native macOS menu-bar app that reads AirPods head-orientation via `CMHeadphoneMotionManager` and streams it as a head tracker. This guide covers setup, permissions, and common issues.

## Requirements

- **macOS 14 or newer.**
- **AirPods that support spatial-audio head tracking:**
  - AirPods 4
  - AirPods 3rd generation
  - AirPods Pro (1st and 2nd generation)
  - AirPods Max
  - Beats Fit Pro

Devices without spatial-audio head tracking do not report motion and will not work.

## Motion & Fitness permission (TCC)

AirTracker needs the **Motion & Fitness** privacy permission to read headphone motion. This permission is tied to the app's code-signing identity, so it must be granted to the actual signed `.app`:

1. Launch the signed app — either `make run` (builds and runs the app bundle) or the downloaded release `.app`.
2. Accept the Motion & Fitness prompt when it appears.

If you never saw the prompt or previously denied it, grant it manually:

- **System Settings → Privacy & Security → Motion & Fitness**, then enable AirTracker.

To reset the permission state:

```sh
make reset-tcc
```

> **Note:** ad-hoc signatures change the app's identity on each rebuild. After rebuilding you may need to re-grant Motion & Fitness because macOS sees the new build as a different app.

## Local Network permission

If you stream to a PC on your LAN (for example, OpenTrack running on a gaming machine), macOS will ask for **Local Network** access. Grant it so the UDP datagrams can leave your Mac. You can manage it later under **System Settings → Privacy & Security → Local Network**.

## Troubleshooting

### No data / 0 Hz

AirPods only report motion while they are the **active audio output**:

- Play any audio so the AirPods become the active output device.
- Disable automatic device-switching so the AirPods do not hop to your iPhone or another device mid-session (on iPhone: **Settings → Bluetooth → your AirPods → Connect to This iPhone → When Last Connected to This iPhone**).

If AirTracker shows 0 Hz, the AirPods are almost certainly not the active output.

### Gatekeeper blocks the downloaded release

Release builds are unsigned / ad-hoc signed, so Gatekeeper may refuse to open them on first launch. To open anyway:

- **Right-click the app → Open**, then confirm.

This only needs to be done once per build.

### Axis calibration

Use the per-axis **Source / Invert / Scale** controls (available both in the menu-bar menu and in the web viewer) to make the on-screen head match your real head movements:

- **Source** — which input axis drives each output axis (axis-order remapping).
- **Invert** — flip an axis direction.
- **Scale** — adjust sensitivity per axis.

Recenter the orientation at any time with the **Recenter** button or the **⌃⌥C** hotkey.
