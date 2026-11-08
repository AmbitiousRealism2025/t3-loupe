import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const runner = ["/usr/lib/qt6/bin/qmltestrunner", "/usr/bin/qmltestrunner6", "/usr/bin/qmltestrunner"].find(existsSync);
const root = new URL("../", import.meta.url).pathname;

// Exercise the unchanged Theme.qml in Qt, not a JS VM: Qt Quick also exposes a
// Color type, which must not shadow the shell's singleton. Host tokens and file
// APIs are stubbed; palette derivation, bindings and Connections are real code.
test("Theme: resolves Omarchy colors and follows live token changes", { skip: runner ? false : "qmltestrunner not installed" }, () => {
  const tmp = mkdtempSync(join(tmpdir(), "loupe-theme-"));
  try {
    for (const dir of ["lib", "qs/Commons", "Quickshell/Io", "tests/qml"]) mkdirSync(join(tmp, dir), { recursive: true });
    for (const file of ["Theme.qml", "lib/Palette.js", "tests/qml/tst_theme.qml"]) copyFileSync(join(root, file), join(tmp, file));
    writeFileSync(join(tmp, "Quickshell/qmldir"), "module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n");
    writeFileSync(join(tmp, "Quickshell/Quickshell.qml"), `pragma Singleton
import QtQuick
QtObject { function env(name) { return "/nonexistent-loupe-theme-test" } }
`);
    writeFileSync(join(tmp, "Quickshell/Io/qmldir"), "module Quickshell.Io\nFileView 1.0 FileView.qml\n");
    writeFileSync(join(tmp, "Quickshell/Io/FileView.qml"), `import QtQuick
QtObject {
  property string path: ""
  property bool printErrors: false
  signal loaded()
  signal loadFailed()
  function text() { return "" }
  function reload() { loadFailed() }
}
`);
    writeFileSync(join(tmp, "qs/Commons/qmldir"), "module qs.Commons\nsingleton Color 1.0 Color.qml\n");
    writeFileSync(join(tmp, "qs/Commons/Color.qml"), `pragma Singleton
import QtQuick
QtObject {
  property color background: "#01041f"
  property color foreground: "#d6cae3"
  property color accent: "#647dad"
  property color urgent: "#958bbb"
  property color muted: "#5b5d63"
  property var shellValues: ({})
  readonly property QtObject popups: QtObject {
    property color background: "#01041f"
    property color text: "#d6cae3"
  }
  readonly property QtObject bar: QtObject {
    property color background: "#01041f"
    property color text: "#d6cae3"
  }
}
`);
    const result = spawnSync(runner, ["-import", tmp, "-input", join(tmp, "tests/qml")], {
      env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QML_DISABLE_DISK_CACHE: "1" },
      encoding: "utf8",
      timeout: 60_000,
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stdout, /Totals: \d+ passed, 0 failed/);
    assert.doesNotMatch(result.stdout + result.stderr, /TypeError|no signal of the target matches/);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
});

// Qt 6.12 added QtQuick's Color type, which wins over qs.Commons' Color whatever the
// import order. Every runtime file must reach the shell's palette as Omarchy.Color.
test("Theme: no QML file names the shell's Color unqualified", () => {
  const files = readdirSync(root, { recursive: true }).filter((f) => f.endsWith(".qml") && !f.startsWith("tests/") && !f.startsWith("."));
  const bare = [];
  for (const file of files) {
    readFileSync(join(root, file), "utf8").split("\n").forEach((line, i) => {
      if (/(^|[^.\w])Color\b/.test(line.replace(/\/\/.*$/, ""))) bare.push(`${file}:${i + 1}`);
    });
  }
  assert.ok(files.length > 10, "found the plugin's QML files");
  assert.deepEqual(bare, []);
});
