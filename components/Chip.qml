import QtQuick
import qs.Commons

// Small tag: optional icon + text, tinted by a role color.
Rectangle {
  id: root
  property string icon: ""
  property string text: ""
  property color tone: "white"
  property color ink: tone
  property string fontFamily: Style.font.family
  property bool outlined: false
  property bool mono: false
  // Plain: an icon and its words with no box round them. A fact about a thread is not something
  // to press, and a bordered tag reads as a button.
  property bool plain: false

  implicitWidth: row.implicitWidth + (plain ? 0 : Style.space(12))
  implicitHeight: Math.max(label.implicitHeight, iconItem.size) + (plain ? Style.space(2) : Style.space(5))
  radius: Math.min(Style.cornerRadius, height / 2)
  color: outlined || plain ? "transparent" : Qt.rgba(tone.r, tone.g, tone.b, 0.13)
  border.width: plain ? 0 : 1
  border.color: Qt.rgba(tone.r, tone.g, tone.b, outlined ? 0.45 : 0.22)

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(plain ? 6 : 4)
    LucideIcon {
      id: iconItem
      visible: root.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      name: root.icon || "circle-dot"
      color: root.ink
      size: Math.round(Typo.caption * 1.15)
    }
    Text {
      id: label
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      textFormat: Text.PlainText
      color: root.ink
      font.family: root.fontFamily
      font.pixelSize: Typo.caption
      font.weight: Font.Medium
      renderType: Text.NativeRendering
    }
  }
}
