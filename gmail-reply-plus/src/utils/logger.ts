// Tiny namespaced logger. Silent by default; flip DEBUG to trace Gmail DOM work.
// No analytics, no network — purely local console output.

const PREFIX = "%c[Gmail Reply+]";
const STYLE = "color:#1a73e8;font-weight:600";

const DEBUG = false;

export const log = {
  debug(...args: unknown[]): void {
    if (DEBUG) console.debug(PREFIX, STYLE, ...args);
  },
  info(...args: unknown[]): void {
    console.info(PREFIX, STYLE, ...args);
  },
  warn(...args: unknown[]): void {
    console.warn(PREFIX, STYLE, ...args);
  },
  error(...args: unknown[]): void {
    console.error(PREFIX, STYLE, ...args);
  },
};
