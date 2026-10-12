import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "components"
import "lib/Store.js" as Store
import "lib/Format.js" as Format

// Panel content: header, state distribution, machines, filters, thread list, providers.
Item {
  id: root

  property var service: null
  property bool reduceMotion: false
  property bool opened: false
  readonly property alias keyCatcher: keys

  signal closeRequested()
  signal switchRequested(int direction)

  readonly property var colors: service ? service.theme.popup : ({})
  readonly property var rows: service ? service.rows : []
  readonly property var environments: service ? service.environments : []
  readonly property double now: service ? service.now : Date.now()
  readonly property string fontFamily: Style.font.family
  readonly property string monoFamily: Style.font.resolvedFamily || Style.font.family

  property string filter: "attention"
  property bool filterChosen: false
  property var expanded: ({})
  property int cursor: -1
  property string query: ""

  readonly property var visible_: Store.visibleRows(rows, filter, query, expanded)
  readonly property var dist: Store.distribution(rows)
  readonly property int needCount: Store.filterCount(rows, "attention")
  readonly property int activeCount: Store.filterCount(rows, "active")
  readonly property int allCount: Store.filterCount(rows, "all")
  readonly property bool multiMachine: environments.length > 1
  readonly property bool hasMetered: {
    for (var i = 0; i < environments.length; i++)
      for (var j = 0; j < environments[i].providers.length; j++)
        if (environments[i].providers[j].windows.length) return true
    return false
  }

  // Fixed chrome height + list content: lets KeyboardPanel fit the card to content.
  implicitHeight: chrome.implicitHeight + Style.space(10) + Math.min(list.contentHeight, Style.space(900)) + Style.space(8) + footer.implicitHeight

  // Open on whatever needs you; otherwise on what's active.
  function pickDefaultFilter() {
    if (filterChosen) return
    filter = needCount > 0 ? "attention" : activeCount > 0 ? "active" : "all"
  }
  onOpenedChanged: if (opened) { filterChosen = false; pickDefaultFilter(); cursor = -1; list.positionViewAtBeginning() }
  onNeedCountChanged: if (opened && !filterChosen && filter === "attention" && needCount === 0) pickDefaultFilter()

  function setFilter(f) { filter = f; filterChosen = true; cursor = -1; list.positionViewAtBeginning() }

  function toggleExpand(row) {
    var next = {}
    for (var k in expanded) next[k] = expanded[k]
    if (next[row.key]) delete next[row.key]
    else {
      next[row.key] = true
      if (service) service.requestDetail(row.envId, row.id)
    }
    expanded = next
  }

  // Focus a thread (notification click): make it visible, expanded and under the cursor.
  function focusKey(key) {
    var row = service ? service.rowByKey(key) : null
    if (!row) return
    if (Store.visibleRows(rows, filter, query, expanded).indexOf(row) < 0) { filter = "all"; filterChosen = true }
    var next = {}
    for (var k in expanded) next[k] = expanded[k]
    next[row.parentId ? row.envId + ":" + row.parentId : key] = true
    next[key] = true
    expanded = next
    if (service) service.requestDetail(row.envId, row.id)
    Qt.callLater(function() {
      for (var i = 0; i < visible_.length; i++) if (visible_[i].key === key) { cursor = i; list.positionViewAtIndex(i, ListView.Contain) }
    })
    // Again once the drawer has laid out at full height.
    settleScroll.restart()
  }

  function moveCursor(dy) {
    if (!visible_.length) return
    cursor = cursor < 0 ? 0 : Math.max(0, Math.min(visible_.length - 1, cursor + dy))
    list.positionViewAtIndex(cursor, ListView.Contain)
  }

  function act(row, action) {
    if (action === "focus") {
      // T3's single-instance handler raises its window for any t3code:// URL.
      Util.execArgv(["xdg-open", "t3code://app"])
      root.closeRequested()
    } else if (action === "pr" && row.pr && row.pr.url) {
      Qt.openUrlExternally(row.pr.url)
    } else if (action === "copy") {
      Util.execArgv(["wl-copy", "--", row.title])
    }
  }

  Timer {
    id: settleScroll
    interval: 350
    onTriggered: if (root.cursor >= 0) list.positionViewAtIndex(root.cursor, ListView.Contain)
  }

  // Refresh pinned detail while a drawer stays open.
  Timer {
    interval: 45000
    repeat: true
    running: root.opened && Object.keys(root.expanded).length > 0
    onTriggered: {
      for (var k in root.expanded) {
        var row = root.service ? root.service.rowByKey(k) : null
        if (row) root.service.requestDetail(row.envId, row.id)
      }
    }
  }

  PanelKeyCatcher {
    id: keys
    anchors.fill: parent
    blocked: search.activeFocus
    onCloseRequested: root.query !== "" ? root.query = "" : root.closeRequested()
    onTabRequested: function(direction) { root.switchRequested(direction) }
    onMoveRequested: function(dx, dy) {
      if (dy) root.moveCursor(dy)
      else if (dx) {
        var order = Store.FILTERS
        root.setFilter(order[Math.max(0, Math.min(order.length - 1, order.indexOf(root.filter) + dx))])
      }
    }
    onActivateRequested: if (root.cursor >= 0 && root.cursor < root.visible_.length) root.toggleExpand(root.visible_[root.cursor])
    onTextKey: function(t) {
      if (t === "1") root.setFilter("attention")
      else if (t === "2") root.setFilter("active")
      else if (t === "3") root.setFilter("all")
      else if (t === "/") search.forceActiveFocus()
      else if (t === "r" && root.service) root.service.refresh()
      else if (t === "o" && root.cursor >= 0) root.act(root.visible_[root.cursor], "focus")
      else if (t === "g") {
        for (var i = 0; i < root.visible_.length; i++) if (Store.ATTENTION[root.visible_[i].state]) { root.cursor = i; list.positionViewAtIndex(i, ListView.Contain); break }
      }
    }

    Column {
      id: chrome
      width: parent.width
      spacing: Style.space(12)

      // Header
      Item {
        width: parent.width
        height: Math.max(headRing.height, headText.implicitHeight)

        ActivityRing {
          id: headRing
          anchors.verticalCenter: parent.verticalCenter
          diameter: Math.round(Style.font.display * 1.25)
          thickness: Math.max(3, Math.round(diameter / 8))
          segments: root.dist
          colors: root.colors
          spinning: root.service && root.service.counts.busy > 0
          alert: root.service && root.service.counts.attention > 0
          reduceMotion: root.reduceMotion
          offline: root.service && !root.service.known
          centerText: root.service && root.service.known ? String(root.service.counts.active) : "—"
          textColor: root.colors.text
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
        }

        Column {
          id: headText
          anchors.left: headRing.right
          anchors.leftMargin: Style.space(12)
          anchors.right: headActions.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            text: "T3 Loupe"
            textFormat: Text.PlainText
            color: root.colors.text
            font.family: root.fontFamily
            font.pixelSize: Math.round(Style.font.heading * 1.125)
            font.weight: Font.DemiBold
          }
          Text {
            width: parent.width
            text: {
              if (!root.service) return "Service not loaded"
              if (root.service.health === "down") return "Collector stopped — restarting"
              if (root.service.configError) return "Connection settings unreadable (" + root.service.configError + ")"
              if (!root.environments.length) return "No T3 environments paired"
              var c = root.service.counts
              var parts = []
              if (c.attention) parts.push(c.attention + " need" + (c.attention === 1 ? "s" : "") + " you")
              parts.push(c.busy + " working")
              if (c.review) parts.push(c.review + " done")
              parts.push(Format.plural(root.environments.length, "machine"))
              return parts.join("  ·  ")
            }
            textFormat: Text.PlainText
            color: root.colors.textDim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Row {
          id: headActions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          PanelActionButton {
            iconText: "󰑐"
            foreground: root.colors.textDim
            tooltipText: "Reconnect (r)"
            onClicked: if (root.service) root.service.refresh()
          }
          PanelActionButton {
            iconText: "×"
            foreground: root.colors.textDim
            tooltipText: "Close"
            onClicked: root.closeRequested()
          }
        }
      }

      // State distribution
      Column {
        width: parent.width
        spacing: Style.space(5)
        visible: root.service && root.service.known && root.activeCount > 0
        Row {
          id: segBar
          width: parent.width
          height: Style.space(5)
          spacing: Style.space(2)
          readonly property real total: {
            var t = 0
            for (var i = 0; i < root.dist.length; i++) t += root.dist[i].count
            return Math.max(1, t)
          }
          readonly property int present: root.dist.filter(function(d) { return d.count > 0 }).length
          Repeater {
            model: root.dist
            Rectangle {
              required property var modelData
              visible: modelData.count > 0
              height: segBar.height
              width: Math.max(Style.space(4), (segBar.width - segBar.spacing * Math.max(0, segBar.present - 1)) * modelData.count / segBar.total)
              radius: Math.min(Style.cornerRadius, height / 2)
              color: root.colors[modelData.role] || root.colors.track
              Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }
          }
        }
        Row {
          spacing: Style.space(12)
          Repeater {
            model: root.dist
            Row {
              required property var modelData
              visible: modelData.count > 0
              spacing: Style.space(5)
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(6); height: width
                radius: Math.min(Style.cornerRadius, width / 2)
                color: root.colors[modelData.role] || root.colors.track
              }
              Text {
                text: modelData.count + " " + modelData.label
                textFormat: Text.PlainText
                color: root.colors.textDim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      // Machines
      Flow {
        width: parent.width
        spacing: Style.space(6)
        visible: root.environments.length > 0
        Repeater {
          model: root.environments
          Rectangle {
            required property var modelData
            readonly property bool ok: Store.environmentOk(modelData.state)
            readonly property bool expiring: modelData.sessionExpiresAt && modelData.sessionExpiresAt - root.now < 3 * 86400000
            height: envRow.implicitHeight + Style.space(8)
            width: envRow.implicitWidth + Style.space(16)
            radius: Style.cornerRadius
            color: root.colors.surface
            border.width: 1
            border.color: ok ? root.colors.line : Qt.rgba(root.colors.attention.r, root.colors.attention.g, root.colors.attention.b, 0.5)
            Row {
              id: envRow
              anchors.centerIn: parent
              spacing: Style.space(6)
              Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(8); height: width
                Rectangle {
                  anchors.fill: parent
                  radius: width / 2
                  color: ok ? root.colors.success : "transparent"
                  border.width: ok ? 0 : 1.5
                  border.color: root.colors.attention
                }
                // Live pulse
                Rectangle {
                  visible: modelData.state === "live" && !root.reduceMotion
                  anchors.centerIn: parent
                  width: parent.width; height: width; radius: width / 2
                  color: "transparent"
                  border.width: 1
                  border.color: root.colors.success
                  SequentialAnimation on scale {
                    running: parent.visible && root.opened
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 2.2; duration: 1600; easing.type: Easing.OutCubic }
                    PauseAnimation { duration: 1400 }
                  }
                  SequentialAnimation on opacity {
                    running: parent.visible && root.opened
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.8; to: 0; duration: 1600; easing.type: Easing.OutCubic }
                    PauseAnimation { duration: 1400 }
                  }
                }
              }
              LucideIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: modelData.url && modelData.url.indexOf("127.0.0.1:3773") >= 0 ? "laptop" : "server"
                color: root.colors.textDim
                size: Math.round(Style.font.caption * 1.25)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                textFormat: Text.PlainText
                color: root.colors.text
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.weight: Font.Medium
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ok ? (expiring ? "pairing expires " + Format.until(modelData.sessionExpiresAt, root.now) : modelData.counts.active + " active")
                  : Store.environmentLabel(modelData.state) + (modelData.stale && modelData.lastLiveAt ? " · seen " + Format.ago(modelData.lastLiveAt, root.now) : "")
                textFormat: Text.PlainText
                color: ok && !expiring ? root.colors.textFaint : root.colors.attentionInk
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      // Filters + search
      Item {
        width: parent.width
        height: Math.max(filters.implicitHeight, search.implicitHeight)
        visible: root.environments.length > 0
        ButtonGroup {
          id: filters
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          options: [
            { value: "attention", label: "Inbox  " + root.needCount, tooltip: "1" },
            { value: "active", label: "Active  " + root.activeCount, tooltip: "2" },
            { value: "all", label: "All  " + root.allCount, tooltip: "3" }
          ]
          value: root.filter
          foreground: root.colors.text
          background: root.colors.background
          accent: root.colors.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          focusable: false
          onChanged: function(v) { root.setFilter(v) }
        }
        TextField {
          id: search
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: activeFocus || text !== "" ? Style.space(150) : Style.space(90)
          placeholderText: "/ filter"
          text: root.query
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          onTextChanged: { root.query = text; root.cursor = -1 }
          Keys.onEscapePressed: { text = ""; keys.forceActiveFocus() }
          Keys.onReturnPressed: keys.forceActiveFocus()
          Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
      }

      // Setup / empty states
      Column {
        visible: root.visible_.length === 0
        width: parent.width
        spacing: Style.space(6)
        topPadding: Style.space(10)
        bottomPadding: Style.space(10)
        LucideIcon {
          anchors.horizontalCenter: parent.horizontalCenter
          name: !root.environments.length ? "plug-zap" : root.filter === "attention" ? "circle-check" : "moon"
          color: root.colors.textFaint
          size: Math.round(Style.font.display * 1.1)
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: !root.environments.length ? "Pair a T3 environment to start"
            : root.query ? "No threads match “" + root.query + "”"
            : root.filter === "attention" ? "Inbox zero — nothing needs you" : root.filter === "active" ? "No active threads" : "No recent threads"
          textFormat: Text.PlainText
          color: root.colors.textDim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          visible: text !== ""
          text: !root.environments.length ? "Run:  t3-loupe pair-local   (see README for remote machines)"
            : root.filter === "attention" && root.activeCount > 0 ? root.activeCount + " active — press 2 to see them" : ""
          textFormat: Text.PlainText
          color: root.colors.textFaint
          font.family: root.monoFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    ListView {
      id: list
      anchors.top: chrome.bottom
      anchors.topMargin: Style.space(10)
      anchors.bottom: footer.top
      anchors.bottomMargin: Style.space(8)
      width: parent.width
      clip: true
      spacing: Style.space(6)
      boundsBehavior: Flickable.StopAtBounds
      model: root.visible_
      reuseItems: false
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      delegate: Column {
        id: cell
        required property var modelData
        required property int index
        width: list.width - (list.contentHeight > list.height ? Style.space(8) : 0)
        spacing: Style.space(4)
        // Grouped view: a heading whenever machine/project changes between roots.
        readonly property string group: root.filter === "all" && !modelData.parentId ? Store.groupKey(modelData, root.environments) : ""
        readonly property bool newGroup: {
          if (group === "") return false
          for (var i = index - 1; i >= 0; i--) {
            var prev = root.visible_[i]
            if (prev.parentId) continue
            return Store.groupKey(prev, root.environments) !== group
          }
          return true
        }
        Text {
          visible: cell.newGroup
          width: parent.width
          topPadding: cell.index > 0 ? Style.space(8) : 0
          text: cell.group
          textFormat: Text.PlainText
          color: root.colors.textFaint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.capitalization: Font.AllUppercase
          font.letterSpacing: 0.8
          elide: Text.ElideRight
        }
      ThreadCard {
        readonly property var modelData: cell.modelData
        readonly property int index: cell.index
        width: parent.width
        row: modelData
        colors: root.colors
        detail: root.service ? root.service.details[modelData.key] || null : null
        now: root.now
        selected: index === root.cursor
        expanded: root.expanded[modelData.key] === true
        reduceMotion: root.reduceMotion
        showMachine: root.multiMachine && root.filter !== "all"
        machineLabel: {
          var e = root.service ? root.service.environment(modelData.envId) : null
          return e ? e.label : ""
        }
        fontFamily: root.fontFamily
        monoFamily: root.monoFamily
        opacity: modelData.stale ? 0.55 : 1
        onClicked: { root.cursor = index; root.toggleExpand(modelData) }
        onActionRequested: function(action) { root.act(modelData, action) }
      }
      }

      add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic } }
      displaced: Transition { NumberAnimation { properties: "y"; duration: 160; easing.type: Easing.OutCubic } }
    }

    Column {
      id: footer
      anchors.bottom: parent.bottom
      width: parent.width
      spacing: Style.space(8)

      PanelSeparator { visible: root.hasMetered; foreground: root.colors.text; strength: 0.10 }

      ProviderStrip {
        visible: root.hasMetered
        width: parent.width
        environments: root.environments
        colors: root.colors
        now: root.now
        fontFamily: root.fontFamily
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignRight
        text: "j/k move  ·  ↵ expand  ·  1 2 3 filter  ·  / search  ·  o open T3  ·  esc"
        textFormat: Text.PlainText
        color: root.colors.textFaint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideLeft
      }
    }
  }
}
