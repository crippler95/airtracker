<div align="center">

# 🐼 AirTracker

**Use your AirPods as a low-latency head tracker for games — natively on macOS.**

</div>

AirTracker is a tiny menu-bar app that reads your AirPods' head-orientation sensors
(via Apple's `CMHeadphoneMotionManager`) and streams it as the **OpenTrack UDP
protocol**, so it works with the hundreds of games that support TrackIR / FreeTrack
through [OpenTrack](https://github.com/opentrack/opentrack) — flight sims, racing sims,
truck sims, and more.

It's the AirPods counterpart to
[sony-head-tracker](https://github.com/NicholasSlattery/sony-head-tracker), reading the
sensors **directly on your Mac** (no iPhone in the loop) and matching its protocol.

> **Works with:** AirPods 4, AirPods 3, AirPods Pro (1st/2nd gen), AirPods Max, Beats Fit Pro —
> any headphones that support Apple's dynamic spatial-audio head tracking.
> **Requires:** macOS 14 or later.

## Features

- 🎧 Reads AirPods orientation directly on macOS (~25 Hz) — no drivers, no iPhone.
- 🎮 **OpenTrack UDP output** (port 4242), byte-for-byte compatible with sony-head-tracker.
- 📡 **JSON UDP** (port 4243) with full sony v2 parity (quaternion, Euler, gyro, accel, `angularVelocity`, `resetCounter`).
- 🌐 **Built-in web viewer** with a live 3D panda, an orientation graph, and every control.
- 🎯 **Recenter** and **pause** from the menu, the web viewer, or global hotkeys (⌃⌥C / ⌃⌥P).
- 🎛️ **Full axis calibration**: per-axis source remap, invert, and sensitivity scale.
- 🖥️ **Any target host** — stream to OpenTrack on this Mac *or* a Windows PC on your LAN.
- ⌨️ **CLI mode** — `probe`, `bridge`, `dump`, `diagnostics` for headless / scripted use.
- 💾 Config import/export, diagnostics export, launch-at-login, auto-reconnect.

## Install

**Download** the latest `AirTracker-vX.Y.Z-macos-universal.zip` from
[Releases](https://github.com/crippler95/airtracker/releases), unzip, and move
`AirTracker.app` to Applications. It's an ad-hoc-signed universal (Intel + Apple
Silicon) build, so the first time **right-click → Open** to get past Gatekeeper.

**Or build from source** (Xcode / Swift 6, macOS 14+):

```bash
git clone https://github.com/crippler95/airtracker.git
cd airtracker
make run
```

`make run` builds, assembles `AirTracker.app`, ad-hoc codesigns it, and launches it.
A signed `.app` is required so macOS shows the **Motion & Fitness** permission prompt —
`swift run` on the bare binary will not get the prompt.

On first launch, put your AirPods in and **grant the Motion & Fitness permission**.

## Use it with a game (via OpenTrack)

1. Install [OpenTrack](https://github.com/opentrack/opentrack) — on this Mac, or on the
   Windows PC where you play.
2. In OpenTrack, set **Input → UDP over network**, port **4242**, and press **Start**.
3. In AirTracker's menu, set the **OpenTrack target**: `127.0.0.1` for this Mac, or your
   PC's LAN IP address.
4. Put on your AirPods, look straight ahead, and press **Recenter** (⌃⌥C).
5. In OpenTrack, pick your **Output** (e.g. *freetrack 2.0 / TrackIR*) and launch your game.

Turn your head **left** → yaw goes positive; look **up** → pitch positive; tilt **right** → roll positive.
If any axis feels wrong or swapped, fix it live with the **Invert / Source / Scale**
controls (in the menu's *Advanced* section and in the web viewer).

## Test it without a game

Open the built-in viewer — a 3D panda that mirrors your movement, with a live graph:

```
http://localhost:4244
```

Or watch the raw streams:

```bash
make listen-4242   # opentrack packets: x,y,z,yaw,pitch,roll
make listen-json   # the JSON stream on 4243
```

## CLI

The same binary is a CLI when given a subcommand:

```bash
AirTracker probe          # check hardware + permission (exit 0 = ready)
AirTracker bridge         # stream headlessly (no GUI); --host, --port, --smoothing, --seconds…
AirTracker dump           # print raw motion samples
AirTracker diagnostics    # print a redacted JSON diagnostics bundle
```

## Troubleshooting

- **No data / 0 Hz** — AirPods only report motion while they're the active audio output.
  Play any audio; disable automatic device-switching so they don't hop to your iPhone.
- **No permission prompt** — System Settings → Privacy & Security → Motion & Fitness;
  `make reset-tcc` and relaunch. Ad-hoc signatures change identity per rebuild, so a
  rebuild can require re-granting.
- **Can't reach a PC on the LAN** — allow **Local Network** access under Privacy &
  Security; same network, no firewall blocking UDP 4242.

See [`docs/MACOS.md`](docs/MACOS.md) for more, and [`docs/PROTOCOL.md`](docs/PROTOCOL.md)
for the full wire format.

## How it works

```
CMHeadphoneMotionManager ─► recenter (qRef⁻¹·q) ─► slerp smoothing ─► axis remap/invert/scale ─► Euler
   (AirPods, ~25 Hz)                                                                               │
                                          ┌─────────────────────────────────────────────────────────┤
                                          ▼                     ▼                    ▼
                                  UDP 4242 (OpenTrack)   UDP 4243 (JSON)    WebSocket → web viewer
```

The platform-independent core (`AirTrackerCore`: quaternion math, orientation pipeline,
UDP/WebSocket/HTTP, CLI) is unit-tested and reused by both the GUI and the CLI. See
[`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE). Bundles [Three.js](https://threejs.org) (MIT).

Not affiliated with Apple. AirPods and TrackIR are trademarks of their respective owners.
