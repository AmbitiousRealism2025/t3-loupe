import QtQuick
import qs.Commons
import "lib/Notices.js" as Notices

// Desktop notifications for daemon notices. Preferences live in
// ~/.config/t3-loupe/settings.json under "notifications" (see README).
// Notification text can be read by other local accounts on Omarchy (lib/Notices.js explains
// why), so by default it names only the kind of event; the click opens the thread.
QtObject {
  id: root
  property var service: null

  readonly property var glyphs: ({ attention: "󰂞", milestone: "󰄬", info: "󰌘" })

  // Text is untrusted (thread titles, when details are on); keep it from looking like an option.
  function safe(text, limit) {
    var t = String(text || "").replace(/[\r\t]/g, " ").slice(0, limit)
    return /^-/.test(t) ? "‐" + t.slice(1) : t
  }

  function notice(n) {
    var settings = service ? service.settings : null
    if (!Notices.wanted(n, settings, service ? service.openPanels : 0)) return
    var shown = Notices.text(n, settings)
    var argv = ["omarchy-notification-send", "--app-name", "T3 Loupe",
      "-u", n.severity === "attention" ? "normal" : "low",
      "-g", glyphs[n.severity] || glyphs.info,
      safe(shown.title, 160)]
    var body = safe(shown.body, 400)
    if (body) argv.push(body)
    // The click carries only opaque ids.
    if (n.envId && n.threadId) argv.push("--exec", "omarchy-shell", "-q", "ambitiousrealism.t3-loupe", "focus", n.envId + ":" + n.threadId)
    else argv.push("--exec", "omarchy-shell", "-q", "ambitiousrealism.t3-loupe", "open")
    Util.execArgv(argv)
  }

  function test() {
    notice({ kind: "test", severity: "attention", envId: "", threadId: "", title: "T3 Loupe notifications are on", body: "Click to open the panel." })
  }
}
