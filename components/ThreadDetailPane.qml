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
  // Room past the pane's right edge that is the window's own padding: the scrollbar sits there,
  // so the detail's text ends where the filter box and the footer's rules end, not a scrollbar's
  // width short of them. 0 (the default) keeps the bar inside the pane.
  property real gutter: 0
  readonly property real outset: Math.max(0, Math.min(gutter, scrollBar.inset))
  // What is left between the detail's right edge and the pane's.
  readonly property real contentInset: scrollBar.inset - outset

  // How tall the detail is on its own, whatever the pane's height: the window sizes itself to it.
  readonly property real naturalHeight: hasRow ? column.implicitHeight - column.bottomPadding + Style.space(6) : 0
  // Still waiting for T3 to send this thread's detail: its height is not known yet.
  readonly property bool loading: hasRow && detail === null && !restView.waited
  // Scrollable: the detail itself (without the room kept for the scroll strip) is taller than the pane.
  readonly property bool scrollable: column.implicitHeight - column.bottomPadding > flick.height + 2
  readonly property bool moreBelow: scrollable && flick.contentY + flick.height < flick.contentHeight - 2
  readonly property bool moreAbove: scrollable && flick.contentY > 2
  // The scroll edge never cuts through anything: a line of text, or a thing marked `whole` (an
  // activity row, a fact, the run chart), is drawn in full or not at all. Where the strip's top
  // edge would cut one, a cover reaches up to that thing's top, as the list's strips do.
  readonly property real stripBase: stripProbe.implicitHeight + Style.space(14)
  readonly property real coverMax: Math.max(Style.space(40), flick.height * 0.3)
  // The innermost such thing that the horizontal line at y cuts through, as { top, bottom } in
  // `item`'s coordinates; null where the line falls in a gap.
  function cutAt(item, y) {
    var kids = item.children
    for (var i = 0; i < kids.length; i++) {
      var c = kids[i]
      if (!c.visible || c.height <= 0 || y <= c.y + 0.5 || y >= c.y + c.height - 0.5) continue
      if (c.whole === true) return { top: c.y, bottom: c.y + c.height, heading: c.heading === true }
      if (c.lineCount !== undefined && c.font !== undefined) {
        // Text: the one line of it the edge is on.
        var lines = Math.max(1, c.lineCount)
        var pad = c.topPadding || 0
        var tall = Math.max(1, c.contentHeight / lines)
        var n = Math.max(0, Math.min(lines - 1, Math.floor((y - c.y - pad) / tall)))
        return { top: c.y + pad + n * tall, bottom: c.y + pad + (n + 1) * tall, heading: false }
      }
      var inner = cutAt(c, y - c.y)
      if (inner) return { top: inner.top + c.y, bottom: inner.bottom + c.y, heading: inner.heading }
    }
    return null
  }
  // How far the cover reaches above the strip: up to the top of whatever the strip's edge cuts,
  // and past a section's caption left with none of its rows under it ("ACTIVITY" and nothing).
  readonly property real coverExtra: {
    if (!hasRow || !moreBelow) return 0
    var edge = flick.contentY + flick.height - stripBase
    var cut = cutAt(column, edge)
    var top = cut && edge - cut.top > 0.5 ? cut.top : edge
    var above = cutAt(column, top - Style.space(10))
    if (above && above.heading) top = above.top
    var extra = edge - top
    return extra > 0.5 && extra <= coverMax ? Math.ceil(extra) : 0
  }
  // The same at the pane's top, once it is scrolled: what the top edge cuts is covered down to
  // its foot. Paging lands clear of it; this is for the end of the detail, and for the wheel.
  readonly property real coverTop: {
    if (!hasRow || !moreAbove) return 0
    var cut = cutAt(column, flick.contentY)
    var extra = cut ? cut.bottom - flick.contentY : 0
    return extra > 0.5 && extra <= coverMax ? Math.ceil(extra) : 0
  }
  // d / u: a page down or up through a detail longer than the pane. A page down starts with the
  // first thing the strip was hiding; either way the pane lands with its top line whole.
  function page(direction) {
    var maxY = Math.max(0, flick.contentHeight - flick.height)
    var shown = flick.height - stripBase
    var target = direction > 0 ? flick.contentY + shown - coverExtra - Style.space(4) : flick.contentY - shown + Style.space(4)
    if (direction > 0 && target <= flick.contentY) target = flick.contentY + Math.max(Style.space(40), flick.height * 0.8)
    target = Math.max(0, Math.min(maxY, target))
    var cut = target > 0 && target < maxY ? cutAt(column, target) : null
    if (cut && target - cut.top <= coverMax) target = Math.max(0, cut.top - Style.space(2))
    flick.contentY = target
  }

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
    anchors.rightMargin: -root.outset
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
      bottomPadding: root.stripBase + Style.space(4)

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

        // The actions, for a thread with nothing to hand off: one line under where it runs. A
        // thread that needs you, or has anything else to say first, leads with a block that ends in
        // these same actions (see DetailView), next to the step they carry out, so they are not
        // drawn here as well.
        Item {
          visible: !leadView.hasLead
          width: parent.width
          height: actions.implicitHeight + Style.space(2)
          ThreadActions {
            id: actions
            anchors.bottom: parent.bottom
            width: parent.width
            row: root.row
            colors: root.colors
            fontFamily: root.fontFamily
            monoFamily: root.monoFamily
            copyState: root.copyState
            onActionRequested: function(action) { root.actionRequested(action) }
          }
        }
      }

      // What to act on comes first: the callout and any pending request, right under the title.
      DetailView {
        id: leadView
        visible: hasLead
        width: parent.width
        spacing: column.spacing
        topPadding: 0
        paneMode: true
        part: "lead"
        copyState: root.copyState
        row: root.hasRow ? root.row : ({})
        detail: root.detail
        colors: root.colors
        now: root.now
        fontFamily: root.fontFamily
        monoFamily: root.monoFamily
        onActionRequested: function(action) { root.actionRequested(action) }
      }

      // One fact alone is a line under its caption, like Runs below it: a box around a single
      // figure ("LAST RUN 6m 00s") was the heaviest thing in a short detail.
      Column {
        objectName: "factLine"
        readonly property var fact: root.facts.length === 1 ? root.facts[0] : null
        readonly property bool whole: true
        visible: fact !== null
        width: parent.width
        spacing: Style.space(5)
        SectionCaption { label: parent.fact ? parent.fact.label : ""; foreground: root.colors.text; fontFamily: root.fontFamily; maxWidth: parent.width }
        Row {
          spacing: Style.space(12)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.parent.fact ? parent.parent.fact.value : ""
            textFormat: Text.PlainText
            color: parent.parent.fact && parent.parent.fact.alarm ? root.colors.attentionInk : root.colors.textDim
            font.family: root.fontFamily
            font.pixelSize: Typo.caption
          }
          Meter {
            visible: parent.parent.fact !== null && parent.parent.fact.meter !== undefined
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(150)
            value: parent.parent.fact && parent.parent.fact.meter || 0
            ink: root.colors.textFaint
            danger: root.colors.text
            track: root.colors.edge
          }
          Text {
            visible: text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: parent.parent.fact && parent.parent.fact.note || ""
            textFormat: Text.PlainText
            color: root.colors.textFaint
            font.family: root.fontFamily
            font.pixelSize: Typo.caption
          }
        }
      }

      // Several facts: quiet tiles of label / value / note, as many columns as fit cells about
      // 27 characters wide (two in the usual pane, at any text size), so a value and its note each
      // stay on one line. The
      // tiles are the rows' surface tone with a hairline of panel between them, and no outline:
      // they are figures to read, and an outlined grid outweighed the block above it that says
      // what the thread needs. Text on a tile holds the same floors as on a row.
      Item {
        objectName: "factsGrid"
        visible: root.facts.length > 1
        width: parent.width
        height: factsGrid.implicitHeight
        Grid {
          id: factsGrid
          width: parent.width
          spacing: Style.space(3)
          columns: Math.max(1, Math.min(root.facts.length, Math.floor((width + spacing) / (Typo.caption * 16 + spacing))))
          readonly property real cellWidth: (width - spacing * (columns - 1)) / columns
          // All cells share the tallest height.
          readonly property real cellHeight: {
            var h = 0
            for (var i = 0; i < children.length; i++) if (children[i].children && children[i].children.length) h = Math.max(h, children[i].children[0].implicitHeight + Style.space(18))
            return h
          }
          Repeater {
            model: root.facts.length > 1 ? root.facts : []
            Rectangle {
              objectName: "factTile"
              required property var modelData
              width: factsGrid.cellWidth
              height: Math.max(factsGrid.cellHeight, cell.implicitHeight + Style.space(18))
              radius: Style.cornerRadius
              color: root.colors.surface
              border.width: 0
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
                  ink: root.colors.textFaint
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
        id: restView
        width: parent.width
        spacing: column.spacing
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

  Rectangle {
    objectName: "detailCoverTop"
    visible: root.hasRow && root.coverTop > 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.rightMargin: root.contentInset
    height: root.coverTop
    color: root.colors.background
  }

  // A detail longer than the pane: a solid strip at its foot says so, and names the keys that
  // page it (d down, u back up), each as a keycap you can also click. Solid, so nothing under it
  // is half-faded (a fade dimmed the runs chart below 3:1). The scrollbar stays on meanwhile.
  Rectangle {
    id: scrollStrip
    visible: root.hasRow && root.scrollable
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.rightMargin: root.contentInset
    anchors.bottom: parent.bottom
    height: root.stripBase
    color: root.colors.background
    // The cover: whatever the strip's top edge would cut through is hidden whole.
    Rectangle {
      objectName: "detailCover"
      anchors.bottom: parent.top
      width: parent.width
      height: root.coverExtra
      color: root.colors.background
    }
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
