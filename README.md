# AirTracker

Use your **AirPods** as a low-latency head tracker for games — on **macOS**, natively.

AirTracker is a tiny menu-bar app that reads your AirPods' head-orientation sensors
(via Apple's `CMHeadphoneMotionManager`) and streams it as the **OpenTrack UDP
protocol**, so it works with the hundreds of games that support TrackIR / FreeTrack
through [OpenTrack](https://github.com/opentrack/opentrack) — flight sims, racing sims,
truck sims, and more.

It's the AirPods counterpart to
[sony-head-tracker](https://github.com/NicholasSlattery/sony-head-tracker), reading the
sensors **directly on your Mac** (no iPhone in the loop) and matching its wire format.

> **Works with:** AirPods 4, AirPods 3, AirPods Pro (1st/2nd gen), AirPods Max, Beats Fit Pro —
> any headphones that support Apple's dynamic spatial-audio head tracking.
> **Requires:** macOS 14 or later.

## Features

- 🎧 Reads AirPods orientation directly on macOS (~25 Hz).
- 🎮 **OpenTrack UDP output** on port `4242` — six little-endian `Float64`
  (`x, y, z, yaw, pitch, roll`), identical to sony-head-tracker.
- 📡 **JSON UDP** on port `4243` (quaternion, Euler, gyro, accel) for custom integrations.
- 🌐 **Built-in web viewer** with a live 3D head (Three.js) at `http://localhost:4244`.
- 🎯 **Recenter** from the menu, the web viewer, or a global hotkey (**⌃⌥C**).
- 🎚️ Adjustable smoothing and per-axis inversion.
- 🖥️ Configurable target host — stream to OpenTrack on this Mac *or* a Windows PC on your LAN.

## Build & run

Requires Xcode (Swift 6) on Apple Silicon or Intel macOS 14+.

```bash
git clone https://github.com/<your-user>/airtracker.git
cd airtracker
make run
```

`make run` builds a release binary, assembles `AirTracker.app`, ad-hoc codesigns it, and
launches it. A signed `.app` bundle is required so macOS shows the **Motion & Fitness**
permission prompt — `swift run` on the bare binary will *not* get the prompt.

The app lives in the menu bar (🎧 icon). On first launch, put your AirPods in and
**grant the Motion & Fitness permission** when prompted.

## Use it with a game (via OpenTrack)

1. Install [OpenTrack](https://github.com/opentrack/opentrack) — on this Mac, or on the
   Windows PC where you play.
2. In OpenTrack, set **Input → UDP over network**, port **4242**, and press **Start**.
3. In AirTracker's menu, set the **OpenTrack target**:
   - `127.0.0.1` if OpenTrack runs on this same Mac, or
   - your PC's LAN IP address if OpenTrack runs on your Windows gaming PC.
4. Put on your AirPods, look straight ahead, and press **Recenter** (or **⌃⌥C**).
5. In OpenTrack, pick your **Output** (e.g. *freetrack 2.0 / TrackIR*) and launch your game.

## Test it without a game

Open the built-in viewer — a 3D head that mirrors your movement:

```
http://localhost:4244
```

Or watch the raw OpenTrack packets:

```bash
make listen-4242   # prints x,y,z,yaw,pitch,roll from each packet
make listen-json   # prints the JSON stream on 4243
```

Turn your head **left** → yaw goes positive. Look **up** → pitch positive. Tilt **right** → roll positive.

## Troubleshooting

- **No data / rate stays at 0 Hz.** AirPods only report motion while they're the active
  audio output. Play any audio on the Mac. Also disable automatic device switching so they
  don't hop to your iPhone.
- **No permission prompt.** Open **System Settings → Privacy & Security → Motion & Fitness**
  and enable AirTracker. If it's missing, run `make reset-tcc` and relaunch. Ad-hoc
  signatures change identity on every rebuild, so a rebuild can require re-granting.
- **Can't reach a PC on the LAN.** macOS may prompt for **Local Network** access; allow it
  under **Privacy & Security → Local Network**. Make sure both machines are on the same
  network and no firewall blocks UDP 4242.
- **Axes feel swapped/inverted.** Use the per-axis **Invert** toggles in the menu, or
  OpenTrack's own output mapping.

## How it works

```
CMHeadphoneMotionManager  ──►  recenter (qRef⁻¹·q)  ──►  slerp smoothing  ──►  Euler (deg)
   (AirPods, ~25 Hz)                                                              │
                                          ┌───────────────────────────────────────┤
                                          ▼                    ▼                   ▼
                                  UDP 4242 (OpenTrack)   UDP 4243 (JSON)   WebSocket → web viewer
```

Orientation math is done in quaternion space and only converted to OpenTrack's
yaw/pitch/roll Euler convention at the output. See `Sources/AirTracker/Math/QuaternionMath.swift`.

## License

MIT — see [LICENSE](LICENSE). Bundles [Three.js](https://threejs.org) (MIT).

Not affiliated with Apple. AirPods and TrackIR are trademarks of their respective owners.
