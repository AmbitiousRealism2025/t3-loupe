import QtQuick
import qs.Commons
import qs.Commons as Omarchy

// A gauge: an outlined bar as long as the whole, filled in ink as far as the value. The outline
// is drawn in `track` (a 3:1 tone), so the gauge's full length reads even when the fill is a
// sliver (4% of a limit) or nothing; it is the plan bar's language, solid for done and outlined
// for what is left. The fill turns `danger` near the end.
Item {
  id: root
  property real value: 0          // 0..1
  property color ink: Omarchy.Color.foreground
  property color danger: Omarchy.Color.urgent
  property color track: Qt.rgba(ink.r, ink.g, ink.b, 0.5)
  property real dangerAt: 0.9
  property real fillOpacity: 1
  property real thickness: Style.space(6)

  implicitWidth: Style.space(80)
  implicitHeight: thickness

  readonly property real clamped: Math.max(0, Math.min(1, value))
  readonly property bool alarming: clamped >= dangerAt
  readonly property real corner: Math.min(Style.cornerRadius, height / 2)

  objectName: "meter"

  Rectangle {
    objectName: "meterTrack"
    anchors.fill: parent
    radius: root.corner
    color: "transparent"
    border.width: 1
    border.color: root.track
  }
  Rectangle {
    objectName: "meterFill"
    // Any use at all shows as at least a 2 px sliver.
    width: root.clamped > 0 ? Math.max(Math.min(parent.width, Style.space(2)), parent.width * root.clamped) : 0
    height: parent.height
    radius: root.corner
    color: root.alarming ? root.danger : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, root.fillOpacity)
    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 260 } }
  }
}
