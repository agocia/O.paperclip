# O.Paperclip Maintenance Runbook

## Runtime Logs

O.Paperclip writes diagnostics into the current Application Support root:

- `~/Library/Application Support/fregata-O-PaperclipPackaging/Logs/device-runtime.log`
- `~/Library/Application Support/fregata-O-PaperclipPackaging/Logs/device-runtime.log.1`
- `~/Library/Application Support/fregata-O-PaperclipPackaging/Logs/app-lifecycle.jsonl`
- `~/Library/Application Support/fregata-O-PaperclipPackaging/Logs/incidents.jsonl`
- `~/Library/Application Support/fregata-O-PaperclipPackaging/Logs/model-container.log`
- `~/Library/Application Support/fregata-O-PaperclipPackaging/Logs/uncaught-exceptions.log`
- `~/Library/Application Support/fregata-O-PaperclipPackaging/Logs/crash-signals.log`
- `~/Library/Application Support/fregata-O-PaperclipPackaging/PrivilegedTunnel/opaperclip_tunnel.log`

`device-runtime.log` is the main timeline for tunnel setup, reconnects, send failures, and DVT lifecycle. DVT ACK lines are intentionally throttled; the log now records summaries instead of one line per coordinate.

As of the 2026-04-16 stability fix, an unexpected `dvt-location-stream` exit is treated as a subprocess fault first, not immediately as a full tunnel failure. O.Paperclip now tries to rebuild the DVT stream on the existing RSD tunnel, and only tears the connection down if that rebuild fails.

## Rotation Policy

The app keeps logs bounded instead of letting them grow forever:

- Standard logs rotate at `256 KB`: `device-runtime.log`, `app-lifecycle.jsonl`, `incidents.jsonl`, `PrivilegedTunnel/opaperclip_tunnel.log`
- Compact logs rotate at `64 KB`: `model-container.log`, `uncaught-exceptions.log`, `crash-signals.log`
- Rotation keeps one backup file with a `.1` suffix
- The privileged tunnel wrapper truncates its own live log if it grows past the cap during long-running sessions

## Crash vs Hang

When users report “left it running for hours and came back to a dead app”, distinguish the failure type before changing code:

1. Check `~/Library/Logs/DiagnosticReports/` for a matching crash report.
2. Check `~/Library/Application Support/fregata-O-PaperclipPackaging/Logs/incidents.jsonl`.
3. Check `~/Library/Application Support/CrashReporter/` for a `ForceQuitDate`.

Interpretation:

- `DiagnosticReports` entry present: real crash
- `ForceQuitDate` present but no crash report: the app most likely hung and was force-quit
- `incidents.jsonl` entry with a previous active session: the app terminated without a clean shutdown

Recent field evidence pointed at this sequence for long-session hangs:

1. `dvt-location-stream` exits with `code: 15`
2. older builds immediately treated that as a full connection loss
3. teardown + reconnect overlapped with the still-live app session and could leave the UI in a wedged state

The current build narrows that blast radius by restarting only the DVT subprocess first.

## Legacy Application Support Migration

Older builds used multiple Application Support roots:

- `~/Library/Application Support/O.Paperclip`
- `~/Library/Application Support/O-Paperclip`
- `~/Library/Application Support/fregata-O-PaperclipPackaging`

On startup, the app now performs a one-time maintenance migration:

- Moves user-managed files from legacy roots into the current root
- Preserves and deduplicates:
  - `SavedLocations`
  - `ImportedGPXRoutes`
  - `ImportedPurePointOverlays`
- Rewrites stored file paths in `UserDefaults`
- Deletes only regenerable artifacts from legacy roots:
  - `Logs`
  - `PrivilegedTunnel`
  - `.DS_Store`

The migration writes `maintenance-migration-v1.json` into the current Application Support root so it does not rerun every launch.

## Local Cleanup

If you need to reset only generated artifacts without touching user data:

```bash
rm -rf ~/Library/Application\ Support/fregata-O-PaperclipPackaging/Logs
rm -rf ~/Library/Application\ Support/fregata-O-PaperclipPackaging/PrivilegedTunnel
```

If you need to inspect packaging inputs:

```bash
find O.Paperclip -name '.DS_Store' -delete
xattr -cr O.Paperclip bundled
```

## Verification Checklist

After touching connection, logging, or packaging code:

1. Run `xcodebuild -project O.Paperclip.xcodeproj -scheme O.Paperclip test`.
2. Confirm the app bundle no longer contains `.claude` or other local-only tooling files.
3. Start a long-running `Pin` session and verify `device-runtime.log` only grows within the configured rotation cap.
4. While connected in DVT mode, simulate or observe an unexpected DVT subprocess exit and confirm:
   - the log records `嘗試在既有 tunnel 上重建`
   - successful recovery records `dvt-stream 已重建，維持原有連線`
   - only rebuild failure falls back to `排程自動重連`
5. If you manually unplug USB during a session, treat any follow-up reconnect as tunnel-level recovery.
   - there is no background `ioreg` hot-plug poller anymore
   - `device-runtime.log` should stay quiet until tunnel / DVT actually reports a failure
6. Build a DMG with `scripts/build-dmg.sh` and confirm artifacts land under `build/dmg/artifacts/`.

## Automated Test Notes

- The shared `O.Paperclip` scheme runs `O.PaperclipTests` only. Template-generated UI tests are intentionally excluded from the shared test action.
- XCTest still launches the app host for the unit-test bundle. In that environment, O.Paperclip boots with a minimal placeholder scene and an in-memory model container so tests do not depend on the full map UI.
- On this machine, `xcodebuild test` may block on a macOS password / authorization confirmation. If nobody is present to approve it, the command can time out even when the test bundle itself is healthy.
- If a timeout happens while nobody is at the machine, retry with someone present before treating it as a product or `testmanagerd` failure.
- If the timeout still reproduces with interactive approval available, then clear the project DerivedData and retry before changing product code:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/O.Paperclip-*
```
