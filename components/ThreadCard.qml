import QtQuick
import qs.Commons
import "../lib/Store.js" as Store
import "../lib/Format.js" as Format
import "../lib/Palette.js" as Palette

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
  // Colour budget: the glyph carries the state hue; words stay ink except the alarm states.
  readonly property color tone: colors[Store.stateRole(row.state)] || colors.textDim
  // The glyph is a line icon, held to more than the rail and the wash that share its hue.
  readonly property color glyphInk: colors[Store.stateRole(row.state) + "Glyph"] || tone
  // What the card is drawn on when the pointer is not on it.
  readonly property color restFill: selected ? (row.state === "input" ? Palette.wash(colors.surfaceSelected, tone) : colors.surfaceSelected)
    : row.state === "input" ? Palette.wash(colors.surface, tone) : child ? colors.background : colors.surface
  readonly property bool alarm: Store.isAlarm(row.state)
  readonly property bool needsYou: Store.ATTENTION[row.state] === true
  readonly property color wordInk: Store.inkRole(row.state) ? colors[Store.inkRole(row.state)] : colors.textDim
  readonly property bool loud: Store.isLoud(row.state)
  readonly property var activity: Store.currentActivity(row)
  readonly property real indent: child ? Style.space(22) : 0

  // The time with the word that says what kind of time it is, as on the two-pane rows.
  readonly property string elapsedText: Format.rowTime(row, now, Store.BUSY[row.state] === true)

  readonly property string metaText: {
    var parts = []
    if (showMachine && machineLabel) parts.push(machineLabel)
    if (!child) parts.push(row.project)
    if (row.branch) parts.push(row.branch)
    if (row.model) parts.push(Format.model(row.model))
    // One space either side of the dot, as in the detail pane: the wider gaps cost the line the
    // end of its model name.
    return parts.join(" · ")
  }

  implicitHeight: card.height + Style.space(child ? 2 : 4)

  Rectangle {
    id: card
    objectName: "fill"
    x: root.indent
    width: root.width - root.indent
    height: content.implicitHeight + Style.space(root.child ? 12 : 18)
    radius: Style.cornerRadius
    // Normal / hover / selected. Rows that need you get a rail in their colour, and those waiting on
    // your answer a faint wash too, which they keep while selected; the selected card adds the ring.
    color: root.selected ? (root.row.state === "input" ? Palette.wash(root.colors.surfaceSelected, root.tone) : root.colors.surfaceSelected)
      : hover.hovered ? Style.hoverFillFor(root.colors.text, root.colors.accent)
      : root.row.state === "input" ? Palette.wash(root.colors.surface, root.tone)
      : root.child ? "transparent" : root.colors.surface
    border.width: root.selected ? Style.space(2) : 0
    border.color: root.colors.focus
    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // (As on the two-pane row: a selected needs-you card's rail sits on the card, not on the ring.)
    Rectangle {
      objectName: "railBack"
      visible: root.selected && root.needsYou
      width: rail.width
      height: parent.height
      color: parent.color
    }
    Rail {
      id: rail
      visible: root.needsYou || root.selected
      height: parent.height
      color: root.needsYou ? root.tone : root.colors.focus
      dashed: root.row.state === "failed"
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
          objectName: "stateGlyph"
          anchors.verticalCenter: title.lineCount > 1 ? undefined : parent.verticalCenter
          y: title.lineCount > 1 ? Style.space(1) : 0
          icon: Store.stateIcon(root.row)
          threadState: root.row.state
          color: root.glyphInk
          breathTo: Palette.breathFloor(root.glyphInk, root.restFill)
          size: Math.round(Typo.body * (root.child ? 1.0 : 1.15))
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
          font.pixelSize: root.child ? Typo.caption : Typo.body
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
            color: root.loud ? root.colors.textDim : root.colors.textFaint
            font.family: root.monoFamily
            font.pixelSize: Typo.caption
            font.features: { "tnum": 1 }
          }
          Text {
            anchors.right: parent.right
            visible: !root.child || root.loud
            text: Store.stateLabel(root.row)
            textFormat: Text.PlainText
            color: root.needsYou ? root.wordInk : root.loud ? root.colors.textDim : root.colors.textFaint
            font.family: root.fontFamily
            font.pixelSize: Typo.caption
            font.weight: root.needsYou ? Font.DemiBold : Font.Normal
          }
        }
      }

      // project · branch · model. It stops short of the state word in the right column, which hangs
      // down beside it: a long branch name is cut before it can run into "Run command?".
      ElidedText {
        visible: fullText !== "" && !root.child
        x: glyph.width + Style.space(8)
        width: parent.width - x - right.width - Style.space(16)
        fullText: root.metaText
        color: root.colors.textFaint
        font.family: root.fontFamily
        font.pixelSize: Typo.caption
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
          color: root.activity && root.activity.status === "running" ? root.colors.workingInk : root.colors.textDim
          size: Math.round(Typo.caption * 1.25)
        }
        ElidedText {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - actIcon.width - Style.space(6)
          fullText: root.activity ? root.activity.label : ""
          color: root.colors.textDim
          font.family: root.activity && root.activity.icon === "terminal" ? root.monoFamily : root.fontFamily
          font.pixelSize: Typo.caption
        }
      }

      ThreadChips {
        x: glyph.width + Style.space(8)
        width: parent.width - x
        visible: anyVisible
        row: root.row
        detail: root.detail
        colors: root.colors
        showContext: !root.expanded
        showSubagentTotal: root.expanded
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
