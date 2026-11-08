import QtQuick
import qs.Commons
import "../lib/Format.js" as Format
import "../lib/Store.js" as Store

// Provider usage: "Claude 5h ▬ 38%  week ▬ 61%   Codex 5h ▬ 100% resets in 47m  week ▬ 82%".
// Each bar is labelled with its window. Ink meters (agents-panel style); amber near a limit, since
// a spent quota is a wait, not an error. Providers that report no usage are left out.
Flow {
  id: root

  property var environments: []
  property var colors: ({})
  property double now: Date.now()
  property string fontFamily: Style.font.family

  // Compact (the dropdown): short window names and meters, so both providers fit one row.
  property bool compact: false

  // Flow's spacing is both ways: keep the gap between wrapped rows small and put the wide gap
  // between items as padding on each item instead.
  spacing: Style.space(4)
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

  Repeater {
    model: root.metered
    Row {
      required property var modelData
      rightPadding: root.itemGap
      spacing: root.compact ? Style.space(6) : Style.space(8)
      Rectangle {
        visible: root.unhealthy(modelData)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(6); height: width; radius: width / 2
        color: root.colors.attention
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.name
        textFormat: Text.PlainText
        color: root.colors.text
        font.family: root.fontFamily
        font.pixelSize: Typo.caption
        font.weight: Font.Medium
      }
      Repeater {
        model: modelData.windows.slice(0, 3)
        Row {
          required property var modelData
          readonly property bool high: modelData.usedPercent >= 90
          // A window that's used up says so in words instead of drawing a full bar.
          readonly property bool spent: modelData.usedPercent >= 100
          spacing: root.compact ? Style.space(4) : Style.space(6)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: (root.compact ? Store.windowShort(modelData) : Store.windowLabel(modelData)) + (parent.spent ? ":" : "")
            textFormat: Text.PlainText
            color: root.colors.textFaint
            font.family: root.fontFamily
            font.pixelSize: Typo.caption
          }
          Meter {
            visible: !parent.spent
            anchors.verticalCenter: parent.verticalCenter
            width: root.compact ? Style.space(26) : Style.space(44)
            thickness: Style.space(3)
            value: modelData.usedPercent / 100
            ink: root.colors.text
            // A spent quota is a wait, not a warning: the bar stays ink and the words say when it resets.
            danger: root.colors.text
            track: root.colors.edge
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.spent ? (root.compact ? "full" + (modelData.resetsAt ? ", resets " + Format.until(modelData.resetsAt, root.now).replace("in ", "") : "")
              : "limit reached" + (modelData.resetsAt ? ", resets " + Format.until(modelData.resetsAt, root.now) : ""))
              : Math.round(modelData.usedPercent) + "%" + (parent.high && modelData.resetsAt ? " resets " + Format.until(modelData.resetsAt, root.now) : "")
            textFormat: Text.PlainText
            color: parent.high ? root.colors.text : root.colors.textFaint
            font.family: root.fontFamily
            font.pixelSize: Typo.caption
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
