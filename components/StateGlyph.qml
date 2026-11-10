import QtQuick

// Per-thread status icon: spins while working, breathes while waiting on you.
Item {
  id: root
  property string icon: "circle-dot"
  property string threadState: "idle"
  property color color: "white"
  property real size: 16
  property bool reduceMotion: false
  // How faint a breath goes: the lowest opacity at which the glyph is still a 3:1 mark on the row
  // it is on (Palette.breathFloor). At 1 it doesn't breathe.
  property real breathTo: 0.7

  readonly property bool spinning: (threadState === "working" || threadState === "waiting") && !reduceMotion
  readonly property bool breathing: (threadState === "input" || threadState === "plan") && !reduceMotion && breathTo < 0.97

  implicitWidth: size
  implicitHeight: size

  LucideIcon {
    id: glyph
    anchors.centerIn: parent
    name: root.icon
    color: root.color
    size: root.size
    RotationAnimator on rotation {
      from: 0; to: 360; duration: root.threadState === "waiting" ? 2400 : 1100
      loops: Animation.Infinite
      running: root.spinning && root.visible
    }
  }
  onSpinningChanged: if (!spinning) glyph.rotation = 0

  SequentialAnimation {
    running: root.breathing && root.visible
    loops: Animation.Infinite
    NumberAnimation { target: glyph; property: "opacity"; to: root.breathTo; duration: 800; easing.type: Easing.InOutSine }
    NumberAnimation { target: glyph; property: "opacity"; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
    onRunningChanged: if (!running) glyph.opacity = 1
  }
}
