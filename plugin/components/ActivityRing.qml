import QtQuick
import QtQuick.Shapes

// Segmented ring: one arc per state group, sized by its share of active threads.
// Rotates slowly while anything works; the attention arc breathes when a thread needs you.
Item {
  id: root

  // [{ role, count }] from Store.distribution; colors resolved through `colors`.
  property var segments: []
  property var colors: ({})
  property real diameter: 18
  property real thickness: Math.max(2, diameter / 7)
  property bool spinning: false
  property bool alert: false
  property bool reduceMotion: false
  property bool offline: false
  property string centerText: ""
  property color textColor: "white"
  property string fontFamily: ""
  property real fontSize: 9

  implicitWidth: diameter
  implicitHeight: diameter

  readonly property real total: {
    var t = 0
    for (var i = 0; i < segments.length; i++) t += segments[i].count
    return t
  }
  // Small gaps between arcs read as distinct segments; none when only one is present.
  readonly property int present: {
    var n = 0
    for (var i = 0; i < segments.length; i++) if (segments[i].count > 0) n++
    return n
  }
  readonly property real gap: present > 1 ? 14 : 0

  function startOf(index) {
    var acc = 0
    for (var i = 0; i < index; i++) acc += segments[i] ? segments[i].count : 0
    return total > 0 ? -90 + acc / total * 360 + gap / 2 : -90
  }
  function sweepOf(index) {
    var c = segments[index] ? segments[index].count : 0
    return total > 0 && c > 0 ? Math.max(4, c / total * 360 - gap) : 0
  }
  function colorOf(index) {
    var s = segments[index]
    return s && colors[s.role] ? colors[s.role] : "transparent"
  }

  Shape {
    id: ring
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    readonly property real r: (root.diameter - root.thickness) / 2

    // Track
    ShapePath {
      strokeColor: root.colors.track || "#40808080"
      strokeWidth: root.thickness
      fillColor: "transparent"
      strokeStyle: root.offline ? ShapePath.DashLine : ShapePath.SolidLine
      dashPattern: [1.2, 1.6]
      PathAngleArc { centerX: root.diameter / 2; centerY: root.diameter / 2; radiusX: ring.r; radiusY: ring.r; startAngle: 0; sweepAngle: 360 }
    }

    ShapePath {
      strokeColor: root.colorOf(0); strokeWidth: root.thickness; fillColor: "transparent"; capStyle: ShapePath.FlatCap
      PathAngleArc { centerX: root.diameter / 2; centerY: root.diameter / 2; radiusX: ring.r; radiusY: ring.r; startAngle: root.startOf(0); sweepAngle: root.sweepOf(0) }
    }
    ShapePath {
      strokeColor: root.colorOf(1); strokeWidth: root.thickness; fillColor: "transparent"; capStyle: ShapePath.FlatCap
      PathAngleArc { centerX: root.diameter / 2; centerY: root.diameter / 2; radiusX: ring.r; radiusY: ring.r; startAngle: root.startOf(1); sweepAngle: root.sweepOf(1) }
    }
    ShapePath {
      strokeColor: root.colorOf(2); strokeWidth: root.thickness; fillColor: "transparent"; capStyle: ShapePath.FlatCap
      PathAngleArc { centerX: root.diameter / 2; centerY: root.diameter / 2; radiusX: ring.r; radiusY: ring.r; startAngle: root.startOf(2); sweepAngle: root.sweepOf(2) }
    }
    ShapePath {
      strokeColor: root.colorOf(3); strokeWidth: root.thickness; fillColor: "transparent"; capStyle: ShapePath.FlatCap
      PathAngleArc { centerX: root.diameter / 2; centerY: root.diameter / 2; radiusX: ring.r; radiusY: ring.r; startAngle: root.startOf(3); sweepAngle: root.sweepOf(3) }
    }
    ShapePath {
      strokeColor: root.colorOf(4); strokeWidth: root.thickness; fillColor: "transparent"; capStyle: ShapePath.FlatCap
      PathAngleArc { centerX: root.diameter / 2; centerY: root.diameter / 2; radiusX: ring.r; radiusY: ring.r; startAngle: root.startOf(4); sweepAngle: root.sweepOf(4) }
    }

    RotationAnimator on rotation {
      from: 0; to: 360
      duration: 9000
      loops: Animation.Infinite
      running: root.spinning && !root.reduceMotion && root.visible
    }
    // Settle back to the resting orientation when work stops.
    Behavior on rotation { enabled: !root.spinning; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
  }
  onSpinningChanged: if (!spinning) ring.rotation = 0

  // Breathing halo for attention.
  Rectangle {
    anchors.centerIn: parent
    width: root.diameter + root.thickness * 2
    height: width
    radius: width / 2
    color: "transparent"
    border.width: root.thickness * 0.8
    border.color: root.colors.attention || "red"
    visible: root.alert
    opacity: 0
    SequentialAnimation on opacity {
      running: root.alert && !root.reduceMotion && root.visible
      loops: Animation.Infinite
      NumberAnimation { from: 0.0; to: 0.55; duration: 700; easing.type: Easing.OutCubic }
      NumberAnimation { from: 0.55; to: 0.0; duration: 1100; easing.type: Easing.InCubic }
    }
    Component.onCompleted: if (root.reduceMotion) opacity = 0.4
  }

  Text {
    anchors.centerIn: parent
    text: root.centerText
    visible: text !== ""
    color: root.textColor
    font.family: root.fontFamily
    font.pixelSize: Math.max(6, Math.round(root.centerText.length > 1 ? root.fontSize * 0.86 : root.fontSize))
    font.bold: true
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
  }
}
