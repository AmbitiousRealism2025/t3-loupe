import QtQuick
import qs.Commons

// "Idle (n)" fold: a slim, clickable divider that collapses or reveals idle threads.
Item {
  id: root
  property int count: 0
  property bool open: false
  property bool selected: false
  property var colors: ({})
  property string fontFamily: Style.font.family

  signal clicked()

  implicitHeight: Style.space(26)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.selected ? root.colors.surfaceSelected : hover.hovered ? root.colors.surface : "transparent"
    border.width: root.selected ? 1 : 0
    border.color: Qt.rgba(root.colors.accent.r, root.colors.accent.g, root.colors.accent.b, 0.55)
    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
  }

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: root.clicked() }

  Row {
    id: label
    x: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    LucideIcon {
      anchors.verticalCenter: parent.verticalCenter
      name: "chevron-right"
      color: hover.hovered || root.selected ? root.colors.text : root.colors.textDim
      size: Math.round(Style.font.body * 1.05)
      rotation: root.open ? 90 : 0
      Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Idle (" + root.count + ")"
      textFormat: Text.PlainText
      color: hover.hovered || root.selected ? root.colors.text : root.colors.textDim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: Font.Medium
    }
  }

  // Divider running to the edge.
  Rectangle {
    anchors.left: label.right
    anchors.leftMargin: Style.space(10)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    height: 1
    color: root.colors.line
  }
}
