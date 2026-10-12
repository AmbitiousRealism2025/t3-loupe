import QtQuick
import qs.Commons

// Square icon button with the shell's hover fill.
Rectangle {
  id: root
  property string icon: "circle-dot"
  property color foreground: Color.foreground
  property color hoverForeground: foreground
  property real iconSize: Math.round(Typo.body * 1.15)
  // false: dimmed and inert (e.g. "smaller" at the smallest size).
  property bool available: true
  signal clicked()

  implicitWidth: Math.max(Style.space(26), iconSize + Style.space(10))
  implicitHeight: implicitWidth
  radius: Style.cornerRadius
  opacity: available ? 1 : 0.35
  color: hover.hovered && available ? Style.hoverFillFor(foreground, foreground) : "transparent"
  Behavior on color { ColorAnimation { duration: 120 } }

  LucideIcon {
    anchors.centerIn: parent
    name: root.icon
    size: root.iconSize
    color: hover.hovered && root.available ? root.hoverForeground : root.foreground
  }
  HoverHandler { id: hover; cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor }
  TapHandler { onTapped: if (root.available) root.clicked() }
}
