import QtQuick
import QtQuick.Controls
import qs.Commons
import "../lib/Store.js" as Store
import "../lib/Format.js" as Format

// Right side of the two-pane view: everything about the selected thread.
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
  readonly property color tone: hasRow ? (colors[Store.stateRole(row.state)] || colors.textDim) : colors.textDim
  readonly property color ink: hasRow ? (colors[Store.stateRole(row.state) + "Ink"] || colors.textDim) : colors.textDim

  // Nothing selected
  Column {
    visible: !root.hasRow
    anchors.centerIn: parent
    spacing: Style.space(8)
    LucideIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "activity"; color: root.colors.textFaint; size: Math.round(Style.font.display * 1.1) }
    Text {
      text: "Select a thread to see what it's doing"
      textFormat: Text.PlainText
      color: root.colors.textDim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
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
      spacing: Style.space(10)

      // Title line
      Item {
        width: parent.width
        height: Math.max(title.implicitHeight, glyph.height, timeCol.implicitHeight)
        StateGlyph {
          id: glyph
          y: Style.space(2)
          icon: root.hasRow ? Store.stateIcon(root.row) : "circle-dot"
          threadState: root.hasRow ? root.row.state : "idle"
          color: root.tone
          size: Math.round(Style.font.heading * 1.15)
          reduceMotion: root.reduceMotion
        }
        Text {
          id: title
          anchors.left: glyph.right
          anchors.leftMargin: Style.space(10)
          anchors.right: timeCol.left
          anchors.rightMargin: Style.space(12)
          text: root.hasRow ? root.row.title : ""
          textFormat: Text.PlainText
          color: root.colors.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.weight: Font.DemiBold
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }
        Column {
          id: timeCol
          anchors.right: parent.right
          spacing: Style.space(1)
          Text {
            anchors.right: parent.right
            text: root.hasRow ? Format.elapsed(root.row, root.now, Store.BUSY[root.row.state] === true) : ""
            textFormat: Text.PlainText
            color: root.colors.text
            font.family: root.monoFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.right: parent.right
            text: root.hasRow ? Store.stateLabel(root.row) : ""
            textFormat: Text.PlainText
            color: root.ink
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
          }
        }
      }

      // machine · project · branch · model · mode
      Text {
        x: glyph.width + Style.space(10)
        width: parent.width - x
        text: {
          if (!root.hasRow) return ""
          var parts = []
          if (root.machineLabel) parts.push(root.machineLabel)
          parts.push(root.row.project)
          if (root.row.branch) parts.push(root.row.branch + (root.row.worktree ? " (worktree)" : ""))
          if (root.row.model) parts.push(Format.model(root.row.model))
          if (root.row.mode) parts.push(root.row.mode)
          return parts.join("  ·  ")
        }
        textFormat: Text.PlainText
        color: root.colors.textFaint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      ThreadChips {
        x: glyph.width + Style.space(10)
        width: parent.width - x
        visible: root.hasRow && anyVisible
        row: root.hasRow ? root.row : ({})
        detail: root.detail
        colors: root.colors
        showContext: true
        showSubagentTotal: true
      }

      Rectangle { width: parent.width; height: 1; color: root.colors.line; opacity: 0.8 }

      DetailView {
        width: parent.width
        topPadding: 0
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
