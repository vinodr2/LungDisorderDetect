// Settings persistence + change subscription, shared by all extension surfaces.

import { DEFAULT_SETTINGS, type Settings } from "./types.js";

const KEY = "settings";

/** Load settings, filling any missing keys with defaults (forward compatible). */
export async function loadSettings(): Promise<Settings> {
  try {
    const stored = await chrome.storage.sync.get(KEY);
    return { ...DEFAULT_SETTINGS, ...(stored[KEY] as Partial<Settings> | undefined) };
  } catch {
    // storage.sync can be unavailable (e.g. sync disabled) — fall back to local.
    try {
      const stored = await chrome.storage.local.get(KEY);
      return { ...DEFAULT_SETTINGS, ...(stored[KEY] as Partial<Settings> | undefined) };
    } catch {
      return { ...DEFAULT_SETTINGS };
    }
  }
}

/** Persist settings to both sync (primary) and local (fallback / offline). */
export async function saveSettings(settings: Settings): Promise<void> {
  await Promise.allSettled([
    chrome.storage.sync.set({ [KEY]: settings }),
    chrome.storage.local.set({ [KEY]: settings }),
  ]);
}

/** Subscribe to settings changes from any surface. Returns an unsubscribe fn. */
export function onSettingsChanged(cb: (settings: Settings) => void): () => void {
  const listener = (
    changes: Record<string, chrome.storage.StorageChange>,
    area: string,
  ): void => {
    if ((area === "sync" || area === "local") && changes[KEY]?.newValue) {
      cb({ ...DEFAULT_SETTINGS, ...(changes[KEY].newValue as Partial<Settings>) });
    }
  };
  chrome.storage.onChanged.addListener(listener);
  return () => chrome.storage.onChanged.removeListener(listener);
}

/** Remembered compose window geometry (Feature 11: remember last window size). */
export interface WindowGeometry {
  width: number;
  height: number;
}

export async function loadWindowGeometry(): Promise<WindowGeometry | null> {
  try {
    const stored = await chrome.storage.local.get("windowGeometry");
    return (stored.windowGeometry as WindowGeometry | undefined) ?? null;
  } catch {
    return null;
  }
}

export async function saveWindowGeometry(geometry: WindowGeometry): Promise<void> {
  try {
    await chrome.storage.local.set({ windowGeometry: geometry });
  } catch {
    /* non-fatal */
  }
}
