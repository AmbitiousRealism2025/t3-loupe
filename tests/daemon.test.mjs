import test from "node:test";
import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, symlinkSync, writeFileSync, mkdirSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FakeT3 } from "./lib/fake-t3.mjs";

const D = "../daemon/";
const { ShellStore } = await import(D + "shell-store.ts");
const { classify, buildRows, compareRows, countRows, activityIcon, isUnread } = await import(D + "model.ts");
const { TransitionDetector } = await import(D + "events.ts");
const { ThreadWatch } = await import(D + "thread-watch.ts");
const { loadConfig, saveConfig, upsertEnvironment } = await import(D + "config.ts");
const { tunnelUrl } = await import(D + "tunnel.ts");
const { checkEndpoint, requestJson } = await import(D + "http.ts");
const { EnvironmentConnection } = await import(D + "connection.ts");
const { assertOwnListener, listenerUids } = await import(D + "listener.ts");
const { extractCredential } = await import(D + "pairing.ts");

const iso = (msAgo) => new Date(Date.now() - msAgo).toISOString();
function thread(id, extra = {}) {
  return {
    id, projectId: "p1", title: `Thread ${id}`, status: "idle", activityRunStatus: null, pendingRuntimeRequest: null,
    pendingBackgroundTasks: [], lineage: { parentThreadId: null, relationshipToParent: null, rootThreadId: id },
    modelSelection: { model: "m" }, providerInstanceId: "codex", updatedAt: iso(1000), settledAt: null,
    latestRunCompletedAt: null, lastVisitedAt: null, pullRequests: [], archivedAt: null, deletedAt: null, ...extra,
  };
}
const projects = new Map([["p1", { id: "p1", title: "Proj" }]]);

// ---------- shell store ----------

test("shell store: snapshot resets, metadata snapshot keeps threads, stale sequences ignored", () => {
  const s = new ShellStore();
  s.apply({ kind: "snapshot", snapshot: { schemaVersion: 2, snapshotSequence: 5, projects: [{ id: "p1", title: "A" }], threads: [thread("t1"), thread("t2")] } });
  assert.equal(s.threads.size, 2);
  s.apply({ kind: "snapshot", resolvedRepositoryIdentityRoots: [], snapshot: { schemaVersion: 2, snapshotSequence: 5, projects: [{ id: "p1", title: "B" }], threads: [] } });
  assert.equal(s.threads.size, 2, "metadata-only snapshot must not clear threads");
  assert.equal(s.projects.get("p1").title, "B");
  s.apply({ kind: "thread.updated", sequence: 4, thread: thread("t3") });
  assert.equal(s.threads.has("t3"), false, "replayed event at/below sequence is a duplicate");
  s.apply({ kind: "thread.updated", sequence: 6, thread: thread("t3") });
  assert.equal(s.threads.has("t3"), true);
  s.apply({ kind: "thread.updated", sequence: 7, thread: thread("t1", { archivedAt: iso(0) }) });
  assert.equal(s.threads.has("t1"), false, "archived threads leave the active set");
  s.apply({ kind: "thread.removed", sequence: 8, threadId: "t2" });
  assert.equal(s.threads.size, 1);
  assert.throws(() => s.apply({ kind: "snapshot", snapshot: { schemaVersion: 3, threads: [], projects: [] } }));
});

// ---------- model ----------

test("classify maps T3 status into display states", () => {
  assert.equal(classify(thread("a", { pendingRuntimeRequest: { kind: "command", createdAt: iso(0) }, activityRunStatus: "running" })), "input");
  assert.equal(classify(thread("a", { activityRunStatus: "running", status: "running" })), "working");
  assert.equal(classify(thread("a", { activityRunStatus: "waiting" })), "waiting");
  assert.equal(classify(thread("a", { status: "queued" })), "queued");
  assert.equal(classify(thread("a", { status: "completed", hasActionableProposedPlan: true })), "plan");
  assert.equal(classify(thread("a", { status: "completed", pendingBackgroundTasks: [{ kind: "subagent" }] })), "background");
  assert.equal(classify(thread("a", { status: "failed", lastErrorClass: "usage_limit", usageLimitResetAt: new Date(Date.now() + 60000).toISOString() })), "limited");
  assert.equal(classify(thread("a", { status: "failed", lastErrorClass: "usage_limit", usageLimitResetAt: iso(60000) })), "failed");
  assert.equal(classify(thread("a", { status: "failed" })), "failed");
  assert.equal(classify(thread("a", { status: "interrupted" })), "stopped");
  assert.equal(classify(thread("a", { status: "completed", latestRunCompletedAt: iso(1000), lastVisitedAt: iso(5000) })), "review");
  assert.equal(classify(thread("a", { status: "completed", latestRunCompletedAt: iso(5000), lastVisitedAt: iso(1000) })), "idle");
});

test("subagent threads are never unread", () => {
  assert.equal(isUnread(thread("s", { latestRunCompletedAt: iso(0), lineage: { relationshipToParent: "subagent", rootThreadId: "r" } })), false);
});

test("buildRows keeps active roots, nests live children, drops old settled threads", () => {
  const rows = buildRows("e", [
    thread("root", { activityRunStatus: "running" }),
    thread("kid", { activityRunStatus: "running", lineage: { relationshipToParent: "subagent", rootThreadId: "root", parentThreadId: "root" } }),
    thread("oldkid", { status: "completed", updatedAt: iso(5 * 3600_000), lineage: { relationshipToParent: "subagent", rootThreadId: "root" } }),
    thread("settled-old", { settledAt: iso(9e7), updatedAt: iso(9e7) }),
    thread("settled-recent", { settledAt: iso(1000), updatedAt: iso(1000) }),
  ], projects);
  const ids = rows.map((r) => r.id);
  assert.deepEqual(ids.sort(), ["kid", "root", "settled-recent"].sort());
  const root = rows.find((r) => r.id === "root");
  assert.equal(root.childCount, 2);
  assert.equal(root.activeChildren, 1);
  assert.equal(rows.find((r) => r.id === "kid").parentId, "root");
  assert.equal(root.project, "Proj");
  const counts = countRows(rows);
  assert.equal(counts.busy, 1);
});

test("live threads keep their places: oldest first, whatever updated last", () => {
  const busy = (id, created, updated, extra = {}) =>
    thread(id, { activityRunStatus: "running", createdAt: iso(created), updatedAt: iso(updated), ...extra });
  const order = (threads) => buildRows("e", threads, projects).map((r) => r.id);
  const a = busy("old", 3 * 3600_000, 5000), b = busy("mid", 2 * 3600_000, 9000), c = busy("new", 3600_000, 1000);
  assert.deepEqual(order([c, a, b]), ["old", "mid", "new"]);
  // Fresh activity on the newest thread, or a run finalizing (waiting), never moves it up.
  assert.deepEqual(order([busy("new", 3600_000, 0), a, b]), ["old", "mid", "new"]);
  assert.deepEqual(order([c, b, busy("old", 3 * 3600_000, 0, { activityRunStatus: "waiting" })]), ["old", "mid", "new"]);
  // Needs you still comes first, also oldest first; idle goes most recently touched first.
  const rows = order([
    c, a,
    thread("ask-new", { pendingRuntimeRequest: { kind: "command", createdAt: iso(0) }, createdAt: iso(1000) }),
    thread("plan-old", { hasActionableProposedPlan: true, createdAt: iso(9e6) }),
    thread("idle-stale", { createdAt: iso(9e6), updatedAt: iso(9e6) }),
    thread("idle-fresh", { createdAt: iso(9e6 + 1), updatedAt: iso(1000) }),
  ]);
  assert.deepEqual(rows, ["plan-old", "ask-new", "old", "new", "idle-fresh", "idle-stale"]);
});

test("rows from several machines merge into one order", () => {
  const busy = (id, created) => thread(id, { activityRunStatus: "running", createdAt: iso(created) });
  const laptop = buildRows("laptop", [busy("l-new", 1000), busy("l-old", 9000)], projects);
  const server = buildRows("server", [busy("s-mid", 5000), thread("s-ask", { pendingRuntimeRequest: { kind: "command", createdAt: iso(0) } })], projects);
  assert.deepEqual([...laptop, ...server].sort(compareRows).map((r) => r.id), ["s-ask", "l-old", "s-mid", "l-new"]);
});

test("activity icons follow T3's timeline mapping", () => {
  assert.equal(activityIcon({ type: "command_execution" }), "terminal");
  assert.equal(activityIcon({ type: "file_change" }), "square-pen");
  assert.equal(activityIcon({ type: "reasoning" }), "brain");
  assert.equal(activityIcon({ type: "subagent" }), "bot");
  assert.equal(activityIcon({ type: "approval_request" }), "message-circle");
  assert.equal(activityIcon({ type: "dynamic_tool", toolName: "Read" }), "eye");
  assert.equal(activityIcon({ type: "dynamic_tool", toolName: "Grep" }), "search");
  assert.equal(activityIcon({ type: "dynamic_tool", toolName: "mcp__x__thing" }), "hammer");
  assert.equal(activityIcon({ type: "notification", source: { kind: "monitor" } }), "eye");
  assert.equal(activityIcon({ type: "web_search" }), "globe");
});

// ---------- transitions ----------

test("transitions: silent until synchronized, then one notice per change", () => {
  const d = new TransitionDetector();
  const working = buildRows("e", [thread("a", { activityRunStatus: "running" })], projects);
  assert.deepEqual(d.diff(working, "Mac", false), []);
  assert.deepEqual(d.diff(working, "Mac", true), [], "first synchronized pass only arms the detector");
  const input = buildRows("e", [thread("a", { activityRunStatus: "running", pendingRuntimeRequest: { kind: "command", createdAt: iso(0) } })], projects);
  const n = d.diff(input, "Mac", true);
  assert.equal(n.length, 1);
  assert.equal(n[0].kind, "needs_input");
  assert.match(n[0].title, /wants to run a command/);
  assert.deepEqual(d.diff(input, "Mac", true), [], "no repeat while unchanged");
});

test("transitions: long unread completion is a milestone; short or seen ones are not", () => {
  const d = new TransitionDetector();
  const running = (id) => thread(id, { activityRunStatus: "running", latestRunStartedAt: iso(5 * 60_000) });
  d.diff(buildRows("e", [running("long"), running("seen"), thread("short", { activityRunStatus: "running", latestRunStartedAt: iso(5000) })], projects), "Mac", true);
  const done = buildRows("e", [
    thread("long", { status: "completed", latestRunStartedAt: iso(5 * 60_000), latestRunCompletedAt: iso(0) }),
    thread("seen", { status: "completed", latestRunStartedAt: iso(5 * 60_000), latestRunCompletedAt: iso(1000), lastVisitedAt: iso(0) }),
    thread("short", { status: "completed", latestRunStartedAt: iso(5000), latestRunCompletedAt: iso(0) }),
  ], projects);
  const kinds = d.diff(done, "Mac", true).map((n) => `${n.kind}:${n.threadId}`);
  assert.deepEqual(kinds, ["run_completed:long"]);
});

test("transitions: PR merged and checks failing", () => {
  const d = new TransitionDetector();
  const pr = (state, checks) => thread("a", { status: "completed", pullRequests: [{ repository: "r", number: 7, url: "https://x/7", linkedAt: iso(0), snapshot: { state, checksState: checks, title: "T" } }] });
  d.diff(buildRows("e", [pr("open", "pending")], projects), "Mac", true);
  assert.deepEqual(d.diff(buildRows("e", [pr("open", "failing")], projects), "Mac", true).map((n) => n.kind), ["checks_failed"]);
  assert.deepEqual(d.diff(buildRows("e", [pr("merged", "failing")], projects), "Mac", true).map((n) => n.kind), ["pr_merged"]);
});

// ---------- thread watch ----------

test("thread watch: activity trail, pending command text, context, sequence dedupe", () => {
  const w = new ThreadWatch();
  w.apply({ kind: "snapshot", snapshotSequence: 3, projection: {
    turnItems: [
      { id: "i1", ordinal: 1, type: "reasoning", status: "completed", updatedAt: iso(3000) },
      { id: "i2", ordinal: 2, type: "command_execution", status: "running", input: "rm -rf build && make", updatedAt: iso(1000) },
      { id: "i3", ordinal: 3, type: "approval_request", status: "pending", requestId: "r1", requestKind: "command", options: [{ label: "Allow" }, { label: "Decline" }], updatedAt: iso(500) },
    ],
    runtimeRequests: [{ id: "r1", kind: "command", status: "pending", createdAt: iso(500) }],
    providerThreads: [{ id: "pt", status: "active", contextUsage: { usedTokens: 500, maxTokens: 1000, cost: { amount: 1.5, currency: "USD" } } }],
    runs: [{ id: "run1", ordinal: 1, status: "running", startedAt: iso(60000), completedAt: null }],
    subagents: [],
  } });
  let d = w.detail();
  assert.deepEqual(d.activity.map((a) => a.icon), ["brain", "terminal", "message-circle"]);
  assert.equal(d.pending.length, 1);
  assert.equal(d.pending[0].prompt, "rm -rf build && make", "falls back to the running command's input");
  assert.deepEqual(d.pending[0].options, ["Allow", "Decline"]);
  assert.deepEqual(d.context, { used: 500, max: 1000, cost: 1.5, currency: "USD" });
  assert.equal(w.apply({ kind: "event", sequence: 2, event: { type: "turn-item.updated", payload: { id: "i9", ordinal: 9, type: "web_search" } } }), false);
  assert.equal(w.apply({ kind: "event", sequence: 4, event: { type: "runtime-request.updated", payload: { id: "r1", kind: "command", status: "resolved" } } }), true);
  d = w.detail();
  assert.equal(d.pending.length, 0);
});

// ---------- config ----------

test("config: private round trip keyed by environmentId", () => {
  const dir = join(mkdtempSync(join(tmpdir(), "t3t-")), "cfg");
  const env = { environmentId: "e1", label: "Mac", url: "http://127.0.0.1:3773", token: "t", expiresAt: 1 };
  saveConfig(upsertEnvironment({ version: 1, environments: [] }, env), dir);
  const renamed = upsertEnvironment(loadConfig(dir), { ...env, label: "Laptop" });
  assert.equal(renamed.environments.length, 1, "relabel replaces by identity, not by label");
  saveConfig(renamed, dir);
  assert.equal(loadConfig(dir).environments[0].label, "Laptop");
});

test("config: rejects readable-by-others files and symlinks", () => {
  const dir = mkdtempSync(join(tmpdir(), "t3t-"));
  chmodSync(dir, 0o700);
  writeFileSync(join(dir, "connections.json"), JSON.stringify({ version: 1, environments: [] }), { mode: 0o644 });
  assert.throws(() => loadConfig(dir), /private_config_required/);
  const dir2 = mkdtempSync(join(tmpdir(), "t3t-"));
  chmodSync(dir2, 0o700);
  writeFileSync(join(dir2, "real.json"), "{}", { mode: 0o600 });
  symlinkSync(join(dir2, "real.json"), join(dir2, "connections.json"));
  assert.throws(() => loadConfig(dir2), /private_config_required/);
  const open = mkdtempSync(join(tmpdir(), "t3t-"));
  chmodSync(open, 0o755);
  assert.throws(() => loadConfig(open), /private_config_required/);
});

// ---------- tunnel / endpoint / pairing input ----------

test("tunnel discovery only accepts loopback forwards to the configured host", () => {
  assert.equal(tunnelUrl(["ssh", "-N", "-L", "46363:127.0.0.1:3773", "box"], "box"), "http://127.0.0.1:46363");
  assert.equal(tunnelUrl(["ssh", "-L", "127.0.0.1:5000:localhost:3773", "me@box"], "box"), "http://127.0.0.1:5000");
  assert.equal(tunnelUrl(["ssh", "-L", "0.0.0.0:5000:localhost:3773", "box"], "box"), null);
  assert.equal(tunnelUrl(["ssh", "-L", "46363:127.0.0.1:3773", "other"], "box"), null);
  assert.equal(tunnelUrl(["ssh", "-L", "46363:10.0.0.2:3773", "box"], "box"), null);
});

test("endpoint policy: https anywhere, plaintext only on loopback, no credentials or paths", () => {
  assert.ok(checkEndpoint("https://t3.example.com"));
  assert.ok(checkEndpoint("http://127.0.0.1:3773"));
  for (const bad of ["http://192.168.1.4:3773", "https://u:p@x.com", "https://x.com/api", "ftp://x", "http://127.0.0.1:1/?a=1"]) {
    assert.throws(() => checkEndpoint(bad), /endpoint_invalid/, bad);
  }
});

test("pairing input accepts a token or a link with the token in fragment or query", () => {
  assert.equal(extractCredential("  abc  "), "abc");
  assert.equal(extractCredential("https://host/pair#token=xyz"), "xyz");
  assert.equal(extractCredential("https://host/pair?token=q1"), "q1");
});

// ---------- http hardening ----------

test("http: no redirects followed, auth and size failures classified", async () => {
  let redirectedHit = false;
  const server = createServer((req, res) => {
    if (req.url === "/redirect") { res.writeHead(302, { location: "/target" }); return res.end(); }
    if (req.url === "/target") { redirectedHit = true; res.writeHead(200); return res.end("{}"); }
    if (req.url === "/auth") { res.writeHead(401); return res.end(); }
    if (req.url === "/big") { res.writeHead(200); return res.end(JSON.stringify({ x: "y".repeat(5000) })); }
    res.writeHead(200); res.end("[1]");
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    await assert.rejects(requestJson(base, "/redirect", { token: "secret" }), /failed/);
    assert.equal(redirectedHit, false, "bearer token must not follow a redirect");
    await assert.rejects(requestJson(base, "/auth"), /authentication_required/);
    await assert.rejects(requestJson(base, "/big", { maxBytes: 1000 }), /response_too_large/);
    await assert.rejects(requestJson(base, "/array"), /failed/);
  } finally {
    server.close();
  }
});

// ---------- end to end against a fake T3 ----------

function waitFor(predicate, timeout = 4000) {
  const label = predicate.toString();
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const tick = () => (predicate() ? resolve() : Date.now() - start > timeout ? reject(new Error("timeout waiting for " + label)) : setTimeout(tick, 20));
    tick();
  });
}

test("connection: snapshot → live, acks every chunk, applies deltas, resumes after a drop", async () => {
  const fake = new FakeT3({ snapshot: { schemaVersion: 2, snapshotSequence: 10, projects: [{ id: "p1", title: "Proj" }], threads: [thread("t1", { activityRunStatus: "running" })], archivedThreads: [] } });
  const url = await fake.listen();
  const conn = new EnvironmentConnection({ environmentId: "env-1", label: "Fake", url, token: "tok", expiresAt: Date.now() / 1000 + 86400 * 20 });
  const notices = [];
  conn.onNotice = (n) => notices.push(n);
  conn.start();
  try {
    await waitFor(() => conn.state === "live");
    assert.equal(conn.view().rows.length, 1);
    const shell = fake.subscriptions.find((s) => s.tag === "orchestration.subscribeShell");
    assert.equal(shell.payload.requestCompletionMarker, true);
    await waitFor(() => fake.acks(shell.id) >= 2);

    fake.pushShell([{ kind: "thread.updated", sequence: 11, location: "active", thread: thread("t1", { activityRunStatus: "running", pendingRuntimeRequest: { kind: "permission", createdAt: iso(0) } }) }]);
    await waitFor(() => conn.view().rows[0]?.state === "input");
    await waitFor(() => notices.some((n) => n.kind === "needs_input"));

    assert.ok(fake.subscriptions.some((s) => s.tag === "orchestration.subscribeThread" && s.payload.threadId === "t1"), "busy threads get a live activity subscription");

    fake.dropConnections();
    await waitFor(() => conn.state !== "live");
    await waitFor(() => conn.state === "live", 8000);
    const resumed = fake.subscriptions.find((s) => s.tag === "orchestration.subscribeShell");
    assert.equal(resumed.payload.afterSequence, 11, "reconnect resumes from the applied sequence");
    assert.equal(conn.view().rows[0].state, "input", "rows survive a resume without a fresh snapshot");
  } finally {
    conn.stop();
    await fake.close();
  }
});

test("connection: wrong environment identity is refused", async () => {
  const fake = new FakeT3({ environmentId: "someone-else" });
  const url = await fake.listen();
  const conn = new EnvironmentConnection({ environmentId: "env-1", label: "Fake", url, token: "tok", expiresAt: Date.now() / 1000 + 86400 });
  conn.start();
  try {
    await waitFor(() => conn.state === "environment_changed");
  } finally {
    conn.stop();
    await fake.close();
  }
});

test("connection: rejected token reports pairing required", async () => {
  const fake = new FakeT3({ token: "other" });
  const url = await fake.listen();
  const conn = new EnvironmentConnection({ environmentId: "env-1", label: "Fake", url, token: "tok", expiresAt: Date.now() / 1000 + 86400 });
  conn.start();
  try {
    await waitFor(() => conn.state === "authentication_required");
  } finally {
    conn.stop();
    await fake.close();
  }
});

test("connection: a failed descriptor never leads to sending the token", async () => {
  // Marketplace review #11292: a squatter on a vacant loopback port answers the descriptor
  // with HTTP 500; the HTTP fallback must not then send the bearer token.
  const fake = new FakeT3({ descriptorStatus: 500 });
  const url = await fake.listen();
  const conn = new EnvironmentConnection({ environmentId: "env-1", label: "Fake", url, token: "tok", expiresAt: Date.now() / 1000 + 86400 });
  conn.start();
  try {
    await waitFor(() => conn.state === "failed");
    await new Promise((r) => setTimeout(r, 300));
    assert.deepEqual(fake.credentialed, [], "no request may carry the token before identity is verified");
    assert.notEqual(conn.state, "polling");
  } finally {
    conn.stop();
    await fake.close();
  }
});

test("connection: HTTP fallback re-verifies identity before every poll", async () => {
  const fake = new FakeT3({ refuseSocket: true });
  const url = await fake.listen();
  const conn = new EnvironmentConnection({ environmentId: "env-1", label: "Fake", url, token: "tok", expiresAt: Date.now() / 1000 + 86400 });
  conn.start();
  try {
    await waitFor(() => conn.state === "polling");
    assert.ok(fake.credentialed.includes("/api/orchestration/shell"), "the verified server is polled over HTTP");
    // A different server now answers at the same address.
    fake.environmentId = "someone-else";
    fake.credentialed = [];
    assert.equal(await conn.pollOnce(), false);
    assert.deepEqual(fake.credentialed, [], "a poll must not send the token to an unverified server");
    assert.equal(conn.state, "environment_changed");
  } finally {
    conn.stop();
    await fake.close();
  }
});

function fakeProc({ tcp = [], tcp6 = [] }) {
  const root = mkdtempSync(join(tmpdir(), "t3l-proc-"));
  mkdirSync(join(root, "net"));
  const header = "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n";
  const rows = (entries) => entries.map(([address, state, uid], i) => `   ${i}: ${address} 00000000:0000 ${state} 00000000:00000000 00:00000000 00000000 ${uid} 0 ${1000 + i} 1 0 100 0 0 10 0`).join("\n");
  writeFileSync(join(root, "net", "tcp"), header + rows(tcp) + "\n");
  writeFileSync(join(root, "net", "tcp6"), header + rows(tcp6) + "\n");
  return root;
}

test("loopback trust: secrets go only to a listener this user owns", () => {
  const me = 1001, other = 1002;
  const u = new URL("http://127.0.0.1:3773");
  // 127.0.0.1:3773 = 0100007F:0EBD in /proc/net/tcp.
  assert.doesNotThrow(() => assertOwnListener(u, fakeProc({ tcp: [["0100007F:0EBD", "0A", me]] }), me));
  assert.throws(() => assertOwnListener(u, fakeProc({ tcp: [["0100007F:0EBD", "0A", other]] }), me), /listener_untrusted/);
  assert.throws(() => assertOwnListener(u, fakeProc({ tcp: [["00000000:0EBD", "0A", other]] }), me), /listener_untrusted/, "a wildcard listener also answers");
  assert.throws(() => assertOwnListener(u, fakeProc({ tcp6: [["0".repeat(32) + ":0EBD", "0A", other]] }), me), /listener_untrusted/, "a dual-stack :: listener also answers");
  assert.throws(() => assertOwnListener(u, fakeProc({}), me), /offline/, "nothing listening");
  assert.doesNotThrow(() => assertOwnListener(u, fakeProc({ tcp: [["0100007F:0EBD", "0A", me], ["0200007F:0EBD", "0A", other], ["0100007F:0EBD", "01", other]] }), me),
    "other addresses and non-listening sockets are ignored");
  assert.doesNotThrow(() => assertOwnListener(new URL("http://[::1]:3773"), fakeProc({ tcp6: [["00000000000000000000000001000000:0EBD", "0A", me]] }), me));
  assert.throws(() => assertOwnListener(u, join(tmpdir(), "t3l-no-such-proc"), me), /listener_untrusted/, "unknown ownership fails closed");
  assert.doesNotThrow(() => assertOwnListener(new URL("https://t3.example.com"), "/nonexistent", me), "remote HTTPS is not a loopback question");
});

test("loopback trust: the real /proc sees this process's own listener", async () => {
  const server = createServer(() => {});
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  try {
    const { port } = server.address();
    assert.deepEqual(listenerUids("127.0.0.1", port), [process.getuid()]);
    assert.doesNotThrow(() => assertOwnListener(new URL(`http://127.0.0.1:${port}`)));
  } finally {
    server.close();
  }
});

test("session expiry warning fires once per day inside three days", () => {
  const conn = new EnvironmentConnection({ environmentId: "e", label: "Box", url: "http://127.0.0.1:1", token: "t", expiresAt: (Date.now() + 2 * 86400_000) / 1000 });
  const notices = [];
  conn.onNotice = (n) => notices.push(n);
  conn.checkExpiry();
  conn.checkExpiry();
  assert.equal(notices.length, 1);
  assert.equal(notices[0].kind, "session_expiring");
});
