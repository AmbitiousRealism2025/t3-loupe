import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Drives components/FilterField.qml with real key events through Qt's own test runner, offscreen.
// The component and the store it imports are copied, unchanged, into a temp folder with the same
// layout: the real components/ folder also holds the shell-only singleton Typo, which needs qs.Commons.
// Skipped where qmltestrunner isn't installed.
const runner = ["/usr/lib/qt6/bin/qmltestrunner", "/usr/bin/qmltestrunner6", "/usr/bin/qmltestrunner"].find(existsSync);
const root = new URL("../", import.meta.url).pathname;

test("FilterField: key handling, no paste, no editable text input", { skip: runner ? false : "qmltestrunner not installed" }, () => {
  const tmp = mkdtempSync(join(tmpdir(), "loupe-filter-"));
  try {
    for (const dir of ["components", "lib", "tests/qml"]) mkdirSync(join(tmp, dir), { recursive: true });
    for (const file of ["components/FilterField.qml", "lib/Store.js", "tests/qml/tst_filterfield.qml"]) copyFileSync(join(root, file), join(tmp, file));
    const result = spawnSync(runner, ["-input", join(tmp, "tests/qml")], {
      env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QML_DISABLE_DISK_CACHE: "1" },
      encoding: "utf8",
      timeout: 60_000,
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stdout, /Totals: \d+ passed, 0 failed/);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
});
