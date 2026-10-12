import QtQuick
import Quickshell
import qs.Commons

// Desktop notifications for daemon notices. Preferences live in
// ~/.config/t3-loupe/settings.json under "notifications" (see README).
QtObject {
  id: root
  property var service: null

  // Severity groups on by default; individual kinds can be switched in "kinds".
  readonly property var defaults: ({ attention: true, milestone: true, info: false })
  readonly property var glyphs: ({ attention: "󰂞", milestone: "󰄬", info: "󰌘" })

  function prefs() {
    var s = service && service.settings ? service.settings.notifications : null
    return s && typeof s === "object" ? s : {}
  }

  function wanted(n) {
    var p = prefs()
    if (p.enabled === false) return false
    if (p.kinds && typeof p.kinds[n.kind] === "boolean") return p.kinds[n.kind]
    if (typeof p[n.severity] === "boolean") return p[n.severity]
    if (service && service.openPanels > 0 && p.whenPanelOpen !== true && n.severity !== "attention") return false
    return defaults[n.severity] === true
  }

  // Notification text is untrusted (thread titles); keep it from looking like an option.
  function safe(text, limit) {
    var t = String(text || "").replace(/[\r\t]/g, " ").slice(0, limit)
    return /^-/.test(t) ? "‐" + t.slice(1) : t
  }

  function notice(n) {
    if (!wanted(n)) return
    var argv = ["omarchy-notification-send", "--app-name", "T3 Loupe",
      "-u", n.severity === "attention" ? "normal" : "low",
      "-g", glyphs[n.severity] || glyphs.info,
      safe(n.title, 160)]
    var body = safe(n.body, 400)
    if (body) argv.push(body)
    if (n.envId && n.threadId) argv.push("--exec", "omarchy-shell", "-q", "ambitiousrealism.t3-loupe", "focus", n.envId + ":" + n.threadId)
    else argv.push("--exec", "omarchy-shell", "-q", "ambitiousrealism.t3-loupe", "open")
    Util.execArgv(argv)
  }

  function test() {
    notice({ kind: "test", severity: "attention", envId: "", threadId: "", title: "T3 Loupe notifications are on", body: "Click to open the panel." })
  }
}
