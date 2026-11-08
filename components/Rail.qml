import QtQuick
import qs.Commons

// The left-edge bar on a row: solid, or dashed for a failure, so a failed row differs from one
// waiting on your answer by shape as well as hue (red and violet are close for some readers).
Item {
  id: root
  property color color: "white"
  property bool dashed: false

  width: Style.space(3)

  Rectangle {
    visible: !root.dashed
    anchors.fill: parent
    color: root.color
  }
  Column {
    visible: root.dashed
    spacing: Style.space(3)
    Repeater {
      model: root.dashed ? Math.ceil(root.height / Style.space(8)) : 0
      Rectangle { width: root.width; height: Style.space(5); color: root.color }
    }
  }
  clip: true
}
