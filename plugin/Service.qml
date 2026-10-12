import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "components"

// Shared service: owns the t3-loupe process, the theme palette and notifications.
// Bar widgets (one per monitor, in any bar or the Notch Strip) read from here.
Item {
  id: root

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string configDir: Quickshell.env("HOME") + "/.config/t3-loupe"

  // Latest daemon state (protocol v1).
  property var environments: []
  property var rows: []
  property var counts: ({ active: 0, busy: 0, attention: 0, input: 0, review: 0 })
  property bool known: false
  property string configError: ""
  // starting | ready | stale | down
  property string health: "starting"
  property string lastError: ""
  property double lastReceived: 0

  // Thread detail pushed while a drawer is open: key "env:thread" → detail.
  property var details: ({})
  property int openPanels: 0
  property double now: Date.now()

  property var settings: ({})
  // Panel text size: a pixel bump over the shell's type scale, saved as settings.json "textSize".
  // The footer control and +/- step through four presets; the default is the smallest.
  readonly property var textSizes: [0, 2, 4, 6]
  readonly property real savedTextSize: settings && typeof settings.textSize === "number" ? Math.max(-2, Math.min(8, settings.textSize)) : 0
  property real pendingTextSize: NaN   // shown immediately, until the settings file reloads
  readonly property real textSize: !isNaN(pendingTextSize) ? pendingTextSize : savedTextSize
  // Index of the largest preset at or below the current size.
  readonly property int textSizeStep: {
    var step = 0
    for (var i = 0; i < textSizes.length; i++) if (textSize >= textSizes[i]) step = i
    return step
  }
  onTextSizeChanged: Typo.bump = textSize
  Component.onCompleted: Typo.bump = textSize

  function setTextSize(value) {
    pendingTextSize = value
    var next = {}
    for (var k in settings) next[k] = settings[k]
    next.textSize = value
    settingsFile.setText(JSON.stringify(next, null, 2) + "\n")
  }
  function stepTextSize(delta) {
    var step = textSizeStep
    // An off-preset size (e.g. 1) steps up to the next preset, not past it.
    if (delta > 0 && textSize !== textSizes[step]) step -= 1
    var target = Math.max(0, Math.min(textSizes.length - 1, step + delta))
    if (textSizes[target] !== textSize) setTextSize(textSizes[target])
  }
  readonly property var theme: themeObject
  readonly property var widgets: []

  signal focusRequested(string key)

  Theme { id: themeObject }
  Notifier { id: notifier; service: root }

  // A 1 s clock for elapsed timers, only while someone is looking.
  Timer {
    interval: 1000
    repeat: true
    running: root.openPanels > 0
    triggeredOnStart: true
    onTriggered: root.now = Date.now()
  }

  // The bar ring has no timers; stale detection is coarse.
  Timer {
    interval: 15000
    repeat: true
    running: true
    onTriggered: {
      if (root.health === "ready" && Date.now() - root.lastReceived > 75000) root.health = "stale"
    }
  }

  function consume(line) {
    if (line.length > 4 * 1024 * 1024) return
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (!msg || msg.v !== 1) return
    lastReceived = Date.now()
    if (msg.type === "state") {
      environments = Array.isArray(msg.environments) ? msg.environments : []
      rows = Array.isArray(msg.rows) ? msg.rows : []
      counts = msg.counts || counts
      known = msg.known === true
      configError = msg.configError || ""
      health = "ready"
    } else if (msg.type === "notice") {
      notifier.notice(msg)
    } else if (msg.type === "detail") {
      var next = {}
      for (var k in details) next[k] = details[k]
      next[msg.envId + ":" + msg.threadId] = msg.detail
      details = next
    }
  }

  function send(obj) {
    if (daemon.running) daemon.write(JSON.stringify(obj) + "\n")
  }

  function requestDetail(envId, threadId) { send({ cmd: "detail", envId: envId, threadId: threadId }) }
  function refresh() { send({ cmd: "refresh" }) }

  function rowByKey(key) {
    for (var i = 0; i < rows.length; i++) if (rows[i].key === key) return rows[i]
    return null
  }

  function environment(id) {
    for (var i = 0; i < environments.length; i++) if (environments[i].id === id) return environments[i]
    return null
  }

  // Bar widgets register so a notification click can open the right one.
  function registerWidget(w) { if (widgets.indexOf(w) < 0) widgets.push(w) }
  function unregisterWidget(w) { var i = widgets.indexOf(w); if (i >= 0) widgets.splice(i, 1) }

  function openOnFocusedMonitor(key) {
    var monitor = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name) : ""
    var target = null
    for (var i = 0; i < widgets.length; i++) {
      var w = widgets[i]
      if (!w || typeof w.openAt !== "function") continue
      if (!target) target = w
      if (monitor && w.screenName === monitor) { target = w; break }
    }
    if (target) target.openAt(key || "")
    return target !== null
  }

  readonly property var nodeCommand: {
    var node = settings && typeof settings.node === "string" && settings.node ? settings.node : "node"
    var mode = settings && settings.demo === true ? "demo" : "run"
    return [node, "--disable-warning=ExperimentalWarning", root.pluginDir + "/daemon/main.ts", mode]
  }
  // Settings can switch node binary or demo mode: restart the collector with the new command.
  onNodeCommandChanged: if (daemon.running) { root.details = ({}); daemon.running = false; restart.interval = 300; restart.restart() }

  Process {
    id: daemon
    command: root.nodeCommand
    running: true
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.consume(line) } }
    stderr: SplitParser { onRead: function(line) { if (line.trim()) root.lastError = line.slice(0, 300) } }
    onExited: function(code) {
      if (restart.running) return
      root.health = "down"
      restart.interval = Math.min(60000, restart.interval * 2)
      restart.restart()
    }
    onStarted: restart.interval = 2500
  }

  Timer { id: restart; interval: 2500; onTriggered: daemon.running = true }

  FileView {
    id: settingsFile
    path: root.configDir + "/settings.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.settings = JSON.parse(text()) || {} } catch (e) { root.settings = {} }
      root.pendingTextSize = NaN
    }
    onLoadFailed: root.settings = ({})
  }

  IpcHandler {
    target: "ambitiousrealism.t3-loupe"
    function status(): string {
      return JSON.stringify({ health: root.health, known: root.known, counts: root.counts,
        environments: root.environments.map(function(e) { return { label: e.label, state: e.state, providers: e.providers.length } }),
        lastError: root.lastError })
    }
    function refresh(): string { root.refresh(); return "ok" }
    function open(): string { return root.openOnFocusedMonitor("") ? "ok" : "no widget" }
    function focus(key: string): string { return root.openOnFocusedMonitor(key) ? "ok" : "no widget" }
    function testNotification(): string { notifier.test(); return "ok" }
  }
}
