import QtQuick
import QtQuick.Controls
import qs.Commons

// A scrollbar drawn in the palette's scroll tones: a thumb at 3:1 or better against its track and
// the panel, on a visible track, in every theme (the style's default thumb was about 1.4:1).
// Use it with policy AlwaysOn: it draws itself only while there is something to scroll, and the
// pane keeps a fixed right inset (`inset`) for it, so content never runs under it.
ScrollBar {
  id: root
  property var colors: ({})
  readonly property bool needed: size < 1
  // The room a pane leaves at its right edge for the bar and a gap.
  readonly property real inset: Style.space(14)

  implicitWidth: Style.space(6)
  padding: Style.space(1)

  contentItem: Rectangle {
    implicitWidth: Style.space(4)
    radius: width / 2
    color: root.colors.scrollThumb || "gray"
    opacity: root.needed ? 1 : 0
  }
  background: Rectangle {
    implicitWidth: Style.space(6)
    radius: width / 2
    color: root.colors.scrollTrack || "transparent"
    visible: root.needed
  }
}
