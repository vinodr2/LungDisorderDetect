// Popup: quick toggles for the most-used settings + shortcuts reference.

import type { Settings } from "../utils/types.js";
import { loadSettings, saveSettings } from "../utils/settings.js";

const QUICK: Array<{ key: keyof Settings; label: string }> = [
  { key: "alwaysShowCc", label: "Always show CC" },
  { key: "alwaysShowBcc", label: "Always show BCC" },
  { key: "enableAttachmentPicker", label: "Attach from original" },
  { key: "enableAttachmentAssistant", label: "Attachment assistant" },
  { key: "enableComposeStats", label: "Compose statistics" },
  { key: "enableKeyboardShortcuts", label: "Keyboard shortcuts" },
];

function renderQuick(settings: Settings): void {
  const root = document.getElementById("quick") as HTMLElement;
  root.replaceChildren();
  for (const item of QUICK) {
    const row = document.createElement("label");
    row.className = "pop-row";
    const span = document.createElement("span");
    span.textContent = item.label;
    const toggle = document.createElement("input");
    toggle.type = "checkbox";
    toggle.className = "pop-switch";
    toggle.checked = Boolean(settings[item.key]);
    toggle.addEventListener("change", async () => {
      settings = { ...settings, [item.key]: toggle.checked };
      await saveSettings(settings);
    });
    row.append(span, toggle);
    root.appendChild(row);
  }
}

async function init(): Promise<void> {
  renderQuick(await loadSettings());

  document.getElementById("open-options")?.addEventListener("click", () => {
    chrome.runtime.openOptionsPage();
  });
  document.getElementById("open-shortcuts")?.addEventListener("click", () => {
    chrome.tabs.create({ url: "chrome://extensions/shortcuts" });
  });
}

void init();
