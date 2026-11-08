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
  // Quiet: plain ink instead of the accent, for secondary actions (detail header).
  property bool quiet: false
  readonly property color ink: quiet ? colors.textDim : colors.accentInk

  signal clicked()

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    width: root.width
    spacing: Style.space(8)
    // A keycap: raised face on a darker base, the letter in full ink, so it reads as a key, not a box.
    Item {
      id: cap
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(height, capText.implicitWidth + Style.space(10))
      height: capText.implicitHeight + Style.space(6)
      Rectangle {
        anchors.fill: parent
        radius: Math.min(Style.cornerRadius, Style.space(3))
        color: root.colors.edge
      }
      Rectangle {
        width: parent.width
        height: parent.height - Style.space(2)
        radius: Math.min(Style.cornerRadius, Style.space(3))
        color: hover.hovered ? root.colors.surfaceSelected : Qt.tint(root.colors.background, Qt.rgba(root.colors.text.r, root.colors.text.g, root.colors.text.b, 0.12))
        border.width: 1
        border.color: root.colors.edge
        Text {
          id: capText
          anchors.centerIn: parent
          text: root.key
          textFormat: Text.PlainText
          color: root.colors.text
          font.family: root.monoFamily
          font.pixelSize: Typo.caption
          font.bold: true
        }
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: root.width > 0 ? root.width - cap.width - parent.spacing : implicitWidth
      text: root.text
      textFormat: Text.PlainText
      color: root.ink
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
