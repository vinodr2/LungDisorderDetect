// Options page: render every setting as a labelled toggle and persist changes.

import { DEFAULT_SETTINGS, type Settings } from "../utils/types.js";
import { loadSettings, saveSettings } from "../utils/settings.js";

interface FieldDef {
  key: keyof Settings;
  label: string;
  desc: string;
  group: string;
}

const FIELDS: FieldDef[] = [
  { key: "alwaysShowCc", label: "Always show CC", desc: "Reveal the CC field on every reply.", group: "Headers" },
  { key: "alwaysShowBcc", label: "Always show BCC", desc: "Reveal the BCC field on every reply.", group: "Headers" },
  { key: "alwaysShowSubject", label: "Always show Subject", desc: "Keep the subject line visible and editable.", group: "Headers" },
  { key: "autoConvertToReplyAll", label: "Auto Reply All", desc: "Automatically include all recipients on every reply.", group: "Recipients" },
  { key: "enableAttachmentPicker", label: "Attachment picker", desc: "Show the “Attach from original email” toolbar button.", group: "Attachments" },
  { key: "enableAttachmentAssistant", label: "Attachment assistant", desc: "Warn when you mention an attachment but haven’t added one.", group: "Attachments" },
  { key: "enableComposeStats", label: "Compose statistics", desc: "Character / word count, reading time, and a compose timer.", group: "Compose" },
  { key: "showReplyInfoPanel", label: "Reply information panel", desc: "Expandable summary of the original message.", group: "Compose" },
  { key: "enableKeyboardShortcuts", label: "Keyboard shortcuts", desc: "Ctrl+Shift+R / A / H / S actions inside a reply.", group: "General" },
  { key: "rememberWindowSize", label: "Remember window size", desc: "Restore the last compose window size.", group: "General" },
];

const statusEl = document.getElementById("status") as HTMLElement;

function flash(text: string): void {
  statusEl.textContent = text;
  statusEl.classList.add("show");
  window.setTimeout(() => statusEl.classList.remove("show"), 1400);
}

function render(settings: Settings): void {
  const root = document.getElementById("settings") as HTMLElement;
  root.replaceChildren();

  const groups = [...new Set(FIELDS.map((f) => f.group))];
  for (const group of groups) {
    const section = document.createElement("section");
    section.className = "group";
    const h = document.createElement("h2");
    h.textContent = group;
    section.appendChild(h);

    for (const field of FIELDS.filter((f) => f.group === group)) {
      const row = document.createElement("label");
      row.className = "row";

      const meta = document.createElement("div");
      meta.className = "meta";
      const label = document.createElement("span");
      label.className = "label";
      label.textContent = field.label;
      const desc = document.createElement("span");
      desc.className = "desc";
      desc.textContent = field.desc;
      meta.append(label, desc);

      const toggle = document.createElement("input");
      toggle.type = "checkbox";
      toggle.className = "switch";
      toggle.checked = Boolean(settings[field.key]);
      toggle.addEventListener("change", async () => {
        settings = { ...settings, [field.key]: toggle.checked };
        await saveSettings(settings);
        flash("Saved");
      });

      row.append(meta, toggle);
      section.appendChild(row);
    }
    root.appendChild(section);
  }
}

async function init(): Promise<void> {
  const settings = await loadSettings();
  render(settings);

  document.getElementById("reset")?.addEventListener("click", async () => {
    await saveSettings({ ...DEFAULT_SETTINGS });
    render({ ...DEFAULT_SETTINGS });
    flash("Reset to defaults");
  });
}

void init();
