import QtQuick
import QtTest
import "../.." as Plugin
import "../../lib/Palette.js" as Palette

TestCase {
  id: tc
  name: "BarWidget"
  width: 400
  height: 400
  when: windowShown
  visible: true

  readonly property real now: Date.now()

  function row(key, state) {
    return { key: "e:" + key, envId: "e", id: key, parentId: "", title: key, project: "ops", state: state, rawStatus: "running",
      pendingKind: state === "input" ? "approval" : "", settled: false, background: { subagents: 0, commands: 0, monitors: 0, other: 0 },
      childCount: 0, activeChildren: 0, updatedAt: now }
  }

  // Matte Black's bar tokens.
  readonly property var theme: ({
    bar: Palette.derive({ background: "#121212", foreground: "#bebebe", accent: "#e68e0d", urgent: "#d35f5f", muted: "#333333",
      colors: { red: "#D35F5F", yellow: "#b91c1c", orange: "#c63d3d", green: "#FFC107", magenta: "#D35F5F", blue: "#e68e0d" } }),
    popup: ({})
  })

  QtObject {
    id: service
    property var theme: tc.theme
    property var counts: ({ active: 4, busy: 2, attention: 2, input: 1, review: 0 })
    property bool known: true
    property var environments: [{ id: "e" }]
    property var rows: [tc.row("a", "failed"), tc.row("b", "input"), tc.row("c", "working"), tc.row("d", "working")]
    property var settings: ({})
    property int openPanels: 0
    function registerWidget(w) {}
    function unregisterWidget(w) {}
    function refresh() {}
  }

  Component {
    id: barC
    QtObject {
      property bool vertical: false
      readonly property int barSize: vertical ? 28 : 26
      property string fontFamily: "monospace"
      property color barForeground: "#bebebe"
      property color urgent: "#d35f5f"
      property bool foregroundAnimationEnabled: false
      readonly property QtObject shell: QtObject { function serviceFor(name) { return service } }
      function showTooltip(item, text) {}
      function hideTooltip(item) {}
    }
  }
  Component { id: widgetC; Plugin.BarWidget {} }

  function find(item, pred) {
    if (pred(item)) return item
    for (var i = 0; i < item.children.length; i++) {
      var hit = find(item.children[i], pred)
      if (hit) return hit
    }
    return null
  }
  function parts(widget) {
    return {
      label: find(widget, function(it) { return it.text === "T3 Loupe" }),
      ring: find(widget, function(it) { return it.diameter !== undefined }),
      badge: find(widget, function(it) { return it.radius !== undefined && it.children.length === 1 && it.children[0].text === "2" })
    }
  }
  function make(vertical) {
    var bar = createTemporaryObject(barC, tc, { vertical: vertical })
    var widget = createTemporaryObject(widgetC, tc, { bar: bar })
    widget.width = Qt.binding(function() { return widget.implicitWidth })
    widget.height = Qt.binding(function() { return widget.implicitHeight })
    return widget
  }

  function test_horizontalBarLaysOutInARow() {
    var w = make(false)
    var p = parts(w)
    compare(w.implicitHeight, 26, "as tall as the bar")
    verify(p.label.visible, "the name shows on a horizontal bar")
    verify(p.badge.visible)
    verify(p.ring.mapToItem(w, 0, 0).x > p.label.mapToItem(w, 0, 0).x, "ring right of the name")
    verify(p.badge.mapToItem(w, 0, 0).x > p.ring.mapToItem(w, 0, 0).x, "badge right of the ring")
  }

  function test_verticalBarStacksWithinTheBarWidth() {
    var w = make(true)
    var p = parts(w)
    verify(w.implicitWidth <= 28, "fits a 28px vertical bar, got " + w.implicitWidth)
    verify(!p.label.visible, "no name on a vertical bar")
    verify(p.badge.visible)
    var ring = p.ring.mapToItem(w, 0, 0), badge = p.badge.mapToItem(w, 0, 0)
    verify(badge.y >= ring.y + p.ring.height, "badge below the ring")
    fuzzyCompare(ring.x + p.ring.width / 2, w.width / 2, 1, "ring centred across the bar")
    fuzzyCompare(badge.x + p.badge.width / 2, w.width / 2, 1, "badge centred across the bar")
  }
}
