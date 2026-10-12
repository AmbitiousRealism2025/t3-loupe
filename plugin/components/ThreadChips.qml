import QtQuick
import qs.Commons
import "../lib/Format.js" as Format

// Tags for a thread: error class, subagents, background tasks, PR, context, plan mode.
Flow {
  id: root
  property var row: ({})
  property var detail: null
  property var colors: ({})
  property bool showContext: true
  property bool showSubagentTotal: false

  readonly property bool child: row.parentId !== ""
  readonly property var pr: row.pr || null
  readonly property var ctx: detail && detail.context && detail.context.max > 0 ? detail.context : null
  // Background tasks and child threads describe the same subagents; take the larger view.
  readonly property int subs: Math.max(row.background ? row.background.subagents : 0, row.activeChildren || 0)
  readonly property int tasks: row.background ? row.background.commands + row.background.monitors : 0
  // Decided from data, not from child.visible (which already folds in this Flow's own visibility).
  readonly property bool showError: row.state === "failed" && !!row.errorClass
  readonly property bool showSubs: !child && (subs > 0 || (row.childCount > 0 && showSubagentTotal))
  readonly property bool showTasks: tasks > 0
  readonly property bool showPr: pr !== null
  readonly property bool showCtx: showContext && ctx !== null
  readonly property bool showPlan: row.plan === true && !child
  readonly property bool anyVisible: showError || showSubs || showTasks || showPr || showCtx || showPlan

  spacing: Style.space(5)

  Chip {
    id: errChip
    visible: root.showError
    icon: "circle-alert"
    text: String(root.row.errorClass || "").replace("_", " ")
    tone: root.colors.attention
    ink: root.colors.attentionInk
  }
  Chip {
    id: subChip
    visible: root.showSubs
    icon: "bot"
    text: root.subs > 0 ? Format.plural(root.subs, "subagent") + " running" : Format.plural(root.row.childCount, "subagent")
    tone: root.colors.subagent
    ink: root.colors.subagentInk
  }
  Chip {
    id: taskChip
    visible: root.showTasks
    icon: root.row.background && root.row.background.monitors > 0 ? "eye" : "terminal"
    text: Format.plural(root.tasks, "background task")
    tone: root.colors.info
    ink: root.colors.infoInk
  }
  Chip {
    id: prChip
    visible: root.showPr
    readonly property var p: root.pr || ({})
    icon: p.state === "merged" ? "git-merge" : "git-pull-request"
    text: "#" + p.number + (p.checks === "passing" ? "  ✓" : p.checks === "failing" ? "  ✗" : p.checks === "pending" ? "  …" : "")
      + (p.additions || p.deletions ? "  +" + p.additions + " −" + p.deletions : "")
    tone: p.checks === "failing" ? root.colors.attention : p.state === "merged" ? root.colors.subagent : p.state === "open" ? root.colors.success : root.colors.textFaint
    ink: p.checks === "failing" ? root.colors.attentionInk : p.state === "merged" ? root.colors.subagentInk : p.state === "open" ? root.colors.successInk : root.colors.textDim
  }
  Chip {
    id: ctxChip
    visible: root.showCtx
    icon: "gauge"
    text: root.ctx ? Math.round(root.ctx.used / root.ctx.max * 100) + "% context" : ""
    tone: root.ctx && root.ctx.used / root.ctx.max > 0.85 ? root.colors.warning : root.colors.textFaint
    ink: root.ctx && root.ctx.used / root.ctx.max > 0.85 ? root.colors.warningInk : root.colors.textDim
  }
  Chip {
    id: planChip
    visible: root.showPlan
    icon: "list-todo"
    text: "plan mode"
    tone: root.colors.textFaint
    ink: root.colors.textDim
  }
}
