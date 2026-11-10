import QtQuick
import qs.Commons

// A sentence that wraps without leaving a word alone on its last line. Text fills each line and
// drops what is left onto the next, so a sentence a little longer than its line ends in an orphan
// ("…check the" / "provider"). This breaks it into the same number of lines at a narrower measure,
// so the lines come out about the same length. It never takes more lines than plain wrapping would.
// Give it a width; it is as tall as its lines.
Item {
  id: root
  property alias text: shown.text
  property alias color: shown.color
  property alias font: shown.font
  readonly property alias lineCount: shown.lineCount
  // The longest line as drawn, for tests.
  readonly property alias contentWidth: shown.contentWidth

  implicitWidth: natural.implicitWidth
  implicitHeight: shown.implicitHeight

  // The sentence on one line, and wrapped to the full width: how wide it is, how many lines it needs.
  Text { id: natural; visible: false; text: shown.text; textFormat: Text.PlainText; font: shown.font }
  Text { id: plain; visible: false; width: root.width; text: shown.text; textFormat: Text.PlainText; font: shown.font; wrapMode: Text.Wrap }
  // The narrower measure: an equal share of the sentence per line, and a little over, since a
  // line can only break between words.
  readonly property real measure: plain.lineCount > 1
    ? Math.min(root.width, Math.ceil(natural.implicitWidth / plain.lineCount) + natural.font.pixelSize * 4)
    : root.width
  // Tried at that measure: if it would take an extra line, the full width is used after all.
  Text { id: trial; visible: false; width: root.measure; text: shown.text; textFormat: Text.PlainText; font: shown.font; wrapMode: Text.Wrap }

  Text {
    id: shown
    width: trial.lineCount <= plain.lineCount ? root.measure : root.width
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
  }
}
