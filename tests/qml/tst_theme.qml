import QtQuick
import QtTest
import qs.Commons as Omarchy
import "../.." as Plugin

TestCase {
  name: "Theme"

  Plugin.Theme { id: theme }

  function test_themeTokens() {
    verify(theme.popup !== undefined, "Omarchy Color must not resolve to Qt Quick Color")
    compare(theme.popup.background, "#01041f")
    compare(theme.popup.text, "#d6cae3")
    compare(theme.bar.background, "#01041f")

    Omarchy.Color.popups.background = "#f0f0f0"
    Omarchy.Color.popups.text = "#101010"
    Omarchy.Color.bar.background = "#202030"
    Omarchy.Color.accent = "#334477"
    Omarchy.Color.shellValues = ({ updated: true })

    compare(theme.popup.background, "#f0f0f0")
    compare(theme.popup.text, "#101010")
    compare(theme.bar.background, "#202030")
    verify(theme.popup.light)
  }
}
