import QtQuick
import qs.Commons
import "../lib/Format.js" as Format
import "../lib/Store.js" as Store

// Provider usage limits beside their heading, as one grid: a row per provider, a column per kind
// of window, the same columns for every row.
//   LIMITS USED  Claude  5-hour ▭ 38%                          weekly ▭ 61%   weekly · Fable ▭ 4%
//                Codex   5-hour ▮ limit reached, resets in 47m  weekly ▭ 82%
// The heading says which way the numbers count: they are the share of each limit used.
// Each column holds one kind of window (its label, meter and value) and is as wide as its widest
// entry on any row, so "weekly" starts at the same x for every provider and the meters line up. A
// provider without that kind leaves the cell empty. If the band is too narrow for every column,
// the last ones move to a second line of each provider's row, at the same column for all (see
// Store.usageLines). Ink meters; a spent window has a full meter and says so in words.
// Providers that report no usage are left out.
Row {
  id: root

  property var environments: []
  property var colors: ({})
  property double now: Date.now()
  property string fontFamily: Style.font.family

  // Compact (the dropdown): short window names ("5h", "week") and meters.
  property bool compact: false
  // The footer's bands share a heading column: the widest heading sets it for all of them.
  property real headingColumn: 0
  readonly property real headingWidth: heading.implicitWidth
  // Where the content starts, for the band under this one to line up with.
  readonly property real contentX: heading.visible ? heading.width + spacing : 0
  // The footer's rows share one pitch: a row's height (0: a line of text) and the gap between rows.
  property real rowHeight: 0
  property real rowGap: Style.space(4)
  readonly property real rowTall: rowHeight > 0 ? rowHeight : lineProbe.implicitHeight

  // The gap between columns; the legend under this band uses the same one.
  readonly property real itemGap: compact ? Style.space(12) : Style.space(22)

  // Providers repeat across machines when they share an account; show each once,
  // preferring the freshest usage reading.
  readonly property var providers: {
    var seen = {}
    var out = []
    for (var i = 0; i < environments.length; i++) {
      var env = environments[i]
      if (env.state !== "live" && env.state !== "polling") continue
      for (var j = 0; j < env.providers.length; j++) {
        var p = env.providers[j]
        var key = p.driver + ":" + p.name
        var prev = seen[key]
        if (prev !== undefined) {
          if ((p.checkedAt || 0) > (out[prev].checkedAt || 0)) out[prev] = p
          continue
        }
        seen[key] = out.length
        out.push(p)
      }
    }
    return out
  }
  readonly property var metered: providers.filter(function(p) { return p.windows.length > 0 })
  readonly property var plain: providers.filter(function(p) { return p.windows.length === 0 })
  readonly property bool hasMetered: metered.length > 0

  // The grid: which kinds of window there are, and each provider's window of each kind (or none).
  readonly property var grid: Store.usageGrid(metered, compact)
  // Each column's width: its widest cell on any row, measured from the cells themselves.
  readonly property var columnWidths: {
    var out = []
    for (var i = 0; i < probeColumns.count; i++) {
      var column = probeColumns.itemAt(i)
      out.push(column ? Math.ceil(column.implicitWidth) : 0)
    }
    return out
  }
  // Which columns share a line, and where each starts.
  readonly property var lines: Store.usageLines(columnWidths, body.width - names.implicitWidth - body.gap, itemGap)

  function unhealthy(p) { return p.status === "error" || p.auth === "unauthenticated" }

  spacing: itemGap

  // One window: its kind, a meter as long as the limit, and how much of it is used. A spent
  // window's meter is full and its words are full-weight ink. No colour: a limit is a wait, not
  // a failure.
  component UsageCell: Row {
    property var win: null
    property string label: ""
    readonly property bool spent: win !== null && win.usedPercent >= 100
    spacing: body.gap
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: parent.label
      textFormat: Text.PlainText
      color: root.colors.textFaint
      font.family: root.fontFamily
      font.pixelSize: Typo.caption
    }
    Meter {
      anchors.verticalCenter: parent.verticalCenter
      width: body.meterWidth
      value: parent.win ? parent.win.usedPercent / 100 : 0
      ink: root.colors.text
      danger: root.colors.text
      track: root.colors.edge
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: parent.win ? Store.windowValue(parent.win, root.now, root.compact) : ""
      textFormat: Text.PlainText
      color: parent.win && parent.win.usedPercent >= 90 ? root.colors.text : root.colors.textDim
      font.family: root.fontFamily
      font.pixelSize: Typo.caption
      font.weight: parent.spent ? Font.DemiBold : Font.Normal
    }
  }

  // What the bars are: how much of each provider's usage limit is used, per window.
  Text {
    id: heading
    visible: root.metered.length > 0
    width: Math.max(implicitWidth, root.headingColumn)
    topPadding: Math.max(0, Math.round((root.rowTall - lineProbe.implicitHeight) / 2))
    text: Store.USAGE_HEADING
    textFormat: Text.PlainText
    color: root.colors.textDim
    font.family: root.fontFamily
    font.pixelSize: Typo.caption
    font.bold: true
    font.letterSpacing: 1.2
  }

  Column {
    spacing: root.rowGap

    Item {
      id: body
      readonly property real gap: root.compact ? Style.space(6) : Style.space(8)
      // Long enough to read a share from: a quarter and a half are visibly different lengths.
      // (The dropdown's are shorter: three shared columns have to fit its width.)
      readonly property real meterWidth: root.compact ? Style.space(28) : Style.space(60)
      width: Math.max(0, root.width - (heading.visible ? heading.width + root.spacing : 0))
      height: blocks.implicitHeight

      // Measured, not shown (transparent rather than hidden, so they are laid out and have a
      // width): the names' column, and each kind's column with every provider's cell of that kind.
      Column {
        id: names
        opacity: 0
        Repeater {
          model: root.metered
          Text { required property var modelData; text: modelData.name; textFormat: Text.PlainText; font.family: root.fontFamily; font.pixelSize: Typo.caption; font.weight: Font.Medium }
        }
      }
      Row {
        opacity: 0
        enabled: false
        Repeater {
          id: probeColumns
          model: root.grid.columns
          Column {
            id: probeColumn
            required property string modelData
            required property int index
            Repeater {
              model: root.grid.rows
              UsageCell {
                required property var modelData
                readonly property var cell: modelData.cells[probeColumn.index] || null
                visible: cell !== null
                win: cell ? cell.window : null
                label: probeColumn.modelData
              }
            }
          }
        }
      }
      Text { id: lineProbe; visible: false; text: "Ag"; textFormat: Text.PlainText; font.family: root.fontFamily; font.pixelSize: Typo.caption }

      Column {
        id: blocks
        width: body.width
        spacing: root.rowGap
        Repeater {
          model: root.grid.rows
          Item {
            id: block
            required property var modelData
            width: blocks.width
            height: Math.max(root.rowTall, lineColumn.implicitHeight)
            Item {
              height: root.rowTall
              width: nameText.implicitWidth
              Text {
                id: nameText
                objectName: "block:" + block.modelData.name + ":name"
                anchors.verticalCenter: parent.verticalCenter
                text: block.modelData.name
                textFormat: Text.PlainText
                color: root.colors.text
                font.family: root.fontFamily
                font.pixelSize: Typo.caption
                font.weight: Font.Medium
              }
            }
            Column {
              id: lineColumn
              x: names.implicitWidth + body.gap
              spacing: root.rowGap
              Repeater {
                model: root.lines
                Item {
                  id: line
                  required property var modelData
                  // A line this provider has nothing on isn't drawn, so its row stays one line tall.
                  visible: {
                    for (var i = 0; i < modelData.length; i++) if (block.modelData.cells[modelData[i].column]) return true
                    return false
                  }
                  width: block.width - lineColumn.x
                  height: root.rowTall
                  Repeater {
                    model: line.modelData
                    UsageCell {
                      required property var modelData
                      readonly property var cell: block.modelData.cells[modelData.column] || null
                      // For tests: which provider's window this is, and of which kind.
                      readonly property string kind: root.grid.columns[modelData.column] || ""
                      objectName: cell ? "block:" + block.modelData.name + ":" + cell.index : ""
                      visible: cell !== null
                      x: modelData.x
                      anchors.verticalCenter: parent.verticalCenter
                      win: cell ? cell.window : null
                      label: kind
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // Providers with no usage data are only worth a word when something is wrong with them.
    Text {
      readonly property var broken: root.plain.filter(function(p) { return root.unhealthy(p) })
      visible: broken.length > 0
      text: broken.map(function(p) { return p.name + " needs attention" }).join("  ·  ")
      textFormat: Text.PlainText
      color: root.colors.attentionInk
      font.family: root.fontFamily
      font.pixelSize: Typo.caption
    }
  }
}
