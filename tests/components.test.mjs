import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Loads the panel and its components in Qt's own test runner, offscreen: the status callout, the
// disconnected state, the detail view, a list row and the whole two-pane panel on a stub service,
// with real bindings and layout.
// components/ and lib/ are copied unchanged; the shell's qs.Commons and qs.Ui are stubbed with
// the few tokens and controls these components use. Skipped where qmltestrunner isn't installed.
const runner = ["/usr/lib/qt6/bin/qmltestrunner", "/usr/bin/qmltestrunner6", "/usr/bin/qmltestrunner"].find(existsSync);
const root = new URL("../", import.meta.url).pathname;

const COMMONS = {
  "qmldir": "module qs.Commons\nsingleton Color 1.0 Color.qml\nsingleton Style 1.0 Style.qml\nsingleton Util 1.0 Util.qml\n",
  // Records what the panel would run instead of running it.
  "Util.qml": `pragma Singleton
import QtQuick
QtObject { property var ran: []; function execArgv(argv) { ran = ran.concat([argv]) } }
`,
  "Color.qml": `pragma Singleton
import QtQuick
QtObject {
  property color foreground: "#d6cae3"
  property color background: "#01041f"
  property color accent: "#647dad"
  property color urgent: "#958bbb"
}
`,
  "Style.qml": `pragma Singleton
import QtQuick
QtObject {
  property int cornerRadius: 0
  property int gapsOut: 5
  readonly property QtObject font: QtObject {
    property string family: "monospace"
    property string resolvedFamily: "monospace"
    property int caption: 10
    property int bodySmall: 11
    property int body: 12
    property int subtitle: 13
    property int title: 14
    property int heading: 16
    property int display: 22
  }
  readonly property QtObject spacing: QtObject { property int controlHeight: 24; property int popupPadding: 12 }
  function space(px) { return Math.max(1, Math.round(px)) }
  function hoverFillFor(f, a) { return Qt.rgba(f.r, f.g, f.b, 0.08) }
  function selectedFillFor(f, a) { return Qt.rgba(f.r, f.g, f.b, 0.18) }
}
`,
};
const UI = {
  "qmldir": "module qs.Ui\nButton 1.0 Button.qml\nPanelSectionHeader 1.0 PanelSectionHeader.qml\nButtonGroup 1.0 ButtonGroup.qml\nPanelKeyCatcher 1.0 PanelKeyCatcher.qml\n",
  "ButtonGroup.qml": `import QtQuick
Row {
  property var options: []
  property string value: ""
  property color foreground: "white"
  property color background: "black"
  property color accent: "white"
  property string fontFamily: ""
  property real fontSize: 10
  property bool focusable: false
  signal changed(string value)
  Repeater {
    model: parent.options
    Rectangle {
      required property var modelData
      readonly property bool selected: modelData.value === parent.value
      readonly property string text: modelData.label
      implicitWidth: 80; implicitHeight: 24; width: 80; height: 24
    }
  }
}
`,
  "PanelKeyCatcher.qml": `import QtQuick
FocusScope {
  property bool blocked: false
  signal moveRequested(int dx, int dy)
  signal activateRequested()
  signal returnRequested()
  signal closeRequested()
  signal deleteRequested()
  signal tabRequested(int direction)
  signal textKey(string text)
}
`,
  "Button.qml": `import QtQuick
Rectangle {
  property string text: ""
  property color foreground: "white"
  property color accent: "white"
  property bool bordered: false
  property string fontFamily: ""
  property real fontSize: 10
  signal clicked()
  implicitWidth: 60; implicitHeight: 20
}
`,
  "PanelSectionHeader.qml": `import QtQuick
Text {
  property color foreground: "white"
  property string fontFamily: ""
  property real fontSize: 10
  color: foreground
  font.pixelSize: fontSize
}
`,
};

test("components: status callout, disconnected state, detail and row render the right words", { skip: runner ? false : "qmltestrunner not installed" }, () => {
  const tmp = mkdtempSync(join(tmpdir(), "loupe-components-"));
  try {
    for (const dir of ["components", "lib", "tests/qml", "qs/Commons", "qs/Ui"]) mkdirSync(join(tmp, dir), { recursive: true });
    for (const file of readdirSync(join(root, "components"))) copyFileSync(join(root, "components", file), join(tmp, "components", file));
    for (const file of readdirSync(join(root, "lib"))) copyFileSync(join(root, "lib", file), join(tmp, "lib", file));
    copyFileSync(join(root, "ThreadsPanel.qml"), join(tmp, "ThreadsPanel.qml"));
    copyFileSync(join(root, "tests/qml/tst_components.qml"), join(tmp, "tests/qml/tst_components.qml"));
    for (const [name, text] of Object.entries(COMMONS)) writeFileSync(join(tmp, "qs/Commons", name), text);
    for (const [name, text] of Object.entries(UI)) writeFileSync(join(tmp, "qs/Ui", name), text);
    const result = spawnSync(runner, ["-import", tmp, "-input", join(tmp, "tests/qml")], {
      env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QML_DISABLE_DISK_CACHE: "1" },
      encoding: "utf8",
      timeout: 90_000,
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stdout, /Totals: \d+ passed, 0 failed/);
    assert.doesNotMatch(result.stdout + result.stderr, /TypeError|ReferenceError|is not a type|unavailable/);
    // Any QML warning from the plugin's own files (bad anchors, broken bindings) fails the test.
    assert.doesNotMatch(result.stdout + result.stderr, /QWARN[^\n]*\/(components\/\w+|ThreadsPanel)\.qml/);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
});
