import QtQuick
import qs.Commons
import "../lib/Format.js" as Format
import "../lib/Store.js" as Store

// Provider usage limits beside their heading, one provider per row, whatever its number of windows:
//   USAGE LIMITS  Claude  5-hour ▬ 95% resets in 1h   weekly ▬ 55%   weekly · Fable ▬ 0%
//                 Codex   5-hour ▬ 49%                weekly ▬ 30%
// As an aligned table (windows in shared columns) when that fits the width; otherwise each
// provider is a block whose windows flow onto further lines inside it, never into another
// provider's. Ink meters (agents-panel style); a spent window says so in words. Providers that
// report no usage are left out.
Row {
  id: root

  property var environments: []
  property var colors: ({})
  property double now: Date.now()
  property string fontFamily: Style.font.family

  // Compact (the dropdown): short window names ("5h", "week") and meters.
  property bool compact: false

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

  function unhealthy(p) { return p.status === "error" || p.auth === "unauthenticated" }

  spacing: itemGap

  // What the bars are: how much of each provider's usage limit is used, per window.
  Text {
    id: heading
    visible: root.metered.length > 0
    text: root.compact ? "LIMITS" : "USAGE LIMITS"
    textFormat: Text.PlainText
    color: root.colors.textDim
    font.family: root.fontFamily
    font.pixelSize: Typo.caption
    font.bold: true
    font.letterSpacing: 1.2
  }

  Column {
    spacing: Style.space(4)

    Item {
      id: body
      readonly property real gap: root.compact ? Style.space(6) : Style.space(8)
      readonly property real meterWidth: root.compact ? Style.space(26) : Style.space(44)
      readonly property var table: Store.usageTable(root.metered, root.now, root.compact)
      // The table when it fits; otherwise the blocks. Both stay laid out (the inactive one is
      // transparent, not hidden) so the table's width can be measured either way.
      readonly property bool fits: grid.implicitWidth <= width
      width: Math.max(0, root.width - (heading.visible ? heading.width + root.spacing : 0))
      height: fits ? grid.implicitHeight : blocks.implicitHeight

      Grid {
        id: grid
        opacity: body.fits ? 1 : 0
        enabled: body.fits
        columns: body.table.columns
        columnSpacing: body.gap
        rowSpacing: Style.space(4)
        verticalItemAlignment: Grid.AlignVCenter
        Repeater {
          model: body.table.cells
          Item {
            required property var modelData
            readonly property var cell: modelData
            objectName: "cell:" + cell.provider + ":" + (cell.kind === "name" ? "name" : cell.index + ":" + cell.kind)
            // A blank keeps a width: positioners skip zero-size items, which shifts the rows.
            width: cell.kind === "blank" ? 1 : cell.kind === "meter" ? body.meterWidth
              : cellText.implicitWidth + (dot.visible ? dot.width + Style.space(6) : 0)
            height: Math.max(cellText.implicitHeight, Style.space(3))
            Rectangle {
              id: dot
              visible: cell.kind === "name" && cell.unhealthy === true
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(6); height: width; radius: width / 2
              color: root.colors.attention
            }
            Text {
              id: cellText
              visible: cell.kind !== "meter"
              x: dot.visible ? dot.width + Style.space(6) : 0
              anchors.verticalCenter: parent.verticalCenter
              rightPadding: cell.kind === "value" ? Style.space(root.compact ? 6 : 10) : 0
              text: cell.text || ""
              textFormat: Text.PlainText
              color: cell.kind === "name" ? root.colors.text : cell.kind === "label" ? root.colors.textFaint
                : cell.high ? root.colors.text : root.colors.textFaint
              font.family: root.fontFamily
              font.pixelSize: Typo.caption
              font.weight: cell.kind === "name" ? Font.Medium : Font.Normal
            }
            Meter {
              visible: cell.kind === "meter" && !cell.spent
              anchors.verticalCenter: parent.verticalCenter
              width: body.meterWidth
              thickness: Style.space(3)
              value: cell.value || 0
              ink: root.colors.text
              // A spent quota is a wait, not a warning: the bar stays ink and the words say when it resets.
              danger: root.colors.text
              track: root.colors.edge
            }
          }
        }
      }

      // The names' column width, measured from the names themselves.
      Column {
        id: names
        opacity: 0
        Repeater {
          model: root.metered
          Text { required property var modelData; text: modelData.name; font.family: root.fontFamily; font.pixelSize: Typo.caption; font.weight: Font.Medium }
        }
      }

      Column {
        id: blocks
        opacity: body.fits ? 0 : 1
        enabled: !body.fits
        width: body.width
        spacing: Style.space(4)
        Repeater {
          model: root.metered
          Item {
            id: block
            required property var modelData
            readonly property var labels: Store.windowLabels(modelData.windows, root.compact)
            width: blocks.width
            height: Math.max(nameText.implicitHeight, windows.implicitHeight)
            Text {
              id: nameText
              objectName: "block:" + block.modelData.name + ":name"
              text: block.modelData.name
              textFormat: Text.PlainText
              color: root.colors.text
              font.family: root.fontFamily
              font.pixelSize: Typo.caption
              font.weight: Font.Medium
            }
            Flow {
              id: windows
              x: names.implicitWidth + body.gap
              width: block.width - x
              spacing: Style.space(4)
              Repeater {
                model: block.modelData.windows
                Row {
                  required property var modelData
                  required property int index
                  readonly property bool spent: modelData.usedPercent >= 100
                  objectName: "block:" + block.modelData.name + ":" + index
                  spacing: body.gap
                  rightPadding: root.itemGap
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: block.labels[parent.index] + (parent.spent ? ":" : "")
                    textFormat: Text.PlainText
                    color: root.colors.textFaint
                    font.family: root.fontFamily
                    font.pixelSize: Typo.caption
                  }
                  Meter {
                    visible: !parent.spent
                    anchors.verticalCenter: parent.verticalCenter
                    width: body.meterWidth
                    thickness: Style.space(3)
                    value: modelData.usedPercent / 100
                    ink: root.colors.text
                    danger: root.colors.text
                    track: root.colors.edge
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Store.windowValue(modelData, root.now, root.compact)
                    textFormat: Text.PlainText
                    color: modelData.usedPercent >= 90 ? root.colors.text : root.colors.textFaint
                    font.family: root.fontFamily
                    font.pixelSize: Typo.caption
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
