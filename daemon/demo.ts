// Synthetic feed covering every display state, for UI development and screenshots.
// Enable with {"demo": true} in ~/.config/t3-loupe/settings.json, or run `main.ts demo`.
import { createInterface } from "node:readline";
import { handleDesktopCommand } from "./desktop.ts";
import type { Row } from "./model.ts";
import type { Detail } from "./thread-watch.ts";

const MIN = 60_000;

function row(partial: Partial<Row> & Pick<Row, "id" | "envId" | "title" | "state">): Row {
  return {
    key: `${partial.envId}:${partial.id}`, parentId: "", projectId: "p", project: "t3-code", branch: "", worktree: false,
    provider: "claudeAgent", model: "claude-opus-5-5", mode: "full-access", plan: false, rawStatus: "completed",
    pendingKind: "", pendingSince: null, activeSince: null, lastRunMs: null, completedAt: null, updatedAt: Date.now(),
    unread: false, pinned: false, settled: false, snoozedUntil: null,
    background: { subagents: 0, commands: 0, monitors: 0, other: 0 }, pr: null, prCount: 0, errorClass: "", error: "",
    usageResetAt: null, childCount: 0, activeChildren: 0, activity: [], ...partial,
  };
}

export function runDemo(write: (m: Record<string, unknown>) => void) {
  const t0 = Date.now();
  const at = (minsAgo: number) => t0 - minsAgo * MIN;
  const env = { a: "demo-laptop", b: "demo-server" };
  const rows: Row[] = [
    row({ envId: env.a, id: "approve", title: "Migrate auth middleware to sessions v2", state: "input", rawStatus: "running", pendingKind: "command",
      pendingSince: at(2), activeSince: at(14), project: "web-app", branch: "feat/sessions-v2",
      activity: [{ icon: "terminal", label: "pnpm vitest run auth", status: "completed", at: at(3) }, { icon: "message-circle", label: "Awaiting approval", status: "pending", at: at(2) }] }),
    row({ envId: env.b, id: "question", title: "Pick a queue backend for the ingest worker", state: "input", rawStatus: "running", pendingKind: "user_input",
      pendingSince: at(6), activeSince: at(9), project: "ingest", provider: "codex", model: "gpt-6.1-sol" }),
    row({ envId: env.a, id: "plan", title: "Plan: split the monorepo build into stages", state: "plan", project: "infra", completedAt: at(4), lastRunMs: 6 * MIN, unread: true }),
    row({ envId: env.b, id: "failed", title: "Regenerate API client from OpenAPI", state: "failed", rawStatus: "failed", project: "sdk",
      errorClass: "provider_error", error: "Provider stream closed unexpectedly (502 from upstream) after 41 tool calls.", completedAt: at(11) }),
    row({ envId: env.a, id: "work", title: "Design a robust T3 Loupe plugin", state: "working", rawStatus: "running", activeSince: at(23), project: "t3-loupe", branch: "main",
      background: { subagents: 2, commands: 0, monitors: 0, other: 0 }, childCount: 3, activeChildren: 2,
      pr: { number: 412, title: "Live thread monitor v2", url: "https://example.invalid/pr/412", state: "open", checks: "pending", draft: false, additions: 2140, deletions: 388, review: "" }, prCount: 1,
      activity: [{ icon: "brain", label: "Thought", status: "completed", at: at(1) }, { icon: "square-pen", label: "Edit plugin/ThreadsPanel.qml", status: "running", at: t0 }] }),
    row({ envId: env.a, id: "sub1", parentId: "work", title: "Palette contrast tests across themes", state: "working", rawStatus: "running", activeSince: at(4), model: "glm-5.3-flash", provider: "acpRegistry_glm_agent",
      activity: [{ icon: "terminal", label: "node --test tests/palette.test.mjs", status: "running", at: t0 }] }),
    row({ envId: env.a, id: "sub2", parentId: "work", title: "Survey Omarchy shell UI kit", state: "working", rawStatus: "running", activeSince: at(7), model: "gpt-6.1-sol", provider: "codex",
      activity: [{ icon: "search", label: "grep KeyboardPanel /usr/share/omarchy/shell", status: "running", at: t0 }] }),
    row({ envId: env.b, id: "limited", title: "Bulk-translate docs to German", state: "limited", rawStatus: "failed", project: "docs", provider: "codex", model: "gpt-6.1-sol",
      errorClass: "usage_limit", error: "Usage limit reached for this session window.", usageResetAt: t0 + 47 * MIN }),
    row({ envId: env.b, id: "queued", title: "Bump dependencies and re-run CI", state: "queued", rawStatus: "queued", activeSince: at(1), project: "ingest" }),
    row({ envId: env.b, id: "bench", title: "Benchmark streaming latency across providers", state: "working", rawStatus: "running", activeSince: at(12), project: "research", provider: "codex", model: "gpt-6.1-sol",
      activity: [{ icon: "globe", label: "Search: provider streaming latency p95 2026", status: "running", at: t0 }] }),
    row({ envId: env.a, id: "tooltips", title: "Port notch strip tooltips to the shell API", state: "working", rawStatus: "running", activeSince: at(3), project: "omarchy", branch: "feat/tooltips",
      activity: [{ icon: "eye", label: "Read plugins/bar/Bar.qml", status: "running", at: t0 }] }),
    row({ envId: env.a, id: "onboard", title: "Rework onboarding flow for new users", state: "background", rawStatus: "completed", activeSince: at(9), project: "web-app",
      background: { subagents: 2, commands: 0, monitors: 0, other: 0 },
      activity: [{ icon: "bot", label: "Audit copy across the signup screens", status: "running", at: t0 }] }),
    row({ envId: env.b, id: "migrate", title: "Write the Postgres 18 migration plan", state: "working", rawStatus: "running", activeSince: at(6), project: "infra", provider: "claudeAgent",
      activity: [{ icon: "hammer", label: "pg_upgrade --check (dry run)", status: "running", at: t0 }] }),
    row({ envId: env.a, id: "done", title: "Fix flaky websocket reconnect test", state: "review", project: "web-app", completedAt: at(8), lastRunMs: 19 * MIN, unread: true,
      pr: { number: 409, title: "Deflake reconnect test", url: "https://example.invalid/pr/409", state: "open", checks: "passing", draft: false, additions: 42, deletions: 17, review: "APPROVED" }, prCount: 1 }),
    row({ envId: env.a, id: "idle", title: "Explore notch-aware bar layouts", state: "idle", project: "omarchy", completedAt: at(95), settled: false }),
    row({ envId: env.b, id: "idle2", title: "Draft release notes for 2.4", state: "idle", project: "docs", completedAt: at(180), settled: false }),
    row({ envId: env.a, id: "idle3", title: "Investigate flaky e2e on CI runners", state: "stopped", rawStatus: "interrupted", project: "web-app", completedAt: at(240), settled: false }),
  ];
  const providers = [
    { id: "claudeAgent", name: "Claude", driver: "claudeAgent", status: "ready", auth: "authenticated", version: "", checkedAt: t0,
      windows: [{ label: "Session", kind: "session", usedPercent: 38, resetsAt: t0 + 140 * MIN, durationMins: 300 }, { label: "Weekly", kind: "weekly", usedPercent: 61, resetsAt: t0 + 3 * 1440 * MIN, durationMins: 10080 }] },
    { id: "codex", name: "Codex", driver: "codex", status: "ready", auth: "authenticated", version: "", checkedAt: t0,
      windows: [{ label: "Session", kind: "session", usedPercent: 100, resetsAt: t0 + 47 * MIN, durationMins: 300 }, { label: "Weekly", kind: "weekly", usedPercent: 82, resetsAt: t0 + 5 * 1440 * MIN, durationMins: 10080 }] },
    { id: "pi", name: "Pi", driver: "pi", status: "ready", auth: "authenticated", version: "", checkedAt: t0, windows: [] },
    { id: "amp", name: "Amp", driver: "acpRegistry", status: "warning", auth: "unknown", version: "", checkedAt: t0, windows: [] },
  ];
  const counts = (envId: string) => {
    const roots = rows.filter((r) => r.envId === envId && !r.parentId);
    return { active: roots.length, busy: roots.filter((r) => ["working", "queued", "waiting", "background"].includes(r.state)).length,
      attention: roots.filter((r) => ["input", "plan", "failed"].includes(r.state)).length, input: roots.filter((r) => r.state === "input").length,
      review: roots.filter((r) => r.state === "review").length };
  };
  const environments = [
    { id: env.a, label: "laptop", hostLabel: "laptop", state: "live", stale: false, url: "http://127.0.0.1:3773", serverVersion: "demo", lastLiveAt: t0, sessionExpiresAt: t0 + 20 * 1440 * MIN, retryAt: null, providers, counts: counts(env.a) },
    { id: env.b, label: "build-box", hostLabel: "build-box", state: "live", stale: false, url: "http://127.0.0.1:46363", serverVersion: "demo", lastLiveAt: t0, sessionExpiresAt: t0 + 2 * 1440 * MIN, retryAt: null, providers: providers.slice(0, 2), counts: counts(env.b) },
  ];
  const total = { active: 0, busy: 0, attention: 0, input: 0, review: 0 } as Record<string, number>;
  for (const e of environments) for (const k of Object.keys(total)) total[k] += (e.counts as any)[k];

  const details: Record<string, Detail> = {
    approve: {
      activity: rows[0].activity,
      pending: [{ id: "r1", kind: "command", since: at(2), prompt: "git push --force-with-lease origin feat/sessions-v2 && pnpm db:migrate --env staging", appName: "", options: ["Allow once", "Allow for session", "Decline"], questions: [] }],
      runs: [{ ordinal: 1, status: "completed", startedAt: at(60), completedAt: at(52), durationMs: 8 * MIN }, { ordinal: 2, status: "running", startedAt: at(14), completedAt: null, durationMs: null }],
      context: { used: 412_000, max: 1_000_000, cost: 3.42, currency: "USD" }, subagents: [], todo: { total: 6, done: 4, current: "Run the migration against staging" },
    },
    question: {
      activity: [{ icon: "search", label: "Compare SQS, NATS JetStream and Redis Streams", status: "completed", at: at(7) }, { icon: "message-circle", label: "Question", status: "pending", at: at(6) }],
      pending: [{ id: "r2", kind: "user_input", since: at(6), prompt: "", appName: "", options: [], questions: [{ header: "Queue backend", question: "Which queue should the ingest worker use? Throughput target is ~4k msg/s with at-least-once delivery.", options: ["NATS JetStream", "Redis Streams", "SQS"] }] }],
      runs: [{ ordinal: 1, status: "running", startedAt: at(9), completedAt: null, durationMs: null }], context: { used: 88_000, max: 400_000, cost: null, currency: "" }, subagents: [], todo: null,
    },
    work: {
      activity: [
        { icon: "eye", label: "Read plugin/components/ThreadCard.qml", status: "completed", at: at(4) },
        { icon: "terminal", label: "node --test tests/", status: "completed", at: at(3) },
        { icon: "bot", label: "Palette contrast tests across themes", status: "running", at: at(4) },
        { icon: "brain", label: "Thought", status: "completed", at: at(1) },
        { icon: "square-pen", label: "Edit plugin/ThreadsPanel.qml", status: "running", at: t0 },
      ],
      pending: [],
      runs: [5, 12, 3, 22, 9, 31, 14].map((m, i) => ({ ordinal: i + 1, status: i === 3 ? "failed" : "completed", startedAt: at(200 - i * 25), completedAt: at(200 - i * 25 - m), durationMs: m * MIN }))
        .concat([{ ordinal: 8, status: "running", startedAt: at(23), completedAt: null, durationMs: null }]),
      context: { used: 731_000, max: 1_000_000, cost: 12.8, currency: "USD" },
      subagents: [
        { id: "s1", title: "Palette contrast tests across themes", status: "running", progress: "18 of 22 themes", model: "glm-5.3-flash", startedAt: at(4), completedAt: null, childThreadId: "sub1" },
        { id: "s2", title: "Survey Omarchy shell UI kit", status: "running", progress: "", model: "gpt-6.1-sol", startedAt: at(7), completedAt: null, childThreadId: "sub2" },
        { id: "s3", title: "Record live WebSocket frames", status: "completed", progress: "", model: "glm-5.3", startedAt: at(40), completedAt: at(36), childThreadId: "" },
      ],
      todo: { total: 9, done: 6, current: "Polish the panel and verify every theme" },
    },
  };

  const emit = () => write({ type: "state", at: Date.now(), environments, rows, counts: total, known: true });
  emit();
  setInterval(emit, 5000);
  createInterface({ input: process.stdin }).on("line", (line) => {
    try {
      const cmd = JSON.parse(line);
      if (cmd.cmd === "copy") {
        void handleDesktopCommand(cmd);
      } else if (cmd.cmd === "detail") {
        const id = String(cmd.threadId);
        const d = details[id] ?? { activity: rows.find((r) => r.id === id)?.activity ?? [], pending: [], runs: [], context: null, subagents: [], todo: null };
        write({ type: "detail", envId: cmd.envId, threadId: id, detail: d });
      } else if (cmd.cmd === "notice-test") {
        write({ type: "notice", kind: "needs_input", severity: "attention", envId: env.a, threadId: "approve", title: "Migrate auth middleware wants to run a command", body: "web-app · laptop", at: Date.now(), envLabel: "laptop" });
      }
    } catch {}
  });
}
