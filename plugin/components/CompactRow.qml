import QtQuick
import qs.Commons
import "../lib/Store.js" as Store
import "../lib/Format.js" as Format

// Two-pane list row: state glyph, title, live activity (or project), time and state.
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
  readonly property color tone: colors[Store.stateRole(row.state)] || colors.textDim
  readonly property color ink: colors[Store.stateRole(row.state) + "Ink"] || colors.textDim
  readonly property bool loud: Store.isLoud(row.state)
  readonly property var activity: Store.currentActivity(row)
  readonly property bool showActivity: activity !== null && (Store.BUSY[row.state] === true || row.state === "input")
  readonly property real indent: child ? Style.space(22) : 0
  readonly property string metaText: {
    var parts = []
    if (showMachine && machineLabel) parts.push(machineLabel)
    if (!child) parts.push(row.project)
    if (row.branch) parts.push(row.branch)
    return parts.join("  ·  ")
  }

  implicitHeight: body.implicitHeight + Style.space(child ? 6 : 12)

  // Tree connector for subagents.
  Rectangle { visible: root.child; x: Style.space(9); y: -Style.space(3); width: 1; height: parent.height / 2 + Style.space(3); color: root.colors.line }
  Rectangle { visible: root.child; x: Style.space(9); y: parent.height / 2; width: Style.space(9); height: 1; color: root.colors.line }

  Rectangle {
    id: card
    x: root.indent
    width: parent.width - root.indent
    height: parent.height
    radius: Style.cornerRadius
    color: root.selected ? root.colors.surfaceSelected : hover.hovered ? root.colors.surfaceRaised : root.child ? "transparent" : root.colors.surface
    border.width: root.selected ? 1 : 0
    border.color: Qt.rgba(root.colors.accent.r, root.colors.accent.g, root.colors.accent.b, 0.55)
    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Rectangle {
      width: Style.space(3)
      height: parent.height
      color: root.tone
      opacity: root.loud ? 1 : (root.row.state === "review" ? 0.8 : 0.28)
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.clicked() }

    Item {
      id: body
      x: Style.space(12)
      y: Style.space(root.child ? 3 : 6)
      width: parent.width - Style.space(22)
      implicitHeight: Math.max(left.implicitHeight, right.implicitHeight)

      StateGlyph {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        icon: Store.stateIcon(root.row)
        threadState: root.row.state
        color: root.tone
        size: Math.round(Style.font.body * (root.child ? 1.0 : 1.15))
        reduceMotion: root.reduceMotion
      }

      Column {
        id: left
        anchors.left: glyph.right
        anchors.leftMargin: Style.space(9)
        anchors.right: right.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: root.row.title
          textFormat: Text.PlainText
          color: root.child || root.row.state === "idle" || root.row.state === "stopped" ? root.colors.textDim : root.colors.text
          font.family: root.fontFamily
          font.pixelSize: root.child ? Style.font.caption : Style.font.bodySmall
          font.weight: root.child ? Font.Normal : Font.DemiBold
          elide: Text.ElideRight
        }
        Row {
          visible: root.showActivity || root.metaText !== ""
          width: parent.width
          spacing: Style.space(6)
          LucideIcon {
            id: actIcon
            visible: root.showActivity
            anchors.verticalCenter: parent.verticalCenter
            name: root.activity ? root.activity.icon : "zap"
            color: root.activity && root.activity.status === "running" ? root.colors.accentInk : root.colors.textFaint
            size: Math.round(Style.font.caption * 1.15)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (actIcon.visible ? actIcon.width + parent.spacing : 0)
            text: root.showActivity ? root.activity.label : root.metaText
            textFormat: Text.PlainText
            color: root.showActivity ? root.colors.textDim : root.colors.textFaint
            font.family: root.showActivity && root.activity.icon === "terminal" ? root.monoFamily : root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      Column {
        id: right
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)
        Text {
          anchors.right: parent.right
          text: Format.elapsed(root.row, root.now, Store.BUSY[root.row.state] === true)
          textFormat: Text.PlainText
          color: root.loud ? root.colors.text : root.colors.textFaint
          font.family: root.monoFamily
          font.pixelSize: Style.font.caption
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
  }
}
