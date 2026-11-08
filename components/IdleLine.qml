import QtQuick
import qs.Commons

// "› IDLE 3" fold, styled as a section heading that you can open.
Item {
  id: root
  property int count: 0
  property string label: "Idle"
  property bool open: false
  property bool selected: false
  property var colors: ({})
  property string fontFamily: Style.font.family

  signal clicked()

  implicitHeight: Style.space(28)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.selected ? root.colors.surfaceSelected
      : hover.hovered ? Style.hoverFillFor(root.colors.text, root.colors.accent) : "transparent"
    border.width: root.selected ? Style.space(2) : 0
    border.color: root.colors.focus
    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }
  Rectangle {
    visible: root.selected
    width: Style.space(3); height: parent.height
    color: root.colors.focus
  }

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: root.clicked() }

  Row {
    x: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)
    LucideIcon {
      anchors.verticalCenter: parent.verticalCenter
      name: "chevron-right"
      color: root.colors.textDim
      size: Math.round(Typo.caption * 1.2)
      rotation: root.open ? 90 : 0
      Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    SectionCaption {
      anchors.verticalCenter: parent.verticalCenter
      label: root.label
      count: root.count
      foreground: root.colors.text
      countColor: root.colors.textFaint
      fontFamily: root.fontFamily
    }
  }
}
