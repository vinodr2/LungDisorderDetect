// Feature 4: the compact Reply+ toolbar rendered above each compose body.

import { el } from "../utils/dom.js";

export interface ToolbarHandlers {
  replyAll(): void;
  replySenderOnly(): void;
  convertToReplyAll(): void;
  attachOriginal(): void;
  attachAll(): void;
  toggleCc(): void;
  toggleBcc(): void;
  showSubject(): void;
  expandHeaders(): void;
  collapseHeaders(): void;
  recipientManager(): void;
}

export interface Toolbar {
  root: HTMLElement;
  statsSlot: HTMLElement;
  setAttachmentCount(n: number): void;
  setRecipientCount(n: number): void;
}

interface BtnSpec {
  label: string;
  title: string;
  icon: string;
  onClick: () => void;
  primary?: boolean;
  id?: string;
}

function button(spec: BtnSpec): HTMLButtonElement {
  const b = el("button", {
    className: `grp-btn grp-btn-tool${spec.primary ? " grp-btn-primary" : ""}`,
    title: spec.title,
    attrs: { type: "button", ...(spec.id ? { "data-grp": spec.id } : {}) },
    children: [
      el("span", { className: "grp-btn-icon", text: spec.icon }),
      el("span", { className: "grp-btn-label", text: spec.label }),
    ],
    on: { click: spec.onClick },
  }) as HTMLButtonElement;
  return b;
}

function group(children: HTMLElement[]): HTMLElement {
  return el("div", { className: "grp-tool-group", children });
}

export function buildToolbar(h: ToolbarHandlers): Toolbar {
  const attachOriginalBtn = button({
    label: "Attach original",
    title: "Attach files from the original email (Ctrl+Shift+A)",
    icon: "📎",
    primary: true,
    onClick: h.attachOriginal,
    id: "attach-original",
  });

  const recipientBadge = el("span", { className: "grp-badge", text: "0" });
  const attachBadge = el("span", { className: "grp-badge grp-badge-att", text: "0" });
  attachOriginalBtn.append(attachBadge);

  const recipientBtn = button({
    label: "Recipients",
    title: "Open recipient manager",
    icon: "👥",
    onClick: h.recipientManager,
    id: "recipients",
  });
  recipientBtn.append(recipientBadge);

  const root = el("div", {
    className: "grp-toolbar",
    attrs: { role: "toolbar", "aria-label": "Gmail Reply+ toolbar" },
    children: [
      group([
        button({
          label: "Reply All",
          title: "Reply to everyone",
          icon: "↩↩",
          onClick: h.replyAll,
        }),
        button({
          label: "Sender only",
          title: "Reply to the sender only",
          icon: "↩",
          onClick: h.replySenderOnly,
        }),
        button({
          label: "Convert → All",
          title: "Convert to Reply All (Ctrl+Shift+R)",
          icon: "⇄",
          onClick: h.convertToReplyAll,
          id: "convert-all",
        }),
      ]),
      group([
        attachOriginalBtn,
        button({
          label: "Attach all",
          title: "Attach every file from the original email",
          icon: "📥",
          onClick: h.attachAll,
        }),
      ]),
      group([
        button({ label: "CC", title: "Toggle CC field", icon: "＋", onClick: h.toggleCc }),
        button({ label: "BCC", title: "Toggle BCC field", icon: "＋", onClick: h.toggleBcc }),
        button({ label: "Subject", title: "Show subject", icon: "✎", onClick: h.showSubject }),
      ]),
      group([
        button({
          label: "Expand",
          title: "Expand all headers (Ctrl+Shift+H)",
          icon: "⤢",
          onClick: h.expandHeaders,
        }),
        button({
          label: "Collapse",
          title: "Collapse headers",
          icon: "⤡",
          onClick: h.collapseHeaders,
        }),
        recipientBtn,
      ]),
    ],
  });

  const statsSlot = el("div", { className: "grp-stats-slot" });
  root.append(statsSlot);

  return {
    root,
    statsSlot,
    setAttachmentCount(n: number): void {
      attachBadge.textContent = String(n);
      attachBadge.classList.toggle("grp-badge-hidden", n === 0);
      attachOriginalBtn.classList.toggle("grp-btn-disabled", n === 0);
    },
    setRecipientCount(n: number): void {
      recipientBadge.textContent = String(n);
    },
  };
}
