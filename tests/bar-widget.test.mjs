import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Loads the unchanged BarWidget.qml on a horizontal and a vertical bar, offscreen. The widget's base
// types come from the installed shell when OMARCHY_SHELL (or /usr/share/omarchy/shell) has them;
// otherwise from stubs with the same properties as Omarchy 4.0.2's Ui/Panel.qml and
// Ui/WidgetButton.qml. Panel has no bar geometry; WidgetButton reads `vertical` and `barSize` off the bar.
const runner = ["/usr/lib/qt6/bin/qmltestrunner", "/usr/bin/qmltestrunner6", "/usr/bin/qmltestrunner"].find(existsSync);
const root = new URL("../", import.meta.url).pathname;
const shell = [process.env.OMARCHY_SHELL, "/usr/share/omarchy/shell"].find((dir) => dir && existsSync(join(dir, "Ui/Panel.qml")));

const COMMONS = {
  "qmldir": "module qs.Commons\nsingleton Color 1.0 Color.qml\nsingleton Style 1.0 Style.qml\nsingleton Typo 1.0 Typo.qml\nsingleton Border 1.0 Border.qml\nShellIpc 1.0 ShellIpc.qml\n",
  "Color.qml": `pragma Singleton
import QtQuick
QtObject {
  property color foreground: "#bebebe"
  property color urgent: "#d35f5f"
  readonly property QtObject popups: QtObject { property color background: "#121212" }
}
`,
  "Style.qml": `pragma Singleton
import QtQuick
QtObject {
  property int cornerRadius: 0
  property var easeOut: [0.22, 1, 0.36, 1, 1, 1]
  readonly property QtObject font: QtObject { property string family: "monospace"; property int body: 12 }
  readonly property QtObject spacing: QtObject { property int popupPadding: 12 }
  readonly property QtObject bar: QtObject { property int sizeHorizontal: 26; property int sizeVertical: 28; property int iconSlot: 27; property int iconCanvas: 20; property int iconSize: 14 }
  function duration(ms) { return ms }
  function spaceReal(px) { return px }
  function space(px) { return Math.max(1, Math.round(px)) }
}
`,
  "Typo.qml": "pragma Singleton\nimport QtQuick\nQtObject { property int bump: 0 }\n",
  "Border.qml": "pragma Singleton\nimport QtQuick\nQtObject { function top(spec) { return 0 } }\n",
  "ShellIpc.qml": "import QtQuick\nQtObject { property bool enabled: false; property string target: \"\" }\n",
};
const UI_STUBS = {
  "PanelController.qml": `import QtQuick
QtObject {
  property bool open: false
  function show() { open = true }
  function hide() { open = false }
}
`,
  "Panel.qml": `import QtQuick
import Quickshell.Io
Item {
  id: root
  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})
  property string ipcTarget: ""
  property bool manageIpc: true
  property alias controller: panelController
  readonly property bool opened: panelController.open
  function open() { panelController.show() }
  function close() { panelController.hide() }
  function toggle() { opened ? close() : open() }
  function switchPanel(direction) { return false }
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
  PanelController { id: panelController }
  IpcHandler { enabled: root.manageIpc && root.ipcTarget !== ""; target: root.ipcTarget }
}
`,
  "WidgetButton.qml": `import QtQuick
import qs.Commons
Item {
  id: root
  property var bar: null
  property string text: ""
  property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property real fontSize: Style.font.body
  property color foreground: bar ? bar.barForeground : Color.foreground
  property bool active: false
  property real horizontalMargin: 8.5
  property real verticalPadding: 6
  property real fixedWidth: -1
  property real fixedHeight: -1
  property bool labelVisible: true
  property bool hasVisualContent: text !== ""
  property string tooltipText: ""
  signal pressed(int button)
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property real scaledHorizontalMargin: Style.spaceReal(horizontalMargin)
  readonly property real scaledVerticalPadding: Style.spaceReal(verticalPadding)
  implicitWidth: fixedWidth > 0 ? fixedWidth : (vertical ? barSize : 12)
  implicitHeight: fixedHeight > 0 ? fixedHeight : (vertical ? 12 : barSize)
}
`,
};
const UI_EXTRA = {
  "KeyboardPanel.qml": `import QtQuick
Item {
  property var anchorItem: null
  property var owner: null
  property var bar: null
  property bool open: false
  property var focusTarget: null
  property real contentWidth: 0
  property real contentHeight: 0
  property real padding: 0
  property var borderSpec: null
  function fittedContentWidth(w) { return w }
  function fittedContentHeight(h, max) { return h }
}
`,
  "OpticalGlyph.qml": `import QtQuick
Item {
  property string text: ""
  property string fontFamily: ""
  property real fontSize: 12
  property real paintedSize: 0
  property color color: "#bebebe"
  property real paintedWidth: 0
  property real paintedHeight: 0
  property real paintedCenterX: 0
  property real paintedCenterY: 0
}
`,
};
const QUICKSHELL = {
  "Quickshell/qmldir": "module Quickshell\nsingleton QsWindow 1.0 QsWindow.qml\n",
  "Quickshell/QsWindow.qml": "pragma Singleton\nimport QtQuick\nQtObject { property var window: null }\n",
  "Quickshell/Io/qmldir": "module Quickshell.Io\nIpcHandler 1.0 IpcHandler.qml\n",
  "Quickshell/Io/IpcHandler.qml": "import QtQuick\nQtObject { property bool enabled: false; property string target: \"\" }\n",
};
// The panel windows are not under test: stand-ins with the properties BarWidget sets.
const PLUGIN_STUBS = {
  "components/CenteredWindow.qml": `import QtQuick
Item {
  property bool open: false
  property var bar: null
  property var owner: null
  property var screen: null
  property var colors: ({})
  property bool reduceMotion: false
  property real padding: 0
  default property alias contentData: slot.data
  signal dismissRequested()
  Item { id: slot }
}
`,
  "ThreadsPanel.qml": `import QtQuick
Item {
  property var service: null
  property bool opened: false
  property bool centered: false
  property real gutter: 0
  property bool reduceMotion: false
  readonly property Item keyCatcher: Item {}
  signal closeRequested()
  signal switchRequested(int direction)
  signal layoutToggleRequested()
  function focusKey(key) {}
}
`,
};

test("BarWidget: lays out along the bar, stacked on a vertical bar", { skip: runner ? false : "qmltestrunner not installed" }, () => {
  const tmp = mkdtempSync(join(tmpdir(), "loupe-bar-"));
  try {
    for (const dir of ["components", "lib", "tests/qml", "qs/Commons", "qs/Ui", "Quickshell/Io"]) mkdirSync(join(tmp, dir), { recursive: true });
    for (const file of ["BarWidget.qml", "components/ActivityRing.qml", "tests/qml/tst_barwidget.qml"]) copyFileSync(join(root, file), join(tmp, file));
    for (const file of readdirSync(join(root, "lib"))) copyFileSync(join(root, "lib", file), join(tmp, "lib", file));
    const ui = { ...UI_EXTRA, ...UI_STUBS };
    if (shell) for (const name of Object.keys(UI_STUBS)) delete ui[name];
    if (shell) for (const name of Object.keys(UI_STUBS)) copyFileSync(join(shell, "Ui", name), join(tmp, "qs/Ui", name));
    ui.qmldir = "module qs.Ui\nPanel 1.0 Panel.qml\nPanelController 1.0 PanelController.qml\nWidgetButton 1.0 WidgetButton.qml\nKeyboardPanel 1.0 KeyboardPanel.qml\nOpticalGlyph 1.0 OpticalGlyph.qml\n";
    for (const [name, text] of Object.entries(COMMONS)) writeFileSync(join(tmp, "qs/Commons", name), text);
    for (const [name, text] of Object.entries(ui)) writeFileSync(join(tmp, "qs/Ui", name), text);
    for (const [name, text] of Object.entries({ ...QUICKSHELL, ...PLUGIN_STUBS })) writeFileSync(join(tmp, name), text);
    const result = spawnSync(runner, ["-import", tmp, "-input", join(tmp, "tests/qml")], {
      env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QML_DISABLE_DISK_CACHE: "1" },
      encoding: "utf8",
      timeout: 90_000,
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stdout, /Totals: \d+ passed, 0 failed/);
    assert.doesNotMatch(result.stdout + result.stderr, /TypeError|ReferenceError|is not a type|unavailable/);
    assert.doesNotMatch(result.stdout + result.stderr, /QWARN[^\n]*\/(BarWidget|components\/ActivityRing)\.qml/);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
});
