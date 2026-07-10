// Per-compose orchestrator: mounts the Reply+ toolbar and every feature panel
// onto a single compose/reply window and wires the actions together.

import { el } from "../utils/dom.js";
import {
  getComposeParts,
  findSourceMessage,
  extractMessageInfo,
  getRecipientEmails,
} from "../utils/gmail-dom.js";
import { log } from "../utils/logger.js";
import type { OriginalMessageInfo, Settings, KeyCommand } from "../utils/types.js";
import { buildToolbar, type Toolbar } from "./toolbar.js";
import { mountStats, type StatsController } from "./stats.js";
import { mountAttachmentAssistant, type AssistantController } from "./attachment-assistant.js";
import { buildReplyInfoPanel } from "./reply-info.js";
import { openAttachmentPicker, attachOriginals } from "./attachments.js";
import { openRecipientManager } from "./recipient-manager.js";
import {
  convertToReplyAll,
  readChips,
  rewriteField,
  addRecipients,
  getAccountEmail,
} from "./recipients.js";
import {
  showCc,
  toggleCc,
  toggleBcc,
  expandHeaders,
  collapseHeaders,
  applyHeaderPreferences,
} from "./headers.js";
import { getSubject, setSubject, dedupePrefix, reToFw, stripPrefixes } from "./subject.js";
import { showToast } from "./toast.js";

const ENHANCED_ATTR = "data-grp-enhanced";

/** Everything we hang on an enhanced compose so we can tear it down cleanly. */
interface Enhanced {
  dialog: HTMLElement;
  info: OriginalMessageInfo;
  toolbar: Toolbar;
  stats: StatsController | null;
  assistant: AssistantController | null;
  container: HTMLElement;
  destroy(): void;
}

const registry = new WeakMap<HTMLElement, Enhanced>();
let activeDialog: HTMLElement | null = null;

export function getActiveDialog(): HTMLElement | null {
  if (activeDialog && document.body.contains(activeDialog)) return activeDialog;
  const first = document.querySelector<HTMLElement>(`[${ENHANCED_ATTR}]`);
  return first;
}

/** Enhance a compose dialog exactly once. */
export function enhanceCompose(dialog: HTMLElement, settings: Settings): void {
  if (dialog.getAttribute(ENHANCED_ATTR) === "true") return;
  const parts = getComposeParts(dialog);
  if (!parts.body && !parts.subject) return; // not a real compose yet
  dialog.setAttribute(ENHANCED_ATTR, "true");

  const source = findSourceMessage(dialog);
  const info: OriginalMessageInfo = source
    ? extractMessageInfo(source)
    : emptyInfo();
  const originalRecipients = source ? getRecipientEmails(source) : [];

  dialog.addEventListener("focusin", () => (activeDialog = dialog));
  activeDialog = dialog;

  const toolbar = buildToolbar({
    replyAll: () => doConvertToReplyAll(dialog, info, originalRecipients),
    replySenderOnly: () => doReplySenderOnly(dialog, info),
    convertToReplyAll: () => doConvertToReplyAll(dialog, info, originalRecipients),
    attachOriginal: () => doAttachOriginal(dialog, info),
    attachAll: () => doAttachAll(dialog, info),
    toggleCc: () => toggleCc(dialog),
    toggleBcc: () => toggleBcc(dialog),
    showSubject: () => {
      const s = getComposeParts(dialog).subject;
      s?.closest<HTMLElement>("tr, div")?.classList.add("grp-subject-shown");
      s?.focus();
    },
    expandHeaders: () => expandHeaders(dialog),
    collapseHeaders: () => collapseHeaders(dialog),
    recipientManager: () => openRecipientManager(dialog),
  });

  toolbar.setAttachmentCount(info.attachments.length);
  toolbar.setRecipientCount(readChips(parts.to).length);

  // Assemble the mounted UI: subject tools + toolbar + reply info + stats.
  const container = el("div", { className: "grp-container" });
  container.append(buildSubjectBar(dialog));
  container.append(toolbar.root);
  if (settings.showReplyInfoPanel && source) container.append(buildReplyInfoPanel(info));

  let stats: StatsController | null = null;
  if (settings.enableComposeStats) {
    stats = mountStats(dialog);
    toolbar.statsSlot.append(stats.root);
  }

  let assistant: AssistantController | null = null;
  if (settings.enableAttachmentAssistant) {
    assistant = mountAttachmentAssistant(dialog);
    container.append(assistant.root);
    const body = parts.body;
    body?.addEventListener("input", () => assistant?.check());
  }

  mountContainer(dialog, container);
  applyHeaderPreferences(dialog, settings);

  // Optionally auto-convert every reply into Reply All.
  if (settings.autoConvertToReplyAll && originalRecipients.length) {
    doConvertToReplyAll(dialog, info, originalRecipients, /*silent*/ true);
  }

  // Keep the recipient badge fresh as the user edits To.
  const to = parts.to;
  if (to) {
    const row = to.closest<HTMLElement>(".aoD, .anm, td, div") || to.parentElement;
    if (row) {
      const obs = new MutationObserver(() =>
        toolbar.setRecipientCount(readChips(getComposeParts(dialog).to).length),
      );
      obs.observe(row, { childList: true, subtree: true });
    }
  }

  const enhanced: Enhanced = {
    dialog,
    info,
    toolbar,
    stats,
    assistant,
    container,
    destroy(): void {
      stats?.destroy();
      assistant?.destroy();
      container.remove();
      registry.delete(dialog);
    },
  };
  registry.set(dialog, enhanced);
  log.debug("enhanced compose", { attachments: info.attachments.length });
}

/** Insert the toolbar container above the compose body / editor. */
function mountContainer(dialog: HTMLElement, container: HTMLElement): void {
  const parts = getComposeParts(dialog);
  const anchor =
    parts.body?.closest<HTMLElement>(".Am")?.parentElement ||
    parts.body?.parentElement ||
    parts.subject?.closest<HTMLElement>("tr, div")?.parentElement ||
    dialog;
  anchor.insertBefore(container, anchor.firstChild);
}

/** Subject quick-tools bar (Feature 5). */
function buildSubjectBar(dialog: HTMLElement): HTMLElement {
  const btn = (label: string, title: string, fn: () => void): HTMLElement =>
    el("button", {
      className: "grp-btn grp-btn-small",
      text: label,
      title,
      on: { click: fn },
    });

  return el("div", {
    className: "grp-subject-bar",
    children: [
      el("span", { className: "grp-subject-label", text: "Subject:" }),
      btn("Dedupe RE:", "Collapse repeated Re:/Fwd: prefixes", () =>
        setSubject(dialog, dedupePrefix(getSubject(dialog))),
      ),
      btn("RE → FW", "Convert reply subject to forward", () =>
        setSubject(dialog, reToFw(getSubject(dialog))),
      ),
      btn("Clear prefix", "Remove all Re:/Fwd: prefixes", () =>
        setSubject(dialog, stripPrefixes(getSubject(dialog))),
      ),
      btn("FYI", "Prefix subject with FYI:", () =>
        setSubject(dialog, prefixOnce(getSubject(dialog), "FYI")),
      ),
      btn("Action", "Prefix subject with Action Required:", () =>
        setSubject(dialog, prefixOnce(getSubject(dialog), "Action Required")),
      ),
    ],
  });
}

function prefixOnce(subject: string, prefix: string): string {
  if (subject.toLowerCase().startsWith(prefix.toLowerCase())) return subject;
  return `${prefix}: ${subject}`;
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

function doConvertToReplyAll(
  dialog: HTMLElement,
  info: OriginalMessageInfo,
  originalRecipients: string[],
  silent = false,
): void {
  const { addedTo } = convertToReplyAll(dialog, {
    senderEmail: info.senderEmail,
    toEmails: originalRecipients,
    ccEmails: [],
  });
  if (!silent) {
    showToast(
      addedTo > 0
        ? `Reply All: added ${addedTo} recipient${addedTo === 1 ? "" : "s"}.`
        : "Already replying to everyone.",
    );
  }
}

function doReplySenderOnly(dialog: HTMLElement, info: OriginalMessageInfo): void {
  const sender = info.senderEmail;
  if (!sender) {
    showToast("Couldn't determine the original sender.", { kind: "error" });
    return;
  }
  rewriteField(dialog, "to", [sender]);
  // Clear cc/bcc extras.
  const parts = getComposeParts(dialog);
  if (parts.cc && readChips(parts.cc).length) rewriteField(dialog, "cc", []);
  if (parts.bcc && readChips(parts.bcc).length) rewriteField(dialog, "bcc", []);
  showToast("Now replying to the sender only.");
}

async function doAttachOriginal(dialog: HTMLElement, info: OriginalMessageInfo): Promise<void> {
  if (info.attachments.length === 0) {
    showToast("The original email has no attachments.", { kind: "error" });
    return;
  }
  openAttachmentPicker(info.attachments, {
    onConfirm: async (selected) => {
      const toast = showToast(`Fetching ${selected.length} file(s)…`, { timeout: 0 });
      const { attached, failed } = await attachOriginals(dialog, selected, (done, total, label) =>
        toast.update(label ? `Fetching ${done + 1}/${total}: ${label}` : `Attaching ${total} file(s)…`),
      );
      finishAttach(toast, attached.length, failed.length);
    },
  });
}

async function doAttachAll(dialog: HTMLElement, info: OriginalMessageInfo): Promise<void> {
  if (info.attachments.length === 0) {
    showToast("The original email has no attachments.", { kind: "error" });
    return;
  }
  const toast = showToast(`Fetching ${info.attachments.length} file(s)…`, { timeout: 0 });
  const { attached, failed } = await attachOriginals(dialog, info.attachments, (done, total, label) =>
    toast.update(label ? `Fetching ${done + 1}/${total}: ${label}` : `Attaching…`),
  );
  finishAttach(toast, attached.length, failed.length);
}

function finishAttach(toast: ReturnType<typeof showToast>, ok: number, failed: number): void {
  if (ok > 0 && failed === 0) {
    toast.update(`Attached ${ok} file${ok === 1 ? "" : "s"} to your reply.`);
  } else if (ok > 0) {
    toast.update(`Attached ${ok}; ${failed} could not be fetched.`);
  } else {
    toast.dismiss();
    showToast(
      "Couldn't fetch the attachment(s). Use Gmail's paperclip to attach manually.",
      { kind: "error", timeout: 6000 },
    );
    return;
  }
  window.setTimeout(() => toast.dismiss(), 3500);
}

/** Route a keyboard command to the active compose. */
export function handleCommand(command: KeyCommand): void {
  const dialog = getActiveDialog();
  if (!dialog) return;
  const enhanced = registry.get(dialog);
  switch (command) {
    case "convert-to-reply-all":
      if (enhanced) doConvertToReplyAll(dialog, enhanced.info, getRecipientEmailsSafe(dialog));
      break;
    case "attach-original-files":
      if (enhanced) void doAttachOriginal(dialog, enhanced.info);
      break;
    case "toggle-headers":
      expandHeaders(dialog);
      break;
    case "focus-subject": {
      const s = getComposeParts(dialog).subject;
      s?.closest<HTMLElement>("tr, div")?.classList.add("grp-subject-shown");
      s?.focus();
      break;
    }
  }
}

function getRecipientEmailsSafe(dialog: HTMLElement): string[] {
  const source = findSourceMessage(dialog);
  return source ? getRecipientEmails(source) : [];
}

/** Drop an already-open compose's enhancement when it's removed from the DOM. */
export function teardownRemoved(): void {
  for (const node of document.querySelectorAll<HTMLElement>(`[${ENHANCED_ATTR}]`)) {
    if (!document.body.contains(node)) registry.get(node)?.destroy();
  }
}

function emptyInfo(): OriginalMessageInfo {
  return {
    sender: "",
    senderEmail: "",
    date: "",
    subject: "",
    recipientCount: 0,
    attachments: [],
    threadId: null,
  };
}

/** Attach files by dropping them onto the active/most-recent compose. */
export async function attachFilesToActive(files: File[]): Promise<boolean> {
  const dialog = getActiveDialog();
  if (!dialog) return false;
  const { injectFiles } = await import("./attachments.js");
  return injectFiles(dialog, files);
}

// Re-export a couple of helpers the entry point uses.
export { getAccountEmail, addRecipients, showCc };
