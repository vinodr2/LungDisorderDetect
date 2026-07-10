// Shared types used across content, background, options and popup.

/** User-configurable settings (Feature 11). Persisted in chrome.storage.sync. */
export interface Settings {
  alwaysShowCc: boolean;
  alwaysShowBcc: boolean;
  alwaysShowSubject: boolean;
  enableAttachmentAssistant: boolean;
  enableAttachmentPicker: boolean;
  enableComposeStats: boolean;
  enableKeyboardShortcuts: boolean;
  rememberWindowSize: boolean;
  /** Extra niceties beyond the base spec. */
  showReplyInfoPanel: boolean;
  autoConvertToReplyAll: boolean;
}

export const DEFAULT_SETTINGS: Settings = {
  alwaysShowCc: true,
  alwaysShowBcc: true,
  alwaysShowSubject: true,
  enableAttachmentAssistant: true,
  enableAttachmentPicker: true,
  enableComposeStats: true,
  enableKeyboardShortcuts: true,
  rememberWindowSize: true,
  showReplyInfoPanel: true,
  autoConvertToReplyAll: false,
};

/** A single attachment discovered on the original message. */
export interface OriginalAttachment {
  id: string;
  filename: string;
  /** MIME type when Gmail exposes it, else best-effort from the extension. */
  mimeType: string;
  /** Human-readable size string as shown by Gmail (e.g. "1.2 MB"), if present. */
  sizeLabel: string;
  /** Bytes when known (parsed from Gmail), else null. */
  sizeBytes: number | null;
  /** Direct download URL (same-origin, credentialed) when discoverable. */
  downloadUrl: string | null;
}

/** Snapshot of the message being replied to (Feature 9). */
export interface OriginalMessageInfo {
  sender: string;
  senderEmail: string;
  date: string;
  subject: string;
  recipientCount: number;
  attachments: OriginalAttachment[];
  threadId: string | null;
}

/** Messages exchanged between content script and service worker. */
export type RuntimeMessage =
  | { type: "GET_SETTINGS" }
  | { type: "SETTINGS_CHANGED"; settings: Settings }
  | { type: "COMMAND"; command: KeyCommand };

export type KeyCommand =
  | "convert-to-reply-all"
  | "attach-original-files"
  | "toggle-headers"
  | "focus-subject";
