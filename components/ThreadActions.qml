import QtQuick
import qs.Commons

// A thread's actions, each with its key (the keys work from anywhere in the panel; clicking does
// the same). "o open T3" is the one every needs-you thread ends in, so it is in full ink; copying
// the title (to find the thread in T3, which o brings forward but cannot point at a thread) and
// opening the PR are quieter. One line: where the full labels don't fit the width given, the short
// ones do; a label never wraps. The PR action comes last because not every thread has one, so the
// other two never move.
Item {
  id: root

  property var row: null
  property var colors: ({})
  property string fontFamily: Style.font.family
  property string monoFamily: "monospace"
  // How copying this thread's title just ended: "" | "ok" | "failed". Shown on the copy action.
  property string copyState: ""
  // The dropdown's expanded card has buttons for these two; there the line is the T3 key alone.
  property bool secondary: true
  // The space the line keeps before the edge of what it sits in.
  property real margin: Style.space(16)

  signal actionRequested(string action)

  readonly property bool hasPr: row !== null && row !== undefined && !!row.pr && row.pr.url !== ""
  readonly property bool shortLabels: full.implicitWidth + margin > width

  implicitWidth: full.implicitWidth
  implicitHeight: shown.implicitHeight

  component Keys: Row {
    property bool short: false
    spacing: Style.space(16)
    KeyAction {
      key: "o"; text: parent.short ? "open" : "open T3"
      colors: root.colors; fontFamily: root.fontFamily; monoFamily: root.monoFamily
      onClicked: root.actionRequested("focus")
    }
    KeyAction {
      visible: root.secondary
      key: "c"; text: parent.short ? "copy" : "copy title"; quiet: true
      colors: root.colors; fontFamily: root.fontFamily; monoFamily: root.monoFamily
      feedback: root.copyState === "ok" ? "✓ copied" : root.copyState === "failed" ? "copy failed" : ""
      feedbackInk: root.copyState === "failed" ? root.colors.attentionInk : root.colors.text
      onClicked: root.actionRequested("copy")
    }
    KeyAction {
      visible: root.secondary && root.hasPr
      key: "p"; text: parent.short ? "PR" : "open PR"; quiet: true
      colors: root.colors; fontFamily: root.fontFamily; monoFamily: root.monoFamily
      onClicked: root.actionRequested("pr")
    }
  }

  // Measured, not shown: the full labels' width decides which labels are used.
  Keys { id: full; opacity: 0; enabled: false; y: -10000 }
  Keys { id: shown; short: root.shortLabels }
}
