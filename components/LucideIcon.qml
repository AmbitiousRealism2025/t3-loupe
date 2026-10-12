import QtQuick
import QtQuick.Shapes
import "../lib/Icons.js" as Icons

// A Lucide icon drawn as theme-colored vector strokes (24×24 grid, 2px round strokes).
Item {
  id: root
  property string name: "circle-dot"
  property color color: "white"
  property real size: 16
  property real strokeWidth: 2

  implicitWidth: size
  implicitHeight: size

  Shape {
    width: 24
    height: 24
    anchors.centerIn: parent
    scale: root.size / 24
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: Icons.svg(root.name) }
    }
  }
}
