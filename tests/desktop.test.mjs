// Notifications and clipboard: private text stays out of process argv.
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadQmlJs } from "./lib/qml-js.mjs";

const { copyText, handleDesktopCommand } = await import("../daemon/desktop.ts");
const Notices = loadQmlJs(new URL("../lib/Notices.js", import.meta.url).pathname);

const PRIVATE = "Fix the acme-secret billing bug";
const notice = (extra = {}) => ({ kind: "needs_input", severity: "attention", envId: "e", threadId: "t", title: PRIVATE, body: "acme-web · laptop", ...extra });

test("notifications: generic text by default; details only when opted in", () => {
  const shown = Notices.text(notice(), {});
  assert.equal(shown.title, "A T3 thread needs your input");
  assert.ok(!JSON.stringify(shown).includes("acme"), "no title, project or machine by default");
  for (const kind of ["plan_ready", "run_failed", "usage_limit", "run_completed", "subagents_done", "pr_opened", "pr_merged",
    "checks_failed", "checks_passed", "session_expiring", "environment_offline", "environment_restored"]) {
    assert.ok(!JSON.stringify(Notices.text(notice({ kind }), null)).includes("acme"), kind);
  }
  assert.equal(Notices.text(notice({ kind: "brand_new_kind" }), {}).title, "T3 Loupe", "unknown kinds stay generic");
  assert.deepEqual({ ...Notices.text(notice(), { notifications: { details: true } }) }, { title: PRIVATE, body: "acme-web · laptop" });
  assert.equal(Notices.text(notice({ kind: "test", title: "T3 Loupe notifications are on" }), {}).title, "T3 Loupe notifications are on");
});

test("notifications: preferences, and an open panel holds back all but attention", () => {
  const milestone = notice({ kind: "run_completed", severity: "milestone" });
  const info = notice({ kind: "environment_offline", severity: "info" });
  assert.equal(Notices.wanted(notice(), {}, 0), true);
  assert.equal(Notices.wanted(info, {}, 0), false, "info is off by default");
  assert.equal(Notices.wanted(info, { notifications: { info: true } }, 0), true);
  assert.equal(Notices.wanted(notice(), { notifications: { enabled: false } }, 0), false);
  assert.equal(Notices.wanted(notice(), { notifications: { kinds: { needs_input: false } } }, 0), false);
  assert.equal(Notices.wanted(milestone, {}, 1), false, "panel open");
  assert.equal(Notices.wanted(milestone, { notifications: { milestone: true } }, 1), false, "an explicit switch doesn't bypass the open-panel hold");
  assert.equal(Notices.wanted(milestone, { notifications: { kinds: { run_completed: true } } }, 1), false, "nor does an explicit kind");
  assert.equal(Notices.wanted(milestone, { notifications: { kinds: { run_completed: true } } }, 0), true);
  assert.equal(Notices.wanted(milestone, { notifications: { whenPanelOpen: true } }, 1), true);
  assert.equal(Notices.wanted(notice(), {}, 1), true, "attention always gets through");
});

/** A stand-in for wl-copy that records its argv and stdin, then exits with `code`. */
function fakeCopy(dir, code = 0) {
  const script = join(dir, "fake-wl-copy.mjs");
  writeFileSync(script, `
    import { writeFileSync } from "node:fs";
    const chunks = [];
    process.stdin.on("data", (c) => chunks.push(c));
    process.stdin.on("end", () => {
      writeFileSync(${JSON.stringify(join(dir, "argv.json"))}, JSON.stringify(process.argv));
      writeFileSync(${JSON.stringify(join(dir, "stdin.txt"))}, Buffer.concat(chunks));
      process.exit(${code});
    });`);
  return [process.execPath, script];
}

test("clipboard: text goes to stdin, never argv; success waits for a clean exit", async () => {
  const dir = mkdtempSync(join(tmpdir(), "t3l-copy-"));
  await copyText(PRIVATE, fakeCopy(dir));
  assert.equal(readFileSync(join(dir, "stdin.txt"), "utf8"), PRIVATE);
  assert.ok(!readFileSync(join(dir, "argv.json"), "utf8").includes("acme"), "argv must not contain the text");
});

test("clipboard: failures reject with a code and never crash the collector", async () => {
  const dir = mkdtempSync(join(tmpdir(), "t3l-copy-"));
  await assert.rejects(copyText(PRIVATE, fakeCopy(dir, 3)), /copy_failed/);
  await assert.rejects(copyText(PRIVATE.repeat(4000), ["/usr/bin/false"]), /copy_failed/, "an early exit (EPIPE on stdin) is a failure, not a crash");
  // More than any pipe or socket buffer holds, so a helper that exits 0 without reading must raise EPIPE.
  await assert.rejects(copyText("x".repeat(8 * 1024 * 1024), ["/usr/bin/true"]), /copy_failed/, "exit 0 with the text unread is still a failure");
  await assert.rejects(copyText(PRIVATE, [join(dir, "no-such-command")]), /copy_unavailable/);
});

test("clipboard: a stalled helper is killed on timeout", async () => {
  const dir = mkdtempSync(join(tmpdir(), "t3l-copy-"));
  const pidFile = join(dir, "pid");
  const stall = [process.execPath, "-e", `require("fs").writeFileSync(${JSON.stringify(pidFile)}, String(process.pid)); setTimeout(() => {}, 10000)`];
  await assert.rejects(copyText(PRIVATE, stall, 300), /copy_timeout/);
  const pid = Number(readFileSync(pidFile, "utf8"));
  await new Promise((r) => setTimeout(r, 100));
  assert.throws(() => process.kill(pid, 0), /ESRCH/, "the helper must not outlive the timeout");
});

test("desktop commands: only well-formed copy requests act; logs never contain the text", async () => {
  const copied = [], logs = [];
  const copy = async (t) => { copied.push(t); if (t === "boom") throw new Error(PRIVATE); };
  const log = (l) => logs.push(l);
  assert.equal(await handleDesktopCommand({ cmd: "copy", text: PRIVATE }, copy, log), true);
  assert.equal(await handleDesktopCommand({ cmd: "copy", text: "boom" }, copy, log), true);
  for (const bad of [null, "copy", 7, { cmd: "copy", text: 5 }, { cmd: "copy", text: { toString() { throw new Error("x"); } } }, { cmd: "copy" }, { cmd: "copy", text: "" }]) {
    await handleDesktopCommand(bad, copy, log);
  }
  assert.equal(await handleDesktopCommand({ cmd: "notify", title: PRIVATE }, copy, log), false, "notifications aren't a collector command");
  assert.deepEqual(copied, [PRIVATE, "boom"]);
  assert.deepEqual(logs, ["copy failed: failed"]);
});
