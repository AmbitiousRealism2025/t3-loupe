import QtQuick
import qs.Commons

// A key and what it does, as an action: "[o] Answer in T3". The key works from anywhere in the
// panel; clicking the line does the same thing.
Item {
  id: root
  property string key: "o"
  property string text: ""
  property var colors: ({})
  property string fontFamily: Style.font.family
  property string monoFamily: "monospace"

  signal clicked()

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    width: root.width
    spacing: Style.space(8)
    Rectangle {
      id: cap
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(height, capText.implicitWidth + Style.space(10))
      height: capText.implicitHeight + Style.space(4)
      radius: Math.min(Style.cornerRadius, Style.space(3))
      color: hover.hovered ? Style.hoverFillFor(root.colors.text, root.colors.accent) : "transparent"
      border.width: 1
      border.color: root.colors.accent
      Text {
        id: capText
        anchors.centerIn: parent
        text: root.key
        textFormat: Text.PlainText
        color: root.colors.accentInk
        font.family: root.monoFamily
        font.pixelSize: Typo.caption
        font.bold: true
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: root.width > 0 ? root.width - cap.width - parent.spacing : implicitWidth
      text: root.text
      textFormat: Text.PlainText
      color: root.colors.accentInk
      font.family: root.fontFamily
      font.pixelSize: Typo.caption
      font.weight: Font.Medium
      font.underline: hover.hovered
      wrapMode: Text.Wrap
    }
  }

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: root.clicked() }
}
