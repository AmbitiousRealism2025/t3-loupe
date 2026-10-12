import QtQuick
import qs.Commons
import "../lib/Store.js" as Store
import "../lib/Format.js" as Format

// Two-pane list row. Flat on the surface; the shell's hover/selected fills mark state,
// a 2px accent marker marks the selection, and only the glyph carries colour.
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
  readonly property var activity: Store.currentActivity(row)
  readonly property bool working: Store.BUSY[row.state] === true
  readonly property bool showActivity: activity !== null && (working || row.state === "input")
  readonly property string where: {
    var parts = []
    if (showMachine && machineLabel) parts.push(machineLabel)
    if (!child) parts.push(row.project)
    return parts.join(" · ")
  }

  // What the second line says: the state in words, then the most useful detail.
  readonly property string subtitle: {
    var r = row
    switch (r.state) {
      case "input": return Store.stateLabel(r) + (activity ? " · " + activity.label : "")
      case "failed": return "Failed" + (r.errorClass ? " · " + r.errorClass.replace("_", " ") : "") + (where ? " · " + where : "")
      case "plan": return "Plan ready" + (where ? " · " + where : "")
      case "limited": return "Usage limit" + (r.usageResetAt ? " · resets " + Format.until(r.usageResetAt, now) : "")
      case "queued": return "Queued" + (where ? " · " + where : "")
      case "review":
        if (r.pr) return "#" + r.pr.number + (r.pr.checks === "passing" ? " ✓ checks" : r.pr.checks === "failing" ? " ✗ checks" : "") + (r.lastRunMs ? " · " + Format.duration(r.lastRunMs) + " run" : "")
        return "Done" + (r.lastRunMs ? " · " + Format.duration(r.lastRunMs) + " run" : "") + (where ? " · " + where : "")
      case "background": {
        var subs = Math.max(r.background ? r.background.subagents : 0, r.activeChildren || 0)
        return (subs ? Format.plural(subs, "subagent") : "Background") + (activity ? " · " + activity.label : "")
      }
      case "stopped": return Store.stateLabel(r) + (where ? " · " + where : "")
      case "idle": return where
    }
    return showActivity ? activity.label : where
  }
  readonly property string subtitleIcon: {
    if (row.state === "input") return Store.pendingInfo(row.pendingKind).icon
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
    color: root.selected ? Style.selectedFillFor(root.colors.text, root.colors.accent)
      : hover.hovered ? Style.hoverFillFor(root.colors.text, root.colors.accent)
      : root.child ? "transparent" : root.colors.surface
    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Rectangle {
      visible: root.selected
      y: Style.space(6); width: Style.space(2); height: parent.height - Style.space(12)
      color: root.colors.accent
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
      anchors.right: time.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: root.row.title
        textFormat: Text.PlainText
        color: root.child || root.row.state === "idle" || root.row.state === "stopped" ? root.colors.textDim : root.colors.text
        font.family: root.fontFamily
        font.pixelSize: root.child ? Typo.caption : Typo.bodySmall
        elide: Text.ElideRight
      }
      Row {
        visible: root.subtitle !== ""
        width: parent.width
        spacing: Style.space(6)
        LucideIcon {
          id: subIcon
          visible: root.subtitleIcon !== ""
          anchors.verticalCenter: parent.verticalCenter
          name: root.subtitleIcon || "zap"
          color: root.subtitleLive ? root.colors.accentInk : Store.isAlarm(root.row.state) ? root.colors.attentionInk : root.colors.textFaint
          size: Math.round(Typo.caption * 1.1)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - (subIcon.visible ? subIcon.width + parent.spacing : 0)
          text: root.subtitle
          textFormat: Text.PlainText
          // Alarm exception: needs-input and failed read in attention ink; everything else stays ink.
          color: Store.isAlarm(root.row.state) ? root.colors.attentionInk : root.showActivity ? root.colors.textDim : root.colors.textFaint
          font.family: root.subtitleIcon === "terminal" ? root.monoFamily : root.fontFamily
          font.pixelSize: Typo.caption
          elide: Text.ElideRight
        }
      }
    }

    Text {
      id: time
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: Format.elapsed(root.row, root.now, root.working)
      textFormat: Text.PlainText
      color: root.working || Store.isAlarm(root.row.state) ? root.colors.textDim : root.colors.textFaint
      font.family: root.monoFamily
      font.pixelSize: Typo.caption
    }
  }
}
