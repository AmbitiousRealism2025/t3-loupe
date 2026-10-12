import QtQuick
import qs.Commons

// Footer text-size control: A↓ · four rising bars (one per preset, click to jump) · A↑.
// The smallest preset is the shell's own size.
Row {
  id: root
  property var sizes: [0, 2, 4, 6]
  property int step: 0
  property var colors: ({})
  signal stepRequested(int delta)
  signal sizeRequested(real size)

  spacing: Style.space(4)

  IconButton {
    anchors.verticalCenter: parent.verticalCenter
    icon: "a-arrow-down"
    iconSize: Math.round(Typo.caption * 1.25)
    foreground: root.colors.textDim
    hoverForeground: root.colors.text
    available: root.step > 0
    onClicked: root.stepRequested(-1)
  }

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)
    Repeater {
      model: root.sizes.length
      Item {
        required property int index
        readonly property bool on: index <= root.step
        width: Style.space(7)
        height: Style.space(14)
        Rectangle {
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          width: Style.space(4)
          height: Style.space(5 + index * 3)
          radius: Style.cornerRadius > 0 ? 1 : 0
          color: root.colors.text
          opacity: parent.on ? (index === root.step ? 0.85 : 0.45) : (barHover.hovered ? 0.3 : 0.14)
          Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        HoverHandler { id: barHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.sizeRequested(root.sizes[index]) }
      }
    }
  }

  IconButton {
    anchors.verticalCenter: parent.verticalCenter
    icon: "a-arrow-up"
    iconSize: Math.round(Typo.caption * 1.25)
    foreground: root.colors.textDim
    hoverForeground: root.colors.text
    available: root.step < root.sizes.length - 1
    onClicked: root.stepRequested(1)
  }
}
