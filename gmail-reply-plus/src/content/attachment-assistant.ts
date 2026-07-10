// Feature 8: if the body implies an attachment but none is attached, nudge.

import { el } from "../utils/dom.js";
import { getComposeParts, findNativeAttachButton } from "../utils/gmail-dom.js";
import { qsa } from "../utils/dom.js";

const TRIGGER_RE = /\b(attach(ed|ment|ing)?|enclosed|see (the )?file|please find)\b/i;

/** Does the compose currently have at least one attachment chip? */
function hasAttachment(dialog: HTMLElement): boolean {
  // Gmail renders staged attachment chips with a remove control + filename.
  return (
    qsa<HTMLElement>(dialog, 'div[aria-label*="Remove attachment" i], .dg .vI, .aQH .aZo').length > 0
  );
}

export interface AssistantController {
  root: HTMLElement;
  check(): void;
  destroy(): void;
}

/** Mounts an inline, dismissible banner that appears only when warranted. */
export function mountAttachmentAssistant(dialog: HTMLElement): AssistantController {
  let dismissed = false;

  const message = el("span", {
    className: "grp-assist-text",
    text: "You mentioned an attachment, but nothing is attached.",
  });

  const attachBtn = el("button", {
    className: "grp-btn grp-btn-small grp-btn-primary",
    text: "Attach file",
    on: { click: () => findNativeAttachButton(dialog)?.click() },
  });

  const ignoreBtn = el("button", {
    className: "grp-btn grp-btn-small",
    text: "Ignore",
    on: {
      click: () => {
        dismissed = true;
        root.hidden = true;
      },
    },
  });

  const root = el("div", {
    className: "grp-assist",
    attrs: { role: "status" },
    children: [el("span", { className: "grp-assist-icon", text: "📎" }), message, attachBtn, ignoreBtn],
  });
  root.hidden = true;

  const check = (): void => {
    if (dismissed) return;
    const body = getComposeParts(dialog).body;
    const text = body?.innerText ?? "";
    const shouldWarn = TRIGGER_RE.test(text) && !hasAttachment(dialog);
    root.hidden = !shouldWarn;
  };

  return {
    root,
    check,
    destroy(): void {
      root.remove();
    },
  };
}
