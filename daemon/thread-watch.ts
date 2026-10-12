// Reduced replica of one thread's projection, fed by orchestration.subscribeThread.
// Holds only what the monitor shows: activity trail, pending request text, runs,
// context usage, subagents and plan progress. Everything else is dropped on arrival.
import { type Activity, toActivity } from "./model.ts";
import { clean, cleanBlock, isObject, ms } from "./util.ts";

const KEEP_ITEMS = 40;
const SHOW_ACTIVITY = 6;
const SHOW_RUNS = 12;
const SHOW_SUBAGENTS = 12;

export interface PendingDetail {
  id: string;
  kind: string;
  since: number | null;
  prompt: string;
  appName: string;
  options: string[];
  questions: { header: string; question: string; options: string[] }[];
}

export interface RunSummary {
  ordinal: number;
  status: string;
  startedAt: number | null;
  completedAt: number | null;
  durationMs: number | null;
}

export interface SubagentSummary {
  id: string;
  title: string;
  status: string;
  progress: string;
  model: string;
  startedAt: number | null;
  completedAt: number | null;
  childThreadId: string;
}

export interface Detail {
  activity: Activity[];
  pending: PendingDetail[];
  runs: RunSummary[];
  context: { used: number; max: number; cost: number | null; currency: string } | null;
  subagents: SubagentSummary[];
  todo: { total: number; done: number; current: string } | null;
}

interface ItemSlot { ordinal: number; raw: Record<string, any> }

export class ThreadWatch {
  sequence = -1;
  synchronized = false;
  private items = new Map<string, ItemSlot>();
  private requests = new Map<string, Record<string, any>>();
  private runs = new Map<string, Record<string, any>>();
  private providerThreads = new Map<string, Record<string, any>>();
  private subagents = new Map<string, Record<string, any>>();

  /** Returns true when something visible changed. */
  apply(item: unknown): boolean {
    if (!isObject(item)) return false;
    if (item.kind === "synchronized") {
      this.synchronized = true;
      return false;
    }
    if (item.kind === "snapshot" && isObject(item.projection)) {
      this.reset(item.projection);
      if (typeof item.snapshotSequence === "number") this.sequence = item.snapshotSequence;
      return true;
    }
    if (item.kind === "event" && isObject(item.event)) {
      if (typeof item.sequence === "number") {
        if (item.sequence <= this.sequence) return false;
        this.sequence = item.sequence;
      }
      return this.event(item.event);
    }
    return false;
  }

  private reset(p: Record<string, any>) {
    this.items.clear();
    this.requests.clear();
    this.runs.clear();
    this.providerThreads.clear();
    this.subagents.clear();
    const items = (Array.isArray(p.turnItems) ? p.turnItems : []).filter(isObject);
    for (const raw of items.slice(-KEEP_ITEMS)) this.putItem(raw);
    for (const r of arr(p.runtimeRequests)) this.requests.set(r.id, r);
    for (const r of arr(p.runs)) this.runs.set(r.id, r);
    for (const t of arr(p.providerThreads)) this.providerThreads.set(t.id, t);
    for (const s of arr(p.subagents)) this.subagents.set(s.id, s);
  }

  private event(e: Record<string, any>): boolean {
    const payload = e.payload;
    if (!isObject(payload) || typeof payload.id !== "string") return false;
    switch (e.type) {
      case "turn-item.updated":
        this.putItem(payload);
        return true;
      case "runtime-request.updated":
        this.requests.set(payload.id, payload);
        return true;
      case "run.created":
      case "run.updated":
        this.runs.set(payload.id, payload);
        return true;
      case "provider-thread.updated":
        this.providerThreads.set(payload.id, payload);
        return true;
      case "subagent.updated":
        this.subagents.set(payload.id, payload);
        return true;
    }
    return false;
  }

  private putItem(raw: Record<string, any>) {
    if (typeof raw.id !== "string") return;
    // Keep only fields the labels/icons/pending text need; drop outputs, diffs and bodies.
    const slim: Record<string, any> = {
      id: raw.id, type: raw.type, status: raw.status, title: raw.title, toolSurface: raw.toolSurface,
      toolName: raw.toolName, input: typeof raw.input === "string" ? raw.input.slice(0, 2000) : undefined,
      fileName: raw.fileName, pattern: raw.pattern, patterns: raw.patterns, outcome: raw.outcome,
      source: isObject(raw.source) ? { kind: raw.source.kind } : undefined, summary: raw.summary,
      failure: isObject(raw.failure) ? { message: raw.failure.message } : undefined,
      text: raw.type === "assistant_message" && typeof raw.text === "string" ? raw.text.slice(-400) : undefined,
      requestId: raw.requestId, requestKind: raw.requestKind,
      prompt: typeof raw.prompt === "string" ? raw.prompt.slice(0, 4000) : undefined, appName: raw.appName,
      options: raw.options, questions: raw.questions,
      steps: raw.type === "todo_list" ? raw.steps : undefined,
      providerTurnId: raw.providerTurnId,
      updatedAt: raw.updatedAt, startedAt: raw.startedAt,
    };
    const ordinal = typeof raw.ordinal === "number" ? raw.ordinal : (this.items.get(raw.id)?.ordinal ?? Number.MAX_SAFE_INTEGER);
    this.items.set(raw.id, { ordinal, raw: slim });
    if (this.items.size > KEEP_ITEMS) {
      const oldest = [...this.items.entries()].sort((a, b) => a[1].ordinal - b[1].ordinal)[0];
      // Never evict the item a pending request points at.
      const pendingIds = new Set([...this.requests.values()].filter((r) => r.status === "pending").map((r) => r.id));
      if (!pendingIds.has(oldest[1].raw.requestId)) this.items.delete(oldest[0]);
    }
  }

  private orderedItems(): Record<string, any>[] {
    return [...this.items.values()].sort((a, b) => a.ordinal - b.ordinal).map((s) => s.raw);
  }

  detail(): Detail {
    const items = this.orderedItems();
    const activity = items
      .filter((i) => i.type !== "user_message" && i.type !== "checkpoint")
      .map(toActivity)
      .filter((a): a is Activity => a !== null)
      .slice(-SHOW_ACTIVITY);

    const pending: PendingDetail[] = [];
    for (const r of this.requests.values()) {
      if (r.status !== "pending") continue;
      const approval = items.find((i) => i.requestId === r.id && i.type === "approval_request");
      const question = items.find((i) => i.requestId === r.id && i.type === "user_input_request");
      let prompt = cleanBlock(approval?.prompt, 1200);
      if (!prompt && (r.kind === "command" || approval?.requestKind === "command")) {
        // Providers often put the command on the running command item instead of the approval.
        const command = [...items].reverse().find((i) => i.type === "command_execution" && i.status !== "completed");
        prompt = cleanBlock(command?.input ?? command?.title, 1200);
      }
      if (!prompt && (r.kind === "file-change" || approval?.requestKind === "file-change")) {
        const files = items.filter((i) => i.type === "file_change" && i.status !== "completed").map((i) => i.fileName || i.title).filter(Boolean);
        prompt = cleanBlock(files.join("\n"), 1200);
      }
      pending.push({
        id: clean(r.id, 80),
        kind: clean(r.kind, 24),
        since: ms(r.createdAt),
        prompt,
        appName: clean(approval?.appName, 60),
        options: (Array.isArray(approval?.options) ? approval.options : []).map((o: any) => clean(o?.label, 40)).filter(Boolean).slice(0, 6),
        questions: (Array.isArray(question?.questions) ? question.questions : []).slice(0, 4).map((q: any) => ({
          header: clean(q?.header, 60),
          question: cleanBlock(q?.question, 600),
          options: (Array.isArray(q?.options) ? q.options : []).map((o: any) => clean(o?.label, 60)).filter(Boolean).slice(0, 8),
        })),
      });
    }

    const runs = [...this.runs.values()]
      .sort((a, b) => (a.ordinal ?? 0) - (b.ordinal ?? 0))
      .slice(-SHOW_RUNS)
      .map((r) => {
        const started = ms(r.workStartedAt) ?? ms(r.startedAt);
        const completed = ms(r.completedAt);
        return {
          ordinal: typeof r.ordinal === "number" ? r.ordinal : 0,
          status: clean(r.status, 16),
          startedAt: started,
          completedAt: completed,
          durationMs: started !== null && completed !== null && completed >= started ? completed - started : null,
        };
      });

    let context: Detail["context"] = null;
    const threads = [...this.providerThreads.values()].filter((t) => isObject(t.contextUsage));
    const active = threads.find((t) => t.status === "active") ?? threads.at(-1);
    if (active) {
      const u = active.contextUsage;
      context = {
        used: Number.isFinite(u.usedTokens) ? u.usedTokens : 0,
        max: Number.isFinite(u.maxTokens) ? u.maxTokens : 0,
        cost: isObject(u.cost) && Number.isFinite(u.cost.amount) ? u.cost.amount : null,
        currency: isObject(u.cost) ? clean(u.cost.currency, 8) : "",
      };
    }

    const subagents = [...this.subagents.values()]
      .sort((a, b) => (ms(b.updatedAt) ?? 0) - (ms(a.updatedAt) ?? 0))
      .slice(0, SHOW_SUBAGENTS)
      .map((s) => ({
        id: clean(s.id, 80),
        title: clean(s.title, 120) || clean(s.prompt, 120) || "Subagent",
        status: clean(s.status, 16),
        progress: clean(s.progress, 160),
        model: clean(s.model, 60),
        startedAt: ms(s.startedAt),
        completedAt: ms(s.completedAt),
        childThreadId: clean(s.childThreadId, 80),
      }));

    let todo: Detail["todo"] = null;
    const list = [...items].reverse().find((i) => i.type === "todo_list" && Array.isArray(i.steps));
    if (list) {
      const steps = list.steps.filter(isObject);
      todo = {
        total: steps.length,
        done: steps.filter((s: any) => s.status === "completed").length,
        current: clean(steps.find((s: any) => s.status === "running")?.text, 140),
      };
    }

    return { activity, pending, runs, context, subagents, todo };
  }
}

function arr(value: unknown): Record<string, any>[] {
  return Array.isArray(value) ? value.filter((v): v is Record<string, any> => isObject(v) && typeof v.id === "string") : [];
}
