// Gmail DOM abstraction layer.
//
// Gmail ships obfuscated, frequently-changing class names, so every lookup here
// prefers *semantic* signals that Gmail has kept stable for years — form field
// `name` attributes, ARIA roles, `data-tooltip`, and the `download_url`
// attribute on attachment download buttons — and only falls back to class
// names as a last resort. Each helper is defensive and returns null rather
// than throwing so a Gmail redesign degrades gracefully instead of breaking.

import { qs, qsa, parseSizeLabel } from "./dom.js";
import type { OriginalAttachment, OriginalMessageInfo } from "./types.js";

/** A live compose/reply form plus the fields we care about. */
export interface ComposeParts {
  dialog: HTMLElement;
  to: HTMLTextAreaElement | null;
  cc: HTMLTextAreaElement | null;
  bcc: HTMLTextAreaElement | null;
  subject: HTMLInputElement | null;
  body: HTMLElement | null;
  fileInput: HTMLInputElement | null;
}

/** Roots that can contain a compose form (inline reply or pop-out dialog). */
export function findComposeDialogs(): HTMLElement[] {
  // A compose form is uniquely identified by carrying the subject box or the
  // to-field; walk up to the nearest dialog/compose container from there.
  const anchors = new Set<HTMLElement>();
  for (const field of qsa<HTMLElement>(document, 'input[name="subjectbox"], textarea[name="to"]')) {
    const container =
      field.closest<HTMLElement>('[role="dialog"]') ||
      field.closest<HTMLElement>("form") ||
      field.closest<HTMLElement>(".M9") ||
      field.closest<HTMLElement>(".iN");
    if (container) anchors.add(container);
  }
  return [...anchors];
}

/** Resolve the interesting fields inside a compose dialog. */
export function getComposeParts(dialog: HTMLElement): ComposeParts {
  return {
    dialog,
    to: qs<HTMLTextAreaElement>(dialog, 'textarea[name="to"]'),
    cc: qs<HTMLTextAreaElement>(dialog, 'textarea[name="cc"]'),
    bcc: qs<HTMLTextAreaElement>(dialog, 'textarea[name="bcc"]'),
    subject: qs<HTMLInputElement>(dialog, 'input[name="subjectbox"]'),
    body:
      qs<HTMLElement>(dialog, '[role="textbox"][contenteditable="true"]') ||
      qs<HTMLElement>(dialog, "div.editable[contenteditable='true']"),
    fileInput: qs<HTMLInputElement>(dialog, 'input[type="file"]'),
  };
}

/** The CC / BCC toggle links Gmail shows when those fields are hidden. */
export function findCcBccToggles(dialog: HTMLElement): { cc: HTMLElement | null; bcc: HTMLElement | null } {
  const spans = qsa<HTMLElement>(dialog, 'span[role="link"], span.pE, span.pB, span.aB');
  let cc: HTMLElement | null = null;
  let bcc: HTMLElement | null = null;
  for (const s of spans) {
    const t = (s.textContent || "").trim().toLowerCase();
    if (!cc && t === "cc") cc = s;
    if (!bcc && t === "bcc") bcc = s;
  }
  return { cc, bcc };
}

/** Gmail's native "Attach files" button inside a compose toolbar. */
export function findNativeAttachButton(dialog: HTMLElement): HTMLElement | null {
  return (
    qs<HTMLElement>(dialog, '[command="Files"]') ||
    qs<HTMLElement>(dialog, '[data-tooltip*="Attach" i]') ||
    qs<HTMLElement>(dialog, '[aria-label*="Attach" i]')
  );
}

// ---------------------------------------------------------------------------
// Original message discovery
// ---------------------------------------------------------------------------

/** The main conversation reading pane. */
export function getMainThread(): HTMLElement | null {
  return qs<HTMLElement>(document, '[role="main"]');
}

/**
 * Find the message a given compose form is replying to.
 * For an inline reply the source messages are siblings in the same thread;
 * for a pop-out we fall back to the last expanded message in the open thread.
 */
export function findSourceMessage(dialog: HTMLElement): HTMLElement | null {
  const main = getMainThread();
  if (!main) return null;
  // All rendered messages in the thread. `.adn` wraps each message; `.gs` is
  // the message content. Take expanded ones (they contain a visible body).
  const messages = qsa<HTMLElement>(main, "div.adn, div.gs").filter(
    (m) => !dialog.contains(m) && m.offsetParent !== null,
  );
  if (messages.length === 0) return null;
  // Prefer the message immediately preceding an inline compose, else the last.
  if (main.contains(dialog)) {
    const before = messages.filter(
      (m) => m.compareDocumentPosition(dialog) & Node.DOCUMENT_POSITION_FOLLOWING,
    );
    if (before.length) return before[before.length - 1];
  }
  return messages[messages.length - 1];
}

/** All recipient email addresses on a message (deduped, order-preserving). */
export function getRecipientEmails(message: HTMLElement): string[] {
  const senderEl = qs<HTMLElement>(message, "span.gD, span[email]");
  const seen = new Set<string>();
  const out: string[] = [];
  for (const e of qsa<HTMLElement>(message, "span.g2[email], span.hb[email], span[email]")) {
    if (e === senderEl) continue;
    const email = e.getAttribute("email");
    if (!email) continue;
    const key = email.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(email);
  }
  return out;
}

/** Extract sender / date / subject / recipient + attachment info (Feature 9). */
export function extractMessageInfo(message: HTMLElement): OriginalMessageInfo {
  const senderEl = qs<HTMLElement>(message, "span.gD, span[email]");
  const senderEmail = senderEl?.getAttribute("email") || "";
  const sender = senderEl?.getAttribute("name") || senderEl?.textContent?.trim() || senderEmail;

  const dateEl =
    qs<HTMLElement>(message, "span.g3[title], span.gK span[title], span[data-tooltip][role='gridcell']") ||
    qs<HTMLElement>(message, "span.g3");
  const date = dateEl?.getAttribute("title") || dateEl?.textContent?.trim() || "";

  const subjectEl = qs<HTMLElement>(document, "h2.hP, [data-thread-perm-id] h2");
  const subject = subjectEl?.textContent?.trim() || "";

  // Recipients: the expanded "to" details carry email attributes.
  const recipientEls = qsa<HTMLElement>(message, "span.g2[email], span.hb[email], span[email]").filter(
    (e) => e.getAttribute("email") && e !== senderEl,
  );
  const uniqueRecipients = new Set(recipientEls.map((e) => e.getAttribute("email")!.toLowerCase()));

  const attachments = extractAttachments(message);

  const threadId =
    qs<HTMLElement>(document, "[data-thread-perm-id]")?.getAttribute("data-thread-perm-id") ||
    qs<HTMLElement>(message, "[data-legacy-thread-id]")?.getAttribute("data-legacy-thread-id") ||
    null;

  return {
    sender,
    senderEmail,
    date,
    subject,
    recipientCount: uniqueRecipients.size,
    attachments,
    threadId,
  };
}

/**
 * Discover downloadable attachments on the original message (Feature 3).
 *
 * Gmail places a `download_url` attribute of the form
 *   "<mime>:<filename>:<absolute download url>"
 * on the download control of each attachment chip. That URL is same-origin on
 * mail.google.com and honours the session cookie, so the content script can
 * fetch the bytes directly. When `download_url` is absent we fall back to a
 * plain anchor href and infer the filename from the chip label.
 */
export function extractAttachments(root: HTMLElement): OriginalAttachment[] {
  const results: OriginalAttachment[] = [];
  const seen = new Set<string>();

  // 1) Elements carrying the canonical download_url attribute.
  for (const node of qsa<HTMLElement>(root, "[download_url]")) {
    const raw = node.getAttribute("download_url") || "";
    const parsed = parseDownloadUrl(raw);
    if (!parsed) continue;
    const chip = node.closest<HTMLElement>(".aZo, .aQH, .brc") || node;
    const { sizeLabel, sizeBytes } = readSize(chip);
    const key = parsed.url;
    if (seen.has(key)) continue;
    seen.add(key);
    results.push({
      id: `att-${results.length}`,
      filename: parsed.filename || chipFilename(chip) || `attachment-${results.length + 1}`,
      mimeType: parsed.mime || "application/octet-stream",
      sizeLabel,
      sizeBytes,
      downloadUrl: parsed.url,
    });
  }

  // 2) Fallback: attachment chips exposing a direct download anchor.
  for (const chip of qsa<HTMLElement>(root, ".aZo, .aQH")) {
    const anchor = qs<HTMLAnchorElement>(chip, 'a[href*="view=att"], a[download], a[href*="disp=attd"]');
    if (!anchor || !anchor.href) continue;
    if (seen.has(anchor.href)) continue;
    seen.add(anchor.href);
    const { sizeLabel, sizeBytes } = readSize(chip);
    results.push({
      id: `att-${results.length}`,
      filename: anchor.getAttribute("download") || chipFilename(chip) || `attachment-${results.length + 1}`,
      mimeType: "application/octet-stream",
      sizeLabel,
      sizeBytes,
      downloadUrl: anchor.href,
    });
  }

  return results;
}

function parseDownloadUrl(raw: string): { mime: string; filename: string; url: string } | null {
  // Format: "mime:filename:url" — but the URL itself contains ':' so split on
  // the first two colons only.
  const first = raw.indexOf(":");
  const second = raw.indexOf(":", first + 1);
  if (first === -1 || second === -1) return null;
  const mime = raw.slice(0, first);
  const filename = decodeURIComponent(raw.slice(first + 1, second));
  const url = raw.slice(second + 1);
  if (!/^https?:/i.test(url)) return null;
  return { mime, filename, url };
}

function chipFilename(chip: HTMLElement): string | null {
  const nameEl =
    qs<HTMLElement>(chip, ".aV3, .aQA span, .aYy span[title], [aria-label]") || null;
  const raw =
    nameEl?.getAttribute("title") ||
    nameEl?.getAttribute("aria-label") ||
    nameEl?.textContent ||
    "";
  const cleaned = raw.replace(/\s+/g, " ").trim();
  return cleaned || null;
}

function readSize(chip: HTMLElement): { sizeLabel: string; sizeBytes: number | null } {
  const sizeEl = qs<HTMLElement>(chip, ".SaH2Ve, .aYq, .aV3 + span, .aZo .aYq");
  const label = sizeEl?.textContent?.trim() || matchSizeInText(chip.textContent || "") || "";
  return { sizeLabel: label, sizeBytes: label ? parseSizeLabel(label) : null };
}

function matchSizeInText(text: string): string | null {
  const m = text.match(/[\d.,]+\s*(bytes?|K|KB|M|MB|G|GB)\b/i);
  return m ? m[0].trim() : null;
}
