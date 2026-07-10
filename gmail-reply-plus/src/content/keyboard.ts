// Feature 10: keyboard shortcuts, handled inside the page so they work even
// when the compose has focus. The service worker also forwards any matching
// chrome.commands events (see service-worker.ts) for keys the browser reserves.

import type { KeyCommand } from "../utils/types.js";

type Handler = (command: KeyCommand) => void;

const MAP: Array<{ key: string; shift: boolean; ctrlOrMeta: boolean; command: KeyCommand }> = [
  { key: "r", shift: true, ctrlOrMeta: true, command: "convert-to-reply-all" },
  { key: "a", shift: true, ctrlOrMeta: true, command: "attach-original-files" },
  { key: "h", shift: true, ctrlOrMeta: true, command: "toggle-headers" },
  { key: "s", shift: true, ctrlOrMeta: true, command: "focus-subject" },
];

let handler: Handler | null = null;
let enabled = true;

function onKeyDown(e: KeyboardEvent): void {
  if (!enabled || !handler) return;
  const ctrlOrMeta = e.ctrlKey || e.metaKey;
  if (!ctrlOrMeta || !e.shiftKey) return;
  const key = e.key.toLowerCase();
  const match = MAP.find((m) => m.key === key && m.shift && m.ctrlOrMeta);
  if (!match) return;
  // Only intercept when a compose is present; otherwise let Gmail have the key.
  if (!document.querySelector('input[name="subjectbox"]')) return;
  e.preventDefault();
  e.stopPropagation();
  handler(match.command);
}

export function registerKeyboard(cb: Handler): void {
  handler = cb;
  document.addEventListener("keydown", onKeyDown, true);
}

export function setKeyboardEnabled(value: boolean): void {
  enabled = value;
}
