// Pure derivation: raw T3 thread shells → bounded display rows.
// Only allowlisted, cleaned fields leave this module.
import { clean, cleanBlock, isObject, ms } from "./util.ts";

/** Display states, most urgent first. */
export const STATES = [
  "input",      // pending approval / question
  "plan",       // proposed plan awaiting review
  "failed",     // latest run failed
  "limited",    // provider usage limit hit
  "working",    // preparing / starting / running
  "waiting",    // provider done, checkpoint finalizing
  "queued",
  "background", // no active run, but subagents/commands/monitors still out
  "review",     // completed and not yet seen in T3
  "stopped",    // interrupted / cancelled
  "idle",
] as const;
export type State = (typeof STATES)[number];

export const ATTENTION: ReadonlySet<State> = new Set(["input", "plan", "failed"]);
export const BUSY: ReadonlySet<State> = new Set(["working", "waiting", "queued", "background"]);

export interface PullRequest {
  number: number;
  title: string;
  url: string;
  state: string;   // open | closed | merged
  checks: string;  // passing | failing | pending | ""
  draft: boolean;
  additions: number;
  deletions: number;
  review: string;
}

export interface Activity {
  icon: string;     // lucide icon name, matches T3's timeline mapping
  label: string;
  status: string;   // running | completed | failed | pending …
  at: number | null;
}

export interface Row {
  key: string;
  envId: string;
  id: string;
  parentId: string;   // root thread id for subagents, else ""
  title: string;
  projectId: string;
  project: string;
  branch: string;
  worktree: boolean;
  provider: string;
  model: string;
  mode: string;       // runtime mode (full-access, approval-required …)
  plan: boolean;      // plan interaction mode
  state: State;
  rawStatus: string;
  pendingKind: string;
  pendingSince: number | null;
  activeSince: number | null;
  lastRunMs: number | null;
  completedAt: number | null;
  createdAt: number | null;
  updatedAt: number | null;
  unread: boolean;
  pinned: boolean;
  settled: boolean;
  snoozedUntil: number | null;
  background: { subagents: number; commands: number; monitors: number; other: number };
  pr: PullRequest | null;
  prCount: number;
  errorClass: string;
  error: string;
  usageResetAt: number | null;
  childCount: number;
  activeChildren: number;
  /** Live activity trail (only for threads with an open thread subscription). */
  activity: Activity[];
}

export function classify(t: Record<string, any>, now = Date.now()): State {
  const pending = t.pendingRuntimeRequest;
  if (isObject(pending) && pending.kind) return "input";
  const run = t.activityRunStatus;
  if (run === "preparing" || run === "starting" || run === "running") return "working";
  if (run === "waiting" || t.status === "waiting") return "waiting";
  if (t.status === "queued") return "queued";
  if (t.status === "preparing" || t.status === "starting" || t.status === "running") return "working";
  if (t.hasActionableProposedPlan) return "plan";
  if (Array.isArray(t.pendingBackgroundTasks) && t.pendingBackgroundTasks.length) return "background";
  const resetAt = ms(t.usageLimitResetAt) ?? ms(t.limitRecovery?.resetAt);
  if (t.lastErrorClass === "usage_limit" && resetAt !== null && resetAt > now) return "limited";
  if (t.status === "failed") return "failed";
  if (t.status === "interrupted" || t.status === "cancelled" || t.status === "rolled_back") return "stopped";
  if (t.status === "completed" && isUnread(t)) return "review";
  return "idle";
}

export function isUnread(t: Record<string, any>): boolean {
  // Subagent threads are never "visited" in T3; their parent carries read state.
  if (t.lineage?.relationshipToParent === "subagent") return false;
  const done = ms(t.latestRunCompletedAt);
  if (done === null) return false;
  const visited = ms(t.lastVisitedAt);
  return visited === null || visited < done;
}

function pickPullRequest(t: Record<string, any>): { pr: PullRequest | null; count: number } {
  const all = [t.linkedPullRequest, t.branchPullRequest, ...(Array.isArray(t.pullRequests) ? t.pullRequests : [])].filter(
    (p) => isObject(p) && isObject(p.snapshot) && typeof p.number === "number",
  );
  if (!all.length) return { pr: null, count: 0 };
  const unique = new Map<string, any>();
  for (const p of all) unique.set(`${p.repository}#${p.number}`, p);
  const ranked = [...unique.values()].sort((a, b) => {
    const open = Number(b.snapshot.state === "open") - Number(a.snapshot.state === "open");
    if (open) return open;
    return (ms(b.snapshot.updatedAt) ?? ms(b.linkedAt) ?? 0) - (ms(a.snapshot.updatedAt) ?? ms(a.linkedAt) ?? 0);
  });
  // Explicit links win over recency.
  const chosen = isObject(t.linkedPullRequest) ? t.linkedPullRequest : isObject(t.branchPullRequest) ? t.branchPullRequest : ranked[0];
  const s = chosen.snapshot;
  return {
    count: unique.size,
    pr: {
      number: chosen.number,
      title: clean(s.title, 120),
      url: typeof chosen.url === "string" && /^https:\/\//.test(chosen.url) ? chosen.url.slice(0, 300) : "",
      state: clean(s.state, 12),
      checks: clean(s.checksState, 12),
      draft: s.isDraft === true,
      additions: Number.isFinite(s.additions) ? s.additions : 0,
      deletions: Number.isFinite(s.deletions) ? s.deletions : 0,
      review: clean(s.reviewDecision, 24),
    },
  };
}

function backgroundCounts(t: Record<string, any>) {
  const counts = { subagents: 0, commands: 0, monitors: 0, other: 0 };
  for (const task of Array.isArray(t.pendingBackgroundTasks) ? t.pendingBackgroundTasks : []) {
    if (task?.kind === "subagent") counts.subagents++;
    else if (task?.kind === "command") counts.commands++;
    else if (task?.kind === "monitor") counts.monitors++;
    else counts.other++;
  }
  return counts;
}

export function toRow(envId: string, t: Record<string, any>, projects: Map<string, Record<string, any>>, now = Date.now()): Row {
  const state = classify(t, now);
  const project = projects.get(t.projectId);
  const lineage = isObject(t.lineage) ? t.lineage : {};
  const isSubagent = lineage.relationshipToParent === "subagent";
  const started = ms(t.activityRunStartedAt) ?? ms(t.latestRunStartedAt) ?? ms(t.latestRunRequestedAt);
  const completed = ms(t.latestRunCompletedAt);
  const runStarted = ms(t.latestRunStartedAt);
  const { pr, count } = pickPullRequest(t);
  const selection = isObject(t.modelSelection) ? t.modelSelection : {};
  return {
    key: `${envId}:${t.id}`,
    envId,
    id: clean(t.id, 80),
    parentId: isSubagent ? clean(lineage.rootThreadId || lineage.parentThreadId, 80) : "",
    title: clean(t.title, 140) || "Untitled thread",
    projectId: clean(t.projectId, 80),
    project: clean(project?.title ?? project?.name, 60) || "Project",
    branch: clean(t.branch, 80),
    worktree: typeof t.worktreePath === "string" && t.worktreePath.length > 0,
    provider: clean(t.providerInstanceId, 40),
    model: clean(selection.model, 60),
    mode: clean(t.runtimeMode, 24),
    plan: t.interactionMode === "plan",
    state,
    rawStatus: clean(t.status, 20),
    pendingKind: isObject(t.pendingRuntimeRequest) ? clean(t.pendingRuntimeRequest.kind, 24) : "",
    pendingSince: isObject(t.pendingRuntimeRequest) ? ms(t.pendingRuntimeRequest.createdAt) : null,
    activeSince: BUSY.has(state) || state === "input" ? started : null,
    lastRunMs: completed !== null && runStarted !== null && completed >= runStarted ? completed - runStarted : null,
    completedAt: completed,
    createdAt: ms(t.createdAt),
    updatedAt: ms(t.updatedAt),
    unread: isUnread(t),
    pinned: Boolean(t.pinnedAt),
    settled: Boolean(t.settledAt),
    snoozedUntil: ms(t.snoozedUntil),
    background: backgroundCounts(t),
    pr,
    prCount: count,
    errorClass: clean(t.lastErrorClass, 24),
    error: state === "failed" || state === "limited" ? cleanBlock(t.lastError, 240) : "",
    usageResetAt: ms(t.usageLimitResetAt) ?? ms(t.limitRecovery?.resetAt),
    childCount: 0,
    activeChildren: 0,
    activity: [],
  };
}

export const RECENT_WINDOW = 24 * 3600_000;
const CHILD_RECENT = 2 * 3600_000;
const MAX_CHILDREN = 12;
export const MAX_ROWS = 220;

/** Display sections, in list order; they match the panel's Needs you / Working / Done headings. */
const SECTION: Record<State, number> = {
  input: 0, plan: 0, failed: 0,
  limited: 1, working: 1, waiting: 1, queued: 1, background: 1,
  review: 2, stopped: 3, idle: 4,
};

/** Sort key: needs you first, then busy, then finished, stopped and idle. */
export function rank(row: Row): number {
  return SECTION[row.state];
}

/**
 * List order, by section. Live threads (needs you, working) go oldest first: creation time never
 * changes, so they keep their places while they work instead of swapping on every update; unknown
 * ages sort last. Finished, stopped and idle threads stay still anyway and go most recent first,
 * so the row cap sheds the oldest.
 */
export function compareRows(a: Row, b: Row): number {
  const section = rank(a) - rank(b);
  if (section) return section;
  const age = rank(a) <= 1
    ? (a.createdAt ?? Infinity) - (b.createdAt ?? Infinity)
    : (b.updatedAt ?? 0) - (a.updatedAt ?? 0);
  return age || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0);
}

/**
 * Selects the rows worth shipping: unsettled or pinned roots, anything busy or needing attention,
 * roots touched in the last day, and the live/recent subagents of included roots.
 */
export function buildRows(envId: string, threads: Iterable<Record<string, any>>, projects: Map<string, Record<string, any>>, now = Date.now()): Row[] {
  const all = [...threads].map((t) => toRow(envId, t, projects, now));
  const roots = all.filter((r) => !r.parentId);
  const children = new Map<string, Row[]>();
  for (const r of all) {
    if (!r.parentId) continue;
    const list = children.get(r.parentId) ?? [];
    list.push(r);
    children.set(r.parentId, list);
  }
  const keepRoot = (r: Row) =>
    !r.settled || r.pinned || ATTENTION.has(r.state) || BUSY.has(r.state) || (r.updatedAt ?? 0) > now - RECENT_WINDOW;
  const out: Row[] = [];
  for (const root of roots) {
    const kids = children.get(root.id) ?? [];
    root.childCount = kids.length;
    root.activeChildren = kids.filter((k) => BUSY.has(k.state) || ATTENTION.has(k.state)).length;
    if (!keepRoot(root) && root.activeChildren === 0) continue;
    out.push(root);
    const shown = kids
      .filter((k) => BUSY.has(k.state) || ATTENTION.has(k.state) || (k.updatedAt ?? 0) > now - CHILD_RECENT)
      .sort(compareRows)
      .slice(0, MAX_CHILDREN);
    out.push(...shown);
  }
  // Orphaned children (root not in the active set) surface on their own.
  const rootIds = new Set(roots.map((r) => r.id));
  for (const [parent, kids] of children) {
    if (rootIds.has(parent)) continue;
    out.push(...kids.filter((k) => BUSY.has(k.state) || ATTENTION.has(k.state)).map((k) => ({ ...k, parentId: "" })));
  }
  return out.sort(compareRows).slice(0, MAX_ROWS);
}

export interface Counts {
  active: number;    // unsettled root threads
  busy: number;      // roots working/waiting/queued/background
  attention: number; // roots needing input / plan review / failed
  input: number;
  review: number;    // finished, unseen
}

export function countRows(rows: Row[]): Counts {
  const roots = rows.filter((r) => !r.parentId);
  return {
    active: roots.filter((r) => !r.settled || BUSY.has(r.state) || ATTENTION.has(r.state)).length,
    busy: roots.filter((r) => BUSY.has(r.state)).length,
    attention: roots.filter((r) => ATTENTION.has(r.state)).length,
    input: roots.filter((r) => r.state === "input").length,
    review: roots.filter((r) => r.state === "review").length,
  };
}

/** Maps a T3 turn item to the icon T3's timeline would show (MessagesTimeline.tsx workEntryIconName). */
export function activityIcon(item: Record<string, any>): string {
  if (item.toolSurface === "browser") return "app-window";
  if (item.toolSurface === "computer") return "monitor";
  switch (item.type) {
    case "command_execution": return "terminal";
    case "file_change": return "square-pen";
    case "file_search": return "search";
    case "web_search": return "globe";
    case "reasoning": return "brain";
    case "subagent": return "bot";
    case "approval_request":
    case "user_input_request": return "message-circle";
    case "error": return "circle-alert";
    case "todo_list":
    case "proposed_plan": return "list-todo";
    case "assistant_message": return "sparkles";
    case "checkpoint": return "check";
    case "compaction": return "layers";
    case "notification": {
      if (item.outcome === "failed") return "circle-alert";
      const kind = item.source?.kind;
      return kind === "subagent" || kind === "delegated_task" ? "bot" : kind === "command" ? "terminal" : kind === "monitor" ? "eye" : "zap";
    }
    case "dynamic_tool": {
      const name = String(item.toolName ?? item.title ?? "").toLowerCase();
      if (/\b(read|view|open|cat)\b/.test(name)) return "eye";
      if (/(grep|glob|search|find)/.test(name)) return "search";
      if (/(edit|write|patch)/.test(name)) return "square-pen";
      if (/(fetch|web|browse)/.test(name)) return "globe";
      if (/(task|agent|delegate)/.test(name)) return "bot";
      if (/(bash|shell|exec|command)/.test(name)) return "terminal";
      return "hammer";
    }
  }
  return "zap";
}

const ACTIVITY_TYPES = new Set([
  "command_execution", "file_change", "file_search", "web_search", "reasoning", "subagent",
  "approval_request", "user_input_request", "error", "todo_list", "proposed_plan",
  "assistant_message", "dynamic_tool", "notification", "compaction",
]);

/** Short human label for an activity line. */
export function activityLabel(item: Record<string, any>): string {
  switch (item.type) {
    case "command_execution": return clean(item.input, 160) || clean(item.title, 160) || "Command";
    case "file_change": return clean(item.title, 160) || clean(item.fileName, 160) || "Edit";
    case "file_search": return clean(item.title, 160) || clean(item.pattern, 160) || "Search";
    case "web_search": return clean(item.title, 160) || clean(Array.isArray(item.patterns) ? item.patterns.join(", ") : "", 160) || "Web search";
    case "reasoning": return item.status === "running" ? "Thinking" : "Thought";
    case "assistant_message": return clean(item.markdown ?? item.text, 160) || "Writing";
    case "approval_request": return clean(item.prompt, 160) || "Awaiting approval";
    case "user_input_request": return clean(item.questions?.[0]?.question, 160) || "Question";
    case "subagent": return clean(item.title, 160) || "Subagent";
    case "todo_list": return "Updated plan";
    case "proposed_plan": return "Proposed plan";
    case "error": return clean(item.failure?.message ?? item.title, 160) || "Error";
    case "notification": return clean(item.summary ?? item.title, 160) || "Notification";
    default: return clean(item.title, 160) || clean(item.toolName, 160) || "Tool";
  }
}

export function toActivity(item: Record<string, any>): Activity | null {
  if (!isObject(item) || !ACTIVITY_TYPES.has(item.type)) return null;
  return {
    icon: activityIcon(item),
    label: activityLabel(item),
    status: clean(item.status, 16),
    at: ms(item.updatedAt) ?? ms(item.createdAt) ?? ms(item.startedAt),
  };
}
