/** Whitespace-collapsed, length-bounded display text. Non-strings become "". */
export function clean(value: unknown, limit = 120): string {
  if (typeof value !== "string") return "";
  return value.split(/\s+/).filter(Boolean).join(" ").slice(0, limit);
}

/** Multi-line text bounded for display (keeps line breaks, trims trailing space). */
export function cleanBlock(value: unknown, limit = 600): string {
  if (typeof value !== "string") return "";
  const text = value.replace(/\r\n?/g, "\n").replace(/[^\S\n]+/g, " ").replace(/\n{3,}/g, "\n\n").trim();
  return text.length > limit ? text.slice(0, limit - 1) + "…" : text;
}

/** Epoch milliseconds for an ISO string, or null. */
export function ms(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const t = Date.parse(value);
  return Number.isFinite(t) ? t : null;
}

/** T3 ids are UUIDs, or provider-derived ids of about 200 characters (subagent threads). */
export const MAX_ID = 256;

/** An id the server could plausibly send. Anything else is dropped on arrival, never kept or echoed. */
export function validId(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= MAX_ID && /^[A-Za-z0-9_.:%-]+$/.test(value);
}

export function isObject(value: unknown): value is Record<string, any> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export class Failure extends Error {
  readonly code: string;
  constructor(code: string, detail?: string) {
    super(detail ? `${code}: ${detail}` : code);
    this.code = code;
  }
}

export function failureCode(error: unknown): string {
  return error instanceof Failure ? error.code : "failed";
}
