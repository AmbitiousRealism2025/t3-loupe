import QtQuick
import qs.Commons
import "../lib/Format.js" as Format

// Provider health and usage-limit windows, per connected machine.
Column {
  id: root

  property var environments: []
  property var colors: ({})
  property double now: Date.now()
  property string fontFamily: Style.font.family

  spacing: Style.space(6)

  // Providers repeat across machines when they share an account; show each
  // provider once, preferring the freshest usage reading.
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
    out.sort(function(a, b) { return (b.windows.length > 0) - (a.windows.length > 0) })
    return out
  }
  readonly property var metered: providers.filter(function(p) { return p.windows.length > 0 })
  readonly property var plain: providers.filter(function(p) { return p.windows.length === 0 })

  function statusColor(p) {
    if (p.status === "error" || p.auth === "unauthenticated") return colors.attention
    if (p.status === "warning") return colors.warning
    return colors.success
  }

  Repeater {
    model: root.metered
    Item {
      required property var modelData
      width: root.width
      height: Math.max(nameText.implicitHeight, windows.implicitHeight)

      Row {
        id: nameRow
        spacing: Style.space(6)
        width: Style.space(96)
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(6); height: width; radius: width / 2
          color: root.statusColor(modelData)
        }
        Text {
          id: nameText
          width: nameRow.width - Style.space(12)
          text: modelData.name
          textFormat: Text.PlainText
          color: root.colors.textDim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.weight: Font.Medium
          elide: Text.ElideRight
        }
      }

      Row {
        id: windows
        anchors.left: nameRow.right
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(12)
        Repeater {
          model: modelData.windows.slice(0, 3)
          Column {
            required property var modelData
            width: (windows.width - Style.space(12) * 2) / 3
            spacing: Style.space(3)
            Item {
              width: parent.width
              height: wLabel.implicitHeight
              Text {
                id: wLabel
                text: modelData.label
                textFormat: Text.PlainText
                color: root.colors.textFaint
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width - wPct.implicitWidth - Style.space(4)
              }
              Text {
                id: wPct
                anchors.right: parent.right
                text: Math.round(modelData.usedPercent) + "%" + (modelData.resetsAt && modelData.usedPercent >= 50 ? " · " + Format.until(modelData.resetsAt, root.now).replace("in ", "") : "")
                textFormat: Text.PlainText
                color: modelData.usedPercent >= 90 ? root.colors.attentionInk : modelData.usedPercent >= 75 ? root.colors.warningInk : root.colors.textDim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.features: { "tnum": 1 }
              }
            }
            Meter {
              width: parent.width
              value: modelData.usedPercent / 100
              track: root.colors.track
              fill: root.colors.accent
              warning: root.colors.warning
              danger: root.colors.attention
              thickness: Style.space(3)
            }
          }
        }
      }
    }
  }

  // Providers without usage windows: one quiet line of status dots.
  Flow {
    visible: root.plain.length > 0
    width: root.width
    spacing: Style.space(10)
    Repeater {
      model: root.plain
      Row {
        required property var modelData
        spacing: Style.space(5)
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(6); height: width; radius: width / 2
          color: root.statusColor(modelData)
        }
        Text {
          text: modelData.name
          textFormat: Text.PlainText
          color: root.colors.textFaint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
