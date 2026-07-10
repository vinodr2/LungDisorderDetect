// Feature 3 (highest priority): re-attach files from the original email into
// the reply, Outlook-style, with no manual download/re-upload round trip.
//
// STRATEGY
// --------
// Gmail exposes each attachment's download URL on the same origin
// (mail.google.com) and it honours the logged-in session cookie. Because the
// content script runs on mail.google.com, a credentialed `fetch` returns the
// real bytes. We then hand those bytes to Gmail's own compose uploader by
// simulating the exact gesture a user makes when dragging a file in:
//
//   1. Wrap the fetched Blob in a `File`.
//   2. Put the File on a `DataTransfer`.
//   3. Dispatch dragenter → dragover → drop on the compose body, and, as a
//      fallback, assign `input.files` on the compose file input + fire change.
//
// Gmail's compose listens for both gestures, so one of them lands the upload.
// If the network fetch is blocked (rare — e.g. an unusual CSP), we surface a
// clear message and offer the native attach dialog instead of failing silently.

import { el, formatBytes } from "../utils/dom.js";
import { getComposeParts, findNativeAttachButton } from "../utils/gmail-dom.js";
import { log } from "../utils/logger.js";
import type { OriginalAttachment } from "../utils/types.js";

/** Fetch a single attachment's bytes as a File, using the session cookie. */
export async function fetchAttachmentFile(att: OriginalAttachment): Promise<File> {
  if (!att.downloadUrl) throw new Error(`No download URL for ${att.filename}`);
  const res = await fetch(att.downloadUrl, { credentials: "include" });
  if (!res.ok) throw new Error(`Download failed (${res.status}) for ${att.filename}`);
  const blob = await res.blob();
  const type = blob.type && blob.type !== "text/html" ? blob.type : att.mimeType;
  return new File([blob], att.filename, { type });
}

/**
 * Inject already-fetched Files into a compose dialog. Returns true if a target
 * (drop zone or file input) was found and the gesture was dispatched.
 */
export function injectFiles(dialog: HTMLElement, files: File[]): boolean {
  if (files.length === 0) return false;
  const parts = getComposeParts(dialog);

  const dt = new DataTransfer();
  for (const f of files) dt.items.add(f);

  // Primary path: simulate a drag-and-drop onto the compose body.
  const dropTarget = parts.body || dialog;
  if (dropTarget) {
    const base = { bubbles: true, cancelable: true, composed: true } as const;
    dropTarget.dispatchEvent(new DragEvent("dragenter", { ...base, dataTransfer: dt }));
    dropTarget.dispatchEvent(new DragEvent("dragover", { ...base, dataTransfer: dt }));
    dropTarget.dispatchEvent(new DragEvent("drop", { ...base, dataTransfer: dt }));
  }

  // Fallback path: hand the files straight to Gmail's hidden upload input.
  if (parts.fileInput) {
    try {
      parts.fileInput.files = dt.files;
      parts.fileInput.dispatchEvent(new Event("change", { bubbles: true }));
    } catch (err) {
      log.warn("file input assignment failed", err);
    }
  }

  return Boolean(parts.body || parts.fileInput);
}

/** High-level: fetch selected attachments and inject them, reporting progress. */
export async function attachOriginals(
  dialog: HTMLElement,
  attachments: OriginalAttachment[],
  onProgress?: (done: number, total: number, label: string) => void,
): Promise<{ attached: File[]; failed: OriginalAttachment[] }> {
  const attached: File[] = [];
  const failed: OriginalAttachment[] = [];

  let done = 0;
  for (const att of attachments) {
    onProgress?.(done, attachments.length, att.filename);
    try {
      attached.push(await fetchAttachmentFile(att));
    } catch (err) {
      log.warn("attachment fetch failed", att.filename, err);
      failed.push(att);
    }
    done += 1;
  }
  onProgress?.(done, attachments.length, "");

  if (attached.length > 0) {
    const ok = injectFiles(dialog, attached);
    if (!ok) {
      // No drop target found — open Gmail's native attach dialog as a courtesy.
      findNativeAttachButton(dialog)?.click();
    }
  }
  return { attached, failed };
}

// ---------------------------------------------------------------------------
// Attachment picker UI (checkbox list + Select All)
// ---------------------------------------------------------------------------

const ICON_BY_EXT: Record<string, string> = {
  pdf: "📄", doc: "📝", docx: "📝", xls: "📊", xlsx: "📊", csv: "📊",
  ppt: "📽️", pptx: "📽️", zip: "🗜️", rar: "🗜️", "7z": "🗜️",
  png: "🖼️", jpg: "🖼️", jpeg: "🖼️", gif: "🖼️", svg: "🖼️", webp: "🖼️",
  mp4: "🎞️", mov: "🎞️", mp3: "🎵", wav: "🎵", txt: "📃", eml: "✉️",
};

function iconFor(filename: string): string {
  const ext = filename.split(".").pop()?.toLowerCase() || "";
  return ICON_BY_EXT[ext] || "📎";
}

function sizeText(att: OriginalAttachment): string {
  if (att.sizeBytes != null) return formatBytes(att.sizeBytes);
  return att.sizeLabel || "";
}

export interface PickerCallbacks {
  onConfirm: (selected: OriginalAttachment[]) => void;
  onCancel?: () => void;
}

/** Build and show a modal picker listing the original attachments. */
export function openAttachmentPicker(
  attachments: OriginalAttachment[],
  cb: PickerCallbacks,
): void {
  const existing = document.querySelector(".grp-modal-overlay");
  if (existing) existing.remove();

  const checkboxes: HTMLInputElement[] = [];

  const rows = attachments.map((att, i) => {
    const checkbox = el("input", { attrs: { type: "checkbox", id: `grp-att-${i}` } });
    checkboxes.push(checkbox);
    return el("label", {
      className: "grp-att-row",
      attrs: { for: `grp-att-${i}` },
      children: [
        checkbox,
        el("span", { className: "grp-att-icon", text: iconFor(att.filename) }),
        el("span", {
          className: "grp-att-meta",
          children: [
            el("span", { className: "grp-att-name", text: att.filename, title: att.filename }),
            el("span", {
              className: "grp-att-sub",
              text: [sizeText(att), att.downloadUrl ? "" : "no direct link"]
                .filter(Boolean)
                .join(" · "),
            }),
          ],
        }),
      ],
    });
  });

  const selectAll = el("input", { attrs: { type: "checkbox", id: "grp-att-all" } });
  selectAll.addEventListener("change", () => {
    for (const c of checkboxes) c.checked = selectAll.checked;
  });

  const status = el("div", { className: "grp-modal-status" });

  const attachBtn = el("button", {
    className: "grp-btn grp-btn-primary",
    text: "Attach selected",
  }) as HTMLButtonElement;

  const cancelBtn = el("button", { className: "grp-btn", text: "Cancel" });

  const overlay = el("div", {
    className: "grp-modal-overlay",
    children: [
      el("div", {
        className: "grp-modal",
        attrs: { role: "dialog", "aria-label": "Attach from original email" },
        children: [
          el("div", {
            className: "grp-modal-head",
            children: [
              el("span", { className: "grp-modal-title", text: "Attach from original email" }),
              el("button", {
                className: "grp-modal-close",
                text: "✕",
                title: "Close",
                on: { click: () => close(true) },
              }),
            ],
          }),
          el("label", {
            className: "grp-att-row grp-att-all",
            attrs: { for: "grp-att-all" },
            children: [selectAll, el("span", { className: "grp-att-name", text: "Select all" })],
          }),
          el("div", { className: "grp-att-list", children: rows }),
          status,
          el("div", {
            className: "grp-modal-actions",
            children: [cancelBtn, attachBtn],
          }),
        ],
      }),
    ],
  });

  function close(cancelled: boolean): void {
    overlay.remove();
    document.removeEventListener("keydown", onKey);
    if (cancelled) cb.onCancel?.();
  }

  function onKey(e: KeyboardEvent): void {
    if (e.key === "Escape") close(true);
  }

  cancelBtn.addEventListener("click", () => close(true));
  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) close(true);
  });
  document.addEventListener("keydown", onKey);

  attachBtn.addEventListener("click", () => {
    const selected = attachments.filter((_, i) => checkboxes[i].checked);
    if (selected.length === 0) {
      status.textContent = "Select at least one file.";
      status.classList.add("grp-status-warn");
      return;
    }
    attachBtn.disabled = true;
    cancelBtn.setAttribute("disabled", "true");
    status.classList.remove("grp-status-warn");
    status.textContent = "Fetching…";
    // Defer the heavy work so the button state paints first.
    setTimeout(() => {
      close(false);
      cb.onConfirm(selected);
    }, 0);
  });

  document.body.appendChild(overlay);
}
