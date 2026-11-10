import QtQuick
import qs.Commons

// Text-size control: A↓ · four rising bars (one per preset, click to jump) · A↑. It sits in the
// legend beside its keys ("+/− size"), so the keys and the control read as one thing.
// The smallest preset is the shell's own size.
// compact (the dropdown): the bars alone; the keys beside them step the size.
Row {
  id: root
  property var sizes: [0, 2, 4, 6]
  property int step: 0
  property var colors: ({})
  property bool compact: false
  // One legend line tall: the control never makes its row taller than the keys beside it.
  property real rowHeight: Math.round(Typo.caption * 1.6)
  signal stepRequested(int delta)
  signal sizeRequested(real size)

  spacing: Style.space(2)

  IconButton {
    visible: !root.compact
    anchors.verticalCenter: parent.verticalCenter
    icon: "a-arrow-down"
    iconSize: Math.round(Typo.caption * 1.25)
    implicitHeight: root.rowHeight
    foreground: root.colors.textDim
    hoverForeground: root.colors.text
    available: root.step > 0
    onClicked: root.stepRequested(-1)
  }

  Row {
    id: bars
    anchors.verticalCenter: parent.verticalCenter
    // Each bar's own target is the full height of the row and wider than the bar.
    Repeater {
      model: root.sizes.length
      Item {
        required property int index
        readonly property bool on: index <= root.step
        width: Style.space(9)
        height: root.rowHeight
        Rectangle {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Math.round((parent.height - Style.space(14)) / 2)
          anchors.horizontalCenter: parent.horizontalCenter
          width: Style.space(5)
          height: Style.space(5 + index * 3)
          radius: Style.cornerRadius > 0 ? 1 : 0
          // Graduated steps, all solid: sizes up to the current one in ink, larger ones in the 3:1 edge
          // tone (an outline at this size reads as a missing-glyph box).
          color: parent.on || barHover.hovered ? root.colors.text : root.colors.edge
        }
        HoverHandler { id: barHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.sizeRequested(root.sizes[index]) }
      }
    }
  }

  IconButton {
    visible: !root.compact
    anchors.verticalCenter: parent.verticalCenter
    icon: "a-arrow-up"
    iconSize: Math.round(Typo.caption * 1.25)
    implicitHeight: root.rowHeight
    foreground: root.colors.textDim
    hoverForeground: root.colors.text
    available: root.step < root.sizes.length - 1
    onClicked: root.stepRequested(1)
  }
}
