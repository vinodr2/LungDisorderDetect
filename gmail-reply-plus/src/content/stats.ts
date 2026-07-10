// Feature 7: compose statistics — characters, words, reading time, and a live
// compose-duration timer. Rendered into a slot inside the toolbar.

import { el, debounce } from "../utils/dom.js";
import { getComposeParts } from "../utils/gmail-dom.js";

const WORDS_PER_MINUTE = 200;

export interface StatsController {
  root: HTMLElement;
  destroy(): void;
}

function countWords(text: string): number {
  const trimmed = text.trim();
  if (!trimmed) return 0;
  return trimmed.split(/\s+/).length;
}

function readingTime(words: number): string {
  if (words === 0) return "0s";
  const minutes = words / WORDS_PER_MINUTE;
  if (minutes < 1) return `${Math.max(1, Math.round(minutes * 60))}s`;
  return `${Math.round(minutes)} min`;
}

function fmtDuration(ms: number): string {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const rem = s % 60;
  return m > 0 ? `${m}:${String(rem).padStart(2, "0")}` : `${rem}s`;
}

/** Mount the stats readout for a compose dialog; recomputes on body edits. */
export function mountStats(dialog: HTMLElement): StatsController {
  const chars = el("span", { className: "grp-stat", title: "Characters" });
  const words = el("span", { className: "grp-stat", title: "Words" });
  const read = el("span", { className: "grp-stat", title: "Estimated reading time" });
  const timer = el("span", { className: "grp-stat", title: "Time spent composing" });

  const root = el("div", {
    className: "grp-stats",
    children: [chars, dot(), words, dot(), read, dot(), timer],
  });

  const started = Date.now();

  const recompute = (): void => {
    const body = getComposeParts(dialog).body;
    const text = body?.innerText ?? "";
    const w = countWords(text);
    chars.textContent = `${text.length} chars`;
    words.textContent = `${w} words`;
    read.textContent = `~${readingTime(w)} read`;
  };

  const debounced = debounce(recompute, 150);

  const bodyForListener = getComposeParts(dialog).body;
  bodyForListener?.addEventListener("input", debounced);
  bodyForListener?.addEventListener("keyup", debounced);

  const tick = window.setInterval(() => {
    timer.textContent = `⏱ ${fmtDuration(Date.now() - started)}`;
  }, 1000);
  timer.textContent = "⏱ 0s";
  recompute();

  return {
    root,
    destroy(): void {
      window.clearInterval(tick);
      bodyForListener?.removeEventListener("input", debounced);
      bodyForListener?.removeEventListener("keyup", debounced);
      root.remove();
    },
  };
}

function dot(): HTMLElement {
  return el("span", { className: "grp-stat-sep", text: "·" });
}
