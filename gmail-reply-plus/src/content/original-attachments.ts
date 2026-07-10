// Feature 3 extras: double-click an original attachment to attach it, and drag
// an original attachment straight into the reply. Uses event delegation so it
// works for attachments that render lazily as the user scrolls the thread.

import { extractAttachments } from "../utils/gmail-dom.js";
import { fetchAttachmentFile, injectFiles } from "./attachments.js";
import { getActiveDialog } from "./compose-manager.js";
import { showToast } from "./toast.js";
import type { OriginalAttachment } from "../utils/types.js";

const DND_MIME = "application/x-grp-attachment";

/** Resolve the attachment metadata for a clicked/dragged node, if any. */
function resolveAttachment(node: EventTarget | null): OriginalAttachment | null {
  if (!(node instanceof Element)) return null;
  const chip = node.closest<HTMLElement>("[download_url], .aZo, .aQH");
  if (!chip) return null;
  const found = extractAttachments(chip);
  return found[0] ?? null;
}

async function attachToActive(att: OriginalAttachment, dialog: HTMLElement | null): Promise<void> {
  const target = dialog ?? getActiveDialog();
  if (!target) {
    showToast("Open a reply first, then attach.", { kind: "error" });
    return;
  }
  const toast = showToast(`Fetching ${att.filename}…`, { timeout: 0 });
  try {
    const file = await fetchAttachmentFile(att);
    injectFiles(target, [file]);
    toast.update(`Attached ${att.filename}.`);
    window.setTimeout(() => toast.dismiss(), 3000);
  } catch {
    toast.dismiss();
    showToast(`Couldn't fetch ${att.filename}.`, { kind: "error" });
  }
}

/** Install the global delegated listeners once. */
export function installOriginalAttachmentGestures(): void {
  // Double-click to attach.
  document.addEventListener("dblclick", (e) => {
    const main = (e.target as Element | null)?.closest('[role="main"]');
    if (!main) return;
    const att = resolveAttachment(e.target);
    if (att?.downloadUrl) {
      e.preventDefault();
      void attachToActive(att, null);
    }
  });

  // Drag an original attachment; stash its id on the dataTransfer.
  document.addEventListener("dragstart", (e) => {
    const att = resolveAttachment(e.target);
    if (att?.downloadUrl && e.dataTransfer) {
      e.dataTransfer.setData(DND_MIME, JSON.stringify(att));
      e.dataTransfer.effectAllowed = "copy";
    }
  });

  // Allow dropping onto a compose body.
  document.addEventListener(
    "dragover",
    (e) => {
      if (!e.dataTransfer) return;
      if (Array.from(e.dataTransfer.types).includes(DND_MIME)) {
        const body = (e.target as Element | null)?.closest('[role="textbox"][contenteditable="true"]');
        if (body) {
          e.preventDefault();
          e.dataTransfer.dropEffect = "copy";
        }
      }
    },
    true,
  );

  document.addEventListener(
    "drop",
    (e) => {
      const raw = e.dataTransfer?.getData(DND_MIME);
      if (!raw) return;
      const bodyEl = (e.target as Element | null)?.closest<HTMLElement>(
        '[role="textbox"][contenteditable="true"]',
      );
      if (!bodyEl) return;
      e.preventDefault();
      e.stopPropagation();
      const dialog = bodyEl.closest<HTMLElement>('[role="dialog"]') || getActiveDialog();
      try {
        const att = JSON.parse(raw) as OriginalAttachment;
        void attachToActive(att, dialog);
      } catch {
        /* ignore malformed payloads */
      }
    },
    true,
  );
}
