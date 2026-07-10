// Feature 9: expandable "Reply information" panel summarising the original.

import { el } from "../utils/dom.js";
import type { OriginalMessageInfo } from "../utils/types.js";

export function buildReplyInfoPanel(info: OriginalMessageInfo): HTMLElement {
  const rows: HTMLElement[] = [
    infoRow("From", info.sender + (info.senderEmail ? ` <${info.senderEmail}>` : "")),
    infoRow("Date", info.date || "—"),
    infoRow("Subject", info.subject || "—"),
    infoRow("Recipients", String(info.recipientCount)),
    infoRow("Attachments", String(info.attachments.length)),
  ];
  if (info.attachments.length) {
    rows.push(infoRow("Files", info.attachments.map((a) => a.filename).join(", ")));
  }
  if (info.threadId) rows.push(infoRow("Thread ID", info.threadId));

  const body = el("div", { className: "grp-info-body", children: rows });
  body.hidden = true;

  const caret = el("span", { className: "grp-info-caret", text: "▸" });
  const toggle = el("button", {
    className: "grp-info-toggle",
    attrs: { type: "button", "aria-expanded": "false" },
    children: [caret, el("span", { text: "Reply information" })],
    on: {
      click: () => {
        const open = body.hidden;
        body.hidden = !open;
        caret.textContent = open ? "▾" : "▸";
        toggle.setAttribute("aria-expanded", String(open));
      },
    },
  });

  return el("div", { className: "grp-info", children: [toggle, body] });
}

function infoRow(label: string, value: string): HTMLElement {
  return el("div", {
    className: "grp-info-row",
    children: [
      el("span", { className: "grp-info-label", text: label }),
      el("span", { className: "grp-info-value", text: value, title: value }),
    ],
  });
}
