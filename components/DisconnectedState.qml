import QtQuick
import qs.Commons
import "../lib/Store.js" as Store
import "../lib/Format.js" as Format

// No paired machine is reachable, so there is nothing to list. Instead of an empty list, say so,
// and give each machine what is wrong with it and the step that brings it back.
Column {
  id: root
  property var environments: []
  property var colors: ({})
  property double now: Date.now()
  property string fontFamily: Style.font.family
  property string monoFamily: "monospace"
  // The commands that can be copied, in order: [{ id (machine), text }]. Command n is copied by
  // the digit key n, shown as a keycap on its block; clicking the keycap does the same.
  property var commands: []
  // The panel's last copy: what ("command:<machine id>") and how it ended ("" | "ok" | "failed").
  property string copyTarget: ""
  property string copyResult: ""

  signal copyRequested(string id, string text)

  function commandIndex(id) {
    for (var i = 0; i < commands.length; i++) if (commands[i].id === id) return i
    return -1
  }

  readonly property bool allExpired: {
    for (var i = 0; i < environments.length; i++)
      if (environments[i].state !== "expired" && environments[i].state !== "authentication_required") return false
    return environments.length > 0
  }

  spacing: Style.space(14)

  Row {
    spacing: Style.space(12)
    LucideIcon {
      anchors.verticalCenter: parent.verticalCenter
      name: root.allExpired ? "key-round" : "plug-zap"
      color: root.colors.attention
      size: Math.round(Typo.display * 1.0)
    }
    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)
      Text {
        text: "Not connected to T3"
        textFormat: Text.PlainText
        color: root.colors.text
        font.family: root.fontFamily
        font.pixelSize: Typo.title
        font.bold: true
      }
      Text {
        width: root.width - Style.space(60)
        text: (root.allExpired
          ? (root.environments.length === 1 ? "The pairing has expired" : "All " + root.environments.length + " pairings have expired")
          : "No paired machine is reachable") + ", so Loupe can't see any threads. Nothing is lost: threads keep running in T3."
        textFormat: Text.PlainText
        color: root.colors.textDim
        font.family: root.fontFamily
        font.pixelSize: Typo.bodySmall
        wrapMode: Text.Wrap
      }
    }
  }

  // One card per machine: name and problem, then the fix.
  Repeater {
    model: root.environments
    Rectangle {
      id: card
      required property var modelData
      readonly property var step: Store.repairStep(modelData)
      readonly property bool ok: Store.environmentOk(modelData.state)
      // This machine's place among the copyable commands: its digit key is place + 1.
      readonly property int place: root.commandIndex(modelData.id)
      readonly property string copied: root.copyTarget === "command:" + modelData.id ? root.copyResult : ""
      width: root.width
      height: cardBody.implicitHeight + Style.space(22)
      radius: Style.cornerRadius
      color: root.colors.surface
      border.width: 1
      border.color: root.colors.line

      Rectangle { visible: !card.ok; width: Style.space(3); height: parent.height; color: root.colors.attention }

      Column {
        id: cardBody
        x: Style.space(16)
        y: Style.space(11)
        width: parent.width - Style.space(32)
        spacing: Style.space(8)

        Row {
          spacing: Style.space(8)
          LucideIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: card.modelData.sshHost ? "server" : "laptop"
            color: root.colors.textDim
            size: Math.round(Typo.body * 1.1)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: card.modelData.label
            textFormat: Text.PlainText
            color: root.colors.text
            font.family: root.fontFamily
            font.pixelSize: Typo.body
            font.weight: Font.DemiBold
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Store.environmentLabel(card.modelData.state)
              + (card.modelData.state === "expired" && card.modelData.sessionExpiresAt ? " " + Format.ago(card.modelData.sessionExpiresAt, root.now) : "")
            textFormat: Text.PlainText
            color: card.ok ? root.colors.textDim : root.colors.attentionInk
            font.family: root.fontFamily
            font.pixelSize: Typo.caption
            font.weight: Font.Medium
          }
        }

        Text {
          visible: card.step.kind === "command"
          width: parent.width
          text: "Pair it again from a terminal:"
          textFormat: Text.PlainText
          color: root.colors.textDim
          font.family: root.fontFamily
          font.pixelSize: Typo.caption
        }
        // The command to run, set as code, with the key that copies it at its right end.
        Rectangle {
          visible: card.step.kind === "command"
          width: parent.width
          height: Math.max(cmd.implicitHeight, copyKey.visible ? copyKey.implicitHeight : 0) + Style.space(14)
          radius: Style.cornerRadius
          color: root.colors.background
          border.width: 1
          border.color: root.colors.line
          Text {
            id: cmd
            x: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            // Room is kept for the copy action at its widest ("copy failed"), so the command
            // doesn't re-wrap while the outcome shows.
            width: parent.width - Style.space(20) - (copyKey.visible ? copyProbe.implicitWidth + Style.space(52) : 0)
            text: "$ " + card.step.text
            textFormat: Text.PlainText
            color: root.colors.text
            font.family: root.monoFamily
            font.pixelSize: Typo.caption
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          }
          KeyAction {
            id: copyKey
            visible: card.place >= 0
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            key: String(card.place + 1)
            text: "copy"
            feedback: card.copied === "ok" ? "✓ copied" : card.copied === "failed" ? "copy failed" : ""
            feedbackInk: card.copied === "failed" ? root.colors.attentionInk : root.colors.text
            quiet: true
            colors: root.colors
            fontFamily: root.fontFamily
            monoFamily: root.monoFamily
            onClicked: root.copyRequested(card.modelData.id, card.step.text)
          }
          Text { id: copyProbe; visible: false; text: "copy failed"; textFormat: Text.PlainText; font.family: root.fontFamily; font.pixelSize: Typo.caption; font.weight: Font.Medium }
        }
        Text {
          visible: card.step.kind === "note"
          width: parent.width
          text: card.step.text
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
    width: root.width
    text: "Loupe picks up a new pairing within a few seconds; there is nothing to restart."
    textFormat: Text.PlainText
    color: root.colors.textFaint
    font.family: root.fontFamily
    font.pixelSize: Typo.caption
    wrapMode: Text.Wrap
  }
}
