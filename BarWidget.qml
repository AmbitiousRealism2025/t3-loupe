import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Omarchy
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
  // The panel's own tally, so the ring shows the same number as the Active tab.
  readonly property var tally: service ? Store.tally(service.rows) : ({ needs: 0, working: 0, active: 0 })

  // Widget settings (omarchy bar set ambitiousrealism.t3-loupe <key> <value>)
  readonly property string display: String(setting("display", "label"))  // label | ring | ring-count
  readonly property bool reduceMotion: setting("reduceMotion", false) === true
  readonly property int panelWidth: Number(setting("panelWidth", 540)) || 540

  // "centered" (floating two-pane window, default) or "dropdown" (compact panel under the bar).
  // Widget setting or settings.json "presentation"; `f` in the panel flips it for the session.
  property string presentationOverride: ""
  readonly property string presentation: presentationOverride
    || (service && service.settings && typeof service.settings.presentation === "string" ? service.settings.presentation : "")
    || String(setting("presentation", "centered"))
  readonly property bool centered: presentation === "centered"
  readonly property var content: centered
    ? (centeredLoader.item ? centeredLoader.item.panelContent : null)
    : (dropdownLoader.item ? dropdownLoader.item.panelContent : null)

  function toggleLayout() {
    presentationOverride = centered ? "dropdown" : "centered"
  }

  readonly property var screenObj: {
    var w = QsWindow.window
    return w ? w.screen : null
  }
  readonly property string screenName: screenObj ? String(screenObj.name) : ""

  property string pendingFocus: ""

  // Called by the service for notification clicks / IPC.
  function openAt(key) {
    pendingFocus = key
    if (!opened) open()
    else if (key && content) content.focusKey(key)
  }

  onOpenedChanged: {
    if (service) service.openPanels = Math.max(0, service.openPanels + (opened ? 1 : -1))
    if (opened && pendingFocus) {
      var key = pendingFocus
      pendingFocus = ""
      Qt.callLater(function() { if (root.content) root.content.focusKey(key) })
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
  // The ring shows activity, not a number: the one number in the bar is the needs-you badge, so a
  // glance never has to tell two counts apart. "ring-count" puts the active count beside the ring.
  readonly property string ringText: !service ? "" : !paired ? "+" : !known ? "—" : ""
  readonly property string countValue: !service || !paired || !known ? "" : String(tally.active)
  readonly property bool showRingCount: display !== "ring-count"
  // What the widget says, in words: its tooltip and its accessible name.
  readonly property string summary: !service ? "T3 Loupe: service not running"
    : !paired ? "T3 Loupe: no paired environments"
    : !known ? "T3 Loupe: not connected to T3"
    : (tally.needs ? tally.needs + (tally.needs === 1 ? " thread needs" : " threads need") + " you" : "Nothing needs you")
      + " · " + tally.working + " working · " + tally.done + " done"

  WidgetButton {
    id: button
    bar: root.bar
    anchors.fill: parent
    text: " "
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : glyphRow.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? glyphRow.implicitHeight + scaledVerticalPadding * 2 : -1
    active: root.tally.needs > 0
    tooltipText: root.summary
    Accessible.role: Accessible.Button
    Accessible.name: root.summary
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
        thickness: Math.max(3, Math.round(diameter / 5))
        // Ink like its bar neighbours; what needs you in the colour of its kind, as in the panel.
        // Every arc, and the track when shown, is a 3:1 mark against the bar.
        segments: root.service ? Store.ringSegments(root.service.rows) : []
        colors: root.theme ? ({
          attention: root.theme.bar.attention, ask: root.theme.bar.ask, warning: root.theme.bar.warning,
          ink: root.ink, rest: root.theme.bar.edge, track: root.theme.bar.edge
        }) : ({ ink: root.ink, rest: root.ink, track: root.ink })
        spinning: root.counts.busy > 0
        reduceMotion: root.reduceMotion
        offline: root.service !== null && root.paired && !root.known
        centerText: root.ringText
        textColor: root.ink
        fontFamily: button.fontFamily
        fontSize: Math.max(8, Math.round(diameter * 0.5))
      }

      Text {
        id: countText
        visible: !root.showRingCount && !root.vertical && root.countValue !== ""
        x: glyphRow.offset(countText)
        anchors.verticalCenter: parent.verticalCenter
        text: root.countValue
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
        visible: root.tally.needs > 0
        x: root.vertical ? (glyphRow.width - width) / 2 : glyphRow.offset(badge)
        y: root.vertical ? glyphRow.offset(badge) : (glyphRow.height - height) / 2
        height: Math.round(ring.diameter * 0.78)
        width: Math.max(height, badgeText.implicitWidth + Style.space(9))
        // Filled pill while anything needs you: the one number in the bar that asks for a look. It is
        // the bar's own ink, the numeral in the bar's background: the threads it counts are of
        // several kinds (an answer, a plan, a failure), each with its colour on the ring beside it,
        // and a badge in any one of those colours, failure red say, misnamed the rest. The panel's
        // header shows the same badge. Its corners follow the shell's, square in a square theme.
        radius: Math.min(height / 2, Math.max(Style.space(2), Style.cornerRadius))
        color: root.theme ? root.theme.bar.text : root.ink
        Text {
          id: badgeText
          anchors.centerIn: parent
          text: String(root.tally.needs)
          textFormat: Text.PlainText
          color: root.theme ? root.theme.bar.background : "black"
          font.family: button.fontFamily
          font.pixelSize: Math.max(8, Math.round(ring.diameter * 0.5))
          font.bold: true
          renderType: Text.NativeRendering
        }
      }
    }
  }

  Loader {
    id: dropdownLoader
    active: !root.centered
    sourceComponent: KeyboardPanel {
      id: panel
      readonly property alias panelContent: dropContent
      anchorItem: button
      owner: root
      bar: root.bar
      open: root.opened
      focusTarget: dropContent.keyCatcher
      contentWidth: panel.fittedContentWidth(Style.space(root.panelWidth + Math.max(0, Typo.bump) * 36))
      contentHeight: panel.fittedContentHeight(dropContent.implicitHeight, Style.space(820))

      // Opaque reading surface regardless of popup translucency.
      Rectangle {
        anchors.fill: parent
        anchors.margins: -panel.padding
        radius: Math.max(0, Style.cornerRadius - Border.top(panel.borderSpec))
        color: root.theme ? root.theme.popup.background : Omarchy.Color.popups.background
      }

      ThreadsPanel {
        id: dropContent
        anchors.fill: parent
        service: root.service
        opened: root.opened
        reduceMotion: root.reduceMotion
        onCloseRequested: root.close()
        onSwitchRequested: function(direction) { root.switchPanel(direction) }
        onLayoutToggleRequested: root.toggleLayout()
      }
    }
  }

  Loader {
    id: centeredLoader
    active: root.centered
    sourceComponent: CenteredWindow {
      id: floating
      readonly property alias panelContent: floatContent
      open: root.opened
      bar: root.bar
      owner: root
      screen: root.screenObj
      colors: root.theme ? root.theme.popup : ({})
      onDismissRequested: root.close()
      onOpenChanged: if (open) Qt.callLater(function() { floatContent.keyCatcher.forceActiveFocus() })

      ThreadsPanel {
        id: floatContent
        anchors.fill: parent
        service: root.service
        opened: root.opened
        centered: true
        reduceMotion: root.reduceMotion
        onCloseRequested: root.close()
        onSwitchRequested: function(direction) { root.switchPanel(direction) }
        onLayoutToggleRequested: root.toggleLayout()
      }
    }
  }
}
