import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "components"
import "lib/Store.js" as Store

// Bar entry: activity ring (+ count) that opens the threads panel.
// Works in any bar section and in the custom Notch Strip.
Panel {
  id: root
  moduleName: "ambitiousrealism.t3-loupe"
  manageIpc: false

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor(moduleName) : null
  readonly property var theme: service ? service.theme : null
  readonly property var counts: service ? service.counts : ({ active: 0, busy: 0, attention: 0, input: 0, review: 0 })
  readonly property bool known: service ? service.known : false
  readonly property bool paired: service ? service.environments.length > 0 : false

  // Widget settings (omarchy bar set ambitiousrealism.t3-loupe <key> <value>)
  readonly property string display: String(setting("display", "label"))  // label | ring | ring-count
  readonly property bool reduceMotion: setting("reduceMotion", false) === true
  readonly property int panelWidth: Number(setting("panelWidth", 540)) || 540

  readonly property string screenName: {
    var w = QsWindow.window
    return w && w.screen ? String(w.screen.name) : ""
  }

  property string pendingFocus: ""

  // Called by the service for notification clicks / IPC.
  function openAt(key) {
    pendingFocus = key
    if (!opened) open()
    else if (key) content.focusKey(key)
  }

  onOpenedChanged: {
    if (service) service.openPanels = Math.max(0, service.openPanels + (opened ? 1 : -1))
    if (opened && pendingFocus) {
      var key = pendingFocus
      pendingFocus = ""
      Qt.callLater(function() { content.focusKey(key) })
    }
  }
  onServiceChanged: if (service) service.registerWidget(root)
  Component.onDestruction: {
    if (service) {
      service.unregisterWidget(root)
      if (opened) service.openPanels = Math.max(0, service.openPanels - 1)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color ink: button.foreground
  readonly property string centerText: !service ? "" : !paired ? "+" : !known ? "—" : String(counts.active)
  readonly property bool showRingCount: display !== "ring-count"

  WidgetButton {
    id: button
    bar: root.bar
    anchors.fill: parent
    text: " "
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : glyphRow.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? glyphRow.implicitHeight + scaledVerticalPadding * 2 : -1
    active: root.counts.attention > 0
    tooltipText: !root.service ? "T3 Loupe: service not running"
      : !root.paired ? "T3 Loupe: no paired environments"
      : root.counts.active + " active · " + root.counts.busy + " working · " + root.counts.attention + " need you"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton && root.service) root.service.refresh()
      else root.toggle()
    }

    // Manual layout: [T3 label] ring [count] [attention badge], in a row or a column.
    Item {
      id: glyphRow
      anchors.centerIn: parent
      readonly property real gap: Style.space(5)
      readonly property var parts: [label, ring, countText, badge].filter(function(p) { return p.visible })
      implicitWidth: {
        if (root.vertical) return Math.max.apply(null, parts.map(function(p) { return p.width }))
        var w = 0
        for (var i = 0; i < parts.length; i++) w += parts[i].width + (i ? gap : 0)
        return w
      }
      implicitHeight: {
        if (!root.vertical) return Math.max.apply(null, parts.map(function(p) { return p.height }))
        var h = 0
        for (var i = 0; i < parts.length; i++) h += parts[i].height + (i ? gap : 0)
        return h
      }
      width: implicitWidth
      height: implicitHeight

      function offset(item) {
        var pos = 0
        for (var i = 0; i < parts.length; i++) {
          if (parts[i] === item) return pos
          pos += (root.vertical ? parts[i].height : parts[i].width) + gap
        }
        return 0
      }

      // Name to the left of the ring; part of the same button, so it opens the panel too.
      Text {
        id: label
        visible: root.display === "label" && !root.vertical
        x: glyphRow.offset(label)
        anchors.verticalCenter: parent.verticalCenter
        text: "T3 Loupe"
        textFormat: Text.PlainText
        color: root.ink
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }

      ActivityRing {
        id: ring
        x: root.vertical ? (glyphRow.width - width) / 2 : glyphRow.offset(ring)
        y: root.vertical ? glyphRow.offset(ring) : (glyphRow.height - height) / 2
        readonly property real barSize: Number(root.barSize) || Style.bar.sizeHorizontal
        diameter: Math.max(12, Math.min(barSize - Style.space(8), Style.space(19)))
        thickness: Math.max(2, Math.round(diameter / 7.5))
        segments: root.service ? Store.distribution(root.service.rows) : []
        colors: root.theme ? root.theme.bar : ({})
        spinning: root.counts.busy > 0
        alert: root.counts.attention > 0
        reduceMotion: root.reduceMotion
        offline: root.service !== null && root.paired && !root.known
        centerText: root.showRingCount ? root.centerText : ""
        textColor: root.ink
        fontFamily: button.fontFamily
        fontSize: Math.max(8, Math.round(diameter * 0.5))
      }

      Text {
        id: countText
        visible: !root.showRingCount && !root.vertical
        x: glyphRow.offset(countText)
        anchors.verticalCenter: parent.verticalCenter
        text: root.centerText
        textFormat: Text.PlainText
        color: root.ink
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.bold: true
        renderType: Text.NativeRendering
      }

      // Attention badge: how many threads are waiting on you.
      Rectangle {
        id: badge
        visible: root.counts.attention > 0
        x: root.vertical ? (glyphRow.width - width) / 2 : glyphRow.offset(badge)
        y: root.vertical ? glyphRow.offset(badge) : (glyphRow.height - height) / 2
        height: Math.round(ring.diameter * 0.78)
        width: Math.max(height, badgeText.implicitWidth + Style.space(8))
        radius: Math.min(Style.cornerRadius, height / 2)
        color: root.theme ? root.theme.bar.attention : Color.urgent
        Text {
          id: badgeText
          anchors.centerIn: parent
          text: String(root.counts.attention)
          textFormat: Text.PlainText
          color: root.theme && root.theme.bar.light ? "#ffffff" : (root.theme ? root.theme.bar.background : Color.bar.background)
          font.family: button.fontFamily
          font.pixelSize: Math.max(8, Math.round(ring.diameter * 0.5))
          font.bold: true
          renderType: Text.NativeRendering
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: content.keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.panelWidth))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(820))

    // Opaque reading surface regardless of popup translucency.
    Rectangle {
      anchors.fill: parent
      anchors.margins: -panel.padding
      radius: Math.max(0, Style.cornerRadius - Border.top(panel.borderSpec))
      color: root.theme ? root.theme.popup.background : Color.popups.background
    }

    ThreadsPanel {
      id: content
      anchors.fill: parent
      service: root.service
      opened: root.opened
      reduceMotion: root.reduceMotion
      onCloseRequested: root.close()
      onSwitchRequested: function(direction) { root.switchPanel(direction) }
    }
  }
}
