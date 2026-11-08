import QtQuick
import qs.Commons
import qs.Commons as Omarchy

// Thin gauge in the shell's style: a solid ink fill over a hairline track. The track is drawn in
// `track` (a 3:1 tone) so the gauge's full length is visible; the fill turns `danger` near the end.
Item {
  id: root
  property real value: 0          // 0..1
  property color ink: Omarchy.Color.foreground
  property color danger: Omarchy.Color.urgent
  property color track: Qt.rgba(ink.r, ink.g, ink.b, 0.5)
  property real dangerAt: 0.9
  property real fillOpacity: 1
  property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

  implicitWidth: Style.space(80)
  implicitHeight: thickness

  readonly property real clamped: Math.max(0, Math.min(1, value))
  readonly property bool alarming: clamped >= dangerAt

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: Math.max(1, Math.round(parent.height / 3))
    radius: height / 2
    color: root.track
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
