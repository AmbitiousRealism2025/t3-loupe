import QtQuick
import qs.Commons
import "../lib/Format.js" as Format

// Provider usage on one line each: "Claude ▬ 38% ▬ 61%   Codex ▬ 100% · 47m ▬ 82%".
// Ink meters (agents-panel style); attention only near a limit. Providers without
// usage windows collapse into a quiet trailing list.
Flow {
  id: root

  property var environments: []
  property var colors: ({})
  property double now: Date.now()
  property string fontFamily: Style.font.family

  spacing: Style.space(22)

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

  Repeater {
    model: root.metered
    Row {
      required property var modelData
      spacing: Style.space(8)
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
        color: root.colors.textDim
        font.family: root.fontFamily
        font.pixelSize: Typo.caption
      }
      Repeater {
        model: modelData.windows.slice(0, 3)
        Row {
          required property var modelData
          readonly property bool high: modelData.usedPercent >= 90
          spacing: Style.space(6)
          Meter {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(54)
            thickness: Style.space(3)
            value: modelData.usedPercent / 100
            ink: root.colors.text
            danger: root.colors.attention
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(modelData.usedPercent) + "%" + (parent.high && modelData.resetsAt ? " · " + Format.until(modelData.resetsAt, root.now).replace("in ", "") : "")
            textFormat: Text.PlainText
            color: parent.high ? root.colors.attentionInk : root.colors.textFaint
            font.family: root.fontFamily
            font.pixelSize: Typo.caption
          }
        }
      }
    }
  }

  Text {
    visible: root.plain.length > 0
    text: root.plain.map(function(p) { return (root.unhealthy(p) ? "! " : "") + p.name }).join("  ·  ")
    textFormat: Text.PlainText
    color: root.colors.textFaint
    font.family: root.fontFamily
    font.pixelSize: Typo.caption
  }
}
