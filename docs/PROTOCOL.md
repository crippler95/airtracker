# AirTracker Wire-Format Reference

AirTracker streams AirPods head-orientation over several transports. This document is the authoritative reference for every byte and field it emits. It deliberately mirrors the protocol used by [sony-head-tracker](https://github.com/NicholasSlattery/sony-head-tracker) so existing tooling works unchanged.

## Ports

| Port | Protocol | Purpose | Configurable |
|------|----------|---------|--------------|
| 4242 | UDP | OpenTrack binary output | Yes (host + port) |
| 4243 | UDP | JSON output | No |
| 4244 | HTTP | Web viewer | No |
| 4245 | WebSocket | JSON output for web viewer | No |

## OpenTrack UDP (port 4242)

The default output targets OpenTrack's **"UDP over network"** input. Both the destination host and port are configurable, so you can stream to another machine on your LAN.

One datagram is sent per motion sample. Each datagram is **exactly 48 bytes**: six little-endian IEEE-754 `float64` (double) values, in this order:

| Index | Field | Unit | Notes |
|-------|-------|------|-------|
| 0 | x | cm | Translation, always `0.0` |
| 1 | y | cm | Translation, always `0.0` |
| 2 | z | cm | Translation, always `0.0` |
| 3 | yaw | degrees | `+` = look left |
| 4 | pitch | degrees | `+` = look up |
| 5 | roll | degrees | `+` = tilt head right |

Translation (`x`, `y`, `z`) is always `0.0` — AirPods provide orientation only, no position. Rotation is expressed in degrees using the convention above. This is exactly what OpenTrack's "UDP over network" input expects, so no axis remapping is required on the OpenTrack side.

### Decoding in Python

```python
import socket
import struct

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", 4242))

while True:
    data, _ = sock.recvfrom(64)
    x, y, z, yaw, pitch, roll = struct.unpack("<6d", data)
    print(f"yaw={yaw:+.1f} pitch={pitch:+.1f} roll={roll:+.1f}")
```

`struct.unpack('<6d', data)` returns the six doubles in order `[x, y, z, yaw, pitch, roll]`.

## JSON UDP (port 4243) and WebSocket (port 4245)

Both transports emit one UTF-8 JSON object per motion sample. The schema is **version 2** and matches sony-head-tracker.

```json
{
  "version": 2,
  "device": "AirPods (CoreMotion)",
  "rotationVector": [x, y, z],
  "quaternion": [w, x, y, z],
  "yprDegrees": [yaw, pitch, roll],
  "gyroscope": [x, y, z],
  "accelerometer": [x, y, z],
  "angularVelocity": [x, y, z],
  "resetCounter": 0,
  "packetsPerSecond": 25,
  "receiveLatencyMs": -1.0
}
```

### Field reference

| Field | Type | Description |
|-------|------|-------------|
| `version` | int | Schema version. Currently `2`. |
| `device` | string | Source device label, e.g. `"AirPods (CoreMotion)"`. |
| `rotationVector` | `[x, y, z]` | Imaginary part of the quaternion. |
| `quaternion` | `[w, x, y, z]` | Recentered orientation. |
| `yprDegrees` | `[yaw, pitch, roll]` | Post-remap Euler angles, in degrees. |
| `gyroscope` | `[x, y, z]` | Angular velocity in rad/s from CoreMotion `rotationRate` (smoothed). |
| `accelerometer` | `[x, y, z]` | CoreMotion `userAcceleration` in g (smoothed). |
| `angularVelocity` | `[x, y, z]` | **Deprecated** alias of `gyroscope`. |
| `resetCounter` | int | Increments on each recenter. |
| `packetsPerSecond` | int | Rolling 1-second sample count. |
| `receiveLatencyMs` | float | Always `-1` — CoreMotion provides no device timestamp. |

### WebSocket `settings` object

The WebSocket variant additionally includes a `settings` object carrying the current axis configuration, so the web viewer can mirror the menu controls. It reflects the per-axis sources, inverts, scales, and smoothing:

```json
{
  "version": 2,
  "device": "AirPods (CoreMotion)",
  "quaternion": [1.0, 0.0, 0.0, 0.0],
  "yprDegrees": [0.0, 0.0, 0.0],
  "settings": {
    "sources": { "yaw": "yaw", "pitch": "pitch", "roll": "roll" },
    "inverts": { "yaw": false, "pitch": false, "roll": false },
    "scales": { "yaw": 1.0, "pitch": 1.0, "roll": 1.0 },
    "smoothing": 0.2
  }
}
```

The plain JSON UDP output (port 4243) does **not** include the `settings` object.
