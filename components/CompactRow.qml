import QtQuick
import qs.Commons
import "../lib/Store.js" as Store
import "../lib/Format.js" as Format

// Two-pane list row. Flat on the surface; the shell's hover/selected fills mark state.
// Rows that need you carry a rail and a faint wash in their colour (red: blocked or failed;
// amber: plan to review); the selected row adds an accent outline and rail.
Item {
  id: root

  property var row: ({})
  property var colors: ({})
  property double now: Date.now()
  property bool selected: false
  property bool reduceMotion: false
  property bool showMachine: false
  property string machineLabel: ""
  property string fontFamily: Style.font.family
  property string monoFamily: "monospace"

  signal clicked()

  readonly property bool child: row.parentId !== ""
  readonly property color glyphColor: colors[Store.stateRole(row.state)] || colors.textDim
  readonly property bool needsYou: Store.ATTENTION[row.state] === true
  readonly property color wordInk: Store.inkRole(row.state) ? colors[Store.inkRole(row.state)] : colors.textDim
  readonly property var activity: Store.currentActivity(row)
  readonly property bool working: Store.BUSY[row.state] === true
  readonly property bool showActivity: activity !== null && (working || row.state === "input")

  // What the second line says: the state in words and the most useful detail. Where the thread
  // runs is not part of it (the group headings, the right column and the detail carry that).
  readonly property string subtitle: {
    var r = row
    switch (r.state) {
      case "input": return Store.stateLabel(r) + (activity ? " · " + activity.label : "")
      case "failed": {
        var cause = Store.failureCause(r).label
        return "Failed" + (cause ? " · " + cause : "")
      }
      case "plan": return "Plan ready"
      case "limited": return "Usage limit" + (r.usageResetAt ? " · resets " + Format.until(r.usageResetAt, now) : "")
      case "queued": return "Queued"
      case "review":
        if (r.pr) return "#" + r.pr.number + (r.pr.checks === "passing" ? " ✓ checks" : r.pr.checks === "failing" ? " ✗ checks" : "") + (r.lastRunMs ? " · " + Format.duration(r.lastRunMs) + " run" : "")
        return "Done" + (r.lastRunMs ? " · " + Format.duration(r.lastRunMs) + " run" : "")
      case "background": {
        var subs = Math.max(r.background ? r.background.subagents : 0, r.activeChildren || 0)
        return (subs ? Format.plural(subs, "subagent") : "Background") + (activity ? " · " + activity.label : "")
      }
      case "stopped": return Store.stateLabel(r)
      case "idle": return r.rawStatus === "completed" ? "Done" + (r.lastRunMs ? " · " + Format.duration(r.lastRunMs) + " run" : "") : "Idle"
    }
    return showActivity ? activity.label : Store.stateLabel(r)
  }
  // Rows waiting on your answer are the ones to act on now: only they get a wash. Failures and plans
  // carry their rail and words, so the two needs-you hues never sit side by side as two fills.
  readonly property bool washed: row.state === "input"
  readonly property string subtitleIcon: {
    if (row.state === "input") return Store.pendingInfo(row.pendingKind).icon
    if (row.state === "failed") return Store.failureCause(row).icon
    if (row.state === "review" && row.pr) return "git-pull-request"
    if (row.state === "background") return "bot"
    if (showActivity) return activity.icon
    return ""
  }
  readonly property bool subtitleLive: showActivity && activity.status === "running" && working

  implicitHeight: body.implicitHeight + Style.space(child ? 8 : 14)

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: root.child ? Style.space(18) : 0
    radius: Style.cornerRadius
    // Shaded rows (subagents sit unshaded under their parent); hover and selection step up from there.
    color: root.selected ? root.colors.surfaceSelected
      : hover.hovered ? Style.hoverFillFor(root.colors.text, root.colors.accent)
      : root.washed ? Qt.tint(root.colors.surface, Qt.rgba(root.glyphColor.r, root.glyphColor.g, root.glyphColor.b, 0.07))
      : root.child ? "transparent" : root.colors.surface
    border.width: root.selected ? Style.space(2) : 0
    border.color: root.colors.focus
    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }

    // Rail: the state's colour on rows that need you, the accent on the selected row.
    Rail {
      visible: root.needsYou || root.selected
      height: parent.height
      color: root.needsYou ? root.glyphColor : root.colors.focus
      dashed: root.row.state === "failed"
    }
  }

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  TapHandler { onTapped: root.clicked() }

  Item {
    id: body
    x: Style.space(root.child ? 28 : 10)
    y: Style.space(root.child ? 4 : 7)
    width: parent.width - x - Style.space(10)
    implicitHeight: Math.max(left.implicitHeight, glyph.height)

    StateGlyph {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      icon: Store.stateIcon(root.row)
      threadState: root.row.state
      color: root.glyphColor
      size: Math.round(Typo.body * (root.child ? 0.95 : 1.1))
      reduceMotion: root.reduceMotion
    }

    Column {
      id: left
      anchors.left: glyph.right
      anchors.leftMargin: Style.space(10)
      anchors.right: right.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      ElidedText {
        width: parent.width
        fullText: root.row.title
        color: root.child || root.row.state === "idle" || root.row.state === "stopped" ? root.colors.textDim : root.colors.text
        font.family: root.fontFamily
        font.pixelSize: root.child ? Typo.caption : Typo.bodySmall
      }
      // Second line: the state and reason, and nothing else, so they have the whole width and are
      // never the part that gets cut. Where the thread runs sits under the time instead.
      Row {
        id: line
        visible: root.subtitle !== ""
        width: parent.width
        spacing: Style.space(6)
        LucideIcon {
          id: subIcon
          visible: root.subtitleIcon !== ""
          anchors.verticalCenter: parent.verticalCenter
          name: root.subtitleIcon || "zap"
          color: root.subtitleLive ? root.colors.accentInk : root.needsYou ? root.wordInk : root.colors.textFaint
          size: Math.round(Typo.caption * 1.1)
        }
        ElidedText {
          id: reason
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - (subIcon.visible ? subIcon.width + parent.spacing : 0)
          fullText: root.subtitle
          // Rows that need you say so in their colour; everything else stays ink.
          color: root.needsYou ? root.wordInk : root.showActivity ? root.colors.textDim : root.colors.textFaint
          font.family: root.subtitleIcon === "terminal" ? root.monoFamily : root.fontFamily
          font.pixelSize: Typo.caption
        }
      }
    }

    // Right column: the time, and under it the machine (when there are several). Sized by the
    // texts' own implicit widths, which follow every font change; nothing here is measured once.
    Column {
      id: right
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        id: time
        anchors.right: parent.right
        text: Format.elapsed(root.row, root.now, root.working)
        textFormat: Text.PlainText
        color: root.working || root.needsYou ? root.colors.textDim : root.colors.textFaint
        font.family: root.monoFamily
        font.pixelSize: Typo.caption
      }
      Text {
        id: machine
        visible: text !== ""
        anchors.right: parent.right
        text: root.showMachine && root.machineLabel && !root.child ? root.machineLabel : ""
        textFormat: Text.PlainText
        color: root.colors.textFaint
        font.family: root.fontFamily
        font.pixelSize: Typo.caption
      }
    }
  }
}
