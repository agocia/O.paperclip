# O.Paperclip — Project Knowledge Base

**Generated:** 2026-04-15
**Commit:** working tree
**Branch:** develop

## OVERVIEW

macOS SwiftUI app that spoofs iOS device GPS location via `pymobiledevice3`. Connects to iPhone/iPad over USB or Wi-Fi tunnel, then injects simulated coordinates through DVT instruments or legacy `simulate-location` CLI. Supports A→B route following, fixed-point pinning, multi-waypoint routes, saved route replay with automatic mode switching, live remaining-time display, explicit start/end map markers, and KML-based "PurePoint" overlay import.

## STRUCTURE

```
O.Paperclip/
├── O_PaperclipApp.swift                       # @main entry, SwiftData container, XCTest host-app fallback
├── ContentView.swift                          # Root split view + map composition
├── AppViewModel.swift                         # Route calc, simulation timer, save/apply workflows
├── Core/
│   ├── Algorithms/RouteMotionEngine.swift     # Pure distance/interpolation helpers
│   ├── Constants/AppConstants.swift
│   ├── Models/AppState.swift
│   └── Models/Types.swift
├── Services/
│   ├── Device/DeviceManager.swift             # pymobiledevice3 orchestration, tunnel lifecycle + reconnect recovery
│   ├── Device/DVTLocationStream.swift         # Persistent Python subprocess for real-time GPS injection
│   ├── Diagnostics/AppDiagnostics.swift
│   ├── Diagnostics/DiagnosticsMaintenance.swift # Log rotation + legacy Application Support migration
│   ├── Location/LocationSearchService.swift
│   ├── Location/MKMapItem+Compatibility.swift # Compatibility helpers for MapKit item accessors
│   ├── PurePoint/PurePointOverlaySupport.swift
│   ├── Routes/ImportedGPXRouteSupport.swift
│   └── SavedLocations/SavedLocationSupport.swift
├── UI/
│   ├── Controls/MovementSettingsSectionView.swift
│   ├── Sidebar/DeviceStatusSectionView.swift
│   └── ...
├── Info.plist
├── O_Paperclip.entitlements
bundled/
├── pymobiledevice3                          # Bundled CLI binary
└── pymobiledevice3-bundle/                 # Fast bundle variant
O.PaperclipTests/
└── O_PaperclipTests.swift                  # Parser, logging, migration, GPX/save/apply, joystick, route timing tests
docs/
└── maintenance.md                          # Diagnostics, retention, migration, verification runbook
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| GPS injection pipeline | `Services/Device/DVTLocationStream.swift` | Inline Python script via `Process` stdin/stdout |
| Device connection flow | `Services/Device/DeviceManager.connectDeviceInternal()` | Sequential: resolve CLI → list devices → start tunnel → verify RSD → detect mode |
| Tunnel establishment | `Services/Device/DeviceManager.startTunnelAndResolveEndpoint()` | Tries TCP then QUIC; falls back to admin prompt via osascript |
| DVT ACK log throttling | `Services/Device/DeviceManager.DVTStreamLogReducer` | Suppresses per-coordinate `OK seq` noise and emits summaries |
| DVT unexpected-exit recovery | `Services/Device/DeviceManager.handleDvtStreamExit()` | Rebuilds the DVT subprocess on the existing tunnel first; only escalates to full reconnect if rebuild fails |
| Debug log UI updates | `Core/Protocols/DeviceControlling.swift` + `UI/Sidebar/DeviceStatusSectionView.swift` | Sidebar log panel updates via dedicated publisher, not whole-view redraw |
| Route simulation loop | `AppViewModel.startSimulation()` | 1.2s Timer on RunLoop.main, delegates to `RouteMotionEngine` |
| Coordinate throttling | `AppViewModel.shouldSendCoordinateUpdate()` | ≥2m distance OR ≥3s elapsed |
| Saved item apply flow | `AppViewModel.applySavedLocation()` | Programmatic mode switch with restore rules for point / route / loop |
| Route timing + endpoint markers | `AppViewModel.travelTimeSummary` + `ContentView` map annotations | Draft shows one-way estimate, active route shows remaining time |
| State machine | `Core/Models/AppState.swift` + `AppViewModel.handleMainAction()` | selectA → confirmA → selectB → confirmB → calcRoute → routeSelection → ready → moving |
| KML import | `Services/PurePoint/PurePointOverlaySupport.swift` | Full XMLParser delegate, handles StyleMap color resolution, NetworkLink following |
| Map rendering perf | `Services/PurePoint/PurePointRenderEngine.swift` | Viewport filtering at 180 points, density bucketing cap at 220 |
| Python path resolution | `Services/Device/DeviceManager.resolveCLI()` | Bundled binary → standalone CLI → bundle fast path |
| Auto-reconnect | `Services/Device/DeviceManager.scheduleAutoReconnect()` | Exponential backoff capped at 8s |
| Log retention / legacy support cleanup | `Services/Diagnostics/DiagnosticsMaintenance.swift` | Shared rotation policy and one-time migration from old Application Support roots |
| Runtime maintenance guide | `docs/maintenance.md` | Force-quit vs crash triage, cleanup, verification steps |

## CONVENTIONS

- **Language**: All UI strings in Traditional Chinese (zh-TW). Code comments in Chinese.
- **Architecture**: Single-window macOS app. No navigation stack. `ContentView` owns `AppViewModel` via `@State`. `DeviceManager` is a dependency of `AppViewModel`, not injected via environment.
- **Concurrency model**: `@MainActor` on ViewModels. `DeviceManager` uses explicit `DispatchQueue` for connection and send pipelines (NOT async/await). Timer-based simulation on `RunLoop.main`.
- **State management**: `AppViewModel` uses `@Observable`. `DeviceManager` remains `ObservableObject` for connection state, but debug log updates go through a dedicated `CurrentValueSubject` so log churn does not force full-view redraws.
- **Error handling**: `NSError` with Chinese `localizedDescription` throughout `DeviceManager`. No custom Error types except `PurePointImportError`.
- **Process management**: `Process` + `Pipe` for all pymobiledevice3 interaction. Timeout via polling loop (`Thread.sleep`), not `DispatchWorkItem`.
- **Persistence**: `UserDefaults` for map region, connection settings, imported overlay paths, and migration rewrites. `SwiftData` container exists but `Item` model is unused.
- **Naming**: Files named after their primary type. No protocol-oriented abstractions. Enums used as namespaces (`RouteMotionEngine`, `DiagnosticsPaths`).

## ANTI-PATTERNS (DO NOT INTRODUCE)

- **Do NOT split ContentView into separate files** without explicit request — the author keeps it monolithic intentionally.
- **Do NOT convert DeviceManager to async/await** — the explicit queue model is deliberate for controlling tunnel process lifecycle.
- **Do NOT add English UI strings** — all user-facing text must be zh-TW.
- **Do NOT remove the SwiftData container** — it's scaffolding that may be used later.
- **Do NOT add third-party dependencies** — the app bundles pymobiledevice3 and uses only Apple frameworks.
- **Do NOT reintroduce `@Published debugLog` style log churn** — long-running stability depends on keeping debug log updates off the full SwiftUI redraw path.

## UNIQUE PATTERNS

- `DVTLocationStream` embeds a full Python script as a Swift string literal, spawns it as a subprocess, and communicates via stdin/stdout line protocol (`SEQ,LAT,LON` → `OK SEQ` / `ERR`).
- `DeviceManager` has a dual-injection strategy: prefers DVT instruments stream, falls back to legacy `simulate-location set` CLI per-coordinate if DVT service is unavailable (older iOS).
- `DeviceManager` now treats DVT ACKs as diagnostic summaries, not per-event UI logs, to avoid long-session redraw storms.
- `DeviceManager` now treats unexpected `dvt-location-stream` exits as a recoverable subprocess fault first: it tries to rebuild the stream on the existing RSD tunnel before tearing the whole connection down. This prevents temporary DVT subprocess exits from cascading into full reconnect storms.
- `DeviceManager` intentionally no longer runs a background USB hot-plug poller. Stability testing showed repeated `ioreg` probes were a regression risk during long sessions, so disconnect recovery is driven by tunnel / DVT failures instead.
- `TunnelOutputParser` is a static parser that extracts RSD host/port from multiple output formats (structured, JSON, script-mode, `--rsd` flag).
- Map camera position is persisted to `UserDefaults` on every change and restored on launch with validation.
- PurePoint rendering uses a spatial bucketing algorithm to cap annotations at 220 while maintaining geographic distribution.
- `AppDiagnostics` installs C-level signal handlers (`SIGABRT`, `SIGSEGV`, etc.) using `Darwin.signal()` and writes to fd directly (async-signal-safe).
- `AppDiagnostics` now uses shared rotating log stores and performs one-time migration from `O.Paperclip` / `O-Paperclip` into `fregata-O-PaperclipPackaging`.
- The app host launched by XCTest boots a placeholder scene with an in-memory model container so unit tests do not depend on the full map UI startup path.

## COMMANDS

```bash
# Build (Xcode)
xcodebuild -project O.Paperclip.xcodeproj -scheme O.Paperclip -configuration Release build

# Test
xcodebuild -project O.Paperclip.xcodeproj -scheme O.Paperclip test
```

The bundled pymobiledevice3 binary is at `bundled/pymobiledevice3`.  
App resolves CLI in order: bundled binary → `~/.local/bin` → homebrew → system Python module.

On this machine, `xcodebuild test` may pause for a macOS password / authorization confirmation. If no one is present to approve it, the command will eventually time out even when the test bundle itself is fine.

## NOTES

- `Item.swift` SwiftData model and `sharedModelContainer` are Xcode template leftovers — not used by any feature.
- `ContentView.init()` creates `DeviceManager` and `LocationSearchService` inline — no dependency injection container.
- `Services/Location/MKMapItem+Compatibility.swift` provides the compatibility accessors used by `AppViewModel` and `LocationSearchService`.
- `default.profraw` in root is a code coverage artifact — should be gitignored.
- `scripts/build-dmg.sh` now writes artifacts to `build/dmg/artifacts/` instead of the repo root.
- The app bundle copy phase strips `.DS_Store` out of `bundled/pymobiledevice3-bundle`, so packaging no longer depends on external cleanup scripts to remove Finder junk.
- Automated tests now cover KML / GPX parsing, log rotation, legacy Application Support migration, DVT ACK reduction, saved-item restore rules, joystick movement, route replacement, timing summaries, and several utility parsers.
- Automated tests also cover the DVT recovery path: unexpected stream exit rebuilds in place, and rebuild failure falls back to full reconnect.
