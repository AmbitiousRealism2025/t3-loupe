import QtQuick
import QtQuick.Shapes

// Segmented ring: one arc per state group, sized by its share of active threads.
// Rotates slowly while anything works. No halo: the arcs carry the state, each at 3:1 or more.
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

  // Least arc a present segment gets, so one thread among many still reads as a segment, not a tick.
  property real minSweep: 34
  // Sweep per segment: proportional, with every present segment raised to minSweep and the room
  // taken from the larger ones.
  readonly property var sweeps: {
    var n = segments.length, out = []
    var room = 360 - present * gap
    if (total <= 0) { for (var i = 0; i < n; i++) out.push(0); return out }
    var floor = Math.min(minSweep, room / Math.max(1, present))
    var raised = 0, rest = 0
    for (var j = 0; j < n; j++) {
      var c = segments[j] ? segments[j].count : 0
      var share = c > 0 ? c / total * room : 0
      out.push(share)
      if (c > 0 && share < floor) raised += floor - share
      else if (c > 0) rest += share - floor
    }
    for (var k = 0; k < n; k++) {
      if (out[k] <= 0) continue
      if (out[k] < floor) out[k] = floor
      else if (rest > 0) out[k] -= (out[k] - floor) / rest * raised
    }
    return out
  }
  function startOf(index) {
    var acc = 0
    for (var i = 0; i < index; i++) acc += sweeps[i] > 0 ? sweeps[i] + gap : 0
    return -90 + acc + gap / 2
  }
  function sweepOf(index) { return sweeps[index] || 0 }
  function colorOf(index) {
    var s = segments[index]
    return s && colors[s.role] ? colors[s.role] : "transparent"
  }

  Shape {
    id: ring
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    readonly property real r: (root.diameter - root.thickness) / 2

    // Track: only when there is nothing to show (or offline, dashed), so no faint ring sits behind the arcs.
    ShapePath {
      strokeColor: root.total > 0 && !root.offline ? "transparent" : (root.colors.track || "#40808080")
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
