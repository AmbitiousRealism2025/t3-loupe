import QtQuick
import qs.Commons
import qs.Ui
import "../lib/Store.js" as Store
import "../lib/Format.js" as Format

// Thread detail. Data arrives lazily from a live thread subscription.
// paneMode (two-pane window): the header above already shows context, PR and actions,
// so this view leaves them out and pairs plan steps with the runs chart.
Column {
  id: root

  property var row: ({})
  property var detail: null
  property var colors: ({})
  property double now: Date.now()
  property bool paneMode: false
  property string fontFamily: Style.font.family
  property string monoFamily: "monospace"

  signal actionRequested(string action)

  spacing: Style.space(12)
  topPadding: Style.space(6)

  readonly property bool loading: detail === null
  readonly property var runs: detail ? detail.runs : []
  function runDuration(r) { return r.durationMs !== null ? r.durationMs : (r.startedAt ? now - r.startedAt : 0) }
  readonly property real longestRun: {
    var m = 1
    for (var i = 0; i < runs.length; i++) m = Math.max(m, runDuration(runs[i]))
    return m
  }
  readonly property int failedRuns: runs.filter(function(r) { return r.status === "failed" }).length
  readonly property var ctx: detail && detail.context && detail.context.max > 0 ? detail.context : null
  readonly property var todo: detail ? detail.todo : null

  component ActionButton: Button {
    foreground: root.colors.text
    accent: root.colors.accent
    bordered: true
    fontFamily: root.fontFamily
    fontSize: Typo.caption
  }

  component Caption: SectionCaption {
    foreground: root.colors.text
    countColor: root.colors.textFaint
    fontFamily: root.fontFamily
  }

  component Note: Text {
    textFormat: Text.PlainText
    color: root.colors.textFaint
    font.family: root.fontFamily
    font.pixelSize: Typo.caption
    elide: Text.ElideRight
  }

  Note {
    visible: root.loading
    text: "Loading thread…"
  }

  // Pending approval / question, with the actual text. The alarm exception: attention tint.
  Repeater {
    model: root.detail ? root.detail.pending : []
    Rectangle {
      required property var modelData
      width: root.width
      height: pend.implicitHeight + Style.space(18)
      radius: Style.cornerRadius
      color: Qt.rgba(root.colors.attention.r, root.colors.attention.g, root.colors.attention.b, 0.07)

      Rectangle { width: Style.space(2); height: parent.height; color: root.colors.attention }

      Column {
        id: pend
        x: Style.space(14)
        y: Style.space(9)
        width: parent.width - Style.space(24)
        spacing: Style.space(7)

        Row {
          spacing: Style.space(7)
          LucideIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: Store.pendingInfo(modelData.kind).icon
            color: root.colors.attentionInk
            size: Math.round(Typo.body * 1.1)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Store.pendingInfo(modelData.kind).label + (modelData.appName ? "  ·  " + modelData.appName : "")
            textFormat: Text.PlainText
            color: root.colors.attentionInk
            font.family: root.fontFamily
            font.pixelSize: Typo.bodySmall
            font.weight: Font.DemiBold
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!modelData.since
            text: "waiting " + Format.duration(root.now - modelData.since)
            textFormat: Text.PlainText
            color: root.colors.textDim
            font.family: root.fontFamily
            font.pixelSize: Typo.caption
          }
        }

        Rectangle {
          visible: modelData.prompt !== ""
          width: parent.width
          height: promptText.implicitHeight + Style.space(14)
          radius: Style.cornerRadius
          color: root.colors.background
          Text {
            id: promptText
            x: Style.space(10)
            y: Style.space(7)
            width: parent.width - Style.space(20)
            text: modelData.prompt
            textFormat: Text.PlainText
            color: root.colors.text
            font.family: modelData.kind === "command" ? root.monoFamily : root.fontFamily
            font.pixelSize: Typo.bodySmall
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
            spacing: Style.space(4)
            Text {
              width: parent.width
              text: (modelData.header ? modelData.header + ": " : "") + modelData.question
              textFormat: Text.PlainText
              color: root.colors.text
              font.family: root.fontFamily
              font.pixelSize: Typo.bodySmall
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

        Note { text: "Answer in T3 — Loupe is read-only."; font.italic: true }
      }
    }
  }

  // Activity trail, newest last — T3's timeline icons. Live steps get a dot and "now".
  Column {
    visible: root.detail !== null && root.detail.activity.length > 0
    width: root.width
    spacing: Style.space(5)
    Caption { label: "Activity" }
    Repeater {
      model: root.detail ? root.detail.activity : []
      Item {
        required property var modelData
        readonly property bool live: modelData.status === "running" || modelData.status === "pending"
        width: root.width
        height: Math.max(aText.implicitHeight, aIcon.height) + Style.space(2)
        LucideIcon {
          id: aIcon
          anchors.verticalCenter: parent.verticalCenter
          name: modelData.icon
          color: parent.live ? root.colors.accentInk : modelData.status === "failed" ? root.colors.attentionInk : root.colors.textFaint
          size: Math.round(Typo.body * 1.05)
        }
        Text {
          id: aText
          anchors.left: aIcon.right
          anchors.leftMargin: Style.space(9)
          anchors.right: aWhen.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.label
          textFormat: Text.PlainText
          color: parent.live ? root.colors.text : root.colors.textDim
          font.family: modelData.icon === "terminal" ? root.monoFamily : root.fontFamily
          font.pixelSize: Typo.caption
          elide: Text.ElideRight
        }
        Row {
          id: aWhen
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(5)
          Rectangle {
            visible: parent.parent.live
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(6); height: width; radius: width / 2
            color: modelData.status === "pending" ? root.colors.attention : root.colors.accent
          }
          Text {
            text: modelData.status === "pending" ? "waiting" : parent.parent.live ? "now" : Format.ago(modelData.at, root.now).replace(" ago", "")
            textFormat: Text.PlainText
            color: root.colors.textFaint
            font.family: root.fontFamily
            font.pixelSize: Typo.caption
          }
        }
      }
    }
  }

  // Plan steps and runs, side by side.
  Row {
    visible: root.todo !== null || root.runs.length > 0 || (!root.paneMode && root.ctx !== null)
    width: root.width
    spacing: Style.space(24)
    readonly property real colWidth: (width - spacing) / 2

    // Plan: one segment per step (the step is the unit), current step in accent.
    Column {
      visible: root.todo !== null
      width: parent.colWidth
      spacing: Style.space(6)
      Caption { label: "Plan"; count: -1 }
      Row {
        id: steps
        width: parent.width
        height: Style.space(6)
        spacing: Style.space(3)
        readonly property int total: root.todo ? Math.min(root.todo.total, 24) : 0
        Repeater {
          model: steps.total
          Rectangle {
            required property int index
            readonly property bool done: root.todo && index < root.todo.done
            readonly property bool current: root.todo && index === root.todo.done
            width: (steps.width - steps.spacing * (steps.total - 1)) / Math.max(1, steps.total)
            height: steps.height
            radius: Style.cornerRadius > 0 ? 1 : 0
            color: current ? root.colors.accent : done ? root.colors.text : Qt.rgba(root.colors.text.r, root.colors.text.g, root.colors.text.b, 0.12)
            opacity: done ? 0.55 : 1
          }
        }
      }
      Note {
        width: parent.width
        text: root.todo ? root.todo.done + " of " + root.todo.total + (root.todo.current ? "  ·  now: " + root.todo.current : "") : ""
      }
    }

    // Runs: linear heights, emphasis on the current run, failures in attention.
    Column {
      visible: root.runs.length > 0
      width: parent.colWidth
      spacing: Style.space(6)
      Caption {
        label: "Runs"
        count: root.runs.length
      }
      Item {
        width: parent.width
        height: Style.space(40)
        Row {
          anchors.bottom: baseline.top
          spacing: Style.space(3)
          Repeater {
            model: root.runs
            Rectangle {
              required property var modelData
              required property int index
              readonly property bool current: index === root.runs.length - 1 && (modelData.status === "running" || modelData.status === "starting")
              readonly property bool failed: modelData.status === "failed"
              anchors.bottom: parent.bottom
              width: Style.space(9)
              height: Math.max(Style.space(2), Style.space(38) * root.runDuration(modelData) / root.longestRun)
              radius: Style.cornerRadius > 0 ? 1 : 0
              color: current ? root.colors.accent : failed ? root.colors.attention : root.colors.text
              opacity: current || failed ? 1 : 0.32
            }
          }
        }
        Rectangle { id: baseline; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.colors.line }
      }
      Note {
        width: parent.width
        readonly property var last: root.runs.length ? root.runs[root.runs.length - 1] : null
        text: last ? (last.durationMs === null ? "current " + Format.duration(root.now - (last.startedAt || root.now)) : "last " + Format.duration(last.durationMs))
          + "  ·  longest " + Format.duration(root.longestRun) + (root.failedRuns ? "  ·  " + Format.plural(root.failedRuns, "failed", "failed") : "") : ""
      }
    }

    // Dropdown only: context next to runs (the two-pane header shows it instead).
    Column {
      visible: !root.paneMode && root.ctx !== null && root.todo === null
      width: parent.colWidth
      spacing: Style.space(6)
      Caption { label: "Context" }
      Item { width: 1; height: Style.space(28) }
      Meter {
        width: parent.width
        value: root.ctx ? root.ctx.used / root.ctx.max : 0
        ink: root.colors.text
        danger: root.colors.attention
      }
      Note {
        width: parent.width
        text: root.ctx ? Format.tokens(root.ctx.used) + " / " + Format.tokens(root.ctx.max) + "  ·  " + Math.round(root.ctx.used / root.ctx.max * 100) + "%"
          + (root.ctx.cost !== null ? "  ·  " + Format.money(root.ctx.cost, root.ctx.currency) : "") : ""
      }
    }
  }

  // Subagents
  Column {
    visible: root.detail !== null && root.detail.subagents.length > 0
    width: root.width
    spacing: Style.space(5)
    Caption { label: "Subagents"; count: root.detail ? root.detail.subagents.length : 0 }
    Repeater {
      model: root.detail ? root.detail.subagents : []
      Item {
        required property var modelData
        readonly property string st: modelData.status
        readonly property bool live: st === "running" || st === "pending" || st === "waiting"
        width: root.width
        height: Math.max(sText.implicitHeight, sGlyph.height) + Style.space(2)
        StateGlyph {
          id: sGlyph
          anchors.verticalCenter: parent.verticalCenter
          icon: parent.live ? "loader-circle" : parent.st === "completed" ? "circle-check" : parent.st === "failed" ? "circle-x" : "circle-dot"
          threadState: parent.live ? "working" : "idle"
          color: parent.live ? root.colors.accent : parent.st === "failed" ? root.colors.attention : root.colors.textFaint
          size: Math.round(Typo.body * 1.0)
        }
        Text {
          id: sText
          anchors.left: sGlyph.right
          anchors.leftMargin: Style.space(9)
          anchors.right: sMeta.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.title + (modelData.progress ? "  —  " + modelData.progress : "")
          textFormat: Text.PlainText
          color: parent.live ? root.colors.text : root.colors.textDim
          font.family: root.fontFamily
          font.pixelSize: Typo.caption
          elide: Text.ElideRight
        }
        Text {
          id: sMeta
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: Format.model(modelData.model) + (modelData.completedAt && modelData.startedAt ? "  ·  " + Format.duration(modelData.completedAt - modelData.startedAt)
            : modelData.startedAt && parent.live ? "  ·  " + Format.duration(root.now - modelData.startedAt) : "")
          textFormat: Text.PlainText
          color: root.colors.textFaint
          font.family: root.fontFamily
          font.pixelSize: Typo.caption
        }
      }
    }
  }

  // Error text for failed / limited threads
  Text {
    visible: !!root.row.error
    width: root.width
    text: root.row.error || ""
    textFormat: Text.PlainText
    color: root.colors.attentionInk
    font.family: root.monoFamily
    font.pixelSize: Typo.caption
    wrapMode: Text.Wrap
    maximumLineCount: 5
    elide: Text.ElideRight
  }

  // Dropdown only: PR title and actions (the two-pane header carries these).
  Note {
    visible: !root.paneMode && root.row.pr !== null && root.row.pr !== undefined
    width: root.width
    text: root.row.pr ? "PR #" + root.row.pr.number + "  " + root.row.pr.title + (root.row.prCount > 1 ? "  (+" + (root.row.prCount - 1) + " more)" : "") : ""
  }

  Row {
    visible: !root.paneMode
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
