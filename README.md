# O.Paperclip

**A macOS GPS spoofing tool for iPhone and iPad**, built for real devices over USB or Wi-Fi. It supports pinning a fixed location, A-B routing, multi-point routes, imported fixed routes, joystick control, and KML-based PurePoint overlays.

**Before using this app: your iPhone / iPad must have Developer Mode enabled.**  
**If this project helps you, you can support its development here: Ko-fi: https://ko-fi.com/agocia**

<p align="right">
  <a href="README.CH.md"><img alt="Traditional Chinese" src="https://img.shields.io/badge/繁體中文-gray?style=flat-square"></a>
  <a href="README.md"><img alt="English" src="https://img.shields.io/badge/English-active-2d3748?style=flat-square"></a>
</p>

> ### Project Status
>
> O.Paperclip is an independently maintained open-source project, not a commercial product. It is actively improved, but it should still be treated as a practical tool that evolves with macOS, iOS, and `pymobiledevice3`, not as a guaranteed appliance for every environment.
>
> - The app is designed specifically for macOS-based iPhone / iPad GPS simulation.
> - Stability depends on iOS version, Developer Mode, trust pairing, and your USB / Wi-Fi environment.
> - If you hit a bug, please include your device model, iOS version, connection method, and visible error message when reporting it.
> - The project is provided as-is, without guaranteed long-term maintenance.

## Highlights

### Simulation Modes

| Mode | Description |
| --- | --- |
| **Pin** | Keep the device fixed at a single coordinate |
| **A-B** | Pick a start and end point, calculate a route, and move along it |
| **Multi-Point** | Move through multiple custom route points in order |
| **Joystick** | Push the current position live with arrow keys or WASD |
| **Imported Fixed Route** | Apply a GPX route from the right-side import panel |

### Route and Map Features

- Draft routes and active routes both show clear start / end markers.
- Closed loops collapse into a single `Start / End` marker to avoid overlap.
- Drafts show one-way ETA before movement starts.
- Active routes show live remaining time during movement.
- Saved points and routes automatically switch the app to a compatible mode when applied.
- GPX imported routes and KML PurePoint overlays are supported.

### Connection Behavior

- Supports both **USB** and **Wi-Fi tunnel** connections.
- USB hot-unplug is detected proactively, the simulation is stopped immediately, and auto-reconnect starts automatically.
- Tunnel failures and send failures continue to use the existing reconnect flow.
- You can switch between USB and Wi-Fi while the app is running.

## Requirements

| Item | Requirement |
| --- | --- |
| macOS | macOS 14 Sonoma or later |
| iPhone / iPad | iOS 16 or later |
| Device setup | Developer Mode enabled and trusted with this Mac |
| Connection | USB or Wi-Fi on the same network |
| Other | No separate Python, Homebrew, or `pymobiledevice3` install required |

## Installation

### Download

1. Go to [Releases](../../releases) and download the latest build.
2. Open the `.dmg` and drag `O.Paperclip.app` into `Applications`.
3. If Gatekeeper blocks first launch, right-click the app in Finder and choose `Open`.

### Build From Source

```bash
git clone https://github.com/agocia/O.paperclip.git
cd O.paperclip
xcodebuild -project O.Paperclip.xcodeproj -scheme O.Paperclip -configuration Release build
```

## Before You Start

### 1. Enable Developer Mode on the iPhone / iPad

Go to `Settings` → `Privacy & Security` → `Developer Mode`, then restart the device.

### 2. Complete one USB trust pairing first

When you connect by USB for the first time, iPhone / iPad must trust this Mac.

### 3. Use USB once before Wi-Fi

Wi-Fi tunnel depends on the existing trust pairing, so first-time setup still starts with USB.

## Quick Start

### 1. Connect the Device

**USB**

1. Connect the iPhone / iPad with a cable.
2. Open O.Paperclip.
3. Make sure the connection mode is set to `USB`.
4. Click `Start Connection`.
5. Enter the macOS administrator password if prompted.

**Wi-Fi**

1. Make sure the device and Mac are on the same network.
2. Switch the connection mode to `Wi-Fi`.
3. Click `Start Connection`.

After a successful connection, the sidebar shows the device name and connection state. If USB is unplugged or the tunnel drops, the app detects the disconnect, stops simulation, shows a warning, and starts auto-reconnect.

### 2. Choose a Mode

The mode picker currently shows four modes:

- `A-B`
- `Pin`
- `Multi-Point`
- `Joystick`

`Fixed Route` no longer appears in the mode picker. Use the right-side `Import & Saved` panel instead.

### 3. Set a Location and Start

**A-B**

1. Pick point A on the map.
2. Confirm point A.
3. Pick point B.
4. Confirm point B and choose a route.
5. Click `Start Moving`.

**Pin**

1. Pick a location on the map.
2. Click `Pin This Location`.

**Multi-Point**

1. Add multiple route points in order.
2. Click `Start Moving`.

**Joystick**

1. Start joystick control.
2. Move with arrow keys or `WASD`.

### 4. Stop or Clear

- `Stop`: stop the current simulation.
- `Clear Route` / `Clear Location`: clear the current draft or pinned state.

## Import and Saved Items

The right-side `Import & Saved` panel handles:

- Saved points
- Saved A-B routes
- Saved multi-point routes
- Saved loop routes
- Imported GPX fixed routes
- Imported KML PurePoint overlays

### Saved Item Mapping

When you click `Apply`, the app switches automatically:

- Saved point → `Pin`
- Saved A-B route → `A-B`
- Saved multi-point route → `Multi-Point`
- Saved fixed-route source → `Multi-Point`
- Saved loop → `Multi-Point` with closed-loop enabled

## PurePoint Overlay

PurePoint overlays let you display custom KML-based points on the map:

1. Click `Import KML`.
2. Select a `.kml` file.
3. Filter imported categories on the map as needed.

## Troubleshooting

### The app keeps spinning after I click Start Connection

Check the following:

- The device is unlocked
- This Mac is trusted
- Developer Mode is enabled
- For Wi-Fi, both devices are on the same subnet

### Why does the app ask for my administrator password?

Tunnel setup needs temporary elevated privileges. This is expected.

### Why does movement stop when I unplug the cable?

This is expected. The app actively checks whether the USB device is still present. Once it confirms the disconnect, it stops simulation, shows `Device disconnected, simulation stopped, reconnecting...`, and starts auto-reconnect.

### Can I switch to Wi-Fi after connecting over USB?

Yes. Switching to `Wi-Fi` disconnects the active USB session and rebuilds the connection over Wi-Fi.

### GPS did not return to normal after stopping

Try clearing the location again, or restart location services on the device.

## Diagnostics and Maintenance

- Runtime logs now live under `~/Library/Application Support/fregata-O-PaperclipPackaging/Logs/`.
- Long-running sessions use bounded log rotation, including lifecycle, incident, model bootstrap, and privileged tunnel logs.
- Older Application Support roots (`O.Paperclip`, `O-Paperclip`) are migrated into the current root on launch, while only regenerable tunnel and log artifacts are cleaned.
- DMG build artifacts are written to `build/dmg/artifacts/` instead of the repository root.
- The maintenance runbook is documented in [docs/maintenance.md](docs/maintenance.md).

## Development

### Build

```bash
xcodebuild -project O.Paperclip.xcodeproj -scheme O.Paperclip -configuration Debug build
```

### Test

```bash
xcodebuild -project O.Paperclip.xcodeproj -scheme O.Paperclip test
```

Shared scheme notes:

- The shared `O.Paperclip` scheme runs `O.PaperclipTests` only. The stock template UI tests are not part of the shared test action.
- When XCTest launches the host app, O.Paperclip uses a minimal placeholder scene and an in-memory model container so the logic test bundle does not depend on the full map UI at startup.

## Project Structure

```text
O.Paperclip/
├── O.Paperclip/
│   ├── Core/
│   ├── Services/
│   ├── UI/
│   └── ContentView.swift
├── O.PaperclipTests/
├── bundled/
└── O.Paperclip.xcodeproj
```

## Disclaimer

This tool is intended for development testing, privacy protection, and other legitimate use cases. Do not use it for cheating, fraud, or any activity that violates platform terms or local laws. You are solely responsible for how you use it.

## License

MIT License. See [LICENSE](LICENSE).
