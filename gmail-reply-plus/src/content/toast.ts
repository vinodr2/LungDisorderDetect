// Minimal, non-blocking toast used to keep the user informed (e.g. attachment
// fetch progress / results). Local-only, auto-dismisses.

import { el } from "../utils/dom.js";

let container: HTMLElement | null = null;

function ensureContainer(): HTMLElement {
  if (container && document.body.contains(container)) return container;
  container = el("div", { className: "grp-toast-container" });
  document.body.appendChild(container);
  return container;
}

export interface Toast {
  update(message: string): void;
  dismiss(): void;
}

export function showToast(message: string, opts: { timeout?: number; kind?: "info" | "error" } = {}): Toast {
  const text = el("span", { className: "grp-toast-text", text: message });
  const node = el("div", {
    className: `grp-toast grp-toast-${opts.kind ?? "info"}`,
    attrs: { role: "status" },
    children: [el("span", { className: "grp-toast-icon", text: opts.kind === "error" ? "⚠️" : "✅" }), text],
  });
  ensureContainer().appendChild(node);

  let timer: number | undefined;
  const schedule = (ms: number): void => {
    if (timer) clearTimeout(timer);
    timer = window.setTimeout(() => node.remove(), ms);
  };
  if (opts.timeout !== 0) schedule(opts.timeout ?? 3500);

  return {
    update(msg: string): void {
      text.textContent = msg;
    },
    dismiss(): void {
      if (timer) clearTimeout(timer);
      node.remove();
    },
  };
}
