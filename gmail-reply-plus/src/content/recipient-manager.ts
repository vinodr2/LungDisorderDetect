// Feature 6: Outlook-style recipient manager modal.

import { el } from "../utils/dom.js";
import { getComposeParts } from "../utils/gmail-dom.js";
import {
  readChips,
  parseEmails,
  findDuplicates,
  rewriteField,
  addRecipients,
} from "./recipients.js";

type FieldKey = "to" | "cc" | "bcc";

export function openRecipientManager(dialog: HTMLElement): void {
  document.querySelector(".grp-modal-overlay")?.remove();

  const state: Record<FieldKey, string[]> = {
    to: readChips(getComposeParts(dialog).to),
    cc: readChips(getComposeParts(dialog).cc),
    bcc: readChips(getComposeParts(dialog).bcc),
  };

  const listEl = el("div", { className: "grp-rm-list" });
  const countEl = el("span", { className: "grp-rm-count" });
  const search = el("input", {
    className: "grp-rm-search",
    attrs: { type: "search", placeholder: "Search recipients…" },
  }) as HTMLInputElement;

  function total(): number {
    return state.to.length + state.cc.length + state.bcc.length;
  }

  function render(): void {
    const q = search.value.trim().toLowerCase();
    const dupSet = new Set(findDuplicates([...state.to, ...state.cc, ...state.bcc]));
    listEl.replaceChildren();
    (["to", "cc", "bcc"] as FieldKey[]).forEach((key) => {
      const matches = state[key].filter((e) => !q || e.toLowerCase().includes(q));
      if (matches.length === 0) return;
      listEl.append(el("div", { className: "grp-rm-group-label", text: key.toUpperCase() }));
      for (const email of matches) {
        const isDup = dupSet.has(email.toLowerCase());
        listEl.append(
          el("div", {
            className: `grp-rm-item${isDup ? " grp-rm-dup" : ""}`,
            children: [
              el("span", { className: "grp-rm-email", text: email, title: isDup ? "Duplicate" : "" }),
              el("button", {
                className: "grp-rm-remove",
                text: "✕",
                title: "Remove",
                on: {
                  click: () => {
                    state[key] = state[key].filter((e) => e !== email);
                    render();
                  },
                },
              }),
            ],
          }),
        );
      }
    });
    const dupCount = dupSet.size;
    countEl.textContent = `${total()} recipient${total() === 1 ? "" : "s"}${
      dupCount ? ` · ${dupCount} duplicate${dupCount === 1 ? "" : "s"}` : ""
    }`;
  }

  const pasteBox = el("input", {
    className: "grp-rm-paste",
    attrs: { type: "text", placeholder: "Paste addresses, then Enter to add to To…" },
  }) as HTMLInputElement;
  pasteBox.addEventListener("keydown", (e) => {
    if ((e as KeyboardEvent).key !== "Enter") return;
    const emails = parseEmails(pasteBox.value);
    const existing = new Set([...state.to, ...state.cc, ...state.bcc].map((x) => x.toLowerCase()));
    for (const em of emails) if (!existing.has(em.toLowerCase())) state.to.push(em);
    pasteBox.value = "";
    render();
  });

  const actions = el("div", {
    className: "grp-rm-tools",
    children: [
      toolBtn("Copy all", "📋", async () => {
        const all = [...state.to, ...state.cc, ...state.bcc].join(", ");
        try {
          await navigator.clipboard.writeText(all);
        } catch {
          /* clipboard may be blocked; ignore */
        }
      }),
      toolBtn("Remove duplicates", "🧹", () => {
        const seen = new Set<string>();
        (["to", "cc", "bcc"] as FieldKey[]).forEach((key) => {
          state[key] = state[key].filter((e) => {
            const k = e.toLowerCase();
            if (seen.has(k)) return false;
            seen.add(k);
            return true;
          });
        });
        render();
      }),
      toolBtn("Sort A→Z", "🔤", () => {
        (["to", "cc", "bcc"] as FieldKey[]).forEach((key) => {
          state[key] = [...state[key]].sort((a, b) => a.localeCompare(b));
        });
        render();
      }),
    ],
  });

  function apply(): void {
    // Rewrite each field to match the edited state.
    rewriteField(dialog, "to", state.to);
    if (state.cc.length) rewriteField(dialog, "cc", state.cc);
    if (state.bcc.length) rewriteField(dialog, "bcc", state.bcc);
    // Ensure any addresses added via paste that map to To are present.
    addRecipients(getComposeParts(dialog).to, state.to);
    close();
  }

  const overlay = el("div", {
    className: "grp-modal-overlay",
    children: [
      el("div", {
        className: "grp-modal grp-modal-wide",
        attrs: { role: "dialog", "aria-label": "Recipient manager" },
        children: [
          el("div", {
            className: "grp-modal-head",
            children: [
              el("span", { className: "grp-modal-title", text: "Recipients" }),
              countEl,
              el("button", { className: "grp-modal-close", text: "✕", on: { click: close } }),
            ],
          }),
          search,
          listEl,
          pasteBox,
          actions,
          el("div", {
            className: "grp-modal-actions",
            children: [
              el("button", { className: "grp-btn", text: "Cancel", on: { click: close } }),
              el("button", { className: "grp-btn grp-btn-primary", text: "Apply", on: { click: apply } }),
            ],
          }),
        ],
      }),
    ],
  });

  function close(): void {
    overlay.remove();
    document.removeEventListener("keydown", onKey);
  }
  function onKey(e: KeyboardEvent): void {
    if (e.key === "Escape") close();
  }
  overlay.addEventListener("click", (e) => e.target === overlay && close());
  document.addEventListener("keydown", onKey);
  search.addEventListener("input", render);

  document.body.appendChild(overlay);
  render();
}

function toolBtn(label: string, icon: string, onClick: () => void): HTMLElement {
  return el("button", {
    className: "grp-btn grp-btn-small",
    children: [el("span", { text: icon }), el("span", { text: label })],
    on: { click: onClick },
  });
}
