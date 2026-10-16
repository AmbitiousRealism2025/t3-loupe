import QtQuick
import "../lib/Store.js" as Store

// The panel's filter box. It has no editable text input: TextField, TextInput and TextEdit can read
// the clipboard on their own, and a filter has no use for paste. Typing arrives as key events instead,
// so the box takes keys only while it has focus. Enter and Esc hand them back to the panel.
// Not supported on purpose: paste, mouse selection and input-method composition.
Item {
  id: root

  property string text: ""
  property string placeholder: "/ filter"
  property color foreground: "white"
  property color dim: "gray"
  property color border: "gray"
  property color accent: "white"
  property string fontFamily: ""
  property real fontSize: 12
  property real radius: 0
  property real padding: 8

  // Typing changed the text; the owner stores it and binds `text` back.
  signal edited(string text)
  // Enter or Esc: give the keys back to the panel.
  signal finished()
  signal clicked()

  implicitWidth: 100
  implicitHeight: Math.ceil(label.implicitHeight) + padding * 1.5
  activeFocusOnTab: false

  Keys.onPressed: function(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var other = (event.modifiers & (Qt.AltModifier | Qt.MetaModifier)) !== 0
    var action = "text"
    if (event.key === Qt.Key_Escape) action = "escape"
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) action = "enter"
    else if (event.key === Qt.Key_Backspace) action = ctrl ? "word" : "backspace"
    else if (ctrl && event.key === Qt.Key_W) action = "word"
    else if (ctrl && event.key === Qt.Key_U) action = "clear"
    else if (ctrl || other) { event.accepted = true; return }
    var result = Store.editFilter(root.text, action, event.text)
    if (!result.handled) return
    event.accepted = true
    if (result.query !== root.text) root.edited(result.query)
    if (result.done) root.finished()
  }

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: "transparent"
    border.width: 1
    border.color: root.activeFocus ? root.accent : root.border
  }

  Text {
    id: label
    anchors.left: parent.left
    anchors.leftMargin: root.padding
    anchors.right: parent.right
    anchors.rightMargin: root.padding + (root.activeFocus ? 3 : 0)
    anchors.verticalCenter: parent.verticalCenter
    text: root.text !== "" ? root.text : root.placeholder
    textFormat: Text.PlainText
    color: root.text !== "" ? root.foreground : root.dim
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    elide: Text.ElideLeft
    maximumLineCount: 1
  }

  // Static caret, so there is nothing to animate or to switch off for reduced motion.
  Rectangle {
    visible: root.activeFocus
    x: Math.min(label.x + (root.text !== "" ? label.contentWidth : 0) + 1, root.width - root.padding)
    anchors.verticalCenter: parent.verticalCenter
    width: 1
    height: Math.ceil(label.implicitHeight) - 2
    color: root.foreground
  }

  HoverHandler { cursorShape: Qt.IBeamCursor }
  TapHandler { onTapped: root.clicked() }
}
