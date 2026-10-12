import QtQuick
import qs.Commons
import qs.Ui

// Section heading in the shell's PanelSectionHeader style: bold caption, darkened ink,
// letter-spaced uppercase label, with an optional quiet count.
Row {
  id: root
  property string label: ""
  property int count: -1
  property color foreground: Color.foreground
  property color countColor: Qt.darker(foreground, 1.9)
  property string fontFamily: Style.font.family
  // When set, the label elides to fit instead of overflowing (e.g. narrow facts cells).
  property real maxWidth: -1

  spacing: Style.space(8)

  PanelSectionHeader {
    anchors.verticalCenter: parent.verticalCenter
    text: root.label.toUpperCase()
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: Typo.caption
    font.letterSpacing: 1.2
    width: root.maxWidth > 0 ? Math.min(implicitWidth, root.maxWidth - (countText.visible ? countText.implicitWidth + root.spacing : 0)) : implicitWidth
    elide: Text.ElideRight
  }
  Text {
    id: countText
    visible: root.count >= 0
    anchors.verticalCenter: parent.verticalCenter
    text: String(root.count)
    textFormat: Text.PlainText
    color: root.countColor
    font.family: root.fontFamily
    font.pixelSize: Typo.caption
  }
}
