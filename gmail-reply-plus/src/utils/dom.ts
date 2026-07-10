// Small, dependency-free DOM helpers. No jQuery.

/** Create an element with attributes, classes, and children in one call. */
export function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  props: Partial<{
    className: string;
    text: string;
    html: string;
    title: string;
    attrs: Record<string, string>;
    on: Partial<Record<keyof HTMLElementEventMap, (ev: Event) => void>>;
    children: (Node | string)[];
  }> = {},
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (props.className) node.className = props.className;
  if (props.text != null) node.textContent = props.text;
  if (props.html != null) node.innerHTML = props.html;
  if (props.title) node.title = props.title;
  if (props.attrs) for (const [k, v] of Object.entries(props.attrs)) node.setAttribute(k, v);
  if (props.on)
    for (const [k, v] of Object.entries(props.on)) node.addEventListener(k, v as EventListener);
  if (props.children)
    for (const c of props.children) node.append(typeof c === "string" ? document.createTextNode(c) : c);
  return node;
}

/** First matching element within a root, typed. */
export function qs<T extends Element = HTMLElement>(
  root: ParentNode,
  selector: string,
): T | null {
  return root.querySelector<T>(selector);
}

/** All matching elements within a root, as a real array. */
export function qsa<T extends Element = HTMLElement>(
  root: ParentNode,
  selector: string,
): T[] {
  return Array.from(root.querySelectorAll<T>(selector));
}

/** Debounce a function (used to throttle stats + observer callbacks). */
export function debounce<A extends unknown[]>(
  fn: (...args: A) => void,
  ms: number,
): (...args: A) => void {
  let t: number | undefined;
  return (...args: A) => {
    if (t) clearTimeout(t);
    t = window.setTimeout(() => fn(...args), ms);
  };
}

/** Wait for a descendant matching `selector` to appear under `root`. */
export function waitFor(
  root: HTMLElement,
  selector: string,
  timeoutMs = 5000,
): Promise<HTMLElement | null> {
  return new Promise((resolve) => {
    const found = root.querySelector<HTMLElement>(selector);
    if (found) return resolve(found);
    const obs = new MutationObserver(() => {
      const hit = root.querySelector<HTMLElement>(selector);
      if (hit) {
        obs.disconnect();
        resolve(hit);
      }
    });
    obs.observe(root, { childList: true, subtree: true });
    window.setTimeout(() => {
      obs.disconnect();
      resolve(null);
    }, timeoutMs);
  });
}

/** Humanize a byte count into a Gmail-style size label. */
export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return "0 B";
  const units = ["B", "KB", "MB", "GB"];
  const i = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
  const val = bytes / Math.pow(1024, i);
  return `${val >= 10 || i === 0 ? Math.round(val) : val.toFixed(1)} ${units[i]}`;
}

/** Parse a Gmail size label ("1.2 MB", "834 K", "512 bytes") into bytes. */
export function parseSizeLabel(label: string): number | null {
  const m = label.trim().match(/([\d.,]+)\s*(bytes?|B|K|KB|M|MB|G|GB)/i);
  if (!m) return null;
  const value = parseFloat(m[1].replace(/,/g, ""));
  if (!Number.isFinite(value)) return null;
  const unit = m[2].toUpperCase();
  const scale: Record<string, number> = {
    BYTE: 1, BYTES: 1, B: 1, K: 1024, KB: 1024,
    M: 1024 ** 2, MB: 1024 ** 2, G: 1024 ** 3, GB: 1024 ** 3,
  };
  return Math.round(value * (scale[unit] ?? 1));
}
