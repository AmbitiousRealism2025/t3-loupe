import QtQuick
import qs.Commons
import "../lib/Store.js" as Store
import "../lib/Format.js" as Format

// One thread. Collapsed: state, title, context line, live activity, chips.
// Expanded: DetailView with pending request text, activity trail, runs, context, subagents.
Item {
  id: root

  property var row: ({})
  property var colors: ({})
  property var detail: null
  property double now: Date.now()
  property bool selected: false
  property bool expanded: false
  property bool reduceMotion: false
  property bool showMachine: false
  property string machineLabel: ""
  property string fontFamily: Style.font.family
  property string monoFamily: "monospace"

  signal clicked()
  signal actionRequested(string action)

  readonly property bool child: row.parentId !== ""
  readonly property color tone: colors[roleFor(row.state)] || colors.textDim
  readonly property color ink: colors[roleFor(row.state) + "Ink"] || colors.textDim
  readonly property bool loud: Store.ATTENTION[row.state] === true || Store.BUSY[row.state] === true || row.state === "limited"
  readonly property var activity: Store.currentActivity(row)
  readonly property real indent: child ? Style.space(22) : 0

  function roleFor(state) {
    return { input: "attention", failed: "attention", plan: "warning", limited: "warning", working: "accent", waiting: "accent",
      queued: "info", background: "subagent", review: "success" }[state] || "idle"
  }

  readonly property string elapsedText: {
    if (row.state === "input" && row.pendingSince) return Format.duration(now - row.pendingSince)
    if (row.activeSince && Store.BUSY[row.state]) return Format.duration(now - row.activeSince)
    if (row.state === "limited" && row.usageResetAt) return "resets " + Format.until(row.usageResetAt, now)
    if (row.completedAt) return Format.ago(row.completedAt, now)
    return Format.ago(row.updatedAt, now)
  }

  readonly property string metaText: {
    var parts = []
    if (showMachine && machineLabel) parts.push(machineLabel)
    if (!child) parts.push(row.project)
    if (row.branch) parts.push(row.branch)
    if (row.model) parts.push(Format.model(row.model))
    return parts.join("  ·  ")
  }

  implicitHeight: card.height + Style.space(child ? 2 : 4)

  // Tree connector for subagent rows.
  Rectangle {
    visible: root.child
    x: Style.space(9)
    y: -Style.space(4)
    width: 1
    height: card.height / 2 + Style.space(4)
    color: root.colors.line
  }
  Rectangle {
    visible: root.child
    x: Style.space(9)
    y: card.height / 2
    width: Style.space(9)
    height: 1
    color: root.colors.line
  }

  Rectangle {
    id: card
    x: root.indent
    width: root.width - root.indent
    height: content.implicitHeight + Style.space(root.child ? 12 : 18)
    radius: Style.cornerRadius
    color: root.selected ? root.colors.surfaceSelected : hover.hovered ? root.colors.surfaceRaised : root.child ? "transparent" : root.colors.surface
    border.width: root.selected ? 1 : 0
    border.color: Qt.rgba(root.colors.accent.r, root.colors.accent.g, root.colors.accent.b, 0.55)
    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // State rail.
    Rectangle {
      width: Style.space(3)
      height: parent.height
      color: root.tone
      opacity: root.loud ? 1 : (root.row.state === "review" ? 0.8 : 0.28)
      radius: Math.min(Style.cornerRadius, width / 2)
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.clicked() }

    Column {
      id: content
      x: Style.space(14)
      y: Style.space(root.child ? 6 : 9)
      width: parent.width - Style.space(24)
      spacing: Style.space(4)

      // Title line
      Item {
        width: parent.width
        height: Math.max(title.implicitHeight, glyph.height)

        StateGlyph {
          id: glyph
          anchors.verticalCenter: title.lineCount > 1 ? undefined : parent.verticalCenter
          y: title.lineCount > 1 ? Style.space(1) : 0
          icon: Store.stateIcon(root.row)
          threadState: root.row.state
          color: root.tone
          size: Math.round(Style.font.body * (root.child ? 1.05 : 1.25))
          reduceMotion: root.reduceMotion
        }

        Text {
          id: title
          anchors.left: glyph.right
          anchors.leftMargin: Style.space(8)
          anchors.right: right.left
          anchors.rightMargin: Style.space(10)
          text: root.row.title
          textFormat: Text.PlainText
          color: root.row.state === "idle" || root.row.state === "stopped" ? root.colors.textDim : root.colors.text
          font.family: root.fontFamily
          font.pixelSize: root.child ? Style.font.bodySmall : Style.font.body
          font.weight: root.child ? Font.Normal : Font.DemiBold
          wrapMode: Text.Wrap
          maximumLineCount: root.expanded ? 3 : 2
          elide: Text.ElideRight
        }

        Column {
          id: right
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.space(1)
          Text {
            anchors.right: parent.right
            text: root.elapsedText
            textFormat: Text.PlainText
            color: root.loud ? root.colors.text : root.colors.textFaint
            font.family: root.monoFamily
            font.pixelSize: Style.font.caption
            font.features: { "tnum": 1 }
          }
          Text {
            anchors.right: parent.right
            visible: !root.child || root.loud
            text: Store.stateLabel(root.row)
            textFormat: Text.PlainText
            color: root.loud || root.row.state === "review" ? root.ink : root.colors.textFaint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: root.loud ? Font.DemiBold : Font.Normal
          }
        }
      }

      // project · branch · model
      Text {
        visible: text !== "" && !root.child
        x: glyph.width + Style.space(8)
        width: parent.width - x
        text: root.metaText
        textFormat: Text.PlainText
        color: root.colors.textFaint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      // What it's doing right now (T3 timeline icon + label).
      Row {
        visible: root.activity !== null && !root.expanded && (Store.BUSY[root.row.state] || root.row.state === "input")
        x: glyph.width + Style.space(8)
        width: parent.width - x
        spacing: Style.space(6)
        LucideIcon {
          id: actIcon
          anchors.verticalCenter: parent.verticalCenter
          name: root.activity ? root.activity.icon : "zap"
          color: root.activity && root.activity.status === "running" ? root.colors.accentInk : root.colors.textDim
          size: Math.round(Style.font.caption * 1.25)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - actIcon.width - Style.space(6)
          text: root.activity ? root.activity.label : ""
          textFormat: Text.PlainText
          color: root.colors.textDim
          font.family: root.activity && root.activity.icon === "terminal" ? root.monoFamily : root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // Chips
      Flow {
        visible: chips.count > 0 || ctxChip.visible || bgChip.visible
        x: glyph.width + Style.space(8)
        width: parent.width - x
        spacing: Style.space(5)

        Chip {
          visible: root.row.state === "failed" && root.row.errorClass !== ""
          icon: "circle-alert"
          text: root.row.errorClass.replace("_", " ")
          tone: root.colors.attention
          ink: root.colors.attentionInk
        }
        Chip {
          id: bgChip
          // Background tasks and child threads describe the same subagents; take the larger view.
          readonly property int subs: Math.max(root.row.background ? root.row.background.subagents : 0, root.row.activeChildren)
          visible: !root.child && (subs > 0 || (root.row.childCount > 0 && root.expanded))
          icon: "bot"
          text: subs > 0 ? Format.plural(subs, "subagent") + " running" : Format.plural(root.row.childCount, "subagent")
          tone: root.colors.subagent
          ink: root.colors.subagentInk
        }
        Chip {
          visible: root.row.background && (root.row.background.commands + root.row.background.monitors) > 0
          icon: root.row.background && root.row.background.monitors > 0 ? "eye" : "terminal"
          text: root.row.background ? Format.plural(root.row.background.commands + root.row.background.monitors, "background task") : ""
          tone: root.colors.info
          ink: root.colors.infoInk
        }
        Chip {
          visible: root.row.pr !== null && root.row.pr !== undefined
          readonly property var pr: root.row.pr || ({})
          icon: pr.state === "merged" ? "git-merge" : "git-pull-request"
          text: "#" + pr.number + (pr.checks === "passing" ? "  ✓" : pr.checks === "failing" ? "  ✗" : pr.checks === "pending" ? "  …" : "")
            + (pr.additions || pr.deletions ? "  +" + pr.additions + " −" + pr.deletions : "")
          tone: pr.checks === "failing" ? root.colors.attention : pr.state === "merged" ? root.colors.subagent : pr.state === "open" ? root.colors.success : root.colors.textFaint
          ink: pr.checks === "failing" ? root.colors.attentionInk : pr.state === "merged" ? root.colors.subagentInk : pr.state === "open" ? root.colors.successInk : root.colors.textDim
        }
        Chip {
          id: ctxChip
          readonly property var ctx: root.detail && root.detail.context ? root.detail.context : null
          visible: ctx !== null && ctx.max > 0 && !root.expanded
          icon: "gauge"
          text: ctx ? Math.round(ctx.used / ctx.max * 100) + "% context" : ""
          tone: ctx && ctx.used / ctx.max > 0.85 ? root.colors.warning : root.colors.textFaint
          ink: ctx && ctx.used / ctx.max > 0.85 ? root.colors.warningInk : root.colors.textDim
        }
        Chip {
          visible: root.row.plan && !root.child
          icon: "list-todo"
          text: "plan mode"
          tone: root.colors.textFaint
          ink: root.colors.textDim
        }
        Repeater { id: chips; model: 0 }
      }

      Loader {
        active: root.expanded
        visible: active
        x: glyph.width + Style.space(8)
        width: parent.width - x
        sourceComponent: DetailView {
          row: root.row
          detail: root.detail
          colors: root.colors
          now: root.now
          fontFamily: root.fontFamily
          monoFamily: root.monoFamily
          onActionRequested: function(action) { root.actionRequested(action) }
        }
      }
    }
  }
}
