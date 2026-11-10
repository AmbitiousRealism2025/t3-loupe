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
  // How copying this thread's title just ended: "" | "ok" | "failed".
  property string copyState: ""
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

  // What to do next, as a sentence in full-strength ink; the keys that carry it out follow it
  // (ThreadActions), so the hand-off to T3 is one piece: what to do there, and the key that gets
  // you there.
  component NextStep: Sentence {
    property string step: ""
    objectName: "nextStep"
    lead: "→ "
    text: step
    color: root.colors.text
    font.family: root.fontFamily
    font.pixelSize: Typo.caption
    font.weight: Font.Medium
  }

  StatusCallout {
    width: root.width
    callout: root.lead ? root.callout : null
    row: root.row
    copyState: root.copyState
    secondary: root.paneMode
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
      required property int index
      width: root.width
      height: pend.implicitHeight + Style.space(18)
      radius: Style.cornerRadius
      color: Palette.alpha(root.colors.ask, Palette.BLOCK)

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

        // What T3 will offer, as a sentence: set apart with dots they read as buttons, and Loupe
        // has none to press.
        Text {
          visible: modelData.options.length > 0
          width: parent.width
          text: Store.choicesSentence(modelData.options)
          textFormat: Text.PlainText
          color: root.colors.textDim
          font.family: root.fontFamily
          font.pixelSize: Typo.caption
          wrapMode: Text.Wrap
        }

        NextStep {
          width: parent.width
          step: modelData.kind === "user_input" ? "Answer in T3: Loupe only shows the question" : "Decide in T3: Loupe only shows the request"
        }
        // The keys for it, once, under the last request.
        ThreadActions {
          visible: index === (root.detail ? root.detail.pending.length : 0) - 1
          width: parent.width
          margin: 0
          row: root.row
          colors: root.colors
          fontFamily: root.fontFamily
          monoFamily: root.monoFamily
          copyState: root.copyState
          secondary: root.paneMode
          onActionRequested: function(action) { root.actionRequested(action) }
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
  Text { id: whenProbe; visible: false; text: "59m ago"; textFormat: Text.PlainText; font.family: root.fontFamily; font.pixelSize: Typo.caption }

  component ActivityTrail: Column {
    width: root.width
    spacing: Style.space(5)
    Caption { label: "Activity" }
    Repeater {
      model: root.detail ? root.detail.activity : []
      Item {
        required property var modelData
        // A row is shown whole or not at all where the pane's scroll edge falls (ThreadDetailPane).
        readonly property bool whole: true
        readonly property bool live: modelData.status === "running" || modelData.status === "pending"
        // A step waiting on your answer is marked in the answer's violet, like its row and its
        // request above: red is for failures only, and the accent for what is running.
        readonly property bool asking: modelData.status === "pending" && root.row.state === "input"
        width: root.width
        height: Math.max(aText.implicitHeight, aIcon.height) + Style.space(2)
        LucideIcon {
          id: aIcon
          y: Math.max(0, (Typo.caption * 1.4 - height) / 2)
          name: modelData.icon
          color: parent.asking ? root.colors.askInk : modelData.status === "running" ? root.colors.workingInk
            : modelData.status === "failed" ? root.colors.attentionInk : parent.live ? root.colors.textDim : root.colors.textFaint
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
        // The time column has a fixed width (room for a dot and "waiting", or "59m ago"), so it never shrinks;
        // the activity text beside it wraps and elides instead.
        Row {
          id: aWhen
          anchors.right: parent.right
          width: whenProbe.implicitWidth + Style.space(11)
          layoutDirection: Qt.RightToLeft
          y: Math.max(0, (Typo.caption * 1.4 - height) / 2)
          spacing: Style.space(5)
          Text {
            // "3m ago", as the rows say it: a bare "3m" read as a duration as easily as an age.
            text: modelData.status === "pending" ? "waiting" : parent.parent.live ? "now" : Format.ago(modelData.at, root.now)
            textFormat: Text.PlainText
            color: root.colors.textFaint
            font.family: root.fontFamily
            font.pixelSize: Typo.caption
          }
          Rectangle {
            objectName: "liveDot"
            visible: parent.parent.live
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(6); height: width; radius: width / 2
            color: parent.parent.asking ? root.colors.ask : modelData.status === "pending" ? root.colors.edge : root.colors.working
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
    // Side by side, a wide gutter; stacked, the same gap as every other section.
    readonly property bool paired: width >= Style.space(720)
    spacing: paired ? Style.space(24) : root.spacing
    readonly property real colWidth: paired ? (width - spacing) / 2 : width

    // Plan: one segment per step (the step is the unit), the current step in the working ink.
    Column {
      visible: root.todo !== null
      width: parent.colWidth
      spacing: Style.space(6)
      Caption { label: "Plan"; count: -1 }
      Row {
        id: steps
        readonly property bool whole: true
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
            // Done: solid, in the 3:1 edge tone. Current: full ink at twice the height, so it stands
            // out by shape and by strength, with no hue (a hue is for what needs you). To do: an
            // outline in the edge tone, so every step is drawn and the bar's length is the plan's.
            height: current ? steps.height : Math.round(steps.height / 2)
            anchors.verticalCenter: parent.verticalCenter
            color: current ? root.colors.working : done ? root.colors.edge : "transparent"
            border.width: current || done ? 0 : 1
            border.color: root.colors.edge
          }
        }
      }
      Note {
        objectName: "planCount"
        width: parent.width
        text: root.todo ? root.todo.done + " of " + root.todo.total + " steps done" : ""
      }
      // The step in hand, on a line of its own in full ink: it is what the thread is doing now,
      // and the one line of the plan worth reading at a glance.
      Sentence {
        objectName: "planNow"
        visible: root.todo !== null && !!root.todo.current
        width: parent.width
        lead: "now: "
        leadColor: root.colors.textFaint
        text: root.todo && root.todo.current ? root.todo.current : ""
        color: root.colors.text
        font.family: root.fontFamily
        font.pixelSize: Typo.caption
      }
    }

    // Runs: linear heights, emphasis on the current run; a failed run is red and marked with an ×.
    Column {
      visible: root.runs.length > 0
      width: parent.colWidth
      spacing: Style.space(6)
      readonly property var summary: Store.runsSummary(root.runs, root.now)
      // The count heads the chart; without a chart the sentence below already says how many.
      Caption {
        label: "Runs"
        count: parent.summary.chart ? root.runs.length : -1
      }
      // The chart and its figures side by side: the bars are only as wide as the runs there are,
      // so the figures take the room beside them instead of sitting under a mostly empty plot.
      // If there are so many runs that the figures don't fit beside them, they go underneath.
      Item {
        id: runsRow
        readonly property bool whole: true
        visible: parent.summary.chart
        width: parent.width
        readonly property real gap: Style.space(22)
        readonly property bool beside: chart.width + gap + Style.space(190) <= width
        height: beside ? Math.max(chart.height, figures.implicitHeight) : chart.height + Style.space(6) + figures.implicitHeight
        Column {
          id: figures
          objectName: "runFigures"
          x: runsRow.beside ? chart.width + runsRow.gap : 0
          y: runsRow.beside ? Math.max(0, chart.height - implicitHeight) : chart.height + Style.space(6)
          width: runsRow.width - x
          spacing: Style.space(2)
          Repeater {
            model: runsRow.parent.summary.chart ? runsRow.parent.summary.text.split("  ·  ") : []
            Note { required property string modelData; width: figures.width; text: modelData; color: root.colors.textDim }
          }
          Note { width: figures.width; text: "one bar per run; taller ran longer"; wrapMode: Text.Wrap }
        }
      Item {
        id: chart
        objectName: "runChart"
        width: bars.width
        height: Style.space(52)
        Row {
          id: bars
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
              color: current ? root.colors.working : failed ? root.colors.attention : root.colors.edge
              // The run in progress carries a mark as well as full ink, as the failed one carries its ×.
              Rectangle {
                objectName: "currentRunMark"
                visible: parent.current
                anchors.bottom: parent.top
                anchors.bottomMargin: Style.space(3)
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(5); height: width; radius: width / 2
                color: root.colors.working
              }
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
        Rectangle { id: baseline; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.colors.edge }
      }
      }
      // Too few runs for a chart: the sentence says it all.
      Note {
        visible: !parent.summary.chart
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
        readonly property bool whole: true
        readonly property string st: modelData.status
        readonly property bool live: st === "running" || st === "pending" || st === "waiting"
        width: root.width
        height: Math.max(sText.implicitHeight, sGlyph.height) + Style.space(2)
        StateGlyph {
          id: sGlyph
          y: Math.max(0, (Typo.caption * 1.4 - height) / 2)
          icon: parent.live ? "loader-circle" : parent.st === "completed" ? "circle-check" : parent.st === "failed" ? "circle-x" : "circle-dot"
          threadState: parent.live ? "working" : "idle"
          color: parent.live ? root.colors.working : parent.st === "failed" ? (root.colors.attentionGlyph || root.colors.attention) : root.colors.textFaint
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
    // (A card that leads with a callout or a request already ends that block with "o open T3".)
    ActionButton { visible: !root.hasLead; text: "Focus T3"; onClicked: root.actionRequested("focus") }
    ActionButton {
      visible: root.row.pr !== null && root.row.pr !== undefined && root.row.pr.url !== ""
      text: "Open PR"
      onClicked: root.actionRequested("pr")
    }
    ActionButton { text: "Copy title"; onClicked: root.actionRequested("copy") }
  }
}
