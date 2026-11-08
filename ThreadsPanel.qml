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
  signal layoutToggleRequested()

  // Floating, centered presentation: more room for the list.
  property bool centered: false

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
  onQueryChanged: cursor = -1

  // Idle folds start collapsed and keep their state while the shell runs.
  property var idleOpen: ({})
  readonly property var visible_: Store.visibleRows(rows, filter, query, expanded, idleOpen)
  // Ring: only "needs you" is coloured; working is ink, the rest faint ink.
  readonly property var ringSegs: Store.ringSegments(rows)
  // "Needs you" in one colour where only one fits: the most severe kind present.
  readonly property string needsRole: Store.needsRole(rows)
  readonly property var ringColors: ({
    needs: colors[needsRole], ink: colors.text, track: colors.track,
    inkFaint: colors.text ? Qt.rgba(colors.text.r, colors.text.g, colors.text.b, 0.3) : "transparent"
  })
  // One tally feeds the header, the tabs and the ring, so they always agree.
  readonly property var tally: Store.tally(rows)
  readonly property int needCount: tally.needs
  readonly property int activeCount: tally.active
  readonly property int doneCount: tally.done
  readonly property int allCount: tally.all
  readonly property var link: Store.connection(environments)
  // Nothing reachable and nothing to show: the disconnected state replaces the list and detail.
  readonly property bool disconnected: link.none && rows.length === 0
  readonly property bool multiMachine: environments.length > 1
  readonly property bool hasMetered: {
    for (var i = 0; i < environments.length; i++)
      for (var j = 0; j < environments[i].providers.length; j++)
        if (environments[i].providers[j].windows.length) return true
    return false
  }

  // Fixed chrome height + list content: lets KeyboardPanel fit the card to content.
  // Two-pane takes the full card height so the panes don't jump as the selection changes.
  implicitHeight: centered ? Style.space(2400)
    : chrome.implicitHeight + Style.space(10) + Math.min(list.contentHeight, Style.space(900)) + Style.space(8) + footer.implicitHeight

  // Two-pane selection: the thread shown on the right. Always the item under the cursor.
  property string selectedKey: ""
  readonly property var selectedRow: service && selectedKey ? service.rowByKey(selectedKey) : null
  // The cursor sits on an item, not a position: when the list reorders it follows that item.
  property string cursorKey: ""
  onCursorChanged: syncSelection(true)
  onVisible_Changed: {
    if (cursor < 0) return
    var i = -1
    for (var k = 0; k < visible_.length; k++) if (visible_[k].key === cursorKey) { i = k; break }
    // The item left this view: stay at the same height, on the nearest stop.
    if (i < 0) i = nearestStop(cursor)
    if (i !== cursor) cursor = i
    else syncSelection(false)
  }
  // moved: the cursor itself moved, so refresh the detail even for the same thread.
  function syncSelection(moved) {
    if (cursor < 0 || cursor >= visible_.length) { cursorKey = ""; return }
    var item = visible_[cursor]
    cursorKey = item.key
    if (!centered || item.kind === "idle-line" || item.kind === "section" || (!moved && selectedKey === item.key)) return
    selectedKey = item.key
    detailDebounce.restart()
  }
  function nearestStop(i) {
    i = Math.min(i, visible_.length - 1)
    for (var d = 0; d < visible_.length; d++) {
      if (i + d < visible_.length && Store.isStop(visible_[i + d])) return i + d
      if (i - d >= 0 && Store.isStop(visible_[i - d])) return i - d
    }
    return -1
  }
  function selectFirst() {
    for (var i = 0; i < visible_.length; i++) if (!visible_[i].kind) { cursor = i; return }
  }
  Timer {
    id: detailDebounce
    interval: 150
    onTriggered: if (root.selectedRow && root.service) root.service.requestDetail(root.selectedRow.envId, root.selectedRow.id)
  }

  // Open on whatever needs you; otherwise on what's active.
  function pickDefaultFilter() {
    if (filterChosen) return
    filter = needCount > 0 ? "attention" : activeCount > 0 ? "active" : "all"
  }
  onOpenedChanged: if (opened) {
    filterChosen = false; pickDefaultFilter(); cursor = -1; list.positionViewAtBeginning()
    Qt.callLater(selectFirst)
  }
  onNeedCountChanged: if (opened && !filterChosen && filter === "attention" && needCount === 0) pickDefaultFilter()

  function setFilter(f) {
    filter = f; filterChosen = true; cursor = -1; list.positionViewAtBeginning()
    Qt.callLater(selectFirst)
  }

  function toggleIdle(key) {
    var next = {}
    for (var k in idleOpen) next[k] = idleOpen[k]
    next[key] = !next[key]
    idleOpen = next
  }

  // Enter / click on whatever is under the cursor.
  function activate(item) {
    if (!item) return
    if (item.kind === "idle-line") toggleIdle(item.key)
    else toggleExpand(item)
  }

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
    // Unfold the idle line it may sit behind, in this view and in All.
    var folds = {}
    for (var f in idleOpen) folds[f] = idleOpen[f]
    var root_ = row.parentId ? (service.rowByKey(row.envId + ":" + row.parentId) || row) : row
    folds[Store.idleLineKey(root_, "active")] = true
    folds[Store.idleLineKey(root_, "all")] = true
    idleOpen = folds
    if (Store.visibleRows(rows, filter, query, expanded, idleOpen).indexOf(row) < 0) { filter = "all"; filterChosen = true }
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

  // Section headings are not cursor stops.
  function moveCursor(dy) {
    if (!visible_.length) return
    var step = dy < 0 ? -1 : 1
    var i = cursor < 0 ? (step > 0 ? -1 : visible_.length) : cursor
    for (var n = 0; n < Math.abs(dy); n++) {
      var j = i + step
      while (j >= 0 && j < visible_.length && !Store.isStop(visible_[j])) j += step
      if (j < 0 || j >= visible_.length) break
      i = j
    }
    if (i < 0 || i >= visible_.length) return
    cursor = i
    list.positionViewAtIndex(cursor, ListView.Contain)
  }

  // The key legend: only keys that work here, the same verbs in both layouts, cut by priority to
  // fit one line (Store.legend / Store.fitLegend).
  readonly property string legendMode: disconnected ? "offline" : visible_.length === 0 ? "empty" : "list"
  readonly property var legendHints: Store.legend(legendMode, !!(selectedRow && selectedRow.pr && selectedRow.pr.url))
  readonly property string legendSep: "&nbsp;&nbsp;·&nbsp;&nbsp;"
  function legendPlain(hints) { return hints.map(function(h) { return h.key + " " + h.verb }).join("  ·  ") }
  function legendStyled(hints) {
    return hints.map(function(h) {
      return "<font color=\"" + colors.text + "\">" + h.key + "</font>&nbsp;" + h.verb.replace(/ /g, "&nbsp;")
    }).join(legendSep)
  }

  // One machine: ink dot (hollow attention ring when unreachable), name, and any issue.
  component MachineTag: Row {
    required property var modelData
    readonly property bool ok: Store.environmentOk(modelData.state)
    readonly property bool expiring: !!modelData.sessionExpiresAt && modelData.sessionExpiresAt - root.now < 3 * 86400000
    spacing: Style.space(6)
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(7); height: width; radius: width / 2
      color: parent.ok ? root.colors.text : "transparent"
      opacity: parent.ok ? 0.75 : 1
      border.width: parent.ok ? 0 : 1.5
      border.color: root.colors.attention
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: modelData.label
      textFormat: Text.PlainText
      color: root.colors.textDim
      font.family: root.fontFamily
      font.pixelSize: Typo.caption
    }
    Text {
      visible: !parent.ok || parent.expiring
      anchors.verticalCenter: parent.verticalCenter
      text: !parent.ok ? Store.environmentLabel(modelData.state).toLowerCase() + (modelData.stale && modelData.lastLiveAt ? " · " + Format.ago(modelData.lastLiveAt, root.now) : "")
        : "re-pair " + Format.until(modelData.sessionExpiresAt, root.now)
      textFormat: Text.PlainText
      // Broken is red; still working but expiring soon is amber.
      color: parent.ok ? root.colors.warningInk : root.colors.attentionInk
      font.family: root.fontFamily
      font.pixelSize: Typo.caption
    }
  }

  function act(row, action) {
    if (action === "focus") {
      // Focus the T3 window through Hyprland (by window class). The t3code:// URL handler is
      // unreliable here: xdg-open can fall back to the browser, and the registered handler
      // can point at a stale AppImage after an update.
      if (service) Util.execArgv([service.pluginDir + "/bin/focus-t3"])
      root.closeRequested()
    } else if (action === "pr" && row.pr && row.pr.url) {
      Qt.openUrlExternally(row.pr.url)
    } else if (action === "copy") {
      // Piped to wl-copy's stdin by the collector: the title never appears in a process's argv.
      if (service) service.send({ cmd: "copy", text: row.title })
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
    running: root.opened && (Object.keys(root.expanded).length > 0 || root.selectedRow !== null)
    onTriggered: {
      for (var k in root.expanded) {
        var row = root.service ? root.service.rowByKey(k) : null
        if (row) root.service.requestDetail(row.envId, row.id)
      }
      if (root.centered && root.selectedRow) root.service.requestDetail(root.selectedRow.envId, root.selectedRow.id)
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
    onActivateRequested: if (root.cursor >= 0 && root.cursor < root.visible_.length) root.activate(root.visible_[root.cursor])
    onTextKey: function(t) {
      if (t === "1") root.setFilter("attention")
      else if (t === "2") root.setFilter("active")
      else if (t === "3") root.setFilter("done")
      else if (t === "4") root.setFilter("all")
      else if (t === "/") search.forceActiveFocus()
      else if (t === "f") root.layoutToggleRequested()
      else if ((t === "+" || t === "=") && root.service) root.service.stepTextSize(1)
      else if ((t === "-" || t === "_") && root.service) root.service.stepTextSize(-1)
      else if (t === "r" && root.service) root.service.refresh()
      else if (t === "o") root.act(root.cursor >= 0 ? root.visible_[root.cursor] : null, "focus")
      else if (t === "p" || t === "c") {
        var target = root.centered ? root.selectedRow : (root.cursor >= 0 && !root.visible_[root.cursor].kind ? root.visible_[root.cursor] : null)
        if (target) root.act(target, t === "p" ? "pr" : "copy")
      }
      else if (t === "g") {
        for (var i = 0; i < root.visible_.length; i++) if (!root.visible_[i].kind && Store.ATTENTION[root.visible_[i].state]) { root.cursor = i; list.positionViewAtIndex(i, ListView.Contain); break }
      }
    }

    Column {
      id: chrome
      width: parent.width
      spacing: Style.space(12)

      // Header (PanelHero-style): ring as the hero mark, title, one meta line; machines and actions right.
      Item {
        width: parent.width
        height: Math.max(headRing.height, headText.implicitHeight)

        ActivityRing {
          id: headRing
          anchors.verticalCenter: parent.verticalCenter
          diameter: Math.round(Typo.display * 1.3)
          thickness: Math.max(3, Math.round(diameter / 9))
          segments: root.ringSegs
          colors: root.ringColors
          spinning: root.service && root.service.counts.busy > 0
          alert: root.needCount > 0
          reduceMotion: root.reduceMotion
          offline: root.service && !root.service.known
          centerText: root.service && root.service.known ? String(root.activeCount) : "—"
          textColor: root.colors.text
          fontFamily: root.fontFamily
          fontSize: Typo.bodySmall
        }

        Column {
          id: headText
          anchors.left: headRing.right
          anchors.leftMargin: Style.space(14)
          anchors.right: headRight.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)
          Text {
            text: "T3 Loupe"
            textFormat: Text.PlainText
            color: root.colors.text
            font.family: root.fontFamily
            font.pixelSize: Typo.heading
            font.bold: true
          }
          // The same three numbers as the Inbox, Active and Done tabs; "need you" in its colour.
          Text {
            width: parent.width
            text: {
              function tint(color, words) { return "<font color=\"" + color + "\">" + words + "</font>" }
              var alarm = root.colors.attentionInk
              if (!root.service) return "SERVICE NOT LOADED"
              if (root.service.health === "down") return tint(alarm, "COLLECTOR STOPPED · RESTARTING")
              if (root.service.configError) return tint(alarm, "SETTINGS UNREADABLE · " + root.service.configError.toUpperCase())
              if (!root.environments.length) return "NO T3 MACHINES PAIRED"
              var sep = "&nbsp;&nbsp;·&nbsp;&nbsp;"
              var machines = root.link.connected === root.link.total ? Format.plural(root.link.total, "MACHINE", "MACHINES")
                : tint(alarm, root.link.connected + " OF " + root.link.total + " MACHINES CONNECTED")
              if (root.disconnected) return tint(alarm, "NOT CONNECTED") + sep + Format.plural(root.link.total, "MACHINE", "MACHINES")
              var parts = []
              parts.push(root.needCount ? tint(root.colors[root.needsRole + "Ink"], root.needCount + " NEED" + (root.needCount === 1 ? "S" : "") + " YOU") : "NOTHING NEEDS YOU")
              parts.push(root.tally.working + " WORKING")
              parts.push(root.doneCount + " DONE")
              parts.push(machines)
              return parts.join(sep)
            }
            textFormat: Text.StyledText
            color: root.colors.textDim
            font.family: root.fontFamily
            font.pixelSize: Typo.caption
            font.bold: true
            font.letterSpacing: 1.2
            elide: Text.ElideRight
          }
        }

        Row {
          id: headRight
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(16)
          Repeater {
            model: root.centered ? root.environments : []
            MachineTag { anchors.verticalCenter: parent.verticalCenter }
          }
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            IconButton { icon: "refresh-cw"; foreground: root.colors.textDim; hoverForeground: root.colors.text; onClicked: if (root.service) root.service.refresh() }
            IconButton { icon: "x"; foreground: root.colors.textDim; hoverForeground: root.colors.text; onClicked: root.closeRequested() }
          }
        }
      }

      // Dropdown: machines on one quiet line under the header.
      Flow {
        visible: !root.centered && root.environments.length > 0
        width: parent.width
        spacing: Style.space(16)
        Repeater {
          model: root.centered ? [] : root.environments
          MachineTag {}
        }
      }

      // Filters + search
      Item {
        width: parent.width
        height: Math.max(filters.implicitHeight, search.implicitHeight) + Style.space(4)
        visible: root.environments.length > 0 && !root.disconnected
        ButtonGroup {
          id: filters
          anchors.left: parent.left
          anchors.top: parent.top
          options: [
            { value: "attention", label: "Inbox  " + root.needCount, tooltip: "1" },
            { value: "active", label: "Active  " + root.activeCount, tooltip: "2" },
            { value: "done", label: "Done  " + root.doneCount, tooltip: "3" },
            { value: "all", label: "All  " + root.allCount, tooltip: "4" }
          ]
          value: root.filter
          foreground: root.colors.text
          background: root.colors.background
          accent: root.colors.accent
          fontFamily: root.fontFamily
          fontSize: Typo.caption
          focusable: false
          onChanged: function(v) { root.setFilter(v) }
        }
        // Over each tab: a border in the 3:1 edge tone (the shell's own is lighter) and its number key.
        Repeater {
          model: 4
          Item {
            required property int index
            readonly property Item tab: {
              var n = -1
              for (var i = 0; i < filters.children.length; i++) {
                if (filters.children[i].selected === undefined) continue
                if (++n === index) return filters.children[i]
              }
              return null
            }
            visible: tab !== null
            x: filters.x + (tab ? tab.x : 0)
            y: filters.y + (tab ? tab.y : 0)
            width: tab ? tab.width : 0
            height: tab ? tab.height : 0
            Rectangle {
              anchors.fill: parent
              color: "transparent"
              radius: Style.cornerRadius
              border.width: 1
              border.color: parent.tab && parent.tab.selected === true ? root.colors.focus : root.colors.edge
            }
            Text {
              x: Style.space(3)
              y: Style.space(1)
              text: String(parent.index + 1)
              textFormat: Text.PlainText
              color: root.colors.textFaint
              font.family: root.monoFamily
              font.pixelSize: Math.max(7, Math.round(Typo.caption * 0.8))
            }
          }
        }
        // The current view, marked under its tab in the accent: the shell's selected fill alone is faint.
        Rectangle {
          readonly property Item tab: {
            for (var i = 0; i < filters.children.length; i++) if (filters.children[i].selected === true) return filters.children[i]
            return null
          }
          visible: tab !== null
          x: filters.x + (tab ? tab.x : 0)
          y: filters.y + filters.height + Style.space(1)
          width: tab ? tab.width : 0
          height: Style.space(3)
          color: root.colors.focus
        }
        FilterField {
          id: search
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: activeFocus || text !== "" ? Style.space(150) : Style.space(90)
          text: root.query
          foreground: root.colors.text
          dim: root.colors.textDim
          border: root.colors.textFaint
          accent: root.colors.accent
          fontFamily: root.fontFamily
          fontSize: Typo.caption
          radius: Style.cornerRadius
          padding: Style.space(8)
          onEdited: function(t) { root.query = t }
          onFinished: keys.forceActiveFocus()
          onClicked: forceActiveFocus()
          Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
      }

      // No machine reachable: what is wrong with each, and the step that fixes it.
      DisconnectedState {
        visible: root.disconnected
        width: Math.min(parent.width, Style.space(640))
        anchors.horizontalCenter: parent.horizontalCenter
        topPadding: Style.space(24)
        environments: root.environments
        colors: root.colors
        now: root.now
        fontFamily: root.fontFamily
        monoFamily: root.monoFamily
      }

      // Setup / empty states
      Column {
        visible: root.visible_.length === 0 && !root.disconnected
        width: parent.width
        spacing: Style.space(6)
        topPadding: Style.space(10)
        bottomPadding: Style.space(10)
        LucideIcon {
          anchors.horizontalCenter: parent.horizontalCenter
          name: !root.environments.length ? "plug-zap" : root.filter === "attention" || root.filter === "done" ? "circle-check" : "moon"
          color: root.colors.textFaint
          size: Math.round(Typo.display * 1.1)
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: !root.environments.length ? "Pair a T3 environment to start"
            : root.query ? "No threads match “" + root.query + "”"
            : root.filter === "attention" ? "Nothing needs you right now" : root.filter === "active" ? "Nothing in progress"
            : root.filter === "done" ? "Nothing finished recently" : "No recent threads"
          textFormat: Text.PlainText
          color: root.colors.textDim
          font.family: root.fontFamily
          font.pixelSize: Typo.body
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          visible: text !== ""
          text: !root.environments.length ? "Run:  t3-loupe pair-local   (see README for remote machines)"
            : root.filter === "attention" && root.tally.working > 0 ? Format.plural(root.tally.working, "thread") + " working — press 2 to see them" : ""
          textFormat: Text.PlainText
          color: root.colors.textFaint
          font.family: root.monoFamily
          font.pixelSize: Typo.caption
        }
      }
    }

    ListView {
      id: list
      visible: !root.disconnected
      anchors.top: chrome.bottom
      anchors.topMargin: Style.space(10)
      anchors.bottom: footer.top
      anchors.bottomMargin: Style.space(8)
      width: root.centered ? Math.round(parent.width * 0.44) : parent.width
      clip: true
      spacing: Style.space(root.centered ? 3 : 5)
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
        readonly property string group: root.filter === "all" && !modelData.parentId && !modelData.kind ? Store.groupKey(modelData, root.environments)
          : root.filter === "all" && modelData.kind === "idle-line" ? Store.groupKey(modelData, root.environments) : ""
        readonly property bool newGroup: {
          if (group === "") return false
          for (var i = index - 1; i >= 0; i--) {
            var prev = root.visible_[i]
            if (prev.parentId || prev.kind === "section") continue
            return Store.groupKey(prev, root.environments) !== group
          }
          return true
        }
        readonly property bool isLine: modelData.kind === "idle-line"
        readonly property bool isSection: modelData.kind === "section"
        // Status section (Inbox/Active) or machine/project group (All): shell section-header style.
        Item {
          visible: cell.newGroup || cell.isSection
          width: parent.width
          height: caption.implicitHeight + (cell.index > 0 ? Style.space(10) : Style.space(2))
          SectionCaption {
            id: caption
            x: Style.space(4)
            anchors.bottom: parent.bottom
            label: cell.isSection ? cell.modelData.label : cell.group
            count: cell.isSection ? cell.modelData.count : -1
            foreground: cell.isSection && cell.modelData.key === "sec:needs" ? root.colors[root.needsRole + "Ink"] : root.colors.text
            countColor: root.colors.textFaint
            fontFamily: root.fontFamily
          }
        }
        Loader {
          visible: !cell.isSection
          active: !cell.isSection
          width: parent.width
          sourceComponent: cell.isLine ? lineComponent : root.centered ? rowComponent : cardComponent
        }
        Component {
          id: lineComponent
          IdleLine {
            count: cell.modelData.count
            open: cell.modelData.open
            selected: cell.index === root.cursor
            colors: root.colors
            fontFamily: root.fontFamily
            onClicked: { root.cursor = cell.index; root.toggleIdle(cell.modelData.key) }
          }
        }
        Component {
          id: rowComponent
          CompactRow {
            row: cell.modelData
            colors: root.colors
            now: root.now
            selected: cell.index === root.cursor
            reduceMotion: root.reduceMotion
            showMachine: root.multiMachine && root.filter !== "all"
            machineLabel: {
              var e = root.service ? root.service.environment(cell.modelData.envId) : null
              return e ? e.label : ""
            }
            fontFamily: root.fontFamily
            monoFamily: root.monoFamily
            opacity: cell.modelData.stale ? 0.55 : 1
            onClicked: root.cursor = cell.index
          }
        }
        Component {
          id: cardComponent
          ThreadCard {
            row: cell.modelData
            colors: root.colors
            detail: root.service ? root.service.details[cell.modelData.key] || null : null
            now: root.now
            selected: cell.index === root.cursor
            expanded: root.expanded[cell.modelData.key] === true
            reduceMotion: root.reduceMotion
            showMachine: root.multiMachine && root.filter !== "all"
            machineLabel: {
              var e = root.service ? root.service.environment(cell.modelData.envId) : null
              return e ? e.label : ""
            }
            fontFamily: root.fontFamily
            monoFamily: root.monoFamily
            opacity: cell.modelData.stale ? 0.55 : 1
            onClicked: { root.cursor = cell.index; root.toggleExpand(cell.modelData) }
            onActionRequested: function(action) { root.act(cell.modelData, action) }
          }
        }
      }

      add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic } }
      displaced: Transition { NumberAnimation { properties: "y"; duration: 160; easing.type: Easing.OutCubic } }
    }

    // Two-pane: divider and the selected thread's detail.
    Rectangle {
      visible: root.centered && !root.disconnected
      anchors.top: list.top
      anchors.bottom: list.bottom
      x: list.width + Style.space(8)
      width: 1
      color: root.colors.line
    }
    Loader {
      active: root.centered
      visible: active && !root.disconnected
      anchors.top: list.top
      anchors.bottom: list.bottom
      anchors.left: list.right
      anchors.leftMargin: Style.space(18)
      anchors.right: parent.right
      sourceComponent: ThreadDetailPane {
        row: root.selectedRow
        detail: root.selectedRow && root.service ? root.service.details[root.selectedRow.key] || null : null
        colors: root.colors
        now: root.now
        reduceMotion: root.reduceMotion
        machineLabel: {
          var e = root.selectedRow && root.service ? root.service.environment(root.selectedRow.envId) : null
          return e && root.multiMachine ? e.label : ""
        }
        fontFamily: root.fontFamily
        monoFamily: root.monoFamily
        onActionRequested: function(action) { if (root.selectedRow) root.act(root.selectedRow, action) }
      }
    }

    Column {
      id: footer
      anchors.bottom: parent.bottom
      width: parent.width
      spacing: Style.space(8)

      Rectangle { width: parent.width; height: 1; color: root.colors.line }

      // Two-pane: usage on one line, key hints right-aligned beneath.
      ProviderStrip {
        visible: root.centered && root.hasMetered
        width: parent.width
        environments: root.environments
        colors: root.colors
        now: root.now
        fontFamily: root.fontFamily
      }

      // Dropdown: usage, then hints that wrap between hints.
      ProviderStrip {
        visible: !root.centered && root.hasMetered
        width: parent.width
        environments: root.environments
        colors: root.colors
        now: root.now
        fontFamily: root.fontFamily
      }
      // Bottom row: text size control left, key hints right (hints wrap between hints if narrow).
      Item {
        width: parent.width
        height: Math.max(sizeControl.implicitHeight, hints.implicitHeight)
        TextSizeControl {
          id: sizeControl
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          sizes: root.service ? root.service.textSizes : [0, 2, 4, 6]
          step: root.service ? root.service.textSizeStep : 0
          colors: root.colors
          onStepRequested: function(delta) { if (root.service) root.service.stepTextSize(delta) }
          onSizeRequested: function(size) { if (root.service) root.service.setTextSize(size) }
        }
        FontMetrics { id: legendMetrics; font: hints.font }
        Text {
          id: hints
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - sizeControl.width - Style.space(20)
          horizontalAlignment: Text.AlignRight
          textFormat: Text.StyledText
          // One line: the lowest-priority hints drop out until the rest fit.
          text: root.legendStyled(Store.fitLegend(root.legendHints, function(shown) {
            return legendMetrics.advanceWidth(root.legendPlain(shown)) <= hints.width
          }))
          color: root.colors.textDim
          font.family: root.fontFamily
          font.pixelSize: Typo.caption
        }
      }
    }
  }
}
