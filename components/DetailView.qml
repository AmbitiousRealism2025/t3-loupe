import QtQuick
import qs.Commons
import qs.Ui
import "../lib/Store.js" as Store
import "../lib/Format.js" as Format
import "../lib/Palette.js" as Palette

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

  // part: "all", or the two halves the two-pane view puts either side of its stats:
  // "lead" (the callout and any pending request: what to act on) and "rest" (everything else).
  property string part: "all"
  readonly property bool lead: part !== "rest"
  readonly property bool rest: part !== "lead"
  readonly property bool hasLead: callout !== null || hasPending
  readonly property bool loading: detail === null
  readonly property bool hasPending: detail !== null && detail.pending.length > 0
  readonly property var callout: Store.statusCallout(row, now, hasPending)
  // T3 may never send detail for a thread (a failed one, say). Say so instead of loading forever.
  property bool waited: false
  readonly property string rowKey: row && row.key ? row.key : ""
  onRowKeyChanged: { waited = false; waitTimer.restart() }
  Timer { id: waitTimer; interval: 4000; running: true; onTriggered: root.waited = true }
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

  StatusCallout {
    width: root.width
    callout: root.lead ? root.callout : null
    colors: root.colors
    fontFamily: root.fontFamily
    monoFamily: root.monoFamily
    onActionRequested: function(action) { root.actionRequested(action) }
  }

  Note {
    visible: root.rest && root.loading
    width: root.width
    text: root.waited ? "No activity from T3 for this thread yet." : "Loading activity…"
  }

  // Pending approval / question, with the actual text, in the "waiting for your answer" colour.
  Repeater {
    model: root.lead && root.detail ? root.detail.pending : []
    Rectangle {
      required property var modelData
      width: root.width
      height: pend.implicitHeight + Style.space(18)
      radius: Style.cornerRadius
      color: Palette.alpha(root.colors.ask, 0.09)

      Rectangle { width: Style.space(3); height: parent.height; color: root.colors.ask }

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
            color: root.colors.askInk
            size: Math.round(Typo.body * 1.1)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Store.pendingInfo(modelData.kind).label + (modelData.appName ? "  ·  " + modelData.appName : "")
            textFormat: Text.PlainText
            color: root.colors.askInk
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
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
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
            // The choices T3 offers, as a plain list: Loupe shows them, it can't pick one.
            Repeater {
              model: modelData.options
              Text {
                required property var modelData
                width: parent.width
                text: "·  " + modelData
                textFormat: Text.PlainText
                color: root.colors.textDim
                font.family: root.fontFamily
                font.pixelSize: Typo.caption
                wrapMode: Text.Wrap
              }
            }
          }
        }

        Text {
          visible: modelData.options.length > 0
          width: parent.width
          text: "Choices in T3:  " + modelData.options.join("  ·  ")
          textFormat: Text.PlainText
          color: root.colors.textDim
          font.family: root.fontFamily
          font.pixelSize: Typo.caption
          wrapMode: Text.Wrap
        }

        KeyAction {
          width: parent.width
          wraps: true
          key: "o"
          text: modelData.kind === "user_input" ? "Answer in T3 (Loupe only shows the question)" : "Decide in T3 (Loupe only shows the request)"
          colors: root.colors
          fontFamily: root.fontFamily
          monoFamily: root.monoFamily
          onClicked: root.actionRequested("focus")
        }
      }
    }
  }

  // The collector sends at most three pending requests; the rest are counted here.
  Note {
    visible: root.lead && root.detail !== null && (root.detail.pendingMore || 0) > 0
    width: root.width
    text: root.detail ? "+" + (root.detail.pendingMore || 0) + " more waiting in T3" : ""
  }

  // Activity trail, newest last — T3's timeline icons. Live steps get a dot and "now".
  // The widest time an activity line shows, for its fixed time column.
  Text { id: whenProbe; visible: false; text: "waiting"; textFormat: Text.PlainText; font.family: root.fontFamily; font.pixelSize: Typo.caption }

  component ActivityTrail: Column {
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
          y: Math.max(0, (Typo.caption * 1.4 - height) / 2)
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
          // The callout above already shows a failure's full text; don't print it twice.
          text: Store.repeatsError(modelData, root.row) ? "Failed with the error shown above" : modelData.label
          textFormat: Text.PlainText
          color: parent.live ? root.colors.text : modelData.status === "failed" ? root.colors.attentionInk : root.colors.textDim
          font.family: modelData.icon === "terminal" ? root.monoFamily : root.fontFamily
          font.pixelSize: Typo.caption
          wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          maximumLineCount: 3
          elide: Text.ElideRight
        }
        // The time column has a fixed width (room for a dot and "waiting"), so it never shrinks;
        // the activity text beside it wraps and elides instead.
        Row {
          id: aWhen
          anchors.right: parent.right
          width: whenProbe.implicitWidth + Style.space(11)
          layoutDirection: Qt.RightToLeft
          y: Math.max(0, (Typo.caption * 1.4 - height) / 2)
          spacing: Style.space(5)
          Text {
            text: modelData.status === "pending" ? "waiting" : parent.parent.live ? "now" : Format.ago(modelData.at, root.now).replace(" ago", "")
            textFormat: Text.PlainText
            color: root.colors.textFaint
            font.family: root.fontFamily
            font.pixelSize: Typo.caption
          }
          Rectangle {
            visible: parent.parent.live
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(6); height: width; radius: width / 2
            color: modelData.status === "pending" ? root.colors.attention : root.colors.accent
          }
        }
      }
    }
  }

  // In the dropdown the activity comes first; in the two-pane detail, plan and runs come first, so
  // the runs chart sits high in the pane rather than under its "more below" strip.
  ActivityTrail { visible: !root.paneMode && root.rest && root.detail !== null && root.detail.activity.length > 0 }

  // Plan steps and runs: side by side when there is room for both captions in full, else stacked.
  Flow {
    visible: root.rest && (root.todo !== null || root.runs.length > 0 || (!root.paneMode && root.ctx !== null))
    width: root.width
    spacing: Style.space(24)
    readonly property real colWidth: width >= Style.space(720) ? (width - spacing) / 2 : width

    // Plan: one segment per step (the step is the unit), current step in accent.
    Column {
      visible: root.todo !== null
      width: parent.colWidth
      spacing: Style.space(6)
      Caption { label: "Plan"; count: -1 }
      Row {
        id: steps
        width: parent.width
        height: Style.space(12)
        spacing: Style.space(3)
        readonly property int total: root.todo ? Math.min(root.todo.total, 24) : 0
        Repeater {
          model: steps.total
          Rectangle {
            objectName: "planStep"
            required property int index
            readonly property bool done: root.todo && index < root.todo.done
            readonly property bool current: root.todo && index === root.todo.done
            width: (steps.width - steps.spacing * (steps.total - 1)) / Math.max(1, steps.total)
            radius: Style.cornerRadius > 0 ? 1 : 0
            // Done: solid dim ink. Current: the accent at twice the height, so it stands out by shape
            // as well as hue. To do: an outline in the 3:1 edge tone, so every step is drawn and the
            // bar's length is the plan's length.
            height: current ? steps.height : Math.round(steps.height / 2)
            anchors.verticalCenter: parent.verticalCenter
            color: current ? root.colors.accent : done ? root.colors.textDim : "transparent"
            border.width: current || done ? 0 : 1
            border.color: root.colors.edge
          }
        }
      }
      Note {
        width: parent.width
        text: root.todo ? root.todo.done + " of " + root.todo.total + " steps done" + (root.todo.current ? "  ·  now: " + root.todo.current : "") : ""
        wrapMode: Text.Wrap
      }
    }

    // Runs: linear heights, emphasis on the current run; a failed run is red and marked with an ×.
    Column {
      visible: root.runs.length > 0
      width: parent.colWidth
      spacing: Style.space(6)
      readonly property var summary: Store.runsSummary(root.runs, root.now)
      Caption {
        label: "Runs"
        count: root.runs.length
      }
      Note {
        visible: parent.summary.chart
        width: parent.width
        text: "One bar per run, its height the run's length"
        wrapMode: Text.Wrap
      }
      Item {
        visible: parent.summary.chart
        width: parent.width
        height: Style.space(52)
        Row {
          anchors.bottom: baseline.top
          spacing: Style.space(3)
          Repeater {
            model: root.runs
            Rectangle {
              objectName: "runBar"
              required property var modelData
              required property int index
              readonly property bool current: index === root.runs.length - 1 && (modelData.status === "running" || modelData.status === "starting")
              readonly property bool failed: modelData.status === "failed"
              anchors.bottom: parent.bottom
              width: Style.space(9)
              height: Math.max(Style.space(2), Style.space(38) * root.runDuration(modelData) / root.longestRun)
              radius: Style.cornerRadius > 0 ? 1 : 0
              color: current ? root.colors.accent : failed ? root.colors.attention : root.colors.edge
              Text {
                visible: parent.failed
                anchors.bottom: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                text: "×"
                textFormat: Text.PlainText
                color: root.colors.attentionInk
                font.family: root.fontFamily
                font.pixelSize: Typo.caption
                font.bold: true
              }
            }
          }
        }
        Rectangle { id: baseline; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.colors.line }
      }
      Note {
        width: parent.width
        text: parent.summary.text
        wrapMode: Text.Wrap
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
        danger: root.colors.text
        track: root.colors.edge
      }
      Note {
        width: parent.width
        text: root.ctx ? Format.tokens(root.ctx.used) + " / " + Format.tokens(root.ctx.max) + "  ·  " + Math.round(root.ctx.used / root.ctx.max * 100) + "%"
          + (root.ctx.cost !== null ? "  ·  " + Format.money(root.ctx.cost, root.ctx.currency) : "") : ""
      }
    }
  }

  ActivityTrail { visible: root.paneMode && root.rest && root.detail !== null && root.detail.activity.length > 0 }

  // Subagents
  Column {
    visible: root.rest && root.detail !== null && root.detail.subagents.length > 0
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
          y: Math.max(0, (Typo.caption * 1.4 - height) / 2)
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
          text: modelData.title + (modelData.progress ? "  —  " + modelData.progress : "")
          textFormat: Text.PlainText
          color: parent.live ? root.colors.text : root.colors.textDim
          font.family: root.fontFamily
          font.pixelSize: Typo.caption
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Text {
          id: sMeta
          anchors.right: parent.right
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
