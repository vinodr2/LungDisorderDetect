// Feature 5: subject editing helpers — always visible, de-dupe RE:, RE→FW,
// quick prefixes, and change highlighting.

import { getComposeParts } from "../utils/gmail-dom.js";

const PREFIX_RE = /^\s*(re|fw|fwd)\s*(\[\d+\])?\s*:\s*/i;

/** Strip all leading Re:/Fwd: prefixes, returning the bare subject. */
export function stripPrefixes(subject: string): string {
  let s = subject;
  while (PREFIX_RE.test(s)) s = s.replace(PREFIX_RE, "");
  return s.trim();
}

/** Collapse repeated "Re: Re: Re:" into a single prefix. */
export function dedupePrefix(subject: string): string {
  const hasRe = /^\s*re\s*:/i.test(subject);
  const hasFw = /^\s*(fw|fwd)\s*:/i.test(subject);
  const bare = stripPrefixes(subject);
  if (hasRe) return `Re: ${bare}`;
  if (hasFw) return `Fwd: ${bare}`;
  return bare;
}

/** Convert a reply subject (Re:) into a forward subject (Fwd:). */
export function reToFw(subject: string): string {
  return `Fwd: ${stripPrefixes(subject)}`;
}

/** Apply a quick prefix like "FYI", "Action Required" without duplicating it. */
export function applyPrefix(subject: string, prefix: string): string {
  const tag = `${prefix}: `;
  if (subject.toLowerCase().startsWith(prefix.toLowerCase() + ":")) return subject;
  return tag + subject;
}

export function getSubject(dialog: HTMLElement): string {
  return getComposeParts(dialog).subject?.value ?? "";
}

/** Write a new subject and flag the field as user-changed for highlighting. */
export function setSubject(dialog: HTMLElement, value: string): void {
  const input = getComposeParts(dialog).subject;
  if (!input) return;
  if (input.value === value) return;
  input.value = value;
  input.dispatchEvent(new Event("input", { bubbles: true }));
  input.dispatchEvent(new Event("change", { bubbles: true }));
  input.classList.add("grp-subject-changed");
}
