import QtQuick
import QtTest

// The real FilterField, driven with key events. Run by tests/filter-field.test.mjs.
TestCase {
  id: tc
  name: "FilterField"
  width: 300
  height: 60
  visible: true
  when: windowShown

  Component { id: factory; Item { width: 300; height: 60; property alias box: box
    Loader { id: box; source: Qt.resolvedUrl("../../components/FilterField.qml")
      width: 200; height: 30
      onLoaded: { item.fontFamily = "sans"; item.fontSize = 12 } } } }

  SignalSpy { id: edited; signalName: "edited" }
  SignalSpy { id: finished; signalName: "finished" }
  SignalSpy { id: clicked; signalName: "clicked" }

  property var field: null

  function init() {
    var host = createTemporaryObject(factory, tc)
    tryCompare(host.box, "status", Loader.Ready)
    field = host.box.item
    edited.target = field; edited.clear()
    finished.target = field; finished.clear()
    clicked.target = field; clicked.clear()
    field.forceActiveFocus()
    verify(field.activeFocus)
  }

  // The owner binds `text` back to the stored query; do the same here.
  function type(keys) {
    for (var i = 0; i < keys.length; i++) {
      keyClick(keys[i])
      if (edited.count) { field.text = edited.signalArguments[edited.count - 1][0] }
    }
  }

  function test_typing_builds_the_text() {
    type("riv")
    compare(field.text, "riv")
    compare(edited.count, 3)
    compare(finished.count, 0)
  }

  function test_navigation_letters_are_just_letters() {
    type("jkhlx ")
    compare(field.text, "jkhlx ")
  }

  function test_backspace_and_ctrl_shortcuts() {
    type("two words")
    keyClick(Qt.Key_Backspace); field.text = edited.signalArguments[edited.count - 1][0]
    compare(field.text, "two word")
    keyClick(Qt.Key_W, Qt.ControlModifier); field.text = edited.signalArguments[edited.count - 1][0]
    compare(field.text, "two ")
    keyClick(Qt.Key_U, Qt.ControlModifier); field.text = edited.signalArguments[edited.count - 1][0]
    compare(field.text, "")
  }

  function test_enter_keeps_the_text_and_finishes() {
    type("riv")
    keyClick(Qt.Key_Return)
    compare(finished.count, 1)
    compare(field.text, "riv")
  }

  function test_escape_clears_and_finishes() {
    type("riv")
    keyClick(Qt.Key_Escape)
    compare(finished.count, 1)
    compare(edited.signalArguments[edited.count - 1][0], "")
  }

  function test_other_shortcuts_change_nothing() {
    // No paste: Ctrl+V and Shift+Insert do nothing here, and other Ctrl/Alt chords are swallowed.
    keyClick(Qt.Key_V, Qt.ControlModifier)
    keyClick(Qt.Key_Insert, Qt.ShiftModifier)
    keyClick(Qt.Key_A, Qt.AltModifier)
    keyClick(Qt.Key_C, Qt.ControlModifier)
    compare(edited.count, 0)
    compare(field.text, "")
  }

  function test_text_is_capped() {
    for (var i = 0; i < 100; i++) { keyClick("x"); field.text = edited.count ? edited.signalArguments[edited.count - 1][0] : field.text }
    compare(field.text.length, 80)
  }

  function test_tap_reports_a_click() {
    mouseClick(field)
    compare(clicked.count, 1)
  }

  function test_no_editable_text_input_inside() {
    function walk(item) {
      var name = String(item)
      verify(name.indexOf("TextInput") < 0 && name.indexOf("TextField") < 0 && name.indexOf("TextEdit") < 0, name)
      for (var i = 0; i < item.children.length; i++) walk(item.children[i])
    }
    walk(field)
  }
}
