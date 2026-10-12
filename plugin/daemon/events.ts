// Turns row transitions into notification events. Silent until the stream is synchronized,
// so start-up and resume replays never produce a burst.
import type { Row } from "./model.ts";

export type Severity = "attention" | "milestone" | "info";

export interface Notice {
  kind: string;
  severity: Severity;
  envId: string;
  threadId: string;
  title: string;
  body: string;
  at: number;
}

export const NOTICE_KINDS = {
  needs_input: "attention",
  plan_ready: "attention",
  run_failed: "attention",
  usage_limit: "attention",
  run_completed: "milestone",
  subagents_done: "milestone",
  pr_opened: "milestone",
  pr_merged: "milestone",
  checks_failed: "attention",
  checks_passed: "milestone",
  session_expiring: "attention",
  environment_offline: "info",
  environment_restored: "info",
} as const satisfies Record<string, Severity>;
export type NoticeKind = keyof typeof NOTICE_KINDS;

const REPEAT_WINDOW = 2 * 60_000;
/** Runs shorter than this complete silently (quick replies are not milestones). */
export const LONG_RUN_MS = 60_000;

function plural(n: number, word: string) {
  return `${n} ${word}${n === 1 ? "" : "s"}`;
}

export function duration(ms: number): string {
  const s = Math.round(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ${String(s % 60).padStart(2, "0")}s`;
  return `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, "0")}m`;
}

const PENDING_LABEL: Record<string, string> = {
  command: "wants to run a command",
  "file-read": "wants to read a file",
  "file-change": "wants to change files",
  "mcp-elicitation": "needs MCP input",
  permission: "needs permission",
  dynamic_tool_call: "wants to use a tool",
  user_input: "has a question",
  auth_refresh: "needs to re-authenticate",
};

export function pendingLabel(kind: string): string {
  return PENDING_LABEL[kind] ?? "needs input";
}

export class TransitionDetector {
  private last = new Map<string, Row>();
  private sent = new Map<string, number>();
  private armed = false;

  /** Compares the new rows to the previous call. Returns the notices to emit. */
  diff(rows: Row[], envLabel: string, synchronized: boolean, now = Date.now()): Notice[] {
    const next = new Map(rows.map((r) => [r.key, r]));
    const notices: Notice[] = [];
    if (this.armed && synchronized) {
      for (const row of rows) {
        const before = this.last.get(row.key);
        if (!before) continue;
        for (const n of this.compare(before, row, envLabel, now)) {
          const dedupe = `${n.kind}:${row.key}`;
          if ((this.sent.get(dedupe) ?? 0) > now - REPEAT_WINDOW) continue;
          this.sent.set(dedupe, now);
          notices.push(n);
        }
      }
    }
    if (synchronized) this.armed = true;
    this.last = next;
    for (const [k, t] of this.sent) if (t < now - REPEAT_WINDOW) this.sent.delete(k);
    return notices;
  }

  private compare(a: Row, b: Row, env: string, now: number): Notice[] {
    const out: Notice[] = [];
    const where = `${b.project} · ${env}`;
    const make = (kind: NoticeKind, title: string, body: string): Notice => ({
      kind, severity: NOTICE_KINDS[kind], envId: b.envId, threadId: b.id, title, body, at: now,
    });
    // Subagent rows only report attention; their parent carries the milestones.
    const child = b.parentId !== "";

    if (b.state === "input" && (a.state !== "input" || a.pendingSince !== b.pendingSince)) {
      out.push(make("needs_input", `${b.title} ${pendingLabel(b.pendingKind)}`, where));
    }
    if (b.state === "plan" && a.state !== "plan") out.push(make("plan_ready", `Plan ready: ${b.title}`, where));
    if (b.state === "failed" && a.state !== "failed") {
      out.push(make("run_failed", `Failed: ${b.title}`, b.error ? `${b.error}\n${where}` : where));
    }
    if (b.state === "limited" && a.state !== "limited") {
      const reset = b.usageResetAt ? ` · resets ${new Date(b.usageResetAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}` : "";
      out.push(make("usage_limit", `Usage limit: ${b.title}`, `${b.provider}${reset}\n${where}`));
    }
    if (child) return out;

    const finished = b.completedAt !== null && b.completedAt !== a.completedAt && b.rawStatus === "completed";
    if (finished && (b.lastRunMs ?? 0) >= LONG_RUN_MS && b.unread) {
      out.push(make("run_completed", `Done: ${b.title}`, `${duration(b.lastRunMs ?? 0)} · ${where}`));
    }
    const subsBefore = a.background.subagents + a.activeChildren;
    const subsAfter = b.background.subagents + b.activeChildren;
    if (subsBefore >= 2 && subsAfter === 0) out.push(make("subagents_done", `Subagents finished: ${b.title}`, `${plural(subsBefore, "subagent")} · ${where}`));

    if (b.pr) {
      const samePr = a.pr?.number === b.pr.number;
      if (!samePr && b.pr.state === "open") out.push(make("pr_opened", `PR #${b.pr.number} opened`, `${b.pr.title}\n${where}`));
      if (samePr && a.pr!.state !== "merged" && b.pr.state === "merged") out.push(make("pr_merged", `PR #${b.pr.number} merged`, `${b.pr.title}\n${where}`));
      if (samePr && a.pr!.checks !== b.pr.checks) {
        if (b.pr.checks === "failing") out.push(make("checks_failed", `Checks failing on PR #${b.pr.number}`, `${b.pr.title}\n${where}`));
        if (b.pr.checks === "passing" && a.pr!.checks === "pending") out.push(make("checks_passed", `Checks passed on PR #${b.pr.number}`, `${b.pr.title}\n${where}`));
      }
    }
    return out;
  }
}
