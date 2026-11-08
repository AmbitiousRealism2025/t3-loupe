import QtQuick
import QtTest
import "../../components"
import "../.." as Plugin
import "../../lib/Palette.js" as Palette
import "../../lib/Store.js" as Store
import qs.Commons

TestCase {
  id: tc
  name: "Components"
  when: windowShown
  // TestCase is hidden by default, and a child's `visible` reports its effective visibility.
  visible: true
  width: 900; height: 900

  readonly property double now: Date.UTC(2026, 10, 8, 12, 0, 0)
  readonly property var colors: Palette.derive({ background: "#01041f", foreground: "#D6CAE3", accent: "#647dad", urgent: "#958bbb",
    colors: { red: "#958bbb", yellow: "#9dfeff", orange: "#a59cc5", green: "#83cbee", cyan: "#96dfff", blue: "#647dad", magenta: "#9ba3e5" } })

  function row(extra) {
    var r = { key: "e:t", envId: "e", id: "t", parentId: "", title: "Nightly dependency audit (8AM daily)", project: "ops", branch: "", model: "glm-5.3",
      provider: "", state: "idle", rawStatus: "completed", pendingKind: "", pendingSince: null, activeSince: null, lastRunMs: null, completedAt: null,
      updatedAt: now, settled: false, background: { subagents: 0, commands: 0, monitors: 0, other: 0 }, pr: null, prCount: 0, errorClass: "", error: "",
      usageResetAt: null, childCount: 0, activeChildren: 0, activity: [] }
    for (var k in extra) r[k] = extra[k]
    return r
  }

  // Every visible Text under an item, in tree order.
  function texts(item) {
    var out = []
    function walk(it) {
      if (!it || it.visible === false) return
      if (it.text !== undefined && typeof it.text === "string" && it.text !== "" && it.font !== undefined)
        out.push(it.text.replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " "))
      var kids = it.children || []
      for (var i = 0; i < kids.length; i++) walk(kids[i])
    }
    walk(item)
    return out
  }
  function named(item, name) {
    var out = []
    function walk(it) {
      if (!it) return
      if (it.objectName === name) out.push(it)
      var kids = it.children || []
      for (var i = 0; i < kids.length; i++) walk(kids[i])
    }
    walk(item)
    return out
  }
  function has(item, pattern) {
    var all = texts(item)
    for (var i = 0; i < all.length; i++) if (pattern.test(all[i])) return true
    return false
  }

  Component { id: calloutC; StatusCallout { width: 480; colors: tc.colors; monoFamily: "monospace" } }
  Component { id: disconnectedC; DisconnectedState { width: 600; colors: tc.colors; now: tc.now; monoFamily: "monospace" } }
  Component { id: detailC; DetailView { width: 480; colors: tc.colors; now: tc.now; paneMode: true; monoFamily: "monospace" } }
  Component { id: rowC; CompactRow { width: 420; colors: tc.colors; now: tc.now; monoFamily: "monospace" } }
  Component { id: keyC; KeyAction { width: 300; colors: tc.colors; text: "Answer in T3" } }
  SignalSpy { id: spy; signalName: "actionRequested" }

  function test_failedCalloutNamesCauseAndKeepsRawError() {
    var r = row({ state: "failed", rawStatus: "failed", errorClass: "provider_error", error: '401: {"code":"1000","message":"Authentication Failed"}', completedAt: now - 8 * 86400000 })
    var c = createTemporaryObject(calloutC, tc, { callout: Store.statusCallout(r, now, false) })
    verify(c.visible)
    verify(has(c, /^The provider rejected the sign-in$/), texts(c).join(" | "))
    verify(has(c, /^Failed 8d ago · sign-in rejected$/))
    verify(has(c, /^401: \{"code":"1000","message":"Authentication Failed"\}$/), "raw provider text shown verbatim")
    verify(has(c, /Sign in to the provider again in T3/))
    verify(c.height > 60)
    spy.target = c; spy.clear()
    c.actionRequested("focus")
    compare(spy.count, 1)
  }

  function test_detailWithoutDataStopsSayingLoading() {
    var r = row({ state: "failed", rawStatus: "failed", errorClass: "provider_error", error: "401: nope", completedAt: now - 60000 })
    var d = createTemporaryObject(detailC, tc, { row: r, detail: null })
    verify(has(d, /^The provider rejected the sign-in$/), "the error leads, even with no detail")
    verify(has(d, /^Loading activity…$/))
    tryVerify(function() { return has(d, /^No activity from T3 for this thread yet\.$/) }, 6000)
    verify(!has(d, /Loading/))
  }

  function test_requestChoicesArePlainTextWithAnAction() {
    var r = row({ state: "input", rawStatus: "running", pendingKind: "command", pendingSince: now - 120000 })
    var detail = { activity: [], runs: [], context: null, subagents: [], todo: null,
      pending: [{ id: "r1", kind: "command", since: now - 120000, prompt: "git push --force-with-lease origin feat/sessions-v2 && pnpm db:migrate --env staging", appName: "",
                  options: ["Allow once", "Allow for session", "Decline"], questions: [] }] }
    var d = createTemporaryObject(detailC, tc, { row: r, detail: detail })
    verify(has(d, /^Choices in T3:  Allow once  ·  Allow for session  ·  Decline$/), texts(d).join(" | "))
    verify(has(d, /^Decide in T3/))
    verify(!has(d, /^Allow once$/), "no option is drawn on its own like a button")
    verify(!has(d, /^Waiting for your answer$/), "the loaded request replaces the callout")
  }

  function test_disconnectedNamesEachMachineAndItsFix() {
    var envs = [
      { id: "a", label: "laptop", sshHost: "", state: "expired", url: "http://127.0.0.1:3773", sessionExpiresAt: now - 2 * 86400000 },
      { id: "b", label: "build-box", sshHost: "build-box", state: "expired", url: "http://127.0.0.1:46363", sessionExpiresAt: now - 5 * 3600000 }
    ]
    var s = createTemporaryObject(disconnectedC, tc, { environments: envs })
    verify(has(s, /^Not connected to T3$/))
    verify(has(s, /^All 2 pairings have expired/))
    verify(has(s, /^\$ t3-loupe pair-local --label laptop$/), texts(s).join(" | "))
    verify(has(s, /^\$ t3-loupe pair-ssh --ssh-host build-box --label build-box$/))
    verify(has(s, /^Pairing expired 2d ago$/))
    verify(has(s, /^Pairing expired 5h ago$/))
  }

  function test_failedRowSaysWhy() {
    var r = row({ state: "failed", rawStatus: "failed", errorClass: "provider_error", completedAt: now - 51 * 60000, project: "web-app",
      error: "This thread's workspace folder no longer exists or is not a directory: /home/dev/code/web-app. Restore the folder at this path before retrying." })
    var c = createTemporaryObject(rowC, tc, { row: r })
    verify(has(c, /^Failed · folder missing$/), texts(c).join(" | "))
    verify(!has(c, /web-app/), "the project is left to the group heading and the detail pane")
    compare(c.needsYou, true)
    compare(c.wordInk, tc.colors.attentionInk)
  }

  // A stand-in for Service.qml: the state the collector would send, nothing running.
  Component {
    id: serviceC
    QtObject {
      property var rows: []
      property var environments: []
      property var counts: ({ active: 0, busy: 0, attention: 0, input: 0, review: 0 })
      property bool known: true
      property string health: "ready"
      property string configError: ""
      property double now: tc.now
      property var details: ({})
      property var settings: ({})
      readonly property var textSizes: [0, 2, 4, 6]
      property int textSizeStep: 0
      readonly property string pluginDir: "/nonexistent"
      readonly property var theme: ({ popup: tc.colors })
      property var requested: []
      function rowByKey(key) { for (var i = 0; i < rows.length; i++) if (rows[i].key === key) return rows[i]; return null }
      function environment(id) { for (var i = 0; i < environments.length; i++) if (environments[i].id === id) return environments[i]; return null }
      function requestDetail(envId, threadId) { requested = requested.concat([envId + ":" + threadId]) }
      function refresh() {}
      function send(obj) {}
      function stepTextSize(d) {}
      function setTextSize(v) {}
    }
  }
  Component { id: panelC; Plugin.ThreadsPanel { width: 860; height: 760; centered: true } }

  function liveEnv(id, label) { return { id: id, label: label, sshHost: "", state: "live", stale: false, url: "", sessionExpiresAt: now + 20 * 86400000, providers: [] } }

  function test_panelHeaderAndTabsAgree() {
    var svc = createTemporaryObject(serviceC, tc)
    svc.environments = [liveEnv("e", "laptop"), liveEnv("f", "build-box")]
    svc.rows = [row({ key: "e:a", id: "a", state: "input", pendingKind: "command", rawStatus: "running" }),
                row({ key: "e:b", id: "b", state: "failed", rawStatus: "failed", error: "401: no", errorClass: "provider_error" }),
                row({ key: "e:c", id: "c", state: "working", rawStatus: "running", activeSince: now - 60000 }),
                row({ key: "e:d", id: "d", state: "limited", rawStatus: "failed", errorClass: "usage_limit", usageResetAt: now + 600000 }),
                row({ key: "e:e", id: "e", state: "review", completedAt: now - 60000 }),
                row({ key: "e:i", id: "i", state: "idle", completedAt: now - 7200000 })]
    var p = createTemporaryObject(panelC, tc, { service: svc })
    p.opened = true
    verify(has(p, /^2 NEED YOU  ·  2 WORKING  ·  2 DONE$/), texts(p).join(" | "))
    compare(p.needCount, 2)
    compare(p.activeCount, 4)
    compare(p.doneCount, 2)
    compare(p.allCount, 6)
    // The Inbox lists exactly what the header calls "need you".
    compare(p.filter, "attention")
    var listed = p.visible_.filter(function(x) { return !x.kind }).map(function(x) { return x.id })
    compare(listed, ["a", "b"])
    // The first thread is selected on open, and its detail requested.
    tryCompare(p, "selectedKey", "e:a")
    verify(!p.disconnected)
  }

  function test_panelDisconnectedReplacesTheEmptyList() {
    var svc = createTemporaryObject(serviceC, tc)
    svc.known = false
    svc.environments = [
      { id: "a", label: "laptop", sshHost: "", state: "expired", stale: false, url: "http://127.0.0.1:3773", sessionExpiresAt: now - 2 * 86400000, providers: [] },
      { id: "b", label: "build-box", sshHost: "build-box", state: "expired", stale: false, url: "http://127.0.0.1:46363", sessionExpiresAt: now - 5 * 3600000, providers: [] }
    ]
    var p = createTemporaryObject(panelC, tc, { service: svc })
    p.opened = true
    verify(p.disconnected)
    verify(has(p, /^NOT CONNECTED/), texts(p).join(" | "))
    verify(has(p, /^Not connected to T3$/))
    verify(has(p, /^\$ t3-loupe pair-ssh --ssh-host build-box --label build-box$/))
    verify(!has(p, /No recent threads/))
    verify(!has(p, /Select a thread/))
    verify(!has(p, /^Inbox/), "no tabs of zeros")
  }

  Component { id: dropdownC; Plugin.ThreadsPanel { width: 540; height: 760; centered: false } }

  function test_dropdownSelectsTheFirstThreadOnOpen() {
    var svc = createTemporaryObject(serviceC, tc)
    svc.environments = [liveEnv("e", "laptop")]
    svc.rows = [row({ key: "e:b", id: "b", state: "failed", rawStatus: "failed", error: "This thread's workspace folder no longer exists or is not a directory: /x. Restore it.", errorClass: "provider_error" }),
                row({ key: "e:p", id: "p", state: "plan", completedAt: now - 240000, lastRunMs: 360000 })]
    var p = createTemporaryObject(dropdownC, tc, { service: svc })
    p.opened = true
    tryCompare(p, "cursor", 0)
    verify(has(p, /^folder missing$/), texts(p).join(" | "))
    // Enter expands the card into the detail, which leads with the cause and the next step.
    p.activate(p.visible_[0])
    tryVerify(function() { return has(p, /^The thread's working folder is gone$/) })
    verify(has(p, /Restore the folder at that path/))
  }

  function test_planBarDrawsEveryStep() {
    var r = row({ state: "working", rawStatus: "running", activeSince: now - 60000 })
    var runs = [{ ordinal: 1, status: "completed", startedAt: now - 3600000, completedAt: now - 3000000, durationMs: 600000 },
                { ordinal: 2, status: "failed", startedAt: now - 2000000, completedAt: now - 1900000, durationMs: 100000 },
                { ordinal: 3, status: "running", startedAt: now - 60000, completedAt: null, durationMs: null }]
    var d = createTemporaryObject(detailC, tc, { row: r, detail: { activity: [], pending: [], runs: runs, context: null, subagents: [], todo: { total: 9, done: 6, current: "Polish" } } })
    var steps = named(d, "planStep")
    compare(steps.length, 9)
    var pending = steps.filter(function(s) { return s.border.width > 0 })
    compare(pending.length, 2, "steps 8 and 9 are outlined")
    verify(Palette.contrast(pending[0].border.color, colors.background) >= 3)
    verify(steps[6].color !== steps[5].color, "current differs from done")
    var bars = named(d, "runBar")
    compare(bars.length, 3)
    verify(Palette.contrast(bars[0].color, colors.background) >= 3, "a past run is a 3:1 mark")
    verify(has(d, /run 2 failed/), texts(d).join(" | "))
    verify(has(d, /^×$/), "the failed bar carries a mark, not just a colour")
  }

  function test_subSecondRunAndRepeatedErrorAreNotDrawnTwice() {
    var err = "This thread's workspace folder no longer exists or is not a directory: /home/dev/code/web-app. Restore the folder at this path before retrying."
    var r = row({ state: "failed", rawStatus: "failed", errorClass: "provider_error", error: err, completedAt: now - 51 * 60000 })
    var d = createTemporaryObject(detailC, tc, { row: r, detail: { pending: [], context: null, subagents: [], todo: null,
      activity: [{ icon: "terminal", label: "Preparing workspace", status: "completed", at: now - 51 * 60000 }, { icon: "circle-alert", label: err, status: "failed", at: now - 51 * 60000 }],
      runs: [{ ordinal: 1, status: "failed", startedAt: now - 51 * 60000, completedAt: now - 51 * 60000, durationMs: 0 }] } })
    verify(has(d, /^Failed with the error shown above$/), texts(d).join(" | "))
    compare(texts(d).filter(function(t) { return t === err }).length, 1, "the error is printed once, in the card")
    compare(named(d, "runBar").filter(function(b) { return b.visible }).length, 0, "no chart for a sub-second run")
    verify(has(d, /^1 run, failed after <1s$/))
  }

  Component { id: paneC; ThreadDetailPane { width: 520; height: 700; colors: tc.colors; now: tc.now; monoFamily: "monospace" } }

  function test_detailHeaderWrapsWholeItemsAndLabelsItsActions() {
    var r = row({ state: "input", rawStatus: "running", pendingKind: "command", pendingSince: now - 120000, project: "web-app", branch: "feat/sessions-v2", model: "claude-opus-5-5",
      pr: { number: 412, title: "x", url: "https://example.invalid/pr/412", state: "open", checks: "pending", draft: false, additions: 2140, deletions: 388, review: "" } })
    var p = createTemporaryObject(paneC, tc, { row: r, machineLabel: "laptop" })
    var all = texts(p)
    verify(all.indexOf("laptop ·") >= 0 && all.indexOf("claude-opus-5-5") >= 0, all.join(" | "))
    verify(!all.some(function(t) { return /^·/.test(t) }), "no item starts with a separator")
    verify(has(p, /^open T3$/) && has(p, /^PR$/) && has(p, /^copy title$/), "each action is labelled")
    verify(has(p, /^#412$/), "the PR number stands alone")
    verify(has(p, /^checks pending · \+2140 −388 lines$/), texts(p).join(" | "))
  }

  function textItem(item, value) {
    var found = null
    function walk(it) {
      if (!it || found || it.visible === false) return
      if (it.text === value && it.font !== undefined) { found = it; return }
      var kids = it.children || []
      for (var i = 0; i < kids.length; i++) walk(kids[i])
    }
    walk(item)
    return found
  }

  function test_actionKeysNeverBreakAtAnyWidth() {
    var r = row({ state: "input", rawStatus: "running", pendingKind: "command", pendingSince: now - 120000, project: "web-app", branch: "feat/sessions-v2",
      pr: { number: 412, title: "x", url: "https://example.invalid/pr/412", state: "open", checks: "pending", draft: false, additions: 1, deletions: 1, review: "" } })
    var widths = [360, 440, 520, 700]
    for (var i = 0; i < widths.length; i++) {
      var p = createTemporaryObject(paneC, tc, { row: r, machineLabel: "laptop", width: widths[i] })
      wait(0)
      var labels = ["open T3", "PR", "copy title"]
      for (var j = 0; j < labels.length; j++) {
        var t = textItem(p, labels[j])
        verify(t !== null && t.visible, labels[j])
        compare(t.lineCount, 1, labels[j] + " at " + widths[i])
        verify(t.width >= t.implicitWidth - 0.5, labels[j] + " has its full width at " + widths[i])
      }
    }
  }

  function test_dropdownLegendKeepsEveryKey() {
    var svc = createTemporaryObject(serviceC, tc)
    svc.environments = [liveEnv("e", "laptop")]
    svc.rows = [row({ key: "e:a", id: "a", state: "working", rawStatus: "running", activeSince: now - 60000 })]
    var p = createTemporaryObject(dropdownC, tc, { service: svc })
    p.opened = true
    tryVerify(function() { return p.cursor >= 0 && !p.visible_[p.cursor].kind })
    var all = texts(p).join(" | ")
    var keys = ["j/k select", "↵ details", "g next needing you", "1–4 view", "/ filter", "o open T3", "f layout", "r refresh", "esc close"]
    for (var i = 0; i < keys.length; i++) verify(all.indexOf(keys[i]) >= 0, keys[i] + " in " + all)
  }

  function test_legendShowsOnlyWorkingKeys() {
    var svc = createTemporaryObject(serviceC, tc)
    svc.environments = [liveEnv("e", "laptop")]
    svc.rows = [row({ key: "e:a", id: "a", state: "input", pendingKind: "command", rawStatus: "running" })]
    var p = createTemporaryObject(panelC, tc, { service: svc })
    p.opened = true
    verify(has(p, /g next needing you/), texts(p).join(" | "))
    verify(has(p, /j\/k select/))
    svc.known = false
    svc.rows = []
    svc.environments = [{ id: "a", label: "laptop", sshHost: "", state: "expired", stale: false, url: "http://127.0.0.1:3773", sessionExpiresAt: now - 1000, providers: [] }]
    tryVerify(function() { return p.disconnected })
    verify(!has(p, /j\/k select/), "no selection keys when there is nothing to select")
    verify(!has(p, /next needing you/))
    verify(has(p, /r refresh/))
  }

  // The reason is what tells failed rows apart: it is never the part that gets cut. The shell
  // creates rows before it settles its type scale (shell.toml, then the panel's text-size bump), so
  // the font grows after the row exists; round 4 measured once, at the small size, and cut the
  // reason in the shell while this test, at a fixed size, passed. This one changes size afterwards.
  function test_rowReasonSurvivesAFontChangeAfterCreation() {
    var r = row({ state: "failed", rawStatus: "failed", errorClass: "provider_error", completedAt: now - 60000, project: "a-long-project-name",
      error: '401: {"code":"1000","message":"Authentication Failed"}' })
    var q = row({ key: "e:q", id: "q", state: "input", rawStatus: "running", pendingKind: "user_input", project: "ingest" })
    var bumps = [0, 2, 4, 6]
    var made = []
    for (var w = 0; w < 2; w++) made.push(createTemporaryObject(rowC, tc, { row: w ? q : r, width: 340, showMachine: true, machineLabel: "build-box" }))
    try {
      for (var i = 0; i < bumps.length; i++) {
        Typo.bump = bumps[i]
        // The two-pane list's width at this size: 44% of a card that widens 56 px per step of bump.
        for (var m = 0; m < made.length; m++) made[m].width = Math.round((820 + bumps[i] * 56) * 0.44) - 20
        wait(0)
        verify(has(made[0], /^Failed · sign-in rejected$/), "bump " + bumps[i] + ": " + texts(made[0]).join(" | "))
        verify(has(made[1], /^Question$/), "bump " + bumps[i] + ": " + texts(made[1]).join(" | "))
        verify(has(made[0], /^build-box$/), "the machine still shows, under the time")
      }
    } finally {
      Typo.bump = 0
    }
  }

  Component { id: ringC; ActivityRing { diameter: 40; colors: ({ attention: "red", ask: "violet", warning: "orange", ink: "white", rest: "gray" }) } }

  function test_ringGivesEverySegmentARealArc() {
    var ring = createTemporaryObject(ringC, tc, { segments: [{ role: "attention", count: 0 }, { role: "ask", count: 0 }, { role: "warning", count: 1 },
      { role: "ink", count: 30 }, { role: "rest", count: 2 }] })
    verify(ring.sweepOf(2) >= 34, "a lone plan is a segment, not a tick: " + ring.sweepOf(2))
    verify(ring.sweepOf(4) >= 34)
    compare(ring.sweepOf(0), 0)
    var total = 0
    for (var i = 0; i < 5; i++) total += ring.sweepOf(i)
    verify(Math.abs(total + ring.present * ring.gap - 360) < 0.5, "the arcs still close the circle: " + total)
  }

  function manyRows() {
    var out = []
    var projects = ["alpha", "beta", "gamma", "delta"]
    for (var i = 0; i < 20; i++)
      out.push(row({ key: "e:r" + i, id: "r" + i, title: "Thread " + i, project: projects[i % 4], state: i % 5 === 0 ? "review" : "working",
        rawStatus: i % 5 === 0 ? "completed" : "running", activeSince: now - 60000, completedAt: now - 60000, childCount: i === 3 ? 2 : 0 }))
    return out
  }
  Component { id: shortPanelC; Plugin.ThreadsPanel { width: 860; height: 420; centered: true } }

  function test_listKeepsOneHeadingAndTheSelectionInView() {
    var svc = createTemporaryObject(serviceC, tc)
    svc.environments = [liveEnv("e", "laptop")]
    svc.rows = manyRows()
    var p = createTemporaryObject(shortPanelC, tc, { service: svc })
    p.opened = true
    p.setFilter("all")
    tryVerify(function() { return p.cursor >= 0 })
    var list = p.listView
    verify(list.contentHeight > list.height, "the list scrolls")
    for (var step = 0; step < 30; step++) {
      p.moveCursor(1)
      wait(20)
      var cell = list.itemAtIndex(p.cursor)
      verify(cell !== null)
      // Fully visible, clear of the pinned heading and of the "more below" strip.
      var bottomLimit = list.contentY + list.height - (list.contentY + list.height < list.contentHeight + list.originY - 2 ? Style.space(22) : 0)
      verify(cell.y + cell.height <= bottomLimit + 0.5, "step " + step + ": selected row under the bottom strip " + JSON.stringify({ y: cell.y, h: cell.height, cy: list.contentY, lh: list.height, ch: list.contentHeight, oy: list.originY, cur: p.cursor }))
      // The pinned heading, when shown, is the group of the rows right under it.
      var heading = p.pinnedHeading
      if (heading) {
        var under = list.indexAt(20, list.contentY + p.pinnedHeight)
        var k = under
        while (k > 0 && p.visible_[k].parentId) k--
        compare(heading.label, Store.groupKey(p.visible_[k], svc.environments), "step " + step)
      }
    }
  }

  function test_legendHoldsItsHeightAsTheSelectionMoves() {
    var svc = createTemporaryObject(serviceC, tc)
    svc.environments = [liveEnv("e", "laptop")]
    svc.rows = manyRows()
    var layouts = [panelC, dropdownC]
    for (var l = 0; l < layouts.length; l++) {
      var p = createTemporaryObject(layouts[l], tc, { service: svc })
      p.opened = true
      p.setFilter("all")
      tryVerify(function() { return p.cursor >= 0 })
      var heights = {}
      for (var i = 0; i < 8; i++) { p.moveCursor(1); wait(0); heights[p.legendHeight] = true }
      compare(Object.keys(heights).length, 1, (l ? "dropdown" : "panel") + " legend heights: " + Object.keys(heights).join(", "))
    }
  }

  function test_keyActionClicks() {
    var k = createTemporaryObject(keyC, tc)
    var clicks = 0
    k.clicked.connect(function() { clicks++ })
    mouseClick(k, 5, k.height / 2)
    compare(clicks, 1)
  }
}
