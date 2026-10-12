import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Experimental presentation: the panel as a centered floating card over a dimmed
// backdrop, sized for many threads. Click outside or press Esc to close.
PanelWindow {
  id: win

  property bool open: false
  property var bar: null
  property var owner: null
  property var colors: ({})
  property real cardWidth: Style.space(820)
  property real maxHeightRatio: 0.84
  default property alias contentData: slot.data
  readonly property alias card: card
  readonly property real padding: Style.spacing.popupPadding + Style.space(6)

  signal dismissRequested()

  readonly property bool shown: open
  visible: open || card.opacity > 0.01
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "t3-loupe"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  // Only one bar popup at a time: take the shared slot while open.
  onOpenChanged: {
    if (!bar || !owner) return
    if (open && typeof bar.requestPopout === "function") bar.requestPopout(owner)
    if (!open && typeof bar.releasePopout === "function") bar.releasePopout(owner)
  }

  // Backdrop
  Rectangle {
    anchors.fill: parent
    color: "#000000"
    opacity: win.open ? 0.38 : 0
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    MouseArea {
      anchors.fill: parent
      onClicked: win.dismissRequested()
    }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(win.cardWidth, win.width - Style.gapsOut * 4)
    height: Math.min(win.height * win.maxHeightRatio, slot.implicitContentHeight + win.padding * 2)
    radius: Style.cornerRadius
    color: win.colors.background || Color.popups.background
    border.width: Math.max(1, Style.space(2))
    border.color: Color.popups.border
    opacity: win.open ? 1 : 0
    scale: win.open ? 1 : 0.965
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    // Swallow clicks so they don't reach the backdrop.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    Item {
      id: slot
      anchors.fill: parent
      anchors.margins: win.padding
      readonly property real implicitContentHeight: children.length ? children[0].implicitHeight : 0
    }
  }
}
