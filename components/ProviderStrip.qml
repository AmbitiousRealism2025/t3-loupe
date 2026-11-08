import QtQuick
import qs.Commons
import "../lib/Format.js" as Format
import "../lib/Store.js" as Store

// Provider usage limits as a small table beside its heading:
//   USAGE LIMITS  Claude  5-hour  ▬  38%   weekly  ▬  61%
//                 Codex   5-hour:    limit reached, resets in 47m   weekly  ▬  82%
// Ink meters (agents-panel style); a spent window says so in words. Providers that report no
// usage are left out.
Row {
  id: root

  property var environments: []
  property var colors: ({})
  property double now: Date.now()
  property string fontFamily: Style.font.family

  // Compact (the dropdown): short window names and meters, so both providers fit one row.
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

  // What the bars are: how much of each provider's usage limit is used, per window.
  Text {
    visible: root.metered.length > 0
    rightPadding: root.itemGap
    text: root.compact ? "LIMITS" : "USAGE LIMITS"
    textFormat: Text.PlainText
    color: root.colors.textDim
    font.family: root.fontFamily
    font.pixelSize: Typo.caption
    font.bold: true
    font.letterSpacing: 1.2
  }

  // A small table: one row per provider, its name in the first column, then each window's label,
  // meter and value in columns of their own, so names and meters line up down the rows.
  Column {
    spacing: Style.space(4)
    Grid {
      id: table
      readonly property var model: Store.usageTable(root.metered, root.now, root.compact)
      columns: model.columns
      columnSpacing: root.compact ? Style.space(6) : Style.space(8)
      rowSpacing: Style.space(4)
      verticalItemAlignment: Grid.AlignVCenter
      Repeater {
        model: table.model.cells
        Item {
          required property var modelData
          readonly property var cell: modelData
          implicitWidth: cell.kind === "meter" ? meter.width : cellText.implicitWidth + (dot.visible ? dot.width + Style.space(6) : 0)
          implicitHeight: Math.max(cellText.implicitHeight, meter.height)
          width: implicitWidth
          height: implicitHeight
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
            // Values sit a little away from the next window's label.
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
            id: meter
            // A window that's used up says so in words instead of drawing a full bar.
            visible: cell.kind === "meter" && !cell.spent
            anchors.verticalCenter: parent.verticalCenter
            width: cell.kind === "meter" ? (root.compact ? Style.space(26) : Style.space(44)) : 0
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
