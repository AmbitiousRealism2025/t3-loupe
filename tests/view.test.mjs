import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./lib/qml-js.mjs";

const Store = loadQmlJs(new URL("../plugin/lib/Store.js", import.meta.url).pathname);
const Format = loadQmlJs(new URL("../plugin/lib/Format.js", import.meta.url).pathname);

const r = (id, state, extra = {}) => ({ key: "e:" + id, envId: "e", id, parentId: "", state, settled: false, project: "P", title: id, branch: "", model: "", provider: "", ...extra });

test("inbox shows what needs you; children follow parents", () => {
  const rows = [r("a", "input"), r("b", "working"), r("c", "review"), r("k", "working", { parentId: "b" }), r("z", "idle", { settled: true })];
  assert.deepEqual(Array.from(Store.visibleRows(rows, "attention", "", {}), (x) => x.id), ["a", "c"]);
  assert.deepEqual(Array.from(Store.visibleRows(rows, "active", "", {}), (x) => x.id), ["a", "b", "k", "c"]);
  assert.deepEqual(Array.from(Store.visibleRows(rows, "all", "", {}), (x) => x.id), ["a", "b", "k", "c", "z"]);
  assert.equal(Store.filterCount(rows, "attention"), 2);
});

test("all view groups by machine and project, keeping urgency order inside a group", () => {
  const rows = [r("a", "input", { project: "Y" }), r("b", "working", { project: "X" }), r("c", "idle", { project: "Y" })];
  assert.deepEqual(Array.from(Store.visibleRows(rows, "all", "", {}), (x) => x.id), ["b", "a", "c"]);
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
