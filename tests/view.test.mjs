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

test("colour budget: violet for an answer, red for failed, amber for a plan; working is ink, not the accent; ring is ink except needs-you", () => {
  assert.equal(Store.stateRole("input"), "ask");
  assert.equal(Store.stateRole("failed"), "attention");
  assert.equal(Store.stateRole("plan"), "warning");
  assert.equal(Store.stateRole("limited"), "textDim", "amber is for plans only");
  // A hue says "this needs you". What is running has its own role, which the palette draws in ink:
  // the accent is left to selection.
  assert.equal(Store.stateRole("working"), "working");
  assert.equal(Store.stateRole("waiting"), "working");
  assert.ok(!Object.values({ ...Store.ROLE }).includes("accent"), "no state borrows the accent");
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
  // Routine states lead in ink. Only what needs you gets a colour: red is for failures alone.
  assert.equal(bg.tone, "idle", "background work is healthy: never a failure's colour");
  assert.equal(Store.statusCallout(r("q", "queued", { activeSince: now - 60_000 }), now, false).tone, "idle");
  const tones = ["input", "plan", "failed", "limited", "background", "queued", "review", "stopped"].map((s) => [s, Store.statusCallout(r(s, s, { rawStatus: s === "stopped" ? "interrupted" : "completed" }), now, false).tone]);
  assert.deepEqual(tones.filter(([, tone]) => tone === "attention").map(([s]) => s), ["failed"], "one state is red");
  for (const [state, tone] of tones) assert.ok(["attention", "warning", "ask", "success", "idle"].includes(tone), `${state}: ${tone}`);
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
  assert.equal(Store.repairStep(env({ label: "box", sshHost: "box", url: "https://box.example.ts.net" })).text,
    "t3-loupe pair-ssh --ssh-host box --url https://box.example.ts.net --label box");
  assert.equal(Store.repairStep(env({ url: "https://t3.example.com" })).text, "t3-loupe pair --url https://t3.example.com --label laptop");
  assert.equal(Store.repairStep(env({ state: "tunnel_missing", sshHost: "box" })).kind, "note");
  // A server that changed is paired again the way it was paired, not always locally.
  assert.equal(Store.repairStep(env({ state: "environment_changed", label: "box", sshHost: "box", url: "https://box.example.ts.net" })).text,
    "t3-loupe pair-ssh --ssh-host box --url https://box.example.ts.net --label box");
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

test("a row's time says what kind of time it is", () => {
  const now = 10_000_000;
  const time = (state, extra, busy = Store.BUSY[state] === true) => Format.rowTime(r("t", state, extra), now, busy);
  // A duration carries the word for what has lasted that long.
  assert.equal(time("input", { pendingSince: now - 124_000 }), "waiting 2m");
  assert.equal(time("working", { activeSince: now - 23 * 60_000 - 8000 }), "running 23m");
  assert.equal(time("background", { activeSince: now - 9 * 60_000 }), "running 9m");
  assert.equal(time("queued", { activeSince: now - 60_000 }), "queued 1m");
  // A time since and a time until already say what they are.
  assert.equal(time("failed", { completedAt: now - 11 * 60_000 }), "11m ago");
  assert.equal(time("plan", { completedAt: now - 4 * 60_000 }), "4m ago");
  assert.equal(time("limited", { usageResetAt: now + 47 * 60_000 }), "resets in 47m");
  // No bare duration is ever shown: that was the form that could mean either.
  for (const t of [time("input", { pendingSince: now - 42_000 }), time("working", { activeSince: now - 3_725_000 })]) assert.match(t, /^(waiting|running) /);
  // Seconds only under a minute: a row is read at a glance, the detail has the exact time.
  assert.equal(Format.span(42_000), "42s");
  assert.equal(Format.span(124_000), "2m");
  assert.equal(Format.span(3_725_000), "1h 02m");
  assert.equal(Format.span(400), "<1s");
  assert.equal(Format.span(26 * 3_600_000), "1d 2h");
  assert.equal(Format.elapsed(r("t", "working", { activeSince: now - 23 * 60_000 - 8000 }), now, true), "23m 08s", "the detail keeps the seconds");
});

test("a request's choices are a sentence, not a row of buttons", () => {
  assert.equal(Store.choicesSentence(["Allow once", "Allow for session", "Decline"]), "T3 offers: Allow once, Allow for session or Decline");
  assert.equal(Store.choicesSentence(["Yes", "No"]), "T3 offers: Yes or No");
  assert.equal(Store.choicesSentence(["Continue"]), "T3 offers: Continue");
  assert.equal(Store.choicesSentence([]), "");
});

test("legend: three groups by purpose, each in columns two rows tall; Enter at the foot of a column", () => {
  // A group as its columns, each column as its "key verb" cells top to bottom ("" for an empty slot).
  const groups = (mode, opts) => Object.fromEntries(Array.from(Store.legendGroups(mode, opts), (g) =>
    [g.name, Array.from(g.columns, (col) => Array.from(col, (c) => (c.key ? c.key + " " + c.verb : "")))]));
  // The two-pane window: the detail's paging keys are in the legend, with Enter under them.
  assert.deepEqual(groups("list", { enter: "subagents", centered: true }), {
    navigate: [["j/k select", "g needs you"], ["1–4 view", "/ filter"], ["d/u scroll detail", "↵ subagents"]],
    act: [["o open T3", "c copy title"]],
    window: [["f layout", "r refresh"], ["+/− size", "esc close"]],
  });
  // Enter with nothing to do leaves an empty slot at the foot of its column: no other key moves.
  const idle = groups("list", { enter: "", centered: true });
  assert.deepEqual(idle.navigate, [["j/k select", "g needs you"], ["1–4 view", "/ filter"], ["d/u scroll detail", ""]]);
  assert.deepEqual([idle.act, idle.window], [groups("list", { enter: "fold", centered: true }).act, groups("list", { enter: "fold", centered: true }).window]);
  // The dropdown has no detail pane to page: no d/u, and Enter (always "details" or a fold there) has the column.
  assert.deepEqual(groups("list", { enter: "details", centered: false }).navigate, [["j/k select", "g needs you"], ["1–4 view", "/ filter"], ["↵ details"]]);
  assert.ok(!Array.from(Store.legendKeys("list", { enter: "details", centered: false })).some((k) => /^d\/u/.test(k)));
  // No threads in this view: the list keys go, the views and the filter stay.
  assert.deepEqual(groups("empty", { centered: true }), { navigate: [["1–4 view", "/ filter"]], act: [["o open T3"]], window: groups("list", { centered: true }).window });
  // Offline: nothing to navigate. The digits copy the re-pair commands, as many as there are.
  assert.deepEqual(groups("offline", { commands: 2 }), { act: [["1–2 copy command", "o open T3"]], window: groups("list", {}).window });
  assert.deepEqual(groups("offline", { commands: 1 }).act, [["1 copy command", "o open T3"]]);
  assert.deepEqual(groups("offline", { commands: 0 }).act, [["o open T3"]]);
  assert.deepEqual(groups("offline", { commands: 40 }).act[0][0], "1–9 copy command");
  // (Enter says "subagents" only in the two-pane window and "details" only in the dropdown.)
  for (const mode of ["list", "empty", "offline"]) for (const centered of [true, false]) for (const enter of ["", "unfold", "fold", centered ? "subagents" : "details"]) {
    const shown = Array.from(Store.legendGroups(mode, { enter, centered, commands: 2 }));
    assert.deepEqual(shown.map((g) => g.name), mode === "offline" ? ["act", "window"] : ["navigate", "act", "window"]);
    for (const g of shown) for (const col of g.columns) {
      assert.ok(col.length >= 1 && col.length <= 2, "a column is at most two rows tall");
      for (const [i, c] of Array.from(col).entries()) {
        assert.ok(!/·/.test(c.key + c.verb), "no separators");
        if (c.key) assert.ok(c.verb.length > 0, `${c.key} without its label`);
        // Only Enter comes and goes with the selection, and only from the foot of a column.
        if (c.slot === "enter") {
          assert.equal(i, col.length - 1, "Enter is last in its column");
          assert.ok(c.widest.length >= c.verb.length && (!c.verb || Store.ENTER_VERBS.includes(c.verb)), `Enter's column is as wide as the longest verb: ${c.widest}`);
        }
      }
    }
    // Every key the legend lists is one the panel answers in that mode.
    const keys = Array.from(Store.legendKeys(mode, { enter, centered, commands: 2 }));
    assert.equal(new Set(keys).size, keys.length, "no key is listed twice");
  }
  // The text-size control has one place: beside "+/− size".
  const sized = Array.from(Store.legendGroups("list", { centered: true })).flatMap((g) => Array.from(g.columns).flatMap((c) => Array.from(c))).filter((c) => c.slot === "size");
  assert.deepEqual(sized.map((c) => c.key + " " + c.verb), ["+/− size"]);
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
  // A window's value is short whatever its state, so no row's words set the width of a column
  // every provider shares: a percentage, or "full".
  assert.equal(Store.windowValue({ usedPercent: 38 }), "38%");
  assert.equal(Store.windowValue({ usedPercent: 95, resetsAt: now + 3600_000 }), "95%");
  assert.equal(Store.windowValue({ usedPercent: 100, resetsAt: now + 47 * 60_000 }), "full");
  for (const used of [0, 4, 38, 95, 99.6, 100, 140]) assert.ok(Store.windowValue({ usedPercent: used, resetsAt: now + 1000 }).length <= 4, String(used));
  // Which way the numbers count is said once, in the band's heading: they are the share used.
  assert.match(Store.USAGE_HEADING, /\bUSED\b/);
});

test("when a spent or nearly spent window resets is said after its row, not in its cell", () => {
  const now = 10_000_000;
  const w = (label, durationMins, usedPercent, resetsIn) => ({ label, durationMins, usedPercent, resetsAt: resetsIn ? now + resetsIn : 0 });
  const claude = { name: "Claude", windows: [w("Session", 300, 38, 140 * 60_000), w("Weekly", 10080, 61, 3 * 86400_000), w("Weekly · Fable", 10080, 4, 3 * 86400_000)] };
  const codex = { name: "Codex", windows: [w("Session", 300, 100, 47 * 60_000), w("Weekly", 10080, 82, 5 * 86400_000)] };
  const grid = Store.usageGrid([claude, codex], false);
  assert.equal(Store.usageNote(grid.rows[0], grid.columns, now, false), "", "nothing near its limit: nothing to say");
  assert.equal(Store.usageNote(grid.rows[1], grid.columns, now, false), "5-hour resets in 47m");
  const compact = Store.usageGrid([claude, codex], true);
  assert.equal(Store.usageNote(compact.rows[1], compact.columns, now, true), "5h resets 47m");
  // Each window at 90% or more is named, by its kind.
  const both = Store.usageGrid([{ name: "Claude", windows: [w("Session", 300, 95, 3600_000), w("Weekly", 10080, 100, 2 * 86400_000)] }], false);
  assert.equal(Store.usageNote(both.rows[0], both.columns, now, false), "5-hour resets in 1h  ·  weekly resets in 2d");
  assert.equal(Store.usageNote(Store.usageGrid([{ name: "X", windows: [w("Session", 300, 100, 0)] }], false).rows[0], ["5-hour"], now, false), "", "no reset time known");

  // Where it goes: on the grid, where the next column would start, if it fits; else a line below.
  const lines = Store.usageLines([100, 60, 80], 400, 10);
  const place = (row, room, noteWidth) => ({ ...Store.usageNotePlace(row, lines, [100, 60, 80], 10, room, noteWidth) });
  assert.deepEqual(place(grid.rows[1], 400, 120), { line: 0, x: 180 }, "Codex has no third window: its note starts at that column");
  assert.deepEqual(place(grid.rows[0], 400, 120), { line: 0, x: 270 }, "after a full row, past the last column");
  assert.deepEqual(place(grid.rows[0], 380, 120), { line: 1, x: 0 }, "no room: a line of its own");
  const wrapped = Store.usageLines([100, 60, 80], 200, 10);
  assert.deepEqual({ ...Store.usageNotePlace(grid.rows[1], wrapped, [100, 60, 80], 10, 300, 100) }, { line: 0, x: 180 }, "Codex uses only the first line; the note follows it there");
  assert.deepEqual({ ...Store.usageNotePlace(grid.rows[0], wrapped, [100, 60, 80], 10, 300, 100) }, { line: 1, x: 90 }, "Claude's follows its second line");
});

test("usage is one grid: a column per kind of window, shared by every provider", () => {
  const w = (label, durationMins, usedPercent = 10) => ({ label, durationMins, usedPercent });
  const claude = { name: "Claude", windows: [w("Session", 300), w("Weekly", 10080), w("Weekly · Fable", 10080)] };
  const codex = { name: "Codex", windows: [w("Session", 300, 100), w("Weekly", 10080)] };
  const shape = (g) => ({ columns: Array.from(g.columns), rows: Array.from(g.rows, (r) => [r.name, ...Array.from(r.cells, (c) => (c ? c.index : null))]) });
  // The demo's accounts: Codex has no "weekly · Fable", so its cell there is empty.
  assert.deepEqual(shape(Store.usageGrid([claude, codex], false)), {
    columns: ["5-hour", "weekly", "weekly · Fable"], rows: [["Claude", 0, 1, 2], ["Codex", 0, 1, null]] });
  // Whichever provider comes first, and in the dropdown's short names.
  assert.deepEqual(shape(Store.usageGrid([codex, claude], true)), {
    columns: ["5h", "week", "week · Fable"], rows: [["Codex", 0, 1, null], ["Claude", 0, 1, 2]] });
  // A cell is the provider's own window.
  assert.equal(Store.usageGrid([claude, codex], false).rows[1].cells[0].window.usedPercent, 100);
  // Shorter windows come first even when a provider lists only the longer one, or lists them the other way round.
  const weeklyOnly = { name: "Pi", windows: [w("Weekly", 10080)] };
  const backwards = { name: "Amp", windows: [w("Weekly", 10080), w("Session", 300)] };
  assert.deepEqual(shape(Store.usageGrid([weeklyOnly, backwards, claude], false)), {
    columns: ["5-hour", "weekly", "weekly · Fable"], rows: [["Pi", null, 0, null], ["Amp", 1, 0, null], ["Claude", 0, 1, 2]] });
  // Two windows one provider names alike are two kinds; a label Loupe doesn't know is its own kind, last.
  const odd = { name: "X", windows: [w("Weekly", 10080), w("Weekly", 10080), w("Opus monthly cap", 0)] };
  assert.deepEqual(shape(Store.usageGrid([odd, codex], false)), {
    columns: ["5-hour", "weekly", "weekly 2", "Opus monthly cap"], rows: [["X", null, 0, 1, 2], ["Codex", 0, 1, null, null]] });
  assert.deepEqual(shape(Store.usageGrid([], false)), { columns: [], rows: [] });
});

test("usage columns too wide for the band break at the same column on every row", () => {
  const lines = (widths, room, gap = 10) => Array.from(Store.usageLines(widths, room, gap), (line) => Array.from(line, (c) => [c.column, c.x]));
  assert.deepEqual(lines([100, 60, 80], 400), [[[0, 0], [1, 110], [2, 180]]], "all on one line, each after the widest entry before it");
  assert.deepEqual(lines([100, 60, 80], 200), [[[0, 0], [1, 110]], [[2, 0]]], "the third starts a second line at the first column's x");
  assert.deepEqual(lines([100, 60, 80], 170), [[[0, 0], [1, 110]], [[2, 0]]], "a column that just fits stays");
  assert.deepEqual(lines([100, 60, 80], 50), [[[0, 0]], [[1, 0]], [[2, 0]]], "a column wider than the band still gets a line");
  assert.deepEqual(lines([], 100), [[]]);
});

test("what needs you has one name, and the header spells out how the Active tab's number is made", () => {
  assert.deepEqual({ ...Store.VIEW_LABEL }, { attention: "Needs you", active: "Active", done: "Done", all: "All" });
  const line = (t, sum) => Array.from(Store.headerCounts(t, sum), (p, i) => (i ? (p.join ? ` ${p.join} ` : " · ") : "") + p.text).join("");
  const rows = [r("in", "input"), r("pl", "plan"), r("f", "failed", { rawStatus: "failed" }), r("lim", "limited", { rawStatus: "failed" }),
    r("w", "working", { rawStatus: "running" }), r("d", "review"), r("s", "stopped", { rawStatus: "interrupted" }), r("i", "idle", { rawStatus: "" })];
  const t = Store.tally(rows);
  assert.equal(line(t), "3 NEED YOU + 2 WORKING = 5 ACTIVE · 1 DONE · 1 STOPPED · 1 IDLE");
  // The sum on the line is the Active tab's count, and the parts after it add up to All.
  assert.equal(t.needs + t.working, Store.filterCount(rows, "active"));
  assert.equal(t.active + t.done + t.stopped + t.other, Store.filterCount(rows, "all"));
  // Where the line has no room for the sum, the plus sign still says the two belong together.
  assert.equal(line(t, false), "3 NEED YOU + 2 WORKING · 1 DONE · 1 STOPPED · 1 IDLE");
  assert.equal(line(Store.tally([r("a", "input")])), "1 NEEDS YOU + 0 WORKING = 1 ACTIVE · 0 DONE");
  // Nothing waiting: nothing to add up.
  assert.equal(line(Store.tally([r("w", "working"), r("d", "review")])), "NOTHING NEEDS YOU · 1 WORKING · 1 DONE");
  assert.deepEqual(Array.from(Store.headerCounts(t), (p) => p.tone), ["needs", "strong", "quiet", "quiet", "quiet", "quiet"]);
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
