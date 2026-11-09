import QtQuick
import QtQuick.Controls
import qs.Commons
import "../lib/Store.js" as Store
import "../lib/Format.js" as Format
import "../lib/Palette.js" as Palette

// Right side of the two-pane view: everything about the selected thread.
// Header (title, state-led meta, icon actions) → facts strip → detail.
Item {
  id: root

  property var row: null
  property var detail: null
  property var colors: ({})
  property double now: Date.now()
  property bool reduceMotion: false
  property string machineLabel: ""
  property string fontFamily: Style.font.family
  property string monoFamily: "monospace"

  signal actionRequested(string action)

  // How copying this thread's title just ended: "" | "ok" | "failed". Shown on the copy action.
  property string copyState: ""

  // d / u: a page down or up through a detail longer than the pane.
  // Scrollable: the detail itself (without the room kept for the scroll strip) is taller than the pane.
  readonly property bool scrollable: column.implicitHeight - column.bottomPadding > flick.height + 2
  readonly property bool moreBelow: scrollable && flick.contentY + flick.height < flick.contentHeight - 2
  readonly property bool moreAbove: scrollable && flick.contentY > 2
  function page(direction) {
    var step = Math.max(Style.space(40), flick.height * 0.8)
    var maxY = Math.max(0, flick.contentHeight - flick.height)
    flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + direction * step))
  }

  // The thread's actions, labelled with their keys (o, c and p also work from anywhere in the panel).
  // Always on a line of their own, from the pane's left edge, so they are in the same place on
  // every thread; the PR action comes last because not every thread has one.
  // short: "open" and "copy", for when the line is too narrow for the full labels.
  component ActionKeys: Row {
    property bool short: false
    spacing: Style.space(16)
    KeyAction { key: "o"; text: parent.short ? "open" : "open T3"; quiet: true; colors: root.colors; fontFamily: root.fontFamily; monoFamily: root.monoFamily; onClicked: root.actionRequested("focus") }
    KeyAction {
      key: "c"; text: parent.short ? "copy" : "copy title"; quiet: true; colors: root.colors; fontFamily: root.fontFamily; monoFamily: root.monoFamily
      feedback: root.copyState === "ok" ? "✓ copied" : root.copyState === "failed" ? "copy failed" : ""
      feedbackInk: root.copyState === "failed" ? root.colors.attentionInk : root.colors.text
      onClicked: root.actionRequested("copy")
    }
    KeyAction {
      visible: root.hasRow && !!root.row.pr && root.row.pr.url !== ""
      key: "p"; text: parent.short ? "PR" : "open PR"; quiet: true; colors: root.colors; fontFamily: root.fontFamily; monoFamily: root.monoFamily
      onClicked: root.actionRequested("pr")
    }
  }
  // The space the action row keeps before the pane's edge (and the scrollbar beyond it).
  readonly property real actionsMargin: Style.space(16)

  readonly property bool hasRow: row !== null && row !== undefined
  // A new thread starts at its top; an update to the same thread keeps its place.
  readonly property string rowKey: hasRow && row.key ? row.key : ""
  onRowKeyChanged: flick.contentY = 0
  readonly property bool working: hasRow && Store.BUSY[row.state] === true
  readonly property var ctx: detail && detail.context && detail.context.max > 0 ? detail.context : null
  readonly property int subs: hasRow ? Math.max(row.background ? row.background.subagents : 0, row.activeChildren || 0) : 0
  readonly property int subTotal: detail && detail.subagents ? detail.subagents.length : (hasRow ? row.childCount : 0)

  // Facts: label / value / note, only those with data.
  readonly property var facts: {
    if (!hasRow) return []
    var f = []
    if (subs > 0 || subTotal > 0) f.push({ label: "Subagents", value: subs > 0 ? subs + " running" : String(subTotal), note: subs > 0 && subTotal > subs ? subTotal + " total" : "" })
    if (row.pr) {
      // The number is the value; checks and size go on one line underneath.
      var c = row.pr.checks === "passing" ? "✓ checks pass" : row.pr.checks === "failing" ? "✗ checks fail" : row.pr.checks === "pending" ? "checks pending" : row.pr.state
      var size = (row.pr.additions || row.pr.deletions) ? "+" + row.pr.additions + " −" + row.pr.deletions : ""
      f.push({ label: "PR", value: "#" + row.pr.number, note: c + (size ? " · " + size : ""), alarm: row.pr.checks === "failing" })
    }
    if (ctx) f.push({ label: "Context", value: Format.tokens(ctx.used) + " / " + Format.tokens(ctx.max) + " tokens", meter: ctx.used / ctx.max })
    if (ctx && ctx.cost !== null) f.push({ label: "Cost", value: Format.money(ctx.cost, ctx.currency), note: "at API prices" })
    if (!f.length && row.lastRunMs) f.push({ label: "Last run", value: Format.duration(row.lastRunMs) })
    return f
  }

  // Nothing selected
  Column {
    visible: !root.hasRow
    anchors.centerIn: parent
    spacing: Style.space(8)
    LucideIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "activity"; color: root.colors.textFaint; size: Math.round(Typo.display * 1.1) }
    Text {
      text: "Select a thread to see what it's doing"
      textFormat: Text.PlainText
      color: root.colors.textDim
      font.family: root.fontFamily
      font.pixelSize: Typo.bodySmall
    }
  }

  Flickable {
    id: flick
    visible: root.hasRow
    anchors.fill: parent
    contentWidth: width
    contentHeight: root.scrollable ? column.implicitHeight : height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: root.scrollable
    // A visible bar whenever the detail is longer than the pane, so cut-off content reads as "more".
    ScrollBar.vertical: LoupeScrollBar { id: scrollBar; colors: root.colors; policy: ScrollBar.AlwaysOn }

    Column {
      id: column
      // A fixed inset for the scrollbar, whether or not it shows: content never runs under it.
      width: flick.width - scrollBar.inset
      spacing: Style.space(14)
      // Room for the scroll strip at the end, so the last block scrolls fully above it.
      bottomPadding: scrollStrip.height + Style.space(4)

      // Header: the title across the full width; the state; where it runs; then the thread's
      // actions, each with its key.
      Column {
        width: parent.width
        spacing: Style.space(7)

        Text {
          width: parent.width
          text: root.hasRow ? root.row.title : ""
          textFormat: Text.PlainText
          color: root.colors.text
          font.family: root.fontFamily
          font.pixelSize: Typo.title
          font.bold: true
          wrapMode: Text.Wrap
          maximumLineCount: 4
          elide: Text.ElideRight
        }

        // The state, alone on its line, for threads the block below doesn't already lead with:
        // a request, a failure or any other callout names the state and its time itself, and
        // saying it twice a line apart only pushed the detail down.
        Row {
          id: stateRow
          visible: !leadView.hasLead
          spacing: Style.space(7)
          StateGlyph {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
            icon: root.hasRow ? Store.stateIcon(root.row) : "circle-dot"
            threadState: root.hasRow ? root.row.state : "idle"
            color: root.hasRow ? (root.colors[Store.stateRole(root.row.state)] || root.colors.textDim) : root.colors.textDim
            size: Math.round(Typo.body * 1.05)
            reduceMotion: root.reduceMotion
          }
          Text {
            id: stateText
            anchors.verticalCenter: parent.verticalCenter
            text: root.hasRow ? Store.stateLabel(root.row) + " " + Format.elapsed(root.row, root.now, root.working) : ""
            textFormat: Text.PlainText
            color: root.hasRow && Store.inkRole(root.row.state) ? root.colors[Store.inkRole(root.row.state)] : root.colors.text
            font.family: root.fontFamily
            font.pixelSize: Typo.caption
            font.weight: Font.DemiBold
          }
        }

        // Machine · project · branch · model. Wraps by whole items; the separator stays at the end of
        // the item before it, so no line starts with one.
        Flow {
          width: parent.width
          spacing: metaSpace.advanceWidth
          TextMetrics { id: metaSpace; font.family: root.fontFamily; font.pixelSize: Typo.caption; text: " " }
          Repeater {
            model: root.hasRow ? Store.metaParts(root.row, root.machineLabel) : []
            Text {
              required property var modelData
              required property int index
              // One space either side of the dot: the Flow's spacing is one character wide.
              text: modelData + (index < parent.count - 1 ? " ·" : "")
              textFormat: Text.PlainText
              color: root.colors.textFaint
              font.family: root.fontFamily
              font.pixelSize: Typo.caption
            }
          }
          readonly property int count: root.hasRow ? Store.metaParts(root.row, root.machineLabel).length : 0
        }

        // The actions: one line, in the same place on every thread. A key label never wraps; if the
        // full labels don't fit, the short ones do.
        Item {
          width: parent.width
          height: actions.implicitHeight + Style.space(2)
          // Measured, not shown: the full labels' width decides which labels are used.
          ActionKeys { id: fullActions; opacity: 0; enabled: false; y: -10000 }
          ActionKeys {
            id: actions
            anchors.bottom: parent.bottom
            short: fullActions.implicitWidth + root.actionsMargin > parent.width
          }
        }
      }

      // What to act on comes first: the callout and any pending request, right under the title.
      DetailView {
        id: leadView
        visible: hasLead
        width: parent.width
        topPadding: 0
        paneMode: true
        part: "lead"
        row: root.hasRow ? root.row : ({})
        detail: root.detail
        colors: root.colors
        now: root.now
        fontFamily: root.fontFamily
        monoFamily: root.monoFamily
        onActionRequested: function(action) { root.actionRequested(action) }
      }

      // Facts: a hairline grid of label / value / note cells, as many columns as fit cells about
      // 210 px wide (two in the usual pane), so a value and its note each stay on one line.
      Rectangle {
        visible: root.facts.length > 0
        width: parent.width
        height: factsGrid.implicitHeight + 2
        color: root.colors.line
        radius: Style.cornerRadius
        Grid {
          id: factsGrid
          x: 1; y: 1
          width: parent.width - 2
          spacing: 1
          columns: Math.max(1, Math.min(root.facts.length, Math.floor(width / Style.space(210))))
          readonly property real cellWidth: (width - spacing * (columns - 1)) / columns
          // All cells share the tallest height.
          readonly property real cellHeight: {
            var h = 0
            for (var i = 0; i < children.length; i++) if (children[i].children && children[i].children.length) h = Math.max(h, children[i].children[0].implicitHeight + Style.space(18))
            return h
          }
          Repeater {
            model: root.facts
            Rectangle {
              required property var modelData
              width: factsGrid.cellWidth
              height: Math.max(factsGrid.cellHeight, cell.implicitHeight + Style.space(18))
              color: root.colors.background
              Column {
                id: cell
                x: Style.space(12); y: Style.space(9)
                width: parent.width - Style.space(24)
                spacing: Style.space(4)
                SectionCaption { label: modelData.label; foreground: root.colors.text; fontFamily: root.fontFamily; maxWidth: cell.width }
                ElidedText {
                  width: parent.width
                  fullText: modelData.value
                  color: modelData.alarm ? root.colors.attentionInk : root.colors.text
                  font.family: root.fontFamily
                  font.pixelSize: Typo.bodySmall
                  font.weight: Font.Medium
                }
                Meter {
                  visible: modelData.meter !== undefined
                  width: parent.width
                  value: modelData.meter || 0
                  ink: root.colors.text
                  danger: root.colors.text
                  track: root.colors.edge
                }
                // A note too long for its cell wraps onto a second line; it is never cut.
                Text {
                  visible: !!modelData.note
                  width: parent.width
                  text: modelData.note || ""
                  textFormat: Text.PlainText
                  color: root.colors.textFaint
                  font.family: root.fontFamily
                  font.pixelSize: Typo.caption
                  wrapMode: Text.Wrap
                  maximumLineCount: 3
                  elide: Text.ElideRight
                }
              }
            }
          }
        }
      }

      DetailView {
        width: parent.width
        topPadding: 0
        paneMode: true
        part: "rest"
        row: root.hasRow ? root.row : ({})
        detail: root.detail
        colors: root.colors
        now: root.now
        fontFamily: root.fontFamily
        monoFamily: root.monoFamily
        onActionRequested: function(action) { root.actionRequested(action) }
      }
    }
  }

  // A detail longer than the pane: a solid strip at its foot says so, and names the keys that
  // page it (d down, u back up), each as a keycap you can also click. Solid, so nothing under it
  // is half-faded (a fade dimmed the runs chart below 3:1). The scrollbar stays on meanwhile.
  Rectangle {
    id: scrollStrip
    visible: root.hasRow && root.scrollable
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.bottom: parent.bottom
    height: stripProbe.implicitHeight + Style.space(14)
    color: root.colors.background
    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: root.colors.line }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.bottom: parent.bottom
      spacing: Style.space(18)
      KeyAction {
        visible: root.moreAbove
        key: "u"; text: root.moreBelow ? "up ↑" : "back up ↑"; quiet: true
        colors: root.colors; fontFamily: root.fontFamily; monoFamily: root.monoFamily
        onClicked: root.page(-1)
      }
      KeyAction {
        visible: root.moreBelow
        key: "d"; text: "more below ↓"; quiet: true
        colors: root.colors; fontFamily: root.fontFamily; monoFamily: root.monoFamily
        onClicked: root.page(1)
      }
    }
    // The strip's height follows the text size, whichever keys it is showing.
    Text { id: stripProbe; visible: false; text: "Ag"; textFormat: Text.PlainText; font.family: root.monoFamily; font.pixelSize: Typo.caption; font.bold: true }
  }
}
