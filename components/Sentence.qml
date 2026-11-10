import QtQuick
import qs.Commons
import "../lib/Format.js" as Format

// A sentence that wraps. Its lines run the full width it is given, and it never leaves one word
// alone on its last line: plain wrapping drops whatever is left onto the next line, so a sentence
// a little longer than its line ends "…check the" / "provider". Here the word before it comes
// down too ("…check" / "the provider"), and nothing else moves. (It used to even the lines out
// instead, which broke a sentence at 60% of its width beside empty space.) It breaks at spaces
// only, so "auto-resume" stays whole.
// `lead` is drawn before the first line ("→ ", "now: "); later lines hang under the sentence, not
// under the lead, so a second line reads as the same sentence.
// Give it a width; it is as tall as its lines.
Item {
  id: root
  property string text: ""
  property string lead: ""
  property alias color: shown.color
  property color leadColor: shown.color
  property alias font: shown.font
  readonly property alias lineCount: shown.lineCount
  // The longest line as drawn, lead included, for tests.
  readonly property real contentWidth: shown.x + shown.contentWidth
  // The sentence as broken into lines.
  readonly property string laid: {
    // (Read so the lines are broken again when the font changes: advanceWidth is a call.)
    var font = metrics.font
    return Format.wrapSentence(text, shown.width - 1, function(s) { return metrics.advanceWidth(s) })
  }

  implicitWidth: shown.x + metrics.advanceWidth(text)
  implicitHeight: shown.implicitHeight

  FontMetrics { id: metrics; font: shown.font }

  Text {
    id: leadText
    visible: root.lead !== ""
    text: root.lead
    textFormat: Text.PlainText
    color: root.leadColor
    font: shown.font
  }
  Text {
    id: shown
    x: root.lead !== "" ? leadText.implicitWidth : 0
    width: Math.max(0, root.width - x)
    text: root.laid
    textFormat: Text.PlainText
    // The lines are already broken; wrapping stays on for a word longer than the line.
    wrapMode: Text.Wrap
  }
}
