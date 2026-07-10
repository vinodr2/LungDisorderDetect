// Features 2 & 6: Restore Reply All, and the Outlook-style recipient manager.

import { qs, qsa } from "../utils/dom.js";
import { getComposeParts, findCcBccToggles } from "../utils/gmail-dom.js";
import { log } from "../utils/logger.js";

const EMAIL_RE = /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/gi;

/** The address currently signed in, parsed from the Gmail account chip. */
export function getAccountEmail(): string | null {
  const chip = qs<HTMLElement>(document, 'a[aria-label*="Google Account" i], a[href*="SignOutOptions"]');
  const label = chip?.getAttribute("aria-label") || "";
  const m = label.match(EMAIL_RE);
  return m ? m[0].toLowerCase() : null;
}

/** Read the email chips already present in a recipient field. */
export function readChips(field: HTMLTextAreaElement | null): string[] {
  if (!field) return [];
  const row = field.closest<HTMLElement>(".aoD, .anm, tr, div") || field.parentElement;
  if (!row) return [];
  const chips = qsa<HTMLElement>(row, "span[email], div[email]")
    .map((c) => c.getAttribute("email")!.trim())
    .filter(Boolean);
  // De-dupe while preserving order.
  const seen = new Set<string>();
  const out: string[] = [];
  for (const c of chips) {
    const key = c.toLowerCase();
    if (!seen.has(key)) {
      seen.add(key);
      out.push(c);
    }
  }
  return out;
}

/** Find the visible text input Gmail uses for typing into a recipient field. */
function visibleInput(field: HTMLTextAreaElement): HTMLInputElement | null {
  const row = field.closest<HTMLElement>(".aoD, .anm, td, div") || field.parentElement;
  if (!row) return null;
  return (
    qs<HTMLInputElement>(row, "input.agP") ||
    qs<HTMLInputElement>(row, 'input[type="text"]:not([readonly])') ||
    qs<HTMLInputElement>(row, "input")
  );
}

/**
 * Add emails to a recipient field as chips, skipping duplicates and preserving
 * order. Types into Gmail's own input and presses Enter so Gmail tokenizes each
 * address into a native chip (keeps validation + avatar behaviour intact).
 */
export function addRecipients(field: HTMLTextAreaElement | null, emails: string[]): number {
  if (!field || emails.length === 0) return 0;
  const existing = new Set(readChips(field).map((e) => e.toLowerCase()));
  const toAdd = emails.filter((e) => e && !existing.has(e.toLowerCase()));
  if (toAdd.length === 0) return 0;

  const input = visibleInput(field);
  if (!input) {
    // Last-resort fallback: append to the hidden textarea value.
    const current = field.value ? field.value.replace(/\s*$/, "") : "";
    field.value = [current, toAdd.join(", ")].filter(Boolean).join(current ? ", " : "");
    field.dispatchEvent(new Event("input", { bubbles: true }));
    field.dispatchEvent(new Event("change", { bubbles: true }));
    return toAdd.length;
  }

  input.focus();
  for (const email of toAdd) {
    setNativeValue(input, email);
    input.dispatchEvent(new Event("input", { bubbles: true }));
    // Enter tokenizes the typed address into a chip.
    for (const type of ["keydown", "keyup"] as const) {
      input.dispatchEvent(
        new KeyboardEvent(type, { key: "Enter", code: "Enter", keyCode: 13, bubbles: true }),
      );
    }
    input.dispatchEvent(new Event("blur", { bubbles: true }));
  }
  return toAdd.length;
}

/** Assign a value in a way React/Closure-style inputs actually observe. */
function setNativeValue(input: HTMLInputElement, value: string): void {
  const proto = Object.getPrototypeOf(input);
  const desc = Object.getOwnPropertyDescriptor(proto, "value");
  if (desc?.set) desc.set.call(input, value);
  else input.value = value;
}

/** Ensure the CC field is revealed (used before adding CC recipients). */
export function ensureCcVisible(dialog: HTMLElement): void {
  const parts = getComposeParts(dialog);
  if (parts.cc && parts.cc.offsetParent !== null) return;
  findCcBccToggles(dialog).cc?.click();
}

export function ensureBccVisible(dialog: HTMLElement): void {
  const parts = getComposeParts(dialog);
  if (parts.bcc && parts.bcc.offsetParent !== null) return;
  findCcBccToggles(dialog).bcc?.click();
}

/**
 * Feature 2: Convert a sender-only reply into Reply All by restoring the
 * original recipients (original From + To + Cc) minus the signed-in user and
 * anyone already present. Preserves order and prevents duplicates.
 */
export function convertToReplyAll(
  dialog: HTMLElement,
  original: { senderEmail: string; toEmails: string[]; ccEmails: string[] },
): { addedTo: number; addedCc: number } {
  const parts = getComposeParts(dialog);
  const self = getAccountEmail();
  const currentTo = new Set(readChips(parts.to).map((e) => e.toLowerCase()));

  const skip = (e: string): boolean =>
    !e || (self != null && e.toLowerCase() === self) || currentTo.has(e.toLowerCase());

  // The original sender + original To recipients belong in To.
  const toTargets = [original.senderEmail, ...original.toEmails].filter((e) => !skip(e));
  const addedTo = addRecipients(parts.to, toTargets);

  // Original Cc recipients belong in Cc.
  let addedCc = 0;
  const ccTargets = original.ccEmails.filter((e) => !skip(e));
  if (ccTargets.length) {
    ensureCcVisible(dialog);
    const cc = getComposeParts(dialog).cc;
    addedCc = addRecipients(cc, ccTargets);
  }

  log.debug("convertToReplyAll", { addedTo, addedCc });
  return { addedTo, addedCc };
}

// ---------------------------------------------------------------------------
// Recipient manager utilities (Feature 6)
// ---------------------------------------------------------------------------

export function parseEmails(text: string): string[] {
  return Array.from(text.matchAll(EMAIL_RE)).map((m) => m[0]);
}

export function findDuplicates(emails: string[]): string[] {
  const counts = new Map<string, number>();
  for (const e of emails) {
    const k = e.toLowerCase();
    counts.set(k, (counts.get(k) || 0) + 1);
  }
  return [...counts.entries()].filter(([, n]) => n > 1).map(([e]) => e);
}

/** Rebuild a field's chips from a de-duplicated / sorted list. */
export function rewriteField(
  dialog: HTMLElement,
  which: "to" | "cc" | "bcc",
  emails: string[],
): void {
  const parts = getComposeParts(dialog);
  const field = parts[which];
  if (!field) return;
  // Remove existing chips via their close buttons, then re-add the desired set.
  const row = field.closest<HTMLElement>(".aoD, .anm, td, div") || field.parentElement;
  if (row) {
    for (const remove of qsa<HTMLElement>(row, 'div[role="button"][aria-label*="Remove" i], span.vR div')) {
      remove.click();
    }
  }
  addRecipients(field, emails);
}
