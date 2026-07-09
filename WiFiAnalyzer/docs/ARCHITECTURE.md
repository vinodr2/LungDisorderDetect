# WiFiAnalyzer — Architecture

A Windows-only Wi-Fi Analyzer written in **Delphi 12 VCL**, using only the
standard VCL and native Win32/WLAN APIs (no third-party components).

## Goals

- Discover nearby Wi-Fi networks via the native **WLAN API** (`wlanapi.dll`),
  never by shelling out to `netsh`.
- Analyse the RF environment (per-channel load, overlap, recommended channel).
- Present a modern, responsive, real-time dashboard.
- Keep the UI thread free at all times; all scanning happens on a worker thread.

## Layering

Dependencies point strictly downward. Forms contain no business logic.

```
UI (VCL forms/frames)          WiFi.UI.*
        │  binds to
ViewModels                     WiFi.ViewModels.*
        │  uses
Services                       WiFi.Services.{Scanner,Oui,Logger}
        │  uses
RF Analysis Engine             WiFi.Engine.{Channels,Analysis}
        │  uses
WLAN API Wrapper               WiFi.Api.{Wlan,WlanTypes}   (IWlanClient)
        │  uses
Models + Utilities             WiFi.Models, WiFi.Util.*
```

### UI (`WiFi.UI.Main`)
A thin view over the view-model. Owns the scanner service, forwards user input
to the view-model, and redraws when the view-model raises `OnChanged`. The
network list is an owner-drawn `TDrawGrid` that pulls cell text from the
view-model on demand (virtual), so it scales to hundreds of rows.

### ViewModel (`WiFi.ViewModels.Main`)
Holds an independent copy of the latest snapshot, runs the analysis engine,
and exposes filtered/sorted rows plus summary metrics. No VCL dependency, so
it is unit-testable in isolation.

### Services
- **Scanner** (`WiFi.Services.Scanner`): owns a background `TThread` that
  triggers scans, reads results through `IWlanClient`, resolves vendors, and
  marshals an immutable `TScanSnapshot` to the main thread with `TThread.Queue`.
  Interval is configurable; `RefreshNow` forces an immediate scan.
- **OUI** (`WiFi.Services.Oui`): loads `oui.txt` once and maps BSSID → vendor.
- **Logger** (`WiFi.Services.Logger`): thread-safe, never-throwing file logger.

### RF Analysis Engine
- **Channels** (`WiFi.Engine.Channels`): pure conversions between center
  frequency, channel and band (2.4/5/6 GHz) and channel occupancy spans.
- **Analysis** (`WiFi.Engine.Analysis`): per-channel counts, an RSSI/overlap-
  weighted congestion score, and a recommended channel per band. Pure functions
  over a snapshot → `TChannelReport`.

### WLAN Wrapper
- **WlanTypes** (`WiFi.Api.WlanTypes`): faithful Pascal translations of the
  WLAN structs/enums/constants and the `wlanapi.dll` imports.
- **Wlan** (`WiFi.Api.Wlan`): `IWlanClient` interface with a native
  `TWlanClient` and an in-memory `TFakeWlanClient` for tests/design. All
  P/Invoke and marshaling is isolated here.

### Models & Utilities
`TAccessPoint`, `TScanSnapshot`, enums and display helpers (`WiFi.Models`);
signal formatting (`WiFi.Util.Format`); INI-backed settings (`WiFi.Util.Config`).

## Threading model

```
UI thread ──creates──► TScannerService ──owns──► TScanThread
   ▲                                                  │
   │  TThread.Queue(snapshot)                          │ Scan → GetBssList
   └──────────────── OnSnapshot ◄─────────────────────┘ (WLAN API)
```

- The worker thread never touches the VCL.
- Snapshots are immutable and owned by the service; the `OnSnapshot` handler
  copies what it needs and must not free the snapshot.
- `TScanThread.TerminatedSet` signals a wait event so shutdown is prompt even
  mid-interval.

## Error handling

Every WLAN call is checked; failures raise `EWlanError`, are logged, and are
surfaced through `OnError` without crashing. Missing adapter, radio off and
access-denied are treated as recoverable states.

## Extension points (later phases)

`TChannelReport` grows utilization/interference fields; new UI frames dock into
the main form; `IWlanClient` gains IE parsing for channel width; export and
history services slot in beside the existing services — no changes to lower
layers.
