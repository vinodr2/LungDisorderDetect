// Content script entry point.
//
// Responsibilities:
//   • load settings and keep them in sync,
//   • watch Gmail (a SPA) for compose/reply windows via a single reused
//     MutationObserver — never poll,
//   • enhance each new compose exactly once,
//   • wire keyboard shortcuts + original-attachment gestures,
//   • tear down cleanly when composes/threads are removed.

import { debounce } from "../utils/dom.js";
import { findComposeDialogs } from "../utils/gmail-dom.js";
import { loadSettings, onSettingsChanged } from "../utils/settings.js";
import { log } from "../utils/logger.js";
import type { RuntimeMessage, Settings } from "../utils/types.js";
import { enhanceCompose, teardownRemoved, handleCommand } from "./compose-manager.js";
import { registerKeyboard, setKeyboardEnabled } from "./keyboard.js";
import { installOriginalAttachmentGestures } from "./original-attachments.js";

let settings: Settings;

/** Scan for compose windows and enhance any new ones. Debounced by the caller. */
function scan(): void {
  try {
    for (const dialog of findComposeDialogs()) enhanceCompose(dialog, settings);
    teardownRemoved();
  } catch (err) {
    log.error("scan failed", err);
  }
}

const scheduleScan = debounce(scan, 120);

function startObserver(): void {
  const target = document.querySelector<HTMLElement>('[role="main"]') || document.body;
  const observer = new MutationObserver(() => scheduleScan());
  observer.observe(document.body, { childList: true, subtree: true });
  log.debug("observer attached to", target.getAttribute("role") || "body");
  // Initial pass in case a compose is already open (e.g. extension reload).
  scheduleScan();
}

function wireMessaging(): void {
  chrome.runtime.onMessage.addListener((message: RuntimeMessage) => {
    if (message.type === "COMMAND") {
      handleCommand(message.command);
    } else if (message.type === "SETTINGS_CHANGED") {
      settings = message.settings;
      setKeyboardEnabled(settings.enableKeyboardShortcuts);
    }
  });
}

async function main(): Promise<void> {
  settings = await loadSettings();

  registerKeyboard((command) => handleCommand(command));
  setKeyboardEnabled(settings.enableKeyboardShortcuts);

  installOriginalAttachmentGestures();
  wireMessaging();

  onSettingsChanged((next) => {
    settings = next;
    setKeyboardEnabled(settings.enableKeyboardShortcuts);
  });

  // Gmail hash-route changes swap the whole reading pane; rescan on navigation.
  window.addEventListener("hashchange", () => scheduleScan());

  startObserver();
  log.info("ready");
}

void main();
