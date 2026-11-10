import QtQuick
import qs.Commons
import "../lib/Store.js" as Store
import "../lib/Format.js" as Format
import "../lib/Palette.js" as Palette

// Two-pane list row. Flat on the surface; hover and selection lift it a step.
// Rows that need you carry a rail in their colour (violet: an answer; red: failed; amber: a plan
// to review), and those waiting on an answer a faint wash; the selected row adds the ring.
//
// Two lines. The title has the whole of the first, and a second line of its own if it needs one:
// the title is what tells one thread from another, so nothing shares its line. The second line
// says the state and its reason on the left, and on the right the time, with the word that says
// what kind of time it is ("waiting 2m", "running 23m", "4m ago", "resets in 47m").
// Where the thread runs is not on the row: the group headings in All and the detail pane say it.
Item {
  id: root

  property var row: ({})
  property var colors: ({})
  property double now: Date.now()
  property bool selected: false
  // Whether all of this thread's subagents are listed under it (Enter), or only the live ones.
  property bool expanded: false
  property bool reduceMotion: false
  property string fontFamily: Style.font.family
  property string monoFamily: "monospace"

  signal clicked()

  readonly property bool child: row.parentId !== ""
  readonly property color glyphColor: colors[Store.stateRole(row.state)] || colors.textDim
  readonly property bool needsYou: Store.ATTENTION[row.state] === true
  readonly property color wordInk: Store.inkRole(row.state) ? colors[Store.inkRole(row.state)] : colors.textDim
  readonly property var activity: Store.currentActivity(row)
  readonly property bool working: Store.BUSY[row.state] === true
  // What it is doing now. A request's own "awaiting approval" step is not shown as an activity:
  // the state beside it ("Run command?") already says it.
  readonly property bool showActivity: activity !== null && (working || (row.state === "input" && activity.status !== "pending"))
  // Enter lists this thread's subagents: the row says how many there are and whether they are all shown.
  readonly property bool hasChildren: !child && (row.childCount || 0) > 0

  // What the second line says: the state in words and the most useful detail.
  readonly property string subtitle: {
    var r = row
    switch (r.state) {
      case "input": return Store.stateLabel(r) + (showActivity ? " · " + activity.label : "")
      case "failed": {
        var cause = Store.failureCause(r).label
        return "Failed" + (cause ? " · " + cause : "")
      }
      case "plan": return "Plan ready"
      case "limited": return "Usage limit"
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
  // The reason's own icon, where it adds something: not the state's glyph over again.
  readonly property string subtitleIcon: {
    var icon = ""
    if (row.state === "input") icon = Store.pendingInfo(row.pendingKind).icon
    else if (row.state === "failed") icon = Store.failureCause(row).icon
    else if (row.state === "review" && row.pr) icon = "git-pull-request"
    else if (row.state === "background") icon = "bot"
    else if (showActivity) icon = activity.icon
    return icon === Store.stateIcon(row) ? "" : icon
  }
  readonly property bool subtitleLive: showActivity && activity.status === "running" && working

  implicitHeight: body.implicitHeight + Style.space(child ? 8 : 14)

  Rectangle {
    objectName: "fill"
    anchors.fill: parent
    anchors.leftMargin: root.child ? Style.space(18) : 0
    radius: Style.cornerRadius
    // Shaded rows (subagents sit unshaded under their parent); hover and selection step up from there.
    // Selection is a neutral lift and the ring: a washed row keeps its wash under it, so the row
    // still reads as what it is while it is selected.
    color: root.selected ? (root.washed ? Palette.wash(root.colors.surfaceSelected, root.glyphColor) : root.colors.surfaceSelected)
      : hover.hovered ? Style.hoverFillFor(root.colors.text, root.colors.accent)
      : root.washed ? Palette.wash(root.colors.surface, root.glyphColor)
      : root.child ? "transparent" : root.colors.surface
    border.width: root.selected ? Style.space(2) : 0
    border.color: root.colors.focus
    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }

    // Rail: the state's colour on rows that need you, the ring's on any other selected row.
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
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      // The title, whole wherever it fits in two lines; beyond that it is cut with "…" (the detail
      // pane has it in full). A thread with subagents ends its first line with their count and a
      // chevron: Enter lists them all.
      Item {
        width: parent.width
        height: title.implicitHeight
        Text {
          id: title
          objectName: "rowTitle"
          width: parent.width - (kids.visible ? kids.width + Style.space(10) : 0)
          text: root.row.title
          textFormat: Text.PlainText
          color: root.child || root.row.state === "idle" || root.row.state === "stopped" ? root.colors.textDim : root.colors.text
          font.family: root.fontFamily
          font.pixelSize: root.child ? Typo.caption : Typo.bodySmall
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Row {
          id: kids
          objectName: "rowChildren"
          visible: root.hasChildren
          anchors.right: parent.right
          height: titleLine.implicitHeight
          spacing: Style.space(3)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String(root.row.childCount || 0)
            textFormat: Text.PlainText
            color: root.colors.textFaint
            font.family: root.fontFamily
            font.pixelSize: Typo.caption
          }
          LucideIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron-right"
            color: root.colors.textDim
            size: Math.round(Typo.caption * 1.1)
            rotation: root.expanded ? 90 : 0
          }
        }
        // One line of the title's type, for centring the subagent marker on the first line.
        Text { id: titleLine; visible: false; text: "Ag"; textFormat: Text.PlainText; font: title.font }
      }
      // Second line: the state and reason on the left, never cut short by anything but the time;
      // the time on the right, with its word.
      Item {
        id: line
        width: parent.width
        height: Math.max(reasonRow.implicitHeight, time.implicitHeight)
        Text {
          id: time
          objectName: "rowTime"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: Format.rowTime(root.row, root.now, root.working)
          textFormat: Text.PlainText
          color: root.working || root.needsYou ? root.colors.textDim : root.colors.textFaint
          font.family: root.monoFamily
          font.pixelSize: Typo.caption
        }
        Row {
          id: reasonRow
          visible: root.subtitle !== ""
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - time.implicitWidth - Style.space(14)
          spacing: Style.space(6)
          LucideIcon {
            id: subIcon
            visible: root.subtitleIcon !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: root.subtitleIcon || "zap"
            color: root.subtitleLive ? root.colors.workingInk : root.needsYou ? root.wordInk : root.colors.textFaint
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
    }
  }
}
