import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./lib/qml-js.mjs";

const Store = loadQmlJs(new URL("../lib/Store.js", import.meta.url).pathname);
const Format = loadQmlJs(new URL("../lib/Format.js", import.meta.url).pathname);

const r = (id, state, extra = {}) => ({ key: "e:" + id, envId: "e", id, parentId: "", state, settled: false, project: "P", title: id, branch: "", model: "", provider: "", rawStatus: "completed", completedAt: 0, ...extra });
const ids = (list) => Array.from(list, (x) => (x.kind === "idle-line" ? `[idle ${x.count}${x.open ? " open" : ""}]` : x.kind === "section" ? `§${x.label} ${x.count}` : x.id));
const rowIds = (list) => Array.from(list).filter((x) => !x.kind).map((x) => x.id);

test("inbox shows only what needs you; active adds what is in progress; children follow parents", () => {
  const rows = [r("a", "input"), r("b", "working"), r("c", "review"), r("k", "working", { parentId: "b" }), r("z", "idle", { settled: true })];
  assert.deepEqual(ids(Store.visibleRows(rows, "attention", "", {})), ["a"]);
  assert.deepEqual(ids(Store.visibleRows(rows, "active", "", {})), ["§Needs you 1", "a", "§Working 1", "b", "k"]);
  assert.deepEqual(ids(Store.visibleRows(rows, "all", "", {})), ["a", "b", "k", "c", "[idle 1]"]);
  assert.equal(Store.filterCount(rows, "attention"), 1);
});

test("header, tabs and ring count the same sets", () => {
  const rows = [r("in", "input"), r("pl", "plan"), r("f", "failed", { rawStatus: "failed" }), r("lim", "limited", { rawStatus: "failed" }),
    r("w", "working", { rawStatus: "running" }), r("q", "queued", { rawStatus: "queued" }), r("bg", "background"), r("d", "review"),
    r("i", "idle"), r("s", "stopped", { rawStatus: "interrupted" }), r("kid", "working", { parentId: "w", rawStatus: "running" })];
  const t = Store.tally(rows);
  assert.deepEqual({ ...t }, { needs: 3, working: 4, active: 7, done: 2, unread: 1, all: 10, stopped: 1, other: 0 });
  assert.equal(t.active + t.done + t.stopped + t.other, t.all, "the header's parts add up to All");
  assert.equal(Store.filterCount(rows, "attention"), t.needs);
  assert.equal(Store.filterCount(rows, "active"), t.active);
  assert.equal(Store.filterCount(rows, "done"), t.done);
  assert.equal(Store.filterCount(rows, "all"), t.all);
  // The inbox is what the header calls "need you", and nothing else.
  assert.deepEqual(rowIds(Store.visibleRows(rows, "attention", "", {}, {})), ["in", "pl", "f"]);
});

test("all view groups by machine and project, keeping urgency order inside a group", () => {
  const rows = [r("a", "input", { project: "Y" }), r("b", "working", { project: "X" }), r("c", "idle", { project: "Y" })];
  assert.deepEqual(ids(Store.visibleRows(rows, "all", "", {})), ["b", "a", "[idle 1]"]);
});

test("search matches title, project and model", () => {
  const rows = [r("alpha", "working", { model: "opus" }), r("beta", "working")];
  assert.deepEqual(Array.from(Store.visibleRows(rows, "all", "opus", {}), (x) => x.id), ["alpha"]);
});

test("labels and icons for pending requests", () => {
  assert.equal(Store.stateLabel(r("a", "input", { pendingKind: "command" })), "Run command?");
  assert.equal(Store.stateIcon(r("a", "input", { pendingKind: "user_input" })), "message-circle-question");
  assert.equal(Store.stateLabel(r("a", "waiting")), "Finishing");
});

test("formatting", () => {
  assert.equal(Format.duration(65_000), "1m 05s");
  assert.equal(Format.duration(3_725_000), "1h 02m");
  assert.equal(Format.tokens(96_192), "96k");
  assert.equal(Format.tokens(1_000_000), "1M");
  assert.equal(Format.model("zai/glm-5.3"), "glm-5.3");
  assert.equal(Format.ago(Date.now() - 3 * 60_000, Date.now()), "3m ago");
});

test("active folds idle and stopped roots behind one line at the bottom", () => {
  const rows = [
    r("w1", "working", { envId: "A", key: "A:w1" }), r("i1", "idle", { envId: "A", key: "A:i1" }), r("s1", "stopped", { envId: "A", key: "A:s1" }),
    r("w2", "working", { envId: "B", key: "B:w2" }), r("i2", "idle", { envId: "B", key: "B:i2" }),
    r("k", "idle", { envId: "A", key: "A:k", parentId: "i1" }),
  ];
  assert.deepEqual(ids(Store.visibleRows(rows, "all", "", {}, {})), ["w1", "[idle 2]", "w2", "[idle 1]"], "a fold per group, after its live rows");
  // Active is what needs you or is in progress: idle and stopped threads are not in it at all.
  assert.deepEqual(ids(Store.visibleRows(rows, "active", "", {}, {})), ["§Working 2", "w1", "w2"]);
  const open = { [Store.idleLineKey(rows[1], "all")]: true };
  assert.deepEqual(rowIds(Store.visibleRows(rows, "all", "", { "A:i1": true }, open)), ["w1", "i1", "k", "s1", "w2"]);
});

test("all view puts one idle line at the end of each group", () => {
  const rows = [r("x1", "working", { project: "X" }), r("x2", "idle", { project: "X" }), r("y1", "idle", { project: "Y" })];
  assert.deepEqual(ids(Store.visibleRows(rows, "all", "", {}, {})), ["x1", "[idle 1]", "[idle 1]"]);
  const lines = Array.from(Store.visibleRows(rows, "all", "", {}, {})).filter((x) => x.kind === "idle-line");
  assert.deepEqual(lines.map((l) => l.project), ["X", "Y"], "lines carry their group for the section header");
});

test("a text search never folds", () => {
  const rows = [r("alpha", "idle"), r("beta", "working")];
  assert.deepEqual(rowIds(Store.visibleRows(rows, "all", "alp", {}, {})), ["alpha"]);
});

test("done tab: finished threads, newest first, no folding", () => {
  const rows = [
    r("old", "idle", { completedAt: 100 }), r("new", "review", { completedAt: 300 }), r("mid", "idle", { completedAt: 200, settled: true }),
    r("busy", "working", { rawStatus: "running" }), r("fail", "failed", { rawStatus: "failed" }), r("stop", "stopped", { rawStatus: "interrupted" }),
  ];
  assert.deepEqual(ids(Store.visibleRows(rows, "done", "", {}, {})), ["new", "mid", "old"]);
  assert.equal(Store.filterCount(rows, "done"), 3);
  assert.deepEqual(Array.from(Store.FILTERS), ["attention", "active", "done", "all"]);
});

test("sections follow urgency and count only what is shown", () => {
  const rows = [r("in", "input"), r("pl", "plan"), r("lim", "limited"), r("w", "working"), r("q", "queued"), r("d", "review"), r("i", "idle")];
  assert.deepEqual(ids(Store.visibleRows(rows, "active", "", {}, {})),
    ["§Needs you 2", "in", "pl", "§Working 3", "lim", "w", "q"]);
  assert.equal(Store.isStop({ kind: "section" }), false);
  assert.equal(Store.isStop({ kind: "idle-line" }), true);
});

test("colour budget: violet for an answer, red for failed, amber for a plan or limit, accent for working; ring is ink except needs-you", () => {
  assert.equal(Store.stateRole("input"), "ask");
  assert.equal(Store.stateRole("failed"), "attention");
  assert.equal(Store.stateRole("plan"), "warning");
  assert.equal(Store.stateRole("limited"), "textDim", "amber is for plans only");
  assert.equal(Store.stateRole("working"), "accent");
  assert.equal(Store.stateRole("review"), "success");
  for (const s of ["queued", "background", "idle", "stopped"]) assert.equal(Store.stateRole(s), "textDim", s);
  // Words are tinted only on rows that need you.
  assert.equal(Store.inkRole("failed"), "attentionInk");
  assert.equal(Store.inkRole("input"), "askInk");
  assert.equal(Store.inkRole("plan"), "warningInk");
  assert.equal(Store.inkRole("working"), "");
  const segs = Array.from(Store.ringSegments([r("a", "input"), r("b", "plan"), r("x", "failed"), r("c", "working"), r("d", "limited"), r("e", "review"), r("f", "idle")]), (x) => `${x.role}:${x.count}`);
  assert.deepEqual(segs, ["attention:1", "ask:1", "warning:1", "ink:2", "rest:2"], "each kind in its own colour, as in the list");
});

test("filter editing: typing, deleting, word and line clears, and the keys that finish it", () => {
  const edit = (q, action, text) => Store.editFilter(q, action, text);
  assert.deepEqual({ ...edit("", "text", "r") }, { query: "r", done: false, handled: true });
  assert.equal(edit("ri", "text", "v").query, "riv");
  // j, k, h, l, x and space are ordinary letters while typing.
  assert.equal(edit("a", "text", "j").query, "aj");
  assert.equal(edit("a", "text", " ").query, "a ");
  assert.equal(edit("riv", "backspace").query, "ri");
  assert.equal(edit("", "backspace").query, "");
  assert.equal(edit("two words ", "word").query, "two ");
  assert.equal(edit("two words", "word").query, "two ");
  assert.equal(edit("one", "word").query, "");
  assert.equal(edit("anything", "clear").query, "");
  // Enter keeps the text and hands the keys back; Esc clears it and hands them back.
  assert.deepEqual({ ...edit("riv", "enter") }, { query: "riv", done: true, handled: true });
  assert.deepEqual({ ...edit("riv", "escape") }, { query: "", done: true, handled: true });
});

test("filter editing: control characters and unknown actions are not used; length is capped", () => {
  const edit = (q, action, text) => Store.editFilter(q, action, text);
  for (const t of ["", undefined, "\u0000", "\u0008", "\u001b", "\r", "\t", "\u007f", "\u0085"]) {
    assert.deepEqual({ ...edit("ab", "text", t) }, { query: "ab", done: false, handled: false }, JSON.stringify(t));
  }
  assert.equal(edit("ab", "paste", "xyz").handled, false);
  assert.equal(edit("ab", "paste", "xyz").query, "ab");
  assert.equal(edit("x".repeat(80), "text", "y").query, "x".repeat(80));
  // Characters outside the BMP count once, and backspace removes them whole.
  assert.equal(edit("a", "text", "😀").query, "a😀");
  assert.equal(edit("a😀", "backspace").query, "a");
  assert.equal(edit(undefined, "text", "q").query, "q");
});

test("failures are labelled by their real cause, not T3's catch-all class", () => {
  const cause = (error, errorClass = "provider_error", state = "failed") => Store.failureCause({ state, error, errorClass });
  assert.equal(cause('401: {"code":"1000","message":"Authentication Failed"}').key, "auth");
  assert.equal(cause('401: {"code":"1000","message":"Authentication Failed"}').label, "sign-in rejected");
  assert.equal(cause("This thread's workspace folder no longer exists or is not a directory: /home/dev/code/web-app. Restore the folder at this path before retrying.").key, "folder");
  assert.equal(cause("Provider stream closed unexpectedly (502 from upstream) after 41 tool calls.").key, "provider");
  assert.equal(cause("Sign-out", "permission_error").key, "auth");
  assert.equal(cause("socket hang up", "transport_error").key, "transport");
  assert.equal(cause("Usage limit reached", "usage_limit", "limited").key, "limit");
  assert.equal(cause("", "").label, "");
  for (const c of [cause("x"), cause("401"), cause("x", "")]) assert.ok(c.next.length > 0 && c.icon && c.headline, JSON.stringify(c));
});

test("the detail leads with the state, why, and the next step", () => {
  const now = Date.UTC(2026, 10, 8, 12, 0, 0);
  const failed = Store.statusCallout(r("f", "failed", { error: "401: nope", errorClass: "provider_error", completedAt: now - 8 * 86400_000 }), now, false);
  assert.equal(failed.tone, "attention");
  assert.equal(failed.raw, "401: nope");
  assert.equal(failed.body, "Failed 8d ago · sign-in rejected");
  assert.match(failed.next, /Sign in/);
  const limited = Store.statusCallout(r("l", "limited", { errorClass: "usage_limit", usageResetAt: now + 47 * 60_000, error: "Usage limit reached." }), now, false);
  assert.equal(limited.tone, "idle");
  assert.match(limited.body, /^Resets in 47m · at \d\d:\d\d$/);
  const plan = Store.statusCallout(r("p", "plan", { completedAt: now - 4 * 60_000, lastRunMs: 6 * 60_000 }), now, false);
  assert.match(plan.body, /after a 6m 00s run/);
  assert.ok(plan.next);
  const bg = Store.statusCallout(r("b", "background", { background: { subagents: 2, commands: 0, monitors: 0, other: 0 } }), now, false);
  assert.match(bg.body, /^2 subagents still out/);
  // A request whose text has loaded speaks for itself; before that, the callout stands in.
  assert.equal(Store.statusCallout(r("i", "input", { pendingKind: "command" }), now, true), null);
  assert.equal(Store.statusCallout(r("i", "input", { pendingKind: "command" }), now, false).headline, "Waiting for your answer");
  assert.equal(Store.statusCallout(r("w", "working"), now, false), null);
  assert.equal(Store.statusCallout(r("i", "idle"), now, false), null);
});

test("disconnected machines name the step that brings them back", () => {
  const env = (extra) => ({ label: "laptop", state: "expired", url: "http://127.0.0.1:3773", sshHost: "", ...extra });
  assert.deepEqual({ ...Store.repairStep(env()) }, { kind: "command", text: "t3-loupe pair-local --label laptop" });
  assert.deepEqual({ ...Store.repairStep(env({ label: "build-box", sshHost: "build-box", url: "http://127.0.0.1:46363" })) },
    { kind: "command", text: "t3-loupe pair-ssh --ssh-host build-box --label build-box" });
  assert.equal(Store.repairStep(env({ url: "https://t3.example.com" })).text, "t3-loupe pair --url https://t3.example.com --label laptop");
  assert.equal(Store.repairStep(env({ state: "tunnel_missing", sshHost: "box" })).kind, "note");
  // A label that isn't a plain word stays out of the command rather than being quoted wrong.
  assert.equal(Store.repairStep(env({ label: "my laptop" })).text, "t3-loupe pair-local");
  assert.deepEqual({ ...Store.connection([env(), env({ state: "expired" })]) }, { total: 2, connected: 0, none: true });
  assert.deepEqual({ ...Store.connection([env({ state: "live" }), env()]) }, { total: 2, connected: 1, none: false });
  assert.equal(Store.connection([]).none, false);
});

test("sub-second durations read as <1s, not 0s", () => {
  assert.equal(Format.duration(400), "<1s");
  assert.equal(Format.duration(0), "<1s");
  assert.equal(Format.duration(1500), "1s");
});

test("one needs-you colour where only one fits: the most severe kind present", () => {
  assert.equal(Store.needsRole([r("a", "input"), r("b", "failed"), r("c", "plan")]), "attention");
  assert.equal(Store.needsRole([r("a", "input"), r("c", "plan")]), "ask");
  assert.equal(Store.needsRole([r("c", "plan"), r("w", "working")]), "warning");
  assert.equal(Store.needsRole([r("k", "failed", { parentId: "w" }), r("a", "input")]), "ask", "subagents don't count");
});

test("legend: two rows of the keys that work, closed up, Enter last on its row", () => {
  const rows = (mode, enter) => Array.from(Store.legendRows(mode, enter), (row) => Array.from(row, (c) => c.key + " " + c.verb));
  assert.deepEqual(rows("list", "subagents"), [
    ["j/k select", "g needs you", "1–4 view", "/ filter", "↵ subagents"],
    ["o open T3", "f layout", "r refresh", "+/− size", "esc close"],
  ]);
  // Enter with nothing to do isn't there, and nothing else moves: it was last on its row.
  assert.deepEqual(rows("list", ""), [["j/k select", "g needs you", "1–4 view", "/ filter"], rows("list", "x")[1]]);
  assert.deepEqual(rows("list", "")[0], rows("list", "details")[0].slice(0, 4));
  assert.deepEqual(rows("empty", "")[0], ["1–4 view", "/ filter"]);
  // Offline has no list keys: the window keys take the top row, the second is empty.
  assert.deepEqual(rows("offline", ""), [["o open T3", "f layout", "r refresh", "+/− size", "esc close"], []]);
  for (const mode of ["list", "empty", "offline"]) for (const enter of ["", ...Store.ENTER_VERBS]) {
    const shown = Store.legendRows(mode, enter);
    assert.equal(shown.length, 2, "always two rows");
    for (const row of shown) for (const c of row) {
      assert.ok(c.verb.length > 0, `${c.key} without its label`);
      assert.ok(!/·/.test(c.key + c.verb), "no separators");
    }
  }
  assert.equal(Store.enterVerb({ kind: "idle-line", open: false }, true, false), "unfold");
  assert.equal(Store.enterVerb({ kind: "idle-line", open: true }, false, false), "fold");
  assert.equal(Store.enterVerb(r("a", "working", { childCount: 2 }), true, false), "subagents");
  assert.equal(Store.enterVerb(r("a", "working", { childCount: 0 }), true, false), "");
  assert.equal(Store.enterVerb(r("a", "working"), false, true), "details");
  assert.equal(Store.enterVerb(null, true, false), "");
  for (const verb of ["subagents", "details", "unfold", "fold"]) assert.ok(Store.ENTER_VERBS.includes(verb));
});

test("runs caption names failed runs; sub-second runs get words, not a chart", () => {
  const now = 10_000_000;
  const runs = [5, 12, 3, 22].map((m, i) => ({ ordinal: i + 1, status: i === 3 ? "failed" : "completed", startedAt: 0, completedAt: 0, durationMs: m * 60_000 }))
    .concat([{ ordinal: 5, status: "running", startedAt: now - 23 * 60_000, completedAt: null, durationMs: null }]);
  assert.deepEqual({ ...Store.runsSummary(runs, now) }, { chart: true, text: "current 23m 00s  ·  longest 23m 00s  ·  run 4 failed" });
  assert.deepEqual({ ...Store.runsSummary([{ ordinal: 1, status: "failed", startedAt: now, completedAt: now, durationMs: 0 }], now) },
    { chart: false, text: "1 run, failed after <1s" });
  assert.equal(Store.runsSummary([], now).text, "");
  assert.match(Store.runsSummary([{ ordinal: 1, status: "failed", durationMs: 60_000 }, { ordinal: 2, status: "failed", durationMs: 1000 }], now).text, /runs 1, 2 failed/);
});

test("an activity line that repeats the error card is recognised", () => {
  const row = { error: "This thread's workspace folder no longer exists or is not a directory: /x. Restore the folder at this path before retrying." };
  assert.equal(Store.repeatsError({ status: "failed", label: row.error }, row), true);
  assert.equal(Store.repeatsError({ status: "failed", label: row.error.slice(0, 60) + "…" }, row), true, "a cut-short copy too");
  assert.equal(Store.repeatsError({ status: "completed", label: row.error }, row), false);
  assert.equal(Store.repeatsError({ status: "failed", label: "Preparing workspace" }, row), false);
});

test("usage windows are named from T3's label, qualifiers kept, every label distinct", () => {
  const w = (label, durationMins) => ({ label, durationMins });
  assert.equal(Store.windowLabel(w("Session", 300)), "5-hour");
  assert.equal(Store.windowLabel(w("Session", 300), true), "5h");
  assert.equal(Store.windowLabel(w("Weekly", 10080)), "weekly");
  assert.equal(Store.windowLabel(w("Weekly · Fable", 10080)), "weekly · Fable");
  assert.equal(Store.windowLabel(w("Weekly · Fable", 10080), true), "week · Fable");
  assert.equal(Store.windowLabel(w("Session", 1440 * 30)), "30-day");
  assert.equal(Store.windowLabel(w("Opus monthly cap", 43200)), "Opus monthly cap", "unknown labels stay as T3 wrote them");
  assert.equal(Store.windowLabel(w("", 300)), "5-hour", "no label: the length names it");
  const claude = [w("Session", 300), w("Weekly", 10080), w("Weekly · Fable", 10080)];
  assert.deepEqual(Array.from(Store.windowLabels(claude, false)), ["5-hour", "weekly", "weekly · Fable"]);
  assert.deepEqual(Array.from(Store.windowLabels([w("Weekly", 10080), w("Weekly", 10080)], false)), ["weekly", "weekly 2"]);
  for (const n of [1, 2, 3, 4]) {
    const ws = [w("Session", 300), w("Weekly", 10080), w("Weekly · Fable", 10080), w("Weekly", 10080)].slice(0, n);
    for (const compact of [false, true]) {
      const labels = Array.from(Store.windowLabels(ws, compact));
      assert.equal(new Set(labels).size, labels.length, `${n} windows, compact ${compact}: ${labels}`);
    }
  }
  const now = 10_000_000;
  assert.equal(Store.windowValue({ usedPercent: 95, resetsAt: now + 3600_000 }, now, false), "95% resets in 1h", "near the limit: the reset, still with its meter");
  assert.equal(Store.windowValue({ usedPercent: 100, resetsAt: now + 47 * 60_000 }, now, false), "limit reached, resets in 47m");
  assert.equal(Store.windowValue({ usedPercent: 38 }, now, false), "38%");
});

test("detail metadata lists whole items", () => {
  assert.deepEqual(Array.from(Store.metaParts(r("a", "working", { project: "web-app", branch: "feat/x", worktree: true, model: "zai/glm-5.3" }), "laptop")),
    ["laptop", "web-app", "feat/x (worktree)", "glm-5.3"]);
});

test("idle folds are named for what they hold, in the header's words", () => {
  const rows = [r("d1", "idle", { project: "X" }), r("s1", "stopped", { project: "Y", rawStatus: "interrupted" }),
    r("d2", "idle", { project: "Z" }), r("s2", "stopped", { project: "Z", rawStatus: "cancelled" }), r("n", "idle", { project: "W", rawStatus: "" })];
  const labels = Array.from(Store.visibleRows(rows, "all", "", {}, {})).filter((x) => x.kind === "idle-line").map((x) => x.project + ":" + x.label);
  assert.deepEqual(labels, ["W:Idle", "X:Done", "Y:Stopped", "Z:Done & Stopped"]);
});

test("a single run is a sentence, not a one-bar chart", () => {
  const now = 10_000_000;
  assert.deepEqual({ ...Store.runsSummary([{ ordinal: 1, status: "running", startedAt: now - 9 * 60_000, completedAt: null, durationMs: null }], now) },
    { chart: false, text: "1 run, running for 9m 00s" });
  assert.equal(Store.runsSummary([{ ordinal: 1, status: "completed", durationMs: 6 * 60_000 }], now).text, "1 run, took 6m 00s");
});

test("two runs are a sentence too; the chart starts at three", () => {
  const now = 10_000_000;
  const two = [{ ordinal: 1, status: "completed", durationMs: 8 * 60_000 }, { ordinal: 2, status: "running", startedAt: now - 14 * 60_000, durationMs: null }];
  assert.deepEqual({ ...Store.runsSummary(two, now) }, { chart: false, text: "2 runs  ·  current 14m 00s  ·  longest 14m 00s" });
  assert.equal(Store.runsSummary(two.concat([{ ordinal: 3, status: "completed", durationMs: 60_000 }]), now).chart, true);
});
