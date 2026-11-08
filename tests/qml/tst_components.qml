import QtQuick
import QtTest
import "../../components"
import "../.." as Plugin
import "../../lib/Palette.js" as Palette
import "../../lib/Store.js" as Store

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
    verify(has(c, /^Failed · folder missing · web-app$/), texts(c).join(" | "))
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
    verify(has(p, /2 NEEDS? YOU/), texts(p).join(" | "))
    verify(has(p, /2 WORKING/))
    verify(has(p, /2 DONE/))
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

  function test_keyActionClicks() {
    var k = createTemporaryObject(keyC, tc)
    var clicks = 0
    k.clicked.connect(function() { clicks++ })
    mouseClick(k, 5, k.height / 2)
    compare(clicks, 1)
  }
}
