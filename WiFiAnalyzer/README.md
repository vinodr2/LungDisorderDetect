# WiFiAnalyzer

A modern, Windows-only **Wi-Fi Analyzer** built entirely in **Delphi 12 (VCL)**
using only the standard VCL and native **Windows WLAN APIs** — no third-party
components, no `netsh` shell-outs.

It discovers nearby wireless networks, analyses the RF environment (channel
load, overlap, recommended channel) and presents a real-time, non-blocking
dashboard inspired by tools like WiFiInfoView, inSSIDer and Acrylic WiFi.

> **Status:** Phase 4. A polished Networks grid (multi-column sort, grouping,
> CSV/Excel export, copy), a **Channel Analysis** tab (spectrum + heatmap) and a
> **Signal** tab (live RSSI graph, quality/congestion gauges and snapshot
> comparison), backed by a background scanner, WLAN wrapper, models, RF analysis
> engine and signal-history/export services.
> See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and the roadmap below.

## Features

**Networks tab (Phase 1)**
- Native WLAN discovery via `wlanapi.dll` (BSS list + available networks).
- SSID, BSSID, vendor (OUI lookup), channel, band, frequency, RSSI, quality,
  PHY, security, connected and hidden-network detection.
- Background scanning on a worker thread — the UI never freezes.
- Configurable auto-refresh interval and manual **Rescan now**.
- Owner-drawn virtual grid: search, band filter, click-to-sort any column,
  colour-graded signal bars.
- Basic light/dark theming via VCL Styles.

**Networks grid polish (Phase 4)**
- **Multi-column sort**: Shift-click headers to add secondary keys; priority
  badges (▲/▼ + number) show the sort order.
- **Grouping**: group rows by Band / Security / Vendor / Channel, with group
  header bands and per-group counts.
- **Export**: CSV (RFC-4180, UTF-8 BOM) and native **`.xlsx`** (built with the
  RTL's `System.Zip` — no third-party) of the current filtered/sorted rows.
- **Copy**: right-click → Copy row / Copy all (or Ctrl+C) as TSV for pasting
  straight into Excel.

**Channels tab (Phase 2)**
- Per-band (2.4 / 5 / 6 GHz) **spectrum graph**: one arc per network, centered
  on its channel, height by signal, width by channel width; optional fill.
- **Congestion heatmap** strip: one cell per channel, green (quiet) → red
  (busy), labelled with utilization percent.
- Co-channel vs adjacent-channel interference, utilization estimate and the
  **recommended channel** highlighted on the axis.
- All rendering is hand-drawn on `TCanvas`/GDI — no chart library.

**Signal tab (Phase 3)**
- **Live RSSI graph**: tick any networks in the list to plot their signal (dBm)
  over time, one coloured line each, with a legend and time axis.
- **Gauges** for the selected network: a signal-quality meter and a
  channel-congestion gauge, custom-drawn with graded arcs and needles.
- **Snapshot comparison**: pick two past scans and list what was
  added / removed / changed (with RSSI deltas).
- Backed by `WiFi.Services.History` (per-BSSID RSSI ring buffer + scan history).

## Requirements

- **Delphi 12 (Athens)** or later, with the VCL and (for tests) DUnitX.
- **Windows 10 / 11**, a Wi-Fi adapter, and the **WLAN AutoConfig** service
  running (default on Windows).
- Primary target **Win64**; Win32 also configured.

## Build & run

1. Open `WiFiAnalyzer.dproj` in the Delphi 12 IDE.
2. Select the **Win64** platform and the **Debug** (or **Release**) config.
3. In *Project > Options > Application > Manifest*, set DPI awareness to
   **Per Monitor v2** (see `resources/WiFiAnalyzer.manifest` for reference).
4. **Build** and **Run** (F9).
5. Copy `resources/oui.txt` next to the built executable
   (`bin\Win64\Debug\`) so vendor lookup is populated. (The app runs fine
   without it — the Vendor column is just left blank.)

Command-line build (Windows, with RAD Studio environment loaded):

```bat
rsvars.bat
msbuild WiFiAnalyzer.dproj /t:Build /p:Config=Release /p:Platform=Win64
```

## Tests

The pure engine layer is covered by DUnitX tests that need **no radio**:

1. Open `tests\WiFiAnalyzerTests.dpr`.
2. Build as a **Win64** console app and run.

They validate channel↔frequency maths, overlap detection, the recommendation
engine and the fake WLAN client.

## Project layout

```
WiFiAnalyzer.dpr / .dproj     Application project
src/api/                      WLAN types + IWlanClient wrapper (native + fake)
src/models/                   Domain models (TAccessPoint, TScanSnapshot, enums)
src/engine/                   Channel maths + RF analysis engine
src/services/                 Scanner thread, OUI lookup, logger, history, export
src/viewmodels/               Main view-model (filter/sort/metrics)
src/ui/                       Main form + Channels (spectrum/heatmap) + Signal frames
src/util/                     Formatting + INI settings
resources/                    Manifest, OUI database
docs/                         Architecture, class diagram, UI mockups
tests/                        DUnitX engine tests
```

## Roadmap

| Phase | Content |
|-------|---------|
| **1** ✅ | Foundation: WLAN wrapper, models, engine, scanner, view-model, live grid |
| **2** ✅ | Channel Analysis tab: congestion/overlap/interference + spectrum + heatmap |
| **3** ✅ | Signal Visualization: live RSSI graph, history, gauges, snapshot comparison |
| **4** ✅ | Grid polish: multi-sort, grouping, CSV/Excel export, copy rows |
| 5 | Dashboard cards + animated gauges, full theming, High-DPI/multi-monitor, notifications |

All charts, gauges and heatmaps are custom-drawn on `TCanvas`/GDI+ — no chart
libraries, no copyleft dependencies.

## License

[MIT](LICENSE).

## Notes / known limitations (Phase 1)

- **Channel width** is shown as blank until HT/VHT/HE information-element
  parsing lands (Phase 2); the WLAN BSS entry does not expose width directly.
- The bundled `oui.txt` is a small starter subset; drop in the full public
  IEEE OUI registry for complete vendor coverage.
- The WLAN struct translations in `WiFi.Api.WlanTypes` are laid out for the
  documented SDK alignment; if you extend them, keep `{$ALIGN 8}` and match the
  header field order exactly.
