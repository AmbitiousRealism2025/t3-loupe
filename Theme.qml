import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Omarchy
import "lib/Palette.js" as Palette

// Semantic palette for T3 Loupe, rebuilt whenever the Omarchy theme changes.
// Qualify Color explicitly: Qt Quick also exports a type with that name.
// Base tokens come from qs.Commons.Color; extra hues come from the theme's
// colors.toml. `popup` is for panel surfaces, `bar` for marks drawn on the bar.
QtObject {
  id: root

  property var named: ({})
  readonly property string colorsPath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"

  function hexOf(c) { return Qt.rgba(c.r, c.g, c.b, 1).toString() }

  readonly property var popup: Palette.derive({
    background: hexOf(Omarchy.Color.popups.background), foreground: hexOf(Omarchy.Color.popups.text),
    accent: hexOf(Omarchy.Color.accent), urgent: hexOf(Omarchy.Color.urgent), muted: hexOf(Omarchy.Color.muted), colors: named
  })
  readonly property var bar: Palette.derive({
    background: hexOf(Omarchy.Color.bar.background), foreground: hexOf(Omarchy.Color.bar.text),
    accent: hexOf(Omarchy.Color.accent), urgent: hexOf(Omarchy.Color.urgent), muted: hexOf(Omarchy.Color.muted), colors: named
  })

  function stateColor(state) { return Palette.stateColor(popup, state) }
  function stateInk(state) { return Palette.stateInk(popup, state) }
  function role(name) { return popup[name] || popup.textDim }
  function barRole(name) { return bar[name] || bar.textDim }

  property FileView file: FileView {
    path: root.colorsPath
    printErrors: false
    onLoaded: root.named = Palette.parseColorsToml(text())
    onLoadFailed: root.named = ({})
  }

  // The theme directory is replaced on every switch, so a file watch is
  // unreliable; the shell reassigns shellValues on every applied theme.
  property Connections themeWatch: Connections {
    target: Omarchy.Color
    function onShellValuesChanged() { root.file.reload() }
  }
}
