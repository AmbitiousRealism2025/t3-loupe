pragma Singleton
import QtQuick
import qs.Commons

// Loupe's type scale: the shell's tokens plus an optional size bump (pixels), so the panel
// can read larger without changing the shell-wide base size. Set from settings.json
// "textSize" (e.g. 2) and nudged live with +/- in the panel.
QtObject {
  property real bump: 0
  readonly property int caption: Math.round(Style.font.caption + bump)
  readonly property int bodySmall: Math.round(Style.font.bodySmall + bump)
  readonly property int body: Math.round(Style.font.body + bump)
  readonly property int subtitle: Math.round(Style.font.subtitle + bump)
  readonly property int title: Math.round(Style.font.title + bump)
  readonly property int heading: Math.round(Style.font.heading + bump)
  readonly property int display: Math.round(Style.font.display + bump)
}
