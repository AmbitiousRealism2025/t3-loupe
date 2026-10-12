import QtQuick
import QtQuick.Controls
import qs.Commons
import "../lib/Store.js" as Store
import "../lib/Format.js" as Format

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

  readonly property bool hasRow: row !== null && row !== undefined
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
      var c = row.pr.checks === "passing" ? "✓ passing" : row.pr.checks === "failing" ? "✗ failing" : row.pr.checks === "pending" ? "pending" : row.pr.state
      f.push({ label: "Pull request", value: "#" + row.pr.number + " · " + c, note: (row.pr.additions || row.pr.deletions) ? "+" + row.pr.additions + " −" + row.pr.deletions : "", alarm: row.pr.checks === "failing" })
    }
    if (ctx) f.push({ label: "Context", value: Format.tokens(ctx.used) + " / " + Format.tokens(ctx.max), meter: ctx.used / ctx.max })
    if (ctx && ctx.cost !== null) f.push({ label: "Cost", value: Format.money(ctx.cost, ctx.currency), note: "API-equivalent" })
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
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: column
      width: flick.width - (flick.contentHeight > flick.height ? Style.space(10) : 0)
      spacing: Style.space(14)

      // Header: title + state-led meta on the left, icon actions on the right.
      Item {
        width: parent.width
        height: Math.max(headText.implicitHeight, actions.implicitHeight)

        Column {
          id: headText
          anchors.left: parent.left
          anchors.right: actions.left
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(6)

          Text {
            width: parent.width
            text: root.hasRow ? root.row.title : ""
            textFormat: Text.PlainText
            color: root.colors.text
            font.family: root.fontFamily
            font.pixelSize: Typo.title
            font.bold: true
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }
          Row {
            width: parent.width
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
              color: root.hasRow && Store.isAlarm(root.row.state) ? root.colors.attentionInk : root.colors.text
              font.family: root.fontFamily
              font.pixelSize: Typo.caption
              font.weight: Font.Medium
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - glyph.width - stateText.implicitWidth - parent.spacing * 2
              text: {
                if (!root.hasRow) return ""
                var parts = [""]
                if (root.machineLabel) parts.push(root.machineLabel)
                parts.push(root.row.project)
                if (root.row.branch) parts.push(root.row.branch + (root.row.worktree ? " (worktree)" : ""))
                if (root.row.model) parts.push(Format.model(root.row.model))
                return parts.join(" · ")
              }
              textFormat: Text.PlainText
              color: root.colors.textFaint
              font.family: root.fontFamily
              font.pixelSize: Typo.caption
              elide: Text.ElideRight
            }
          }
        }

        Row {
          id: actions
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.space(2)
          IconButton { icon: "app-window"; foreground: root.colors.textDim; hoverForeground: root.colors.text; onClicked: root.actionRequested("focus") }
          IconButton {
            visible: root.hasRow && !!root.row.pr && root.row.pr.url !== ""
            icon: "git-pull-request"; foreground: root.colors.textDim; hoverForeground: root.colors.text
            onClicked: root.actionRequested("pr")
          }
          IconButton { icon: "copy"; foreground: root.colors.textDim; hoverForeground: root.colors.text; onClicked: root.actionRequested("copy") }
        }
      }

      // Facts strip: hairline grid of label / value cells.
      Rectangle {
        visible: root.facts.length > 0
        width: parent.width
        height: factsRow.implicitHeight + 2
        color: root.colors.line
        radius: Style.cornerRadius
        Row {
          id: factsRow
          x: 1; y: 1
          width: parent.width - 2
          spacing: 1
          Repeater {
            model: root.facts
            Rectangle {
              required property var modelData
              width: (factsRow.width - factsRow.spacing * (root.facts.length - 1)) / root.facts.length
              height: Math.max(factsRow.cellHeight, cell.implicitHeight + Style.space(18))
              color: root.colors.background
              Column {
                id: cell
                x: Style.space(12); y: Style.space(9)
                width: parent.width - Style.space(24)
                spacing: Style.space(4)
                SectionCaption { label: modelData.label; foreground: root.colors.text; fontFamily: root.fontFamily; maxWidth: cell.width }
                Text {
                  width: parent.width
                  text: modelData.value
                  textFormat: Text.PlainText
                  color: modelData.alarm ? root.colors.attentionInk : root.colors.text
                  font.family: root.fontFamily
                  font.pixelSize: Typo.bodySmall
                  font.weight: Font.Medium
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }
                Meter {
                  visible: modelData.meter !== undefined
                  width: parent.width
                  value: modelData.meter || 0
                  ink: root.colors.text
                  danger: root.colors.attention
                }
                Text {
                  visible: !!modelData.note
                  width: parent.width
                  text: modelData.note || ""
                  textFormat: Text.PlainText
                  color: root.colors.textFaint
                  font.family: root.fontFamily
                  font.pixelSize: Typo.caption
                  elide: Text.ElideRight
                }
              }
            }
          }
          // All cells share the tallest height.
          readonly property real cellHeight: {
            var h = 0
            for (var i = 0; i < children.length; i++) if (children[i].children && children[i].children.length) h = Math.max(h, children[i].children[0].implicitHeight + Style.space(18))
            return h
          }
        }
      }

      DetailView {
        width: parent.width
        topPadding: 0
        paneMode: true
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
}
