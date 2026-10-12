import QtQuick
import qs.Commons

// Thin horizontal gauge. Fill shifts toward warning/attention as it nears full.
Item {
  id: root
  property real value: 0          // 0..1
  property color track: "#30808080"
  property color fill: "white"
  property color warning: fill
  property color danger: fill
  property real warnAt: 0.75
  property real dangerAt: 0.9
  property real thickness: Style.space(4)

  implicitWidth: Style.space(80)
  implicitHeight: thickness

  readonly property real clamped: Math.max(0, Math.min(1, value))

  Rectangle {
    anchors.fill: parent
    radius: Math.min(Style.cornerRadius, height / 2)
    color: root.track
  }
  Rectangle {
    width: Math.max(root.clamped > 0 ? 2 : 0, parent.width * root.clamped)
    height: parent.height
    radius: Math.min(Style.cornerRadius, height / 2)
    color: root.clamped >= root.dangerAt ? root.danger : root.clamped >= root.warnAt ? root.warning : root.fill
    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 260 } }
  }
}
