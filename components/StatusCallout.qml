import QtQuick
import qs.Commons

// The block a thread's detail leads with: what state it is in, why, the provider's own words when
// there are any, and the one thing to do next. Content comes from Store.statusCallout.
Rectangle {
  id: root
  property var callout: null
  property var colors: ({})
  property string fontFamily: Style.font.family
  property string monoFamily: "monospace"
  // The thread, for the actions the block ends with, and how copying its title just ended.
  property var row: null
  property string copyState: ""
  // Offer copy and PR beside "open T3" (the dropdown's expanded card has its own buttons for them).
  property bool secondary: true

  signal actionRequested(string action)

  readonly property color mark: callout ? (colors[callout.tone] || colors.textFaint) : "transparent"
  readonly property color ink: callout ? (colors[callout.tone + "Ink"] || colors.text) : colors.text
  // Red and amber lead in their own ink; calmer states lead in plain text.
  readonly property bool loud: callout !== null && (callout.tone === "attention" || callout.tone === "warning")

  visible: callout !== null
  implicitHeight: callout ? body.implicitHeight + Style.space(20) : 0
  radius: Style.cornerRadius
  color: callout ? Qt.rgba(mark.r, mark.g, mark.b, loud ? 0.09 : 0.05) : "transparent"

  Rectangle { width: Style.space(3); height: parent.height; color: root.mark }

  Column {
    id: body
    x: Style.space(15)
    y: Style.space(10)
    width: parent.width - Style.space(26)
    spacing: Style.space(7)

    Item {
      width: parent.width
      height: Math.max(icon.height, headline.implicitHeight)
      LucideIcon {
        id: icon
        y: Math.max(0, (Math.min(headline.implicitHeight, headline.font.pixelSize * 1.5) - height) / 2)
        name: root.callout ? root.callout.icon : "circle-dot"
        color: root.loud ? root.ink : root.mark
        size: Math.round(Typo.body * 1.1)
      }
      Text {
        id: headline
        anchors.left: icon.right
        anchors.leftMargin: Style.space(8)
        anchors.right: parent.right
        text: root.callout ? root.callout.headline : ""
        textFormat: Text.PlainText
        color: root.loud ? root.ink : root.colors.text
        font.family: root.fontFamily
        font.pixelSize: Typo.bodySmall
        font.weight: Font.DemiBold
        wrapMode: Text.Wrap
      }
    }

    Sentence {
      visible: text !== ""
      width: parent.width
      text: root.callout ? root.callout.body : ""
      color: root.colors.textDim
      font.family: root.fontFamily
      font.pixelSize: Typo.caption
    }

    // The provider's message, verbatim: it is the evidence, so it is never cut short.
    Rectangle {
      visible: root.callout !== null && root.callout.raw !== ""
      width: parent.width
      height: raw.implicitHeight + Style.space(14)
      radius: Style.cornerRadius
      color: root.colors.background
      border.width: 1
      border.color: root.colors.line
      Text {
        id: raw
        x: Style.space(10)
        y: Style.space(7)
        width: parent.width - Style.space(20)
        text: root.callout ? root.callout.raw : ""
        textFormat: Text.PlainText
        color: root.colors.text
        font.family: root.monoFamily
        font.pixelSize: Typo.caption
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        maximumLineCount: 12
        elide: Text.ElideRight
      }
    }

    // The next step, as a sentence in full-strength ink, and under it the keys that carry it out.
    // The step is done in T3, so the block ends with the key that brings T3 forward, labelled
    // for what it does ("open T3"): the sentence says what to do there, the key how to get there.
    // (A keycap in front of the sentence read as "o restores the folder".)
    Sentence {
      objectName: "nextStep"
      visible: root.callout !== null && root.callout.next !== ""
      width: parent.width
      lead: "→ "
      text: root.callout ? root.callout.next : ""
      color: root.colors.text
      font.family: root.fontFamily
      font.pixelSize: Typo.caption
      font.weight: Font.Medium
    }
    ThreadActions {
      visible: root.callout !== null
      width: parent.width
      margin: 0
      row: root.row
      colors: root.colors
      fontFamily: root.fontFamily
      monoFamily: root.monoFamily
      copyState: root.copyState
      secondary: root.secondary
      onActionRequested: function(action) { root.actionRequested(action) }
    }
  }
}
