import QtQuick

// One line, cut to fit with a single "…" set tight against the last word, whatever Qt would have
// done with the space before it ("sessions…", never "sessions …").
Text {
  id: root
  property string fullText: ""

  TextMetrics {
    id: metrics
    font: root.font
    text: root.fullText
    elide: Qt.ElideRight
    elideWidth: Math.max(0, root.width)
  }

  text: root.width > 0 ? metrics.elidedText.replace(/\s+…$/, "…") : root.fullText
  textFormat: Text.PlainText
  elide: Text.ElideNone
  clip: true
}
