# WiFiAnalyzer — UI Mockups

## Phase 1 — Networks view (implemented)

```
┌ Wi-Fi Analyzer ─────────────────────────────────────────────────────────────┐
│  Search:[ SSID, BSSID or vendor ]   Band:[All ▼]  Interval:[5 s ▼] [Rescan]  │
│                                                              [x] Dark mode    │
├──────────────────────────────────────────────────────────────────────────────┤
│ SSID          │ BSSID          │ Vendor  │Ch│Band │Width│Freq│ RSSI     │Q  │… │
│ HomeNet    ●  │ AA:BB:CC:11:22 │ Netgear │ 6│2.4  │     │2437│ -48 ▇▇▇▇ │92%│  │
│ Office-5G     │ 6C:41:88:AA:BB │ Cisco   │36│5    │     │5180│ -61 ▇▇▇  │78%│  │
│ <hidden>      │ 78:8A:20:00:0F │ Ubiquiti│44│5    │     │5220│ -74 ▇▇   │52%│  │
│ Guest         │ 50:C7:BF:33:44 │ TP-Link │11│2.4  │     │2462│ -83 ▇    │34%│  │
│  … sortable by any column header (click to sort, click again to reverse) …    │
├──────────────────────────────────────────────────────────────────────────────┤
│ 23 networks • 23 shown • adapter: Intel(R) Wi-Fi 6E AX211 • last scan 12:04:31│
└──────────────────────────────────────────────────────────────────────────────┘
```

- The connected network is marked with a dot and a tinted row.
- The RSSI column draws a colour-graded strength bar (green→red).
- Search filters SSID/BSSID/vendor; the band combo filters by band.

## Later phases (planned)

**Dashboard cards row** (Phase 5) across the top:
```
┌ Connected ┐ ┌ Networks ┐ ┌ Strongest ┐ ┌ Congested ch ┐ ┌ Best ch ┐
│ HomeNet   │ │   23     │ │ -42 dBm   │ │ 2.4 GHz #6   │ │ 2.4 #11 │
│ 2.4 #6    │ │          │ │ HomeNet   │ │  (busy)      │ │ 5   #149│
└───────────┘ └──────────┘ └───────────┘ └──────────────┘ └─────────┘
```

**Tabs**: Networks | Channels | Signal | Dashboard
- **Channels** (Phase 2): per-band channel graph + congestion heatmap.
- **Signal** (Phase 3): live RSSI line graph, spectrum/overlap graph, gauges.
- **Dashboard** (Phase 5): summary cards, band/security distribution donuts.

All charts/gauges are custom-drawn on `TCanvas`/GDI+ — no chart libraries.
