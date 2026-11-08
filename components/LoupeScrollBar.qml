import QtQuick
import QtQuick.Controls
import qs.Commons

// A scrollbar drawn in the palette's scroll tones: a thumb at 3:1 or better against its track and
// the panel, on a visible track, in every theme (the style's default thumb was about 1.4:1).
ScrollBar {
  id: root
  property var colors: ({})

  implicitWidth: Style.space(6)
  padding: Style.space(1)

  contentItem: Rectangle {
    implicitWidth: Style.space(4)
    radius: width / 2
    color: root.colors.scrollThumb || "gray"
  }
  background: Rectangle {
    implicitWidth: Style.space(6)
    radius: width / 2
    color: root.colors.scrollTrack || "transparent"
    visible: root.size < 1
  }
}
