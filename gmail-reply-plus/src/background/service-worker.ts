// Background service worker (MV3, module type).
//
// It does very little on purpose — everything meaningful happens locally in the
// content script. Its only jobs are seeding default settings and forwarding the
// browser-level keyboard commands to the Gmail tab (needed for shortcuts the
// page itself cannot intercept, e.g. Ctrl+Shift+R).

import { DEFAULT_SETTINGS } from "../utils/types.js";
import type { KeyCommand, RuntimeMessage } from "../utils/types.js";

chrome.runtime.onInstalled.addListener(async () => {
  const existing = await chrome.storage.sync.get("settings");
  if (!existing.settings) {
    await chrome.storage.sync.set({ settings: DEFAULT_SETTINGS });
  }
});

chrome.commands.onCommand.addListener(async (command) => {
  const known: KeyCommand[] = [
    "convert-to-reply-all",
    "attach-original-files",
    "toggle-headers",
    "focus-subject",
  ];
  if (!known.includes(command as KeyCommand)) return;

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id || !tab.url?.startsWith("https://mail.google.com/")) return;

  const message: RuntimeMessage = { type: "COMMAND", command: command as KeyCommand };
  try {
    await chrome.tabs.sendMessage(tab.id, message);
  } catch {
    // No content script on this tab yet — safe to ignore.
  }
});
