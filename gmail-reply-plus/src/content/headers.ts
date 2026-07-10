// Feature 1: always show full header (To / CC / BCC / Subject), all editable.
// Also powers the Toggle CC / Toggle BCC / Expand / Collapse toolbar actions.

import { getComposeParts, findCcBccToggles } from "../utils/gmail-dom.js";
import type { Settings } from "../utils/types.js";

function isVisible(el: HTMLElement | null): boolean {
  return !!el && el.offsetParent !== null;
}

/** Reveal CC and/or BCC by clicking Gmail's own toggles when hidden. */
export function showCc(dialog: HTMLElement): void {
  if (isVisible(getComposeParts(dialog).cc)) return;
  findCcBccToggles(dialog).cc?.click();
}

export function showBcc(dialog: HTMLElement): void {
  if (isVisible(getComposeParts(dialog).bcc)) return;
  findCcBccToggles(dialog).bcc?.click();
}

/** Toggle helpers used by the toolbar buttons. */
export function toggleCc(dialog: HTMLElement): void {
  const cc = getComposeParts(dialog).cc;
  if (isVisible(cc)) {
    // Gmail keeps CC visible once opened; collapse is emulated by clearing +
    // hiding via its own control if present, else just focus away. Most users
    // expect toggle to reveal, so we only actively reveal here.
    findCcBccToggles(dialog).cc?.click();
  } else {
    showCc(dialog);
  }
}

export function toggleBcc(dialog: HTMLElement): void {
  const bcc = getComposeParts(dialog).bcc;
  if (isVisible(bcc)) findCcBccToggles(dialog).bcc?.click();
  else showBcc(dialog);
}

/** Expand: force CC + BCC + subject all visible (Feature 1 default state). */
export function expandHeaders(dialog: HTMLElement): void {
  showCc(dialog);
  showBcc(dialog);
  dialog.classList.remove("grp-headers-collapsed");
}

/** Collapse: hide the extra header rows we added emphasis to (visual only). */
export function collapseHeaders(dialog: HTMLElement): void {
  dialog.classList.add("grp-headers-collapsed");
}

/** Apply the always-show preferences when a compose first appears. */
export function applyHeaderPreferences(dialog: HTMLElement, settings: Settings): void {
  if (settings.alwaysShowCc) showCc(dialog);
  if (settings.alwaysShowBcc) showBcc(dialog);
  // Subject is always present in Gmail replies once the header is expanded;
  // ensuring CC/BCC are shown also reveals the subject row in inline replies.
  if (settings.alwaysShowSubject) {
    const subject = getComposeParts(dialog).subject;
    if (subject) subject.closest<HTMLElement>("tr, div")?.classList.add("grp-subject-shown");
  }
}
