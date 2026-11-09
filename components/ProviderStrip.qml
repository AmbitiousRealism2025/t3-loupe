import QtQuick
import qs.Commons
import "../lib/Format.js" as Format
import "../lib/Store.js" as Store

// Provider usage limits beside their heading, one provider per row, whatever its number of windows:
//   LIMITS USED  Claude  5-hour ▭ 95% resets in 1h   weekly ▭ 55%   weekly · Fable ▭ 0%
//                Codex   5-hour ◔ limit reached, resets in 47m   weekly ▭ 30%
// The heading says which way the numbers count: they are the share of each limit used.
// Names share a column; each provider's windows sit side by side at their own widths (label,
// meter, value, then the next), so one long value never widens another provider's row. A row
// that's too long wraps inside its provider, never into another's. Ink meters (agents-panel
// style); a spent window says so in words, with the usage-limit gauge, in place of its meter and
// value. Providers that report no usage are left out.
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
    width: Math.max(implicitWidth, root.headingColumn)
    text: Store.USAGE_HEADING
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
      // Long enough to read a share from: a quarter and a half are visibly different lengths.
      readonly property real meterWidth: root.compact ? Style.space(32) : Style.space(60)
      width: Math.max(0, root.width - (heading.visible ? heading.width + root.spacing : 0))
      height: blocks.implicitHeight

      // The names' column width, measured from the names themselves (transparent, not hidden, so
      // it's laid out and has a width).
      Column {
        id: names
        opacity: 0
        Repeater {
          model: root.metered
          Text { required property var modelData; text: modelData.name; textFormat: Text.PlainText; font.family: root.fontFamily; font.pixelSize: Typo.caption; font.weight: Font.Medium }
        }
      }

      Column {
        id: blocks
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
                    text: block.labels[parent.index]
                    textFormat: Text.PlainText
                    color: root.colors.textFaint
                    font.family: root.fontFamily
                    font.pixelSize: Typo.caption
                  }
                  Meter {
                    visible: !parent.spent
                    anchors.verticalCenter: parent.verticalCenter
                    width: body.meterWidth
                    value: modelData.usedPercent / 100
                    ink: root.colors.text
                    danger: root.colors.text
                    track: root.colors.edge
                  }
                  // A spent window: the gauge that marks a usage-limited thread, and full-weight ink.
                  // No colour: a limit is a wait, not a failure.
                  LucideIcon {
                    visible: parent.spent
                    anchors.verticalCenter: parent.verticalCenter
                    name: "gauge"
                    color: root.colors.text
                    size: Math.round(Typo.caption * 1.15)
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Store.windowValue(modelData, root.now, root.compact)
                    textFormat: Text.PlainText
                    color: modelData.usedPercent >= 90 ? root.colors.text : root.colors.textDim
                    font.family: root.fontFamily
                    font.pixelSize: Typo.caption
                    font.weight: parent.spent ? Font.DemiBold : Font.Normal
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
