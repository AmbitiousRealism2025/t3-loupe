import QtQuick
import qs.Commons
import "../lib/Palette.js" as Palette

// A key and what it does, as an action: "[o] Answer in T3". The key works from anywhere in the
// panel; clicking the line does the same thing.
Item {
  id: root
  property string key: "o"
  property string text: ""
  property var colors: ({})
  property string fontFamily: Style.font.family
  property string monoFamily: "monospace"
  // Quiet: dim ink, for secondary actions (detail header). Otherwise full-strength text: it says
  // what to do next, and it must not look like a link.
  property bool quiet: false
  // Wraps: the label wraps inside a width the parent gives (a sentence in a callout). Otherwise it is
  // one line at its natural width and never breaks: its width must not depend on its own width, or
  // the layout can settle on a narrow one and stack the label a letter per line.
  property bool wraps: false
  // What the action just did ("✓ copied"), shown in place of the label for a moment. The action
  // keeps the width of its label meanwhile, so nothing beside it moves.
  property string feedback: ""
  property color feedbackInk: colors.text
  readonly property color ink: quiet ? colors.textDim : colors.text
  readonly property real labelWidth: Math.max(label.implicitWidth, rest.implicitWidth)

  signal clicked()

  implicitWidth: cap.width + row.spacing + (wraps ? label.implicitWidth : labelWidth)
  implicitHeight: row.implicitHeight

  Row {
    id: row
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
        color: hover.hovered ? root.colors.surfaceSelected : Palette.mix(root.colors.background, root.colors.text, 0.12)
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
      id: label
      anchors.verticalCenter: parent.verticalCenter
      width: root.wraps ? Math.max(0, root.width - cap.width - parent.spacing) : root.labelWidth
      text: root.feedback !== "" ? root.feedback : root.text
      textFormat: Text.PlainText
      color: root.feedback !== "" ? root.feedbackInk : root.ink
      font.family: root.fontFamily
      font.pixelSize: Typo.caption
      font.weight: Font.Medium
      font.underline: hover.hovered && root.feedback === ""
      wrapMode: root.wraps ? Text.Wrap : Text.NoWrap
    }
  }
  // The label at rest, measured: it holds the action's width while feedback shows.
  Text { id: rest; visible: false; text: root.text; textFormat: Text.PlainText; font: label.font }

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: root.clicked() }
}
