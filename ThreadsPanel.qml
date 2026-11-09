import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "components"
import "lib/Store.js" as Store
import "lib/Format.js" as Format
import "lib/Palette.js" as Palette

// Panel content: header, state distribution, machines, filters, thread list, providers.
Item {
  id: root

  property var service: null
  property bool reduceMotion: false
  property bool opened: false
  readonly property alias keyCatcher: keys
  // For tests: the list, its pinned heading and the legend.
  readonly property Item listView: list
  readonly property var pinnedHeading: sticky.heading
  readonly property real pinnedHeight: sticky.stripHeight
  readonly property real legendHeight: legend.height
  readonly property real legendWidth: legend.width
  readonly property real legendX: keysBand.contentX
  readonly property real legendRoom: keysBand.width - keysBand.contentX
  readonly property var legendShown: root.legendGroups
  readonly property Item legendItem: legend
  readonly property Item detailItem: detailPane.item

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
  // Ring: what needs you in the colour of its kind (as in the list), working in ink, the rest in the
  // 3:1 edge tone. No number in it: the header beside it says what is counted.
  readonly property var ringSegs: Store.ringSegments(rows)
  readonly property var ringColors: ({
    attention: colors.attention, ask: colors.ask, warning: colors.warning, ink: colors.text, rest: colors.edge, track: colors.edge
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
      for (var i = 0; i < visible_.length; i++) if (visible_[i].key === key) { cursor = i; ensureVisible(i) }
    })
    // Again once the drawer has laid out at full height.
    settleScroll.restart()
  }

  // Scrolls the item at i fully into view, clear of the pinned heading at the top and the
  // "more below" strip at the bottom, with a little room to spare.
  function ensureVisible(i) {
    if (i < 0 || i >= visible_.length) return
    list.positionViewAtIndex(i, ListView.Contain)
    clearOfEdges(i)
    // Once more after the list has laid out the rows it just created (their heights and the
    // list's origin can shift as they appear).
    Qt.callLater(function() { if (root.cursor === i) root.clearOfEdges(i) })
  }
  function clearOfEdges(i) {
    var it = list.itemAtIndex(i)
    if (!it) return
    var margin = Style.space(8)
    var maxY = list.originY + Math.max(0, list.contentHeight - list.height)
    var bottom = list.contentY + list.height - moreBelow.height - margin
    if (it.y + it.height > bottom) list.contentY = Math.min(maxY, list.contentY + (it.y + it.height - bottom))
    var top = list.contentY + (list.contentY > list.originY + 1 ? sticky.stripHeight : 0)
    if (it.y < top && list.contentY > list.originY) list.contentY = Math.max(list.originY, it.y - sticky.stripHeight - margin)
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
    ensureVisible(cursor)
  }

  // The key legend (Store.legendGroups): the keys that work here, grouped by purpose; Enter's names
  // what it does on the item under the cursor, or isn't there.
  readonly property string legendMode: disconnected ? "offline" : visible_.length === 0 ? "empty" : "list"
  readonly property var cursorItem: cursor >= 0 && cursor < visible_.length ? visible_[cursor] : null
  readonly property string enterVerb: Store.enterVerb(cursorItem, centered, cursorItem && !cursorItem.kind ? expanded[cursorItem.key] === true : false)
  readonly property int repairCount: repairCommands.length
  readonly property var legendGroups: Store.legendGroups(legendMode, { enter: enterVerb, centered: centered, commands: repairCount })
  // What the footer is built from: the same groups with Enter's slot left open. It changes only
  // with the mode (not with each state update, nor with the selection), so moving the selection
  // redraws one cell's words, not the legend.
  readonly property var legendFrame: Store.legendGroups(legendMode, { centered: centered, commands: repairCount })

  // Offline: the re-pair command for each machine that has one, in the order shown. Keys 1–9 copy them.
  readonly property var repairCommands: {
    var out = []
    if (!disconnected) return out
    for (var i = 0; i < environments.length; i++) {
      var step = Store.repairStep(environments[i])
      if (step.kind === "command") out.push({ id: environments[i].id, text: step.text })
    }
    return out.slice(0, 9)
  }

  // Copying: what was asked for last ("title:<thread key>" or "command:<machine id>") and how it
  // ended ("ok" | "failed"), as the collector reports it. Shown at the action for a moment.
  property string copyTarget: ""
  property string copyResult: ""
  function copy(target, text) {
    if (!service || !text) return
    copyTarget = target
    copyResult = ""
    copyNote.stop()
    // Piped to wl-copy's stdin by the collector: the text never appears in a process's argv.
    service.send({ cmd: "copy", text: text })
  }
  function copyState(target) { return copyTarget === target ? copyResult : "" }
  Timer { id: copyNote; interval: 2200; onTriggered: { root.copyTarget = ""; root.copyResult = "" } }
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onCopied(ok) {
      if (root.copyTarget === "") return
      root.copyResult = ok ? "ok" : "failed"
      copyNote.restart()
    }
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
        : "pairing expires " + Format.until(modelData.sessionExpiresAt, root.now)
      textFormat: Text.PlainText
      // Broken is red. An expiry is a note in dim ink; amber is kept for plans, so even the last
      // day before it lapses is full ink, not a colour.
      color: !parent.ok ? root.colors.attentionInk : modelData.sessionExpiresAt - root.now < 86400000 ? root.colors.text : root.colors.textDim
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
      root.copy("title:" + row.key, row.title)
    }
  }

  Timer {
    id: settleScroll
    interval: 350
    onTriggered: if (root.cursor >= 0) root.ensureVisible(root.cursor)
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
      // Offline there are no views to switch: the digits copy the re-pair commands instead.
      if (root.disconnected && t.length === 1 && "123456789".indexOf(t) >= 0) {
        var n = "123456789".indexOf(t)
        if (n < root.repairCommands.length) root.copy("command:" + root.repairCommands[n].id, root.repairCommands[n].text)
        return
      }
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
      else if ((t === "d" || t === "u") && detailPane.item) detailPane.item.page(t === "d" ? 1 : -1)
      else if (t === "p" || t === "c") {
        var target = root.centered ? root.selectedRow : (root.cursor >= 0 && !root.visible_[root.cursor].kind ? root.visible_[root.cursor] : null)
        if (target) root.act(target, t === "p" ? "pr" : "copy")
      }
      else if (t === "g") {
        for (var i = 0; i < root.visible_.length; i++) if (!root.visible_[i].kind && Store.ATTENTION[root.visible_[i].state]) { root.cursor = i; root.ensureVisible(i); break }
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
          reduceMotion: root.reduceMotion
          offline: root.service && !root.service.known
          centerText: root.service && root.service.known ? "" : "—"
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
          // The name, and on its line the machines (two-pane window, when they fit there).
          Item {
            id: titleRow
            width: parent.width
            height: Math.max(title.implicitHeight, machinesInline.implicitHeight)
            Text {
              id: title
              anchors.verticalCenter: parent.verticalCenter
              text: "T3 Loupe"
              textFormat: Text.PlainText
              color: root.colors.text
              font.family: root.fontFamily
              font.pixelSize: Typo.heading
              font.bold: true
            }
            Row {
              id: machinesInline
              // Measured even while hidden (opacity, not visible), so `fits` doesn't depend on itself.
              readonly property bool fits: root.centered && implicitWidth + title.implicitWidth + Style.space(24) <= parent.width
              opacity: fits ? 1 : 0
              enabled: fits
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(16)
              Repeater {
                model: root.centered ? root.environments : []
                MachineTag { anchors.verticalCenter: parent.verticalCenter }
              }
            }
          }
          // The counts line: what needs you first, in the colour of the most pressing kind waiting;
          // working in full ink; the rest dimmed. With something waiting it spells out the Active
          // tab's number ("6 NEED YOU + 7 WORKING = 13 ACTIVE"), and the parts after it add up to All.
          // If the sum doesn't fit the line, it goes and the "+" stays.
          Item {
            id: countsLine
            width: parent.width
            height: counts.implicitHeight
            function styled(sum) {
              function tint(color, words) { return "<font color=\"" + color + "\">" + words + "</font>" }
              var alarm = root.colors.attentionInk
              if (!root.service) return "SERVICE NOT LOADED"
              if (root.service.health === "down") return tint(alarm, "COLLECTOR STOPPED · RESTARTING")
              if (root.service.configError) return tint(alarm, "PAIRINGS UNREADABLE · " + root.service.configError.toUpperCase())
              if (!root.environments.length) return "NO T3 MACHINES PAIRED"
              var sep = "&nbsp;&nbsp;·&nbsp;&nbsp;"
              var quiet = root.colors.textFaint
              if (root.disconnected) return tint(alarm, "NOT CONNECTED") + sep + Format.plural(root.link.total, "MACHINE", "MACHINES")
              var tones = { needs: root.colors[Store.needsRole(root.rows) + "Ink"], strong: root.colors.text, quiet: quiet }
              var parts = Store.headerCounts(root.tally, sum)
              var out = ""
              for (var i = 0; i < parts.length; i++) {
                if (i > 0) out += parts[i].join ? tint(quiet, "&nbsp;" + parts[i].join + "&nbsp;") : sep
                out += tint(tones[parts[i].tone], parts[i].text.replace(/ /g, "&nbsp;"))
              }
              if (root.link.connected !== root.link.total) out += sep + tint(alarm, root.link.connected + " OF " + root.link.total + " MACHINES CONNECTED")
              return out
            }
            // The line with the sum spelled out, measured to see whether it fits.
            Text {
              id: countsFull
              visible: false
              text: countsLine.styled(true)
              textFormat: Text.StyledText
              font: counts.font
            }
            Text {
              id: counts
              width: parent.width
              text: countsFull.implicitWidth <= width ? countsFull.text : countsLine.styled(false)
              textFormat: Text.StyledText
              color: root.colors.textDim
              font.family: root.fontFamily
              font.pixelSize: Typo.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }
        }

        // Refresh and close, on the name's line, so the header's right side reads as one row.
        Row {
          id: headRight
          anchors.right: parent.right
          y: Math.round(headText.y + titleRow.y + (titleRow.height - height) / 2)
          spacing: Style.space(2)
          IconButton { icon: "refresh-cw"; foreground: root.colors.textDim; hoverForeground: root.colors.text; onClicked: if (root.service) root.service.refresh() }
          IconButton { icon: "x"; foreground: root.colors.textDim; hoverForeground: root.colors.text; onClicked: root.closeRequested() }
        }
      }

      // Machines on one quiet line under the header: in the dropdown, and in the two-pane window
      // when there are too many to sit beside the name.
      Flow {
        visible: !machinesInline.fits && root.environments.length > 0
        width: parent.width
        spacing: Style.space(16)
        Repeater {
          model: machinesInline.fits ? [] : root.environments
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
          // The views by the names the header and the legend use: what needs you is "Needs you"
          // everywhere, and each count is the header's.
          options: [
            { value: "attention", label: "   " + Store.VIEW_LABEL.attention + "  " + root.needCount, tooltip: "1" },
            { value: "active", label: "   " + Store.VIEW_LABEL.active + "  " + root.activeCount, tooltip: "2" },
            { value: "done", label: "   " + Store.VIEW_LABEL.done + "  " + root.doneCount, tooltip: "3" },
            { value: "all", label: "   " + Store.VIEW_LABEL.all + "  " + root.allCount, tooltip: "4" }
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
            // The tab's key, drawn as a small keycap in the label's first two (blank) character cells,
            // so it reads as a key, not a second count: "[1] Inbox 6". The shell centres the label.
            Rectangle {
              id: digitCap
              readonly property string label: parent.tab ? String(parent.tab.text) : ""
              // Reading tabMetrics.font makes these re-run when the font changes (advanceWidth is a call).
              readonly property real cell: tabMetrics.font ? tabMetrics.advanceWidth("  ") : 0
              x: Math.round((parent.width - (tabMetrics.font ? tabMetrics.advanceWidth(label) : 0)) / 2) - Style.space(2)
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(digit.implicitWidth + Style.space(6), cell - Style.space(1))
              height: digit.implicitHeight + Style.space(2)
              radius: Math.min(Style.cornerRadius, Style.space(2))
              color: "transparent"
              border.width: 1
              border.color: root.colors.edge
              Text {
                id: digit
                anchors.centerIn: parent
                text: String(digitCap.parent.index + 1)
                textFormat: Text.PlainText
                color: root.colors.textDim
                font.family: root.fontFamily
                font.pixelSize: Math.max(7, Typo.caption - 1)
              }
              FontMetrics { id: tabMetrics; font.family: root.fontFamily; font.pixelSize: Typo.caption; font.bold: digitCap.parent.tab ? digitCap.parent.tab.selected === true : false }
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
        commands: root.repairCommands
        copyTarget: root.copyTarget
        copyResult: root.copyResult
        onCopyRequested: function(id, text) { root.copy("command:" + id, text) }
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
          text: !root.environments.length ? "Run:  t3-loupe pair-local   (first time? see Quick start in the README)"
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
      // Shown whenever the list is longer than its pane, in the palette's 3:1 scroll tones.
      ScrollBar.vertical: LoupeScrollBar { id: listBar; colors: root.colors; policy: ScrollBar.AlwaysOn }

      delegate: Column {
        id: cell
        required property var modelData
        required property int index
        // A fixed inset for the scrollbar, whether or not it shows: rows never run under it.
        width: list.width - listBar.inset
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
            foreground: root.colors.text
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
            label: cell.modelData.label || "Idle"
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

    // Scrolled lists keep their place. One heading stays pinned at the top: the group (All) or
    // section (Active) of the row just under it. When the next group's own heading reaches the top,
    // the pinned one gives way to it, so two headings never stack. At the bottom, a solid strip says
    // when more is below (no fade over rows), and the selection is kept clear of both.
    Item {
      x: list.x
      y: list.y
      width: list.width - listBar.inset
      height: sticky.stripHeight
      clip: true
      visible: sticky.heading !== null
      Rectangle {
        id: sticky
        readonly property real stripHeight: stickyCaption.implicitHeight + Style.space(10)
        // The row just under the strip, and the group or section it belongs to.
        readonly property int under: list.visible && list.contentY - list.originY >= 2 ? list.indexAt(Style.space(20), list.contentY + stripHeight) : -1
        readonly property var heading: {
          if (under < 0) return null
          var cell = list.itemAtIndex(under)
          // That row starts its own group and its heading is on screen: pin nothing over it.
          if (cell && (cell.newGroup || cell.isSection) && cell.y >= list.contentY - 1) return null
          for (var k = under; k >= 0 && k < root.visible_.length; k--) {
            var it = root.visible_[k]
            if (it.kind === "section") return { label: it.label, count: it.count }
            if (root.filter === "all" && !it.parentId) return { label: Store.groupKey(it, root.environments), count: -1 }
          }
          return null
        }
        // The next group's heading pushes this one up and out as it arrives, so two never stack.
        readonly property real push: {
          if (under < 0) return 0
          for (var n = under + 1; n < Math.min(root.visible_.length, under + 6); n++) {
            var next = list.itemAtIndex(n)
            if (!next || !(next.newGroup || next.isSection)) continue
            var gap = next.y - (list.contentY + stripHeight)
            return gap < stripHeight ? Math.max(0, stripHeight - Math.max(0, gap)) : 0
          }
          return 0
        }
        y: -push
        width: parent.width
        height: stripHeight
        color: root.colors.background
        SectionCaption {
          id: stickyCaption
          x: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          label: sticky.heading ? sticky.heading.label : " "
          count: sticky.heading ? sticky.heading.count : -1
          foreground: root.colors.text
          countColor: root.colors.textFaint
          fontFamily: root.fontFamily
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.colors.line }
      }
    }
    Rectangle {
      id: moreBelow
      visible: list.visible && list.contentY + list.height < list.contentHeight + list.originY - 2
      x: list.x
      y: list.y + list.height - height
      width: list.width - listBar.inset
      height: Style.space(22)
      color: root.colors.background
      Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: root.colors.line }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        text: "more below ↓"
        textFormat: Text.PlainText
        color: root.colors.textDim
        font.family: root.fontFamily
        font.pixelSize: Typo.caption
      }
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
      id: detailPane
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
        copyState: root.selectedRow ? root.copyState("title:" + root.selectedRow.key) : ""
        onActionRequested: function(action) { if (root.selectedRow) root.act(root.selectedRow, action) }
      }
    }

    Column {
      id: footer
      anchors.bottom: parent.bottom
      width: parent.width
      spacing: Style.space(9)

      Rectangle { width: parent.width; height: 1; color: root.colors.line }

      // The footer is two aligned bands: usage limits on one, the keys on the other. In the
      // two-pane window each has a caption in a shared left column, so their content starts at
      // the same x; the dropdown has no room for the keys' caption and starts them at the edge.
      ProviderStrip {
        id: usage
        visible: root.hasMetered
        // Compact in the dropdown, so each provider fits a row.
        compact: !root.centered
        width: parent.width
        headingColumn: keysBand.captioned ? keysCaption.implicitWidth : 0
        environments: root.environments
        colors: root.colors
        now: root.now
        fontFamily: root.fontFamily
      }

      // The keys that work here, in three groups by purpose (navigate | act | window) with a
      // hairline between groups. Each group is a few columns two rows tall, so keys line up down
      // the rows and the band is always two lines. The text-size control sits beside its keys.
      // Nothing moves as the selection moves: Enter is the one cell that comes and goes, at the
      // foot of its column, which keeps the width of the longest thing Enter can say.
      Item {
        id: keysBand
        width: parent.width
        height: legend.height
        readonly property bool captioned: root.centered
        readonly property real rowHeight: Math.round(Typo.caption * 1.6)
        readonly property real contentX: !captioned ? 0 : usage.visible ? usage.contentX : keysCaption.implicitWidth + usage.itemGap

        Text {
          id: keysCaption
          visible: keysBand.captioned
          y: Math.round((keysBand.rowHeight - implicitHeight) / 2)
          text: "KEYS"
          textFormat: Text.PlainText
          color: root.colors.textDim
          font.family: root.fontFamily
          font.pixelSize: Typo.caption
          font.bold: true
          font.letterSpacing: 1.2
        }

        component LegendCell: Item {
          id: lc
          property var cell: ({})
          // Enter's slot says what Enter does on the item under the cursor, or nothing.
          readonly property bool enterSlot: cell.slot === "enter"
          readonly property string shownKey: enterSlot ? (root.enterVerb !== "" ? "↵" : "") : (cell.key || "")
          readonly property string shownVerb: enterSlot ? root.enterVerb : (cell.verb || "")
          // It keeps the width of the longest thing Enter can say here.
          readonly property real held: cell.widest ? enterProbe.implicitWidth + line.spacing + widestProbe.implicitWidth : 0
          implicitWidth: Math.max(line.implicitWidth, held)
          implicitHeight: keysBand.rowHeight
          Row {
            id: line
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Text {
              visible: text !== ""
              anchors.verticalCenter: parent.verticalCenter
              text: lc.shownKey
              textFormat: Text.PlainText
              color: root.colors.text
              font.family: root.fontFamily
              font.pixelSize: Typo.caption
            }
            Text {
              visible: text !== ""
              anchors.verticalCenter: parent.verticalCenter
              text: lc.shownVerb
              textFormat: Text.PlainText
              color: root.colors.textDim
              font.family: root.fontFamily
              font.pixelSize: Typo.caption
            }
            Loader {
              active: lc.cell.slot === "size"
              visible: active
              anchors.verticalCenter: parent.verticalCenter
              sourceComponent: TextSizeControl {
                compact: !root.centered
                rowHeight: keysBand.rowHeight
                sizes: root.service ? root.service.textSizes : [0, 2, 4, 6]
                step: root.service ? root.service.textSizeStep : 0
                colors: root.colors
                onStepRequested: function(delta) { if (root.service) root.service.stepTextSize(delta) }
                onSizeRequested: function(size) { if (root.service) root.service.setTextSize(size) }
              }
            }
          }
          Text { id: enterProbe; visible: false; text: "↵"; textFormat: Text.PlainText; font.family: root.fontFamily; font.pixelSize: Typo.caption }
          Text { id: widestProbe; visible: false; text: lc.cell.widest || ""; textFormat: Text.PlainText; font.family: root.fontFamily; font.pixelSize: Typo.caption }
        }

        Row {
          id: legend
          x: keysBand.contentX
          readonly property real columnGap: Style.space(root.centered ? 18 : 12)
          readonly property real groupGap: Style.space(root.centered ? 16 : 9)
          readonly property real rowGap: Style.space(3)
          height: keysBand.rowHeight * 2 + rowGap
          Repeater {
            model: root.legendFrame
            Row {
              id: group
              required property var modelData
              required property int index
              objectName: "legendGroup:" + modelData.name
              height: legend.height
              // The hairline between this group and the one before it.
              Item {
                visible: group.index > 0
                width: legend.groupGap * 2 + 1
                height: parent.height
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 1; height: parent.height; color: root.colors.line }
              }
              Row {
                spacing: legend.columnGap
                Repeater {
                  model: group.modelData.columns
                  Column {
                    required property var modelData
                    objectName: "legendColumn"
                    spacing: legend.rowGap
                    Repeater {
                      model: parent.modelData
                      LegendCell { required property var modelData; objectName: "legendCell"; cell: modelData }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
