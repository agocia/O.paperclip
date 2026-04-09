# O.Paperclip

**A macOS GPS spoofing tool built specifically for Mac users, allowing you to inject simulated coordinates into an iPhone or iPad over USB or Wi-Fi.**

Chinese version: [README.md](./README.md)

**Before using this app: your iPhone / iPad must have Developer Mode enabled.**  
**If this project helps you, you can support its development here: Ko-fi: https://ko-fi.com/agocia**

---

## Requirements

| Item | Requirement |
|------|-------------|
| macOS | macOS 14 Sonoma or later |
| iPhone / iPad | iOS 16 or later, with Developer Mode enabled |
| Connection | USB or Wi-Fi (same network) |
| Other | No need to install Python, Homebrew, or any extra packages |

---

## Installation

### Option 1: Download the DMG (Recommended)

1. Go to the [Releases](../../releases) page and download the latest `O.Paperclip.dmg`
2. Open the DMG and drag `O.Paperclip.app` into the `Applications` folder
3. When launching it for the first time, right-click the app, choose `Open`, and confirm to bypass Gatekeeper

### Option 2: Build from Source

```bash
git clone https://github.com/agocia/O.Paperclip.git
cd O.Paperclip
xcodebuild -project O.Paperclip.xcodeproj -scheme O.Paperclip -configuration Release build
```

#### Open the app after building

The command above builds `O.Paperclip.app` into Xcode's `DerivedData` (not into the repository root).

```bash
APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData -path "*/Build/Products/Release/O.Paperclip.app" -print -quit)"
open "$APP_PATH"
```

If you want a fixed output path, use this instead:

```bash
xcodebuild -project O.Paperclip.xcodeproj -scheme O.Paperclip -configuration Release -derivedDataPath build build
open build/Build/Products/Release/O.Paperclip.app
```

> First launch may still be blocked by Gatekeeper. If so, right-click `O.Paperclip.app` → `Open` → confirm.

---

## Before You Start

### iPhone / iPad Setup

1. **Enable Developer Mode** (iOS 16+)  
   Go to `Settings` → `Privacy & Security` → `Developer Mode` → turn it on → restart the device

2. **Trust this Mac** (first USB connection)  
   After connecting via USB, your iPhone will ask whether to trust this computer. Tap `Trust` and enter your passcode.

3. **Extra step for Wi-Fi connection**  
   You must complete the trust pairing once over USB before switching to Wi-Fi mode.

---

## How to Use

### Step 1: Connect Your Device

**USB connection (default):**
1. Connect your iPhone / iPad with a USB cable
2. Open O.Paperclip
3. In the sidebar, make sure `USB` is selected in the connection mode switcher
4. Click `Start Connection`
5. If prompted, enter your Mac administrator password (required to create the tunnel)

**Wi-Fi connection:**
1. Make sure your iPhone and Mac are on the same Wi-Fi network
2. Open O.Paperclip
3. Switch the connection mode in the sidebar to `Wi-Fi`
4. Click `Start Connection`

> If your device is already connected over USB, you can switch directly to Wi-Fi. The app will automatically disconnect the current session and rebuild the tunnel over Wi-Fi.

> After a successful connection, the sidebar will show `Connected` along with the device name.  
> If the USB cable is unplugged or the Wi-Fi tunnel is interrupted, the app will automatically switch to a disconnected state and stop continuous movement until you reconnect.

---

### Step 2: Choose an Operation Mode

Use the segmented control at the top of the sidebar to switch between three modes:

| Mode | Description |
|------|-------------|
| **A-B** | Click a start point A and an end point B on the map, and the app will calculate a route and move along it automatically |
| **Pin** | Stay fixed at a single selected coordinate on the map |
| **Multi-Point** | Select multiple route points in order and move through them one by one |

---

### Step 3: Set the Location

**A-B Route Mode:**
1. Click the map to set point A, then click `Confirm A`
2. Click the map to set point B, then click `Confirm B`
3. Choose a route and click `Start Moving`
4. Adjust speed (km/h) and whether the route should loop

**Pin Mode:**
1. Click the target location on the map
2. Click `Pin This Location`
3. GPS will stay fixed at that point

**Multi-Point Mode:**
1. Click multiple route points on the map in order
2. Click `Start Moving`

> You can also type an address or place name in the search bar to jump directly to a location.

---

### Step 4: Stop Spoofing

Click `Stop` or `Clear Route` to stop GPS spoofing and return the device to its real location.

---

## PurePoint Overlay

You can import KML geographic data and display custom markers on the map:

1. Click `Import KML` in the sidebar
2. Select a `.kml` file
3. The overlay will appear on the map, and you can filter markers by category

---

## Troubleshooting

**Q: The app keeps loading after I click "Start Connection".**  
A: Make sure the iPhone is unlocked and the Mac is trusted. For Wi-Fi mode, confirm both devices are on the same network.

**Q: Why am I asked for the administrator password?**  
A: This is expected. Creating the tunnel requires temporary root privileges.

**Q: Wi-Fi connection failed and it switched back to USB.**  
A: The app automatically falls back to USB. If you want Wi-Fi specifically, make sure both devices are on the same network and your firewall is not blocking the connection.

**Q: I am already connected over USB. Can I switch directly to Wi-Fi?**  
A: Yes. Just change the connection mode in the sidebar to `Wi-Fi`, and the app will automatically disconnect the current USB session and rebuild the tunnel over Wi-Fi.

**Q: Why does the app stop moving after I unplug the phone?**  
A: This is normal behavior. When the tunnel or device connection is interrupted, the app immediately marks the device as disconnected and stops the simulation to avoid fake movement continuing in the background.

**Q: GPS did not return to normal after stopping.**  
A: Click `Clear Location Points` or restart location services on the iPhone.

**Q: Connection fails on iOS 17 or later.**  
A: Make sure Developer Mode is enabled and that the device has already been trusted in Xcode or Finder.

---

## Disclaimer

This tool is intended only for legitimate use cases such as development testing and privacy protection. Do not use it for fraud, game cheating, or any activity that violates terms of service. Users are solely responsible for their actions.

---

## License

MIT License - see [LICENSE](LICENSE)
