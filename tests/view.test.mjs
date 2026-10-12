import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./lib/qml-js.mjs";

const Store = loadQmlJs(new URL("../plugin/lib/Store.js", import.meta.url).pathname);
const Format = loadQmlJs(new URL("../plugin/lib/Format.js", import.meta.url).pathname);

const r = (id, state, extra = {}) => ({ key: "e:" + id, envId: "e", id, parentId: "", state, settled: false, project: "P", title: id, branch: "", model: "", provider: "", rawStatus: "completed", completedAt: 0, ...extra });
const ids = (list) => Array.from(list, (x) => (x.kind === "idle-line" ? `[idle ${x.count}${x.open ? " open" : ""}]` : x.kind === "section" ? `§${x.label} ${x.count}` : x.id));
const rowIds = (list) => Array.from(list).filter((x) => !x.kind).map((x) => x.id);

test("inbox shows what needs you; children follow parents", () => {
  const rows = [r("a", "input"), r("b", "working"), r("c", "review"), r("k", "working", { parentId: "b" }), r("z", "idle", { settled: true })];
  assert.deepEqual(ids(Store.visibleRows(rows, "attention", "", {})), ["§Needs you 1", "a", "§Done 1", "c"]);
  assert.deepEqual(ids(Store.visibleRows(rows, "active", "", {})), ["§Needs you 1", "a", "§Working 1", "b", "k", "§Done 1", "c"]);
  assert.deepEqual(ids(Store.visibleRows(rows, "all", "", {})), ["a", "b", "k", "c", "[idle 1]"]);
  assert.equal(Store.filterCount(rows, "attention"), 2);
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
  assert.deepEqual(ids(Store.visibleRows(rows, "active", "", {}, {})), ["§Working 2", "w1", "w2", "[idle 3]"], "one fold across machines, after every visible row");
  const open = { [Store.idleLineKey(rows[1], "active")]: true };
  assert.deepEqual(rowIds(Store.visibleRows(rows, "active", "", { "A:i1": true }, open)), ["w1", "w2", "i1", "k", "s1", "i2"]);
});

test("all view puts one idle line at the end of each group", () => {
  const rows = [r("x1", "working", { project: "X" }), r("x2", "idle", { project: "X" }), r("y1", "idle", { project: "Y" })];
  assert.deepEqual(ids(Store.visibleRows(rows, "all", "", {}, {})), ["x1", "[idle 1]", "[idle 1]"]);
  const lines = Array.from(Store.visibleRows(rows, "all", "", {}, {})).filter((x) => x.kind === "idle-line");
  assert.deepEqual(lines.map((l) => l.project), ["X", "Y"], "lines carry their group for the section header");
});

test("a text search never folds", () => {
  const rows = [r("alpha", "idle"), r("beta", "working")];
  assert.deepEqual(rowIds(Store.visibleRows(rows, "active", "alp", {}, {})), ["alpha"]);
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
    ["§Needs you 2", "in", "pl", "§Working 3", "lim", "w", "q", "§Done 1", "d", "[idle 1]"]);
  assert.equal(Store.isStop({ kind: "section" }), false);
  assert.equal(Store.isStop({ kind: "idle-line" }), true);
});

test("colour budget: three meanings earn a hue, ring is ink except needs-you", () => {
  assert.equal(Store.stateRole("input"), "attention");
  assert.equal(Store.stateRole("working"), "accent");
  assert.equal(Store.stateRole("review"), "success");
  for (const s of ["plan", "limited", "queued", "background", "idle", "stopped"]) assert.equal(Store.stateRole(s), "textDim", s);
  const segs = Array.from(Store.ringSegments([r("a", "input"), r("b", "plan"), r("c", "working"), r("d", "limited"), r("e", "review"), r("f", "idle")]), (x) => `${x.role}:${x.count}`);
  assert.deepEqual(segs, ["attention:2", "ink:2", "inkFaint:2"]);
});
