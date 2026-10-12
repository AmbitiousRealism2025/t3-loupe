import QtQuick
import qs.Commons
import qs.Ui
import "../lib/Store.js" as Store
import "../lib/Format.js" as Format

// Expanded thread detail. Data arrives lazily from a live thread subscription.
Column {
  id: root

  property var row: ({})
  property var detail: null
  property var colors: ({})
  property double now: Date.now()
  property string fontFamily: Style.font.family
  property string monoFamily: "monospace"

  signal actionRequested(string action)

  spacing: Style.space(10)
  topPadding: Style.space(6)

  readonly property bool loading: detail === null
  readonly property var runs: detail ? detail.runs : []
  readonly property real longestRun: {
    var m = 1
    for (var i = 0; i < runs.length; i++) {
      var d = runs[i].durationMs !== null ? runs[i].durationMs : (runs[i].startedAt ? now - runs[i].startedAt : 0)
      if (d > m) m = d
    }
    return m
  }

  component ActionButton: Button {
    foreground: root.colors.text
    accent: root.colors.accent
    bordered: true
    fontFamily: root.fontFamily
    fontSize: Style.font.caption
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.colors.textFaint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.6
  }

  Text {
    visible: root.loading
    text: "Loading thread…"
    textFormat: Text.PlainText
    color: root.colors.textFaint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  // Pending approval / question, with the actual text.
  Repeater {
    model: root.detail ? root.detail.pending : []
    Rectangle {
      required property var modelData
      width: root.width
      height: pend.implicitHeight + Style.space(16)
      radius: Style.cornerRadius
      color: Qt.rgba(root.colors.attention.r, root.colors.attention.g, root.colors.attention.b, 0.08)
      border.width: 1
      border.color: Qt.rgba(root.colors.attention.r, root.colors.attention.g, root.colors.attention.b, 0.45)

      Column {
        id: pend
        x: Style.space(10)
        y: Style.space(8)
        width: parent.width - Style.space(20)
        spacing: Style.space(6)

        Row {
          spacing: Style.space(6)
          LucideIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: Store.pendingInfo(modelData.kind).icon
            color: root.colors.attentionInk
            size: Math.round(Style.font.body * 1.1)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Store.pendingInfo(modelData.kind).label + (modelData.appName ? "  ·  " + modelData.appName : "")
              + (modelData.since ? "  ·  waiting " + Format.duration(root.now - modelData.since) : "")
            textFormat: Text.PlainText
            color: root.colors.attentionInk
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold
          }
        }

        Rectangle {
          visible: modelData.prompt !== ""
          width: parent.width
          height: promptText.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: root.colors.background
          Text {
            id: promptText
            x: Style.space(8)
            y: Style.space(6)
            width: parent.width - Style.space(16)
            text: modelData.prompt
            textFormat: Text.PlainText
            color: root.colors.text
            font.family: modelData.kind === "command" ? root.monoFamily : root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 10
            elide: Text.ElideRight
          }
        }

        Repeater {
          model: modelData.questions
          Column {
            required property var modelData
            width: pend.width
            spacing: Style.space(3)
            Text {
              width: parent.width
              text: (modelData.header ? modelData.header + ": " : "") + modelData.question
              textFormat: Text.PlainText
              color: root.colors.text
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }
            Flow {
              width: parent.width
              spacing: Style.space(4)
              Repeater {
                model: modelData.options
                Chip { required property var modelData; text: modelData; tone: root.colors.textFaint; ink: root.colors.textDim; outlined: true }
              }
            }
          }
        }

        Flow {
          visible: modelData.options.length > 0
          width: parent.width
          spacing: Style.space(4)
          Repeater {
            model: modelData.options
            Chip { required property var modelData; text: modelData; tone: root.colors.textFaint; ink: root.colors.textDim; outlined: true }
          }
        }

        Text {
          text: "Answer in T3 — this monitor is read-only."
          textFormat: Text.PlainText
          color: root.colors.textFaint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.italic: true
        }
      }
    }
  }

  // Activity trail, newest last — same icons as T3's timeline.
  Column {
    visible: root.detail !== null && root.detail.activity.length > 0
    width: root.width
    spacing: Style.space(4)
    Caption { text: "Activity" }
    Repeater {
      model: root.detail ? root.detail.activity : []
      Row {
        required property var modelData
        required property int index
        width: root.width
        spacing: Style.space(7)
        readonly property bool live: modelData.status === "running" || modelData.status === "pending"
        LucideIcon {
          id: aIcon
          anchors.verticalCenter: parent.verticalCenter
          name: modelData.icon
          color: parent.live ? root.colors.accentInk : modelData.status === "failed" ? root.colors.attentionInk : root.colors.textFaint
          size: Math.round(Style.font.body * 1.05)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - aIcon.width - aTime.implicitWidth - Style.space(14)
          text: modelData.label
          textFormat: Text.PlainText
          color: parent.live ? root.colors.text : root.colors.textDim
          font.family: modelData.icon === "terminal" ? root.monoFamily : root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
        Text {
          id: aTime
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.status === "pending" ? "waiting" : parent.live ? "running" : Format.ago(modelData.at, root.now)
          textFormat: Text.PlainText
          color: parent.live ? root.colors.accentInk : root.colors.textFaint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // Plan progress (todo list)
  Column {
    visible: root.detail !== null && root.detail.todo !== null
    width: root.width
    spacing: Style.space(4)
    Caption { text: root.detail && root.detail.todo ? "Plan  " + root.detail.todo.done + " / " + root.detail.todo.total : "" }
    Meter {
      width: parent.width
      value: root.detail && root.detail.todo && root.detail.todo.total ? root.detail.todo.done / root.detail.todo.total : 0
      track: root.colors.track
      fill: root.colors.success
    }
    Text {
      visible: text !== ""
      width: parent.width
      text: root.detail && root.detail.todo ? root.detail.todo.current : ""
      textFormat: Text.PlainText
      color: root.colors.textDim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  // Runs + context side by side
  Row {
    visible: root.detail !== null && (root.runs.length > 0 || root.detail.context !== null)
    width: root.width
    spacing: Style.space(16)

    Column {
      visible: root.runs.length > 0
      width: (parent.width - Style.space(16)) / 2
      spacing: Style.space(4)
      Caption { text: "Runs" }
      Row {
        height: Style.space(26)
        spacing: Style.space(2)
        Repeater {
          model: root.runs
          Rectangle {
            required property var modelData
            readonly property real dur: modelData.durationMs !== null ? modelData.durationMs : (modelData.startedAt ? root.now - modelData.startedAt : 0)
            anchors.bottom: parent.bottom
            width: Style.space(7)
            height: Math.max(Style.space(2), Style.space(26) * Math.sqrt(dur / root.longestRun))
            radius: Math.min(Style.cornerRadius, 1)
            color: modelData.status === "failed" ? root.colors.attention
              : modelData.status === "running" || modelData.status === "starting" ? root.colors.accent
              : modelData.status === "completed" ? root.colors.success : root.colors.textFaint
            opacity: modelData.status === "completed" ? 0.75 : 1
          }
        }
      }
      Text {
        readonly property var last: root.runs.length ? root.runs[root.runs.length - 1] : null
        text: last ? (last.durationMs !== null ? "last " + Format.duration(last.durationMs) : "running " + Format.duration(root.now - (last.startedAt || root.now))) + "  ·  " + root.runs.length + " runs" : ""
        textFormat: Text.PlainText
        color: root.colors.textDim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      visible: root.detail !== null && root.detail.context !== null && root.detail.context.max > 0
      width: (parent.width - Style.space(16)) / 2
      spacing: Style.space(4)
      readonly property var ctx: root.detail ? root.detail.context : null
      Caption { text: "Context" }
      Item { width: 1; height: Style.space(26) - Style.space(5) }
      Meter {
        width: parent.width
        value: parent.ctx && parent.ctx.max ? parent.ctx.used / parent.ctx.max : 0
        track: root.colors.track
        fill: root.colors.info
        warning: root.colors.warning
        danger: root.colors.attention
      }
      Text {
        readonly property var ctx: parent.ctx
        text: ctx ? Format.tokens(ctx.used) + " / " + Format.tokens(ctx.max) + "  ·  " + Math.round(ctx.used / ctx.max * 100) + "%"
          + (ctx.cost !== null ? "  ·  " + Format.money(ctx.cost, ctx.currency) : "") : ""
        textFormat: Text.PlainText
        color: root.colors.textDim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // Subagents
  Column {
    visible: root.detail !== null && root.detail.subagents.length > 0
    width: root.width
    spacing: Style.space(4)
    Caption { text: "Subagents" }
    Repeater {
      model: root.detail ? root.detail.subagents : []
      Row {
        required property var modelData
        width: root.width
        spacing: Style.space(7)
        readonly property string st: modelData.status
        readonly property bool live: st === "running" || st === "pending" || st === "waiting"
        StateGlyph {
          id: sGlyph
          anchors.verticalCenter: parent.verticalCenter
          icon: parent.live ? "loader-circle" : parent.st === "completed" ? "circle-check" : parent.st === "failed" ? "circle-x" : "circle-dot"
          threadState: parent.live ? "working" : "idle"
          color: parent.live ? root.colors.subagentInk : parent.st === "failed" ? root.colors.attentionInk : parent.st === "completed" ? root.colors.successInk : root.colors.textFaint
          size: Math.round(Style.font.body * 1.0)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - sGlyph.width - sMeta.implicitWidth - Style.space(14)
          text: modelData.title + (modelData.progress ? "  —  " + modelData.progress : "")
          textFormat: Text.PlainText
          color: parent.live ? root.colors.text : root.colors.textDim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
        Text {
          id: sMeta
          anchors.verticalCenter: parent.verticalCenter
          text: Format.model(modelData.model) + (modelData.completedAt && modelData.startedAt ? "  " + Format.duration(modelData.completedAt - modelData.startedAt)
            : modelData.startedAt && parent.live ? "  " + Format.duration(root.now - modelData.startedAt) : "")
          textFormat: Text.PlainText
          color: root.colors.textFaint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // Error text for failed / limited threads
  Text {
    visible: root.row.error !== ""
    width: root.width
    text: root.row.error
    textFormat: Text.PlainText
    color: root.colors.attentionInk
    font.family: root.monoFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
    maximumLineCount: 5
    elide: Text.ElideRight
  }

  // PR title when present
  Text {
    visible: root.row.pr !== null && root.row.pr !== undefined
    width: root.width
    text: root.row.pr ? "PR #" + root.row.pr.number + "  " + root.row.pr.title + (root.row.prCount > 1 ? "  (+" + (root.row.prCount - 1) + " more)" : "") : ""
    textFormat: Text.PlainText
    color: root.colors.textDim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  Row {
    spacing: Style.space(6)
    ActionButton { text: "Focus T3"; onClicked: root.actionRequested("focus") }
    ActionButton {
      visible: root.row.pr !== null && root.row.pr !== undefined && root.row.pr.url !== ""
      text: "Open PR"
      onClicked: root.actionRequested("pr")
    }
    ActionButton { text: "Copy title"; onClicked: root.actionRequested("copy") }
  }
}
