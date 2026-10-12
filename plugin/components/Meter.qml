import QtQuick
import qs.Commons

// Thin gauge in the shell's style: ink fill on a faint ink track, attention only when alarming.
Item {
  id: root
  property real value: 0          // 0..1
  property color ink: Color.foreground
  property color danger: Color.urgent
  property real dangerAt: 0.9
  property real fillOpacity: 0.7
  property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

  implicitWidth: Style.space(80)
  implicitHeight: thickness

  readonly property real clamped: Math.max(0, Math.min(1, value))
  readonly property bool alarming: clamped >= dangerAt

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)
  }
  Rectangle {
    width: Math.max(root.clamped > 0 ? height : 0, parent.width * root.clamped)
    height: parent.height
    radius: height / 2
    color: root.alarming ? root.danger : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, root.fillOpacity)
    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 260 } }
  }
}
