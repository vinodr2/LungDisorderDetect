# Gmail Reply+

Make Gmail replies feel like **Microsoft Outlook** — always-visible headers,
one-click Reply All, an Outlook-style recipient manager, and (the headline
feature) **re-attaching files from the original email with one click** — while
keeping Gmail's native threading and behaviour completely intact.

Everything runs **locally in your browser**. No servers, no APIs, no analytics,
no telemetry, no tracking. The only permission requested is `storage` (for your
settings) plus host access to `mail.google.com`.

---

## Features

| # | Feature | What it does |
|---|---------|--------------|
| 1 | **Always show full header** | To / CC / BCC / Subject are always visible and editable on every reply. |
| 2 | **Restore Reply All** | A **Convert → All** button re-adds every original recipient, de-duplicated, order preserved. |
| 3 | **Attach from original email** ⭐ | Pick any/all attachments from the original message and inject them into the reply — no download/re-upload. Also drag-in and double-click-to-attach. |
| 4 | **Reply toolbar** | Compact toolbar above the compose: Reply All, Sender only, Convert → All, Attach original, Attach all, CC, BCC, Subject, Expand, Collapse, Recipients. |
| 5 | **Subject editing** | Always shown; de-dupe `Re:`, convert `Re: → Fwd:`, clear prefixes, quick `FYI:` / `Action Required:`, with change highlighting. |
| 6 | **Recipient manager** | Count, duplicate detection, search, copy all, paste many, remove duplicates, sort A→Z. |
| 7 | **Compose stats** | Live character count, word count, estimated reading time, and a compose timer. |
| 8 | **Attachment assistant** | If you write "attached", "please find", etc. but haven't attached anything, a gentle nudge appears. |
| 9 | **Reply information** | Expandable panel: original sender, date, subject, recipient count, attachment count + names, thread ID. |
| 10 | **Keyboard shortcuts** | `Ctrl+Shift+R` Convert to Reply All · `Ctrl+Shift+A` Attach original · `Ctrl+Shift+H` Toggle headers · `Ctrl+Shift+S` Focus subject. |
| 11 | **Settings** | Popup + full options page; toggle every feature. |

Light + dark themes, compact density, responsive layout, and multiple
simultaneous compose windows are all supported.

---

## Install (Chrome Developer Mode — Load Unpacked)

You need [Node.js](https://nodejs.org) 18+ once, to build the extension.

```bash
cd gmail-reply-plus
npm install      # one-time: fetches esbuild + typescript
npm run build    # produces the loadable dist/ folder
```

Then in Chrome:

1. Open `chrome://extensions`.
2. Toggle **Developer mode** on (top-right).
3. Click **Load unpacked**.
4. Select the **`gmail-reply-plus/dist`** folder.
5. Open [Gmail](https://mail.google.com), open any email, and click **Reply**.
   The Reply+ toolbar appears above the compose box.

To update after changing the code, run `npm run build` again and click the
**↻ reload** icon on the extension card in `chrome://extensions`.

> Tip: `npm run watch` rebuilds automatically on save — just reload the
> extension card in Chrome after each change.

---

## Build

| Command | Purpose |
|---------|---------|
| `npm run build` | Production build → `dist/` (minified). |
| `npm run watch` | Rebuild on file change (inline sourcemaps, unminified). |
| `npm run typecheck` | Strict TypeScript check, no emit. |
| `npm run clean` | Remove `dist/`. |
| `node scripts/make-icons.mjs` | Regenerate the PNG icons (already committed). |

The build uses **esbuild** (sub-second) and bundles each entry point:

- `content.js` — the Gmail content script (IIFE; MV3 content scripts can't use
  native ES module `import`, so everything is bundled into one file).
- `service-worker.js` — the MV3 background module worker.
- `options.js`, `popup.js` — the settings surfaces.

Static assets (`manifest.json`, `content.css`, the HTML/CSS for options + popup,
and `icons/`) are copied into `dist/` as-is.

---

## Project structure

```
gmail-reply-plus/
├── manifest.json            # Manifest V3
├── build.mjs                # esbuild build (bundle + copy static assets)
├── tsconfig.json            # strict TypeScript config
├── package.json
├── icons/                   # 16 / 48 / 128 px PNGs (generated, committed)
├── scripts/
│   └── make-icons.mjs       # dependency-free PNG icon generator
└── src/
    ├── background/
    │   └── service-worker.ts # seeds settings, forwards keyboard commands
    ├── content/
    │   ├── index.ts              # entry: observer, settings, wiring
    │   ├── compose-manager.ts    # per-compose orchestrator
    │   ├── toolbar.ts            # Feature 4 toolbar
    │   ├── attachments.ts        # Feature 3 fetch + inject + picker
    │   ├── original-attachments.ts # drag-in / double-click gestures
    │   ├── recipients.ts         # Features 2 & 6 logic
    │   ├── recipient-manager.ts  # Feature 6 modal
    │   ├── subject.ts            # Feature 5
    │   ├── headers.ts            # Feature 1
    │   ├── stats.ts             # Feature 7
    │   ├── reply-info.ts        # Feature 9
    │   ├── attachment-assistant.ts # Feature 8
    │   ├── keyboard.ts          # Feature 10
    │   └── toast.ts             # non-blocking notifications
    ├── options/                 # Feature 11 full settings page
    ├── popup/                   # quick toggles + shortcut reference
    ├── styles/
    │   └── content.css          # in-Gmail UI (light/dark/compact)
    └── utils/
        ├── gmail-dom.ts         # all Gmail-specific DOM knowledge
        ├── dom.ts               # generic DOM helpers (no jQuery)
        ├── settings.ts          # chrome.storage load/save/subscribe
        ├── logger.ts
        └── types.ts             # shared types + default settings
```

---

## How "Attach from original email" works (the hard part)

Gmail has **no public API** to re-attach an existing attachment, so Reply+ does
the most seamless thing a Chrome extension realistically can:

1. **Discover** each attachment on the original message. Gmail places a
   `download_url` attribute (`"<mime>:<filename>:<url>"`) on attachment
   download controls; Reply+ parses it, with an anchor-`href` fallback.
2. **Fetch** the bytes with a **credentialed same-origin `fetch`**. Because the
   content script runs on `mail.google.com`, the request carries your session
   cookie and returns the real file — no separate download.
3. **Inject** the file into the reply by reproducing the exact gesture a user
   makes when dragging a file in: a `File` on a `DataTransfer`, dispatched as
   `dragenter → dragover → drop` on the compose body, with an
   `input[type=file]` assignment as a fallback. Gmail's own uploader handles it.

If a fetch is ever blocked (rare — e.g. an unusual network policy), Reply+ tells
you clearly and opens Gmail's native paperclip so you're never stuck.

Because this relies on Gmail's private DOM, a future Gmail redesign can change
the selectors. The code is written defensively (semantic attributes first, class
names only as fallback, null-safe everywhere) so it degrades gracefully rather
than breaking Gmail — see **Troubleshooting**.

---

## Settings

Open settings from the toolbar popup (**All settings**) or
`chrome://extensions` → Gmail Reply+ → **Details** → **Extension options**.

Every feature can be toggled: always-show CC/BCC/Subject, auto Reply All,
attachment picker, attachment assistant, compose statistics, reply-info panel,
keyboard shortcuts, and remember-window-size. Settings sync via
`chrome.storage.sync` (with a `local` fallback) and apply to new composes
immediately.

---

## Privacy & security

- 100% local. No network requests except fetching **your own** attachments from
  Gmail's own servers (same origin, same session you're already logged into).
- No analytics, telemetry, tracking, or third-party code.
- Minimum permissions: `storage` + `https://mail.google.com/*`.
- No remote code; the service worker and content script are fully bundled.

---

## Troubleshooting

**The toolbar doesn't appear.**
Reload Gmail after loading/updating the extension. Confirm the extension is
enabled and has no errors on its `chrome://extensions` card. Make sure you're on
`https://mail.google.com` (not the classic/basic HTML Gmail, which is
unsupported).

**"Attach from original" says it couldn't fetch a file.**
This usually means Gmail changed an attachment's markup or a network policy
blocked the download. Reply+ falls back to opening Gmail's paperclip. Please
open an issue with the Gmail language/layout you're using.

**A button does nothing / selectors seem stale.**
Gmail ships frequent DOM changes. Turn on debug logging by setting `DEBUG = true`
in `src/utils/logger.ts`, rebuild, and check the DevTools console (filter for
`[Gmail Reply+]`) to see which lookup returned null. The Gmail-specific
selectors are centralised in `src/utils/gmail-dom.ts` for quick patching.

**Keyboard shortcut doesn't fire.**
Some combinations (notably `Ctrl+Shift+R`, a browser hard-reload) are reserved
by Chrome and can win before the page sees them. Rebind them at
`chrome://extensions/shortcuts` (the popup's **Rebind shortcuts** link).

**Recipients didn't get added as chips.**
Reply+ types into Gmail's own recipient input and presses Enter to tokenize.
If Gmail changed that input, it falls back to writing the hidden field. Reopen
the compose and retry; report the Gmail version if it persists.

---

## License

MIT — personal use. Not affiliated with Google or Microsoft.
