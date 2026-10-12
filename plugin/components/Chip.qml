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

  implicitWidth: row.implicitWidth + Style.space(12)
  implicitHeight: Math.max(label.implicitHeight, iconItem.size) + Style.space(5)
  radius: Math.min(Style.cornerRadius, height / 2)
  color: outlined ? "transparent" : Qt.rgba(tone.r, tone.g, tone.b, 0.13)
  border.width: 1
  border.color: Qt.rgba(tone.r, tone.g, tone.b, outlined ? 0.45 : 0.22)

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(4)
    LucideIcon {
      id: iconItem
      visible: root.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      name: root.icon || "circle-dot"
      color: root.ink
      size: Math.round(Style.font.caption * 1.15)
    }
    Text {
      id: label
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      textFormat: Text.PlainText
      color: root.ink
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: Font.Medium
      renderType: Text.NativeRendering
    }
  }
}
