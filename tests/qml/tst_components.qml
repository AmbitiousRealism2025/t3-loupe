import QtQuick
import QtQuick.Controls
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
      if (!it || it.visible === false || it.opacity === 0) return
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
    verify(has(d, /^T3 offers: Allow once, Allow for session or Decline$/), texts(d).join(" | "))
    verify(has(d, /^Decide in T3: Loupe only shows the request$/) && has(d, /^→ $/), "the next step, behind its arrow")
    verify(!has(d, /^Allow once$/), "no option is drawn on its own like a button")
    // The hand-off is one piece: the step, and right under it the key that gets you to T3,
    // labelled for what the key does. Once.
    compare(texts(d).filter(function(t) { return t === "o" }).length, 1, "one keycap for T3")
    var step = textItem(d, "Decide in T3: Loupe only shows the request"), open = textItem(d, "open T3")
    verify(open !== null, texts(d).join(" | "))
    var gap = open.mapToItem(d, 0, 0).y - step.mapToItem(d, 0, step.height).y
    verify(gap >= 0 && gap < 30, "the key sits right under the step (" + gap + ")")
    // It is the block's main action: full ink, where copying the title is dim.
    compare(String(open.color), String(Qt.color(tc.colors.text)))
    compare(String(textItem(d, "copy title").color), String(Qt.color(tc.colors.textDim)))
    verify(!has(d, /^Waiting for your answer$/), "the loaded request replaces the callout")
  }

  function test_disconnectedNamesEachMachineAndItsFix() {
    var envs = [
      { id: "a", label: "laptop", sshHost: "", state: "expired", url: "http://127.0.0.1:3773", sessionExpiresAt: now - 2 * 86400000 },
      { id: "b", label: "build-box", sshHost: "build-box", state: "expired", url: "http://127.0.0.1:46363", sessionExpiresAt: now - 5 * 3600000 }
    ]
    var s = createTemporaryObject(disconnectedC, tc, { environments: envs })
    verify(has(s, /^Not connected to T3 Code$/))
    verify(has(s, /^Both pairings have expired/))
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

  // The themes the screenshots use, and one whose hues crowd each other.
  readonly property var matteBlack: Palette.derive({ background: "#121212", foreground: "#bebebe", accent: "#e68e0d", urgent: "#D35F5F",
    colors: { red: "#D35F5F", yellow: "#b91c1c", orange: "#c63d3d", green: "#FFC107", cyan: "#bebebe", blue: "#e68e0d", magenta: "#D35F5F", bright_magenta: "#B91C1C" } })
  readonly property var latte: Palette.derive({ background: "#eff1f5", foreground: "#4c4f69", accent: "#1e66f5", urgent: "#d20f39",
    colors: { red: "#d20f39", yellow: "#df8e1d", orange: "#d84e2b", green: "#40a02b", cyan: "#179299", blue: "#1e66f5", magenta: "#ea76cb" } })

  // Every visible Text under an item, with the colour it is drawn in.
  function inks(item) {
    var out = []
    function walk(it) {
      if (!it || it.visible === false || it.opacity === 0) return
      if (it.font !== undefined && typeof it.text === "string" && it.text !== "") out.push({ text: it.text, color: String(it.color) })
      var kids = it.children || []
      for (var i = 0; i < kids.length; i++) walk(kids[i])
    }
    walk(item)
    return out
  }

  // The selected row, in each layout and theme: its fill takes no hue from the accent or from a
  // state colour other than the row's own wash, a row waiting on an answer keeps that wash, the
  // ring is the palette's, and every word on it holds 4.5:1 against the fill it is actually drawn on.
  function test_selectedRowKeepsItsColoursAndItsContrast() {
    var themes = [{ name: "blue clouds", c: tc.colors }, { name: "matte black", c: tc.matteBlack }, { name: "latte", c: tc.latte }]
    var states = [
      row({ state: "input", rawStatus: "running", pendingKind: "command", pendingSince: now - 120000, activity: [{ icon: "message-circle", label: "Awaiting approval", status: "pending", at: now }] }),
      row({ state: "failed", rawStatus: "failed", errorClass: "provider_error", error: "502", completedAt: now - 660000 }),
      row({ state: "plan", completedAt: now - 240000 }),
      row({ state: "working", rawStatus: "running", activeSince: now - 60000, activity: [{ icon: "eye", label: "Read Bar.qml", status: "running", at: now }] }),
      row({ state: "limited", rawStatus: "failed", errorClass: "usage_limit", usageResetAt: now + 47 * 60000 }),
      row({ state: "review", completedAt: now - 480000, lastRunMs: 1140000 }),
      row({ state: "idle", completedAt: now - 7200000 })
    ]
    var kinds = [{ c: rowC, name: "row" }, { c: cardC, name: "card" }]
    for (var t = 0; t < themes.length; t++) for (var k = 0; k < kinds.length; k++) for (var s = 0; s < states.length; s++) {
      var colors = themes[t].c
      var where = themes[t].name + ", " + kinds[k].name + ", " + states[s].state
      var props = { row: states[s], colors: colors, selected: true }
      if (kinds[k].name === "card") { props.showMachine = true; props.machineLabel = "build-box" }
      var item = createTemporaryObject(kinds[k].c, tc, props)
      var fill = named(item, "fill")[0]
      verify(fill !== undefined, where)
      // The fill animates in; wait for it to land.
      var want = states[s].state === "input" ? colors.surfaceSelectedWash : colors.surfaceSelected
      tryCompare(fill, "color", Qt.color(want), 1000, where + ": the selected fill")
      compare(String(fill.border.color), String(Qt.color(colors.focus)), where + ": the ring")
      verify(fill.border.width >= 2, where + ": the ring is two pixels or more")
      // On a row that needs you the rail keeps the left edge to itself: the ring's left side is
      // covered in the row's own fill, so a failure's dashes don't sit on a stripe of the ring.
      var back = named(item, "railBack")[0]
      compare(back.visible, Store.ATTENTION[states[s].state] === true, where + ": the rail's backing")
      if (back.visible) {
        compare(String(back.color), String(fill.color), where + ": in the row's fill")
        verify(back.width >= fill.border.width, where + ": as wide as the ring it covers")
      }
      var words = inks(item)
      verify(words.length >= 2, where)
      for (var w = 0; w < words.length; w++) {
        var ratio = Palette.contrast(words[w].color, String(fill.color))
        verify(ratio >= 4.5, where + ": '" + words[w].text + "' is " + ratio.toFixed(2) + ":1 on the selected fill")
      }
      // Unselected, the same row sits on its ordinary surface and passes there too.
      item.selected = false
      tryCompare(fill, "color", Qt.color(states[s].state === "input" ? Palette.wash(colors.surface, colors.ask) : colors.surface), 1000, where + ": the ordinary fill")
      var plain = inks(item)
      for (var u = 0; u < plain.length; u++)
        verify(Palette.contrast(plain[u].color, String(fill.color)) >= 4.5, where + ": '" + plain[u].text + "' on an ordinary row")
    }
    // Selection is not a status colour: on a theme whose accent is plan amber, the ring is ink.
    verify(Palette.hsl(tc.matteBlack.focus).s < 0.05, "matte black's ring: " + tc.matteBlack.focus)
    verify(Palette.hsl(tc.matteBlack.surfaceSelected).s < 0.05, "matte black's selected fill: " + tc.matteBlack.surfaceSelected)
  }

  Component { id: cardC; ThreadCard { width: 520; colors: tc.colors; now: tc.now; monoFamily: "monospace" } }

  // Healthy background work is not dressed as a failure: its callout is neutral in every theme,
  // while a failure's is the failure colour. (On Matte Black the old "subagent" hue came out red.)
  // A row's glyph is a line icon in the state's colour, on a row that may be tinted with that same
  // colour. It is the palette's glyph for the state (in a light theme, text-strength; in a dark
  // one, the mark), it holds on the row's own fill selected or not, and where it breathes it never
  // fades below a 3:1 mark on that fill. A failure's glyph does not breathe.
  function test_stateGlyphsHoldOnTheirOwnRows() {
    var themes = [{ name: "matte black", c: tc.matteBlack }, { name: "latte", c: tc.latte }, { name: "blue clouds", c: tc.colors }]
    var states = [row({ state: "input", rawStatus: "running", pendingKind: "command", pendingSince: now - 120000 }),
      row({ state: "plan", completedAt: now - 240000 }),
      row({ state: "failed", rawStatus: "failed", errorClass: "provider_error", error: "502", completedAt: now - 660000 }),
      row({ state: "review", completedAt: now - 60000 })]
    var kinds = [{ c: rowC, name: "row" }, { c: cardC, name: "card" }]
    for (var t = 0; t < themes.length; t++) for (var k = 0; k < kinds.length; k++) for (var s = 0; s < states.length; s++) for (var sel = 0; sel < 2; sel++) {
      var colors = themes[t].c, state = states[s].state
      var where = themes[t].name + ", " + kinds[k].name + ", " + state + (sel ? ", selected" : "")
      var item = createTemporaryObject(kinds[k].c, tc, { row: states[s], colors: colors, selected: sel === 1 })
      var glyph = named(item, "stateGlyph")[0], fill = named(item, "fill")[0]
      var role = Store.stateRole(state)
      compare(String(glyph.color), String(Qt.color(colors[role + "Glyph"])), where + ": the palette's glyph for the state")
      var want = sel ? (state === "input" ? colors.surfaceSelectedWash : colors.surfaceSelected) : state === "input" ? Palette.wash(colors.surface, colors.ask) : colors.surface
      tryCompare(fill, "color", Qt.color(want), 1000, where + ": the fill it sits on")
      compare(String(item.restFill), String(fill.color), where + ": the breath is measured on that fill")
      var floor = colors.light ? 4.5 : 3
      var ratio = Palette.contrast(String(glyph.color), String(fill.color))
      verify(ratio >= floor, where + ": the glyph is " + ratio.toFixed(2) + ":1 on its row (floor " + floor + ")")
      if (state === "input" || state === "plan") {
        compare(glyph.breathTo, Palette.breathFloor(String(glyph.color), String(fill.color)), where)
        verify(glyph.breathTo >= Palette.BREATH_DEEPEST && glyph.breathTo <= 1, where + ": breath " + glyph.breathTo)
        var faded = Palette.mix(String(fill.color), String(glyph.color), glyph.breathTo)
        verify(Palette.contrast(faded, String(fill.color)) >= 3, where + ": at its faintest (" + glyph.breathTo + ") the glyph is " + Palette.contrast(faded, String(fill.color)).toFixed(2) + ":1")
        compare(glyph.breathing, glyph.breathTo < 0.97, where + ": it breathes only where it has contrast to spare")
      } else {
        verify(!glyph.breathing, where + ": does not breathe")
      }
    }
    // With reduced motion nothing breathes.
    var still = createTemporaryObject(rowC, tc, { row: states[0], reduceMotion: true })
    verify(!named(still, "stateGlyph")[0].breathing)
  }

  // A block's icon holds on the block's own fill: a loud block's (a failure, a plan) is drawn in
  // the state's ink, a calm one's (done, an answer with no text yet) in the state's glyph, and
  // the fill is the state's mark at the palette's share.
  function test_blockIconsHoldOnTheirOwnFill() {
    var themes = [{ name: "matte black", c: tc.matteBlack }, { name: "latte", c: tc.latte }]
    var cases = [{ r: row({ state: "failed", rawStatus: "failed", errorClass: "provider_error", error: "502", completedAt: now - 660000 }), role: "attention", loud: true },
      { r: row({ state: "plan", completedAt: now - 240000, lastRunMs: 360000 }), role: "warning", loud: true },
      { r: row({ state: "review", completedAt: now - 60000 }), role: "success", loud: false },
      { r: row({ state: "input", rawStatus: "running", pendingKind: "command", pendingSince: now - 120000 }), role: "ask", loud: false }]
    for (var t = 0; t < themes.length; t++) for (var c = 0; c < cases.length; c++) {
      var colors = themes[t].c, role = cases[c].role
      var where = themes[t].name + ", " + cases[c].r.state
      var block = createTemporaryObject(calloutC, tc, { callout: Store.statusCallout(cases[c].r, now, false), colors: colors })
      var icon = named(block, "calloutIcon")[0]
      compare(String(icon.color), String(Qt.color(cases[c].loud ? colors[role + "Ink"] : colors[role + "Glyph"])), where + ": the icon's colour")
      // The block is translucent: over the panel it comes to the palette's fill.
      var fill = Palette.blockFill(colors.background, colors[role], !cases[c].loud)
      fuzzyCompare(block.color.a, cases[c].loud ? Palette.BLOCK : Palette.BLOCK_QUIET, 0.004, where + ": the block's share of its mark")
      verify(Palette.contrast(String(icon.color), fill) >= (cases[c].loud ? 4.5 : 3), where + ": the icon is " + Palette.contrast(String(icon.color), fill).toFixed(2) + ":1 on the block")
      var head = textItem(block, block.callout.headline)
      verify(Palette.contrast(String(head.color), fill) >= 4.5, where + ": the headline is " + Palette.contrast(String(head.color), fill).toFixed(2) + ":1 on the block")
    }
  }

  function test_backgroundWorkIsNotDrawnAsAFailure() {
    var themes = [tc.colors, tc.matteBlack, tc.latte]
    var bg = row({ state: "background", activeSince: now - 9 * 60000, background: { subagents: 2, commands: 0, monitors: 0, other: 0 } })
    var failed = row({ state: "failed", rawStatus: "failed", errorClass: "provider_error", error: "502", completedAt: now - 660000 })
    for (var t = 0; t < themes.length; t++) {
      var colors = themes[t]
      var c = createTemporaryObject(calloutC, tc, { colors: colors, callout: Store.statusCallout(bg, now, false) })
      verify(has(c, /^The reply is done; background work is still running$/))
      var f = createTemporaryObject(calloutC, tc, { colors: colors, callout: Store.statusCallout(failed, now, false) })
      compare(String(f.mark), String(Qt.color(colors.attention)), "a failure's stripe is the failure colour")
      compare(String(c.mark), String(Qt.color(colors.idle)), "background work's stripe is neutral")
      verify(Palette.hsl(String(c.mark)).s < 0.2 || Palette.distance(String(c.mark), colors.attention) > 0.3, "and nowhere near the failure red: " + c.mark + " vs " + colors.attention)
      compare(String(textItem(c, "The reply is done; background work is still running").color), String(Qt.color(colors.text)), "its headline is plain ink")
    }
  }

  // In the activity trail, a step waiting on your answer is marked in the answer's colour, as its
  // row and its request are; red is left to failures.
  function test_waitingStepIsNotRed() {
    var colors = tc.matteBlack
    var r = row({ state: "input", rawStatus: "running", pendingKind: "command", pendingSince: now - 120000 })
    var d = createTemporaryObject(detailC, tc, { colors: colors, row: r, part: "rest", detail: { pending: [], runs: [], context: null, subagents: [], todo: null,
      activity: [{ icon: "terminal", label: "pnpm vitest run auth", status: "completed", at: now - 180000 }, { icon: "message-circle", label: "Awaiting approval", status: "pending", at: now - 120000 }] } })
    var dots = named(d, "liveDot").filter(function(x) { return x.visible })
    compare(dots.length, 1)
    compare(String(dots[0].color), String(Qt.color(colors.ask)), "the waiting dot is the answer's violet")
    verify(Palette.distance(String(dots[0].color), colors.attention) > 0.25, "not the failure red")
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
      property var palette: tc.colors
      readonly property var theme: ({ popup: palette })
      property var requested: []
      // What the panel sent to the collector, and the collector's word on how a copy ended.
      property var sent: []
      signal copied(bool ok)
      function rowByKey(key) { for (var i = 0; i < rows.length; i++) if (rows[i].key === key) return rows[i]; return null }
      function environment(id) { for (var i = 0; i < environments.length; i++) if (environments[i].id === id) return environments[i]; return null }
      function requestDetail(envId, threadId) { requested = requested.concat([envId + ":" + threadId]) }
      function refresh() {}
      function send(obj) { sent = sent.concat([obj]) }
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
    // The header says what needs you and what is working, and nothing the tabs under it say: the
    // plus joins the two into the Active tab's number.
    // The needs-you count is on an ink pill, in no kind's colour: one of the two is a failure, the
    // other a request, and red (or violet) for both would misname one of them.
    verify(has(p, /^NEED YOU \+ 2 WORKING$/), texts(p).join(" | "))
    verify(!texts(p).some(function(t) { return /\d+ (ACTIVE|DONE|STOPPED)/.test(t) }), "no tab's count is repeated in the header")
    var pill = named(p, "needPill")[0]
    verify(pill.visible)
    compare(texts(pill), ["2"])
    compare(String(pill.color), String(Qt.color(tc.colors.text)), "the pill is ink")
    verify(Palette.contrast(tc.colors.background, String(pill.color)) >= 7, "its number reads on it")
    verify(Palette.distance(String(pill.color), tc.colors.attention) > 0.15 && Palette.distance(String(pill.color), tc.colors.ask) > 0.15, "not the failure's colour, nor the request's")
    // After the counts, what the first is made of, each kind with the rail its rows carry: solid in
    // the answer's colour, dashed in the failure's. The kinds add up to the pill.
    var kinds = named(p, "needKind")
    compare(kinds.map(function(k) { return texts(k).join("") }), ["1 to answer", "1 failed"], texts(p).join(" | "))
    var rails = named(p, "needKindRail")
    compare(String(rails[0].color), String(Qt.color(tc.colors.ask)))
    compare(String(rails[1].color), String(Qt.color(tc.colors.attention)))
    verify(!rails[0].dashed && rails[1].dashed, "a failure's rail is dashed here as on its row")
    compare(p.needKinds.reduce(function(n, k) { return n + k.count }, 0), p.needCount)
    var line = named(p, "needKinds")[0]
    verify(line.mapToItem(p, line.width, 0).x <= p.width + 0.5, "inside the header")
    compare(p.needCount, 2)
    compare(p.activeCount, 4)
    compare(p.doneCount, 2)
    compare(p.allCount, 6)
    // The tabs carry the same numbers under the same names: what needs you is "Needs you" on its
    // tab as in the header, and no tab is called anything else.
    compare(tabLabels(p), ["Needs you 2", "Active 4", "Done 2", "All 6"])
    verify(!texts(p).concat(tabLabels(p)).some(function(t) { return /inbox/i.test(t) }), "one name for what needs you")
    // The view lists exactly what the header calls "need you".
    compare(p.filter, "attention")
    var listed = p.visible_.filter(function(x) { return !x.kind }).map(function(x) { return x.id })
    compare(listed, ["a", "b"])
    // The first thread is selected on open, and its detail requested.
    tryCompare(p, "selectedKey", "e:a")
    verify(!p.disconnected)
  }

  // The tabs as drawn: each label without its leading key cells, single-spaced.
  function tabLabels(p) {
    var out = []
    function walk(it) {
      if (!it || it.visible === false) return
      if (it.selected !== undefined && typeof it.text === "string" && it.modelData !== undefined) out.push(it.text.replace(/\s+/g, " ").trim())
      var kids = it.children || []
      for (var i = 0; i < kids.length; i++) walk(kids[i])
    }
    walk(p)
    return out
  }

  // The header's count line is short enough to fit the dropdown whole, and says so with nothing waiting.
  function test_headerCountsFitAndSayWhenNothingWaits() {
    var svc = createTemporaryObject(serviceC, tc)
    svc.environments = [liveEnv("e", "laptop")]
    svc.rows = [row({ key: "e:a", id: "a", state: "input", pendingKind: "command", rawStatus: "running" }),
                row({ key: "e:c", id: "c", state: "working", rawStatus: "running", activeSince: now - 60000 }),
                row({ key: "e:e", id: "e", state: "review", completedAt: now - 60000 })]
    var widths = [540, 400]
    for (var i = 0; i < widths.length; i++) {
      var p = createTemporaryObject(dropdownC, tc, { service: svc, width: widths[i] })
      p.opened = true
      wait(0)
      verify(has(p, /^NEEDS YOU \+ 1 WORKING$/), texts(p).join(" | "))
      var line = textItem(p, null, /^<font.*NEEDS.*YOU/)
      verify(line !== null && line.implicitWidth <= line.width + 0.5, "the line fits whole at " + widths[i])
    }
    // Nothing waiting: no pill, and nothing to add up.
    var calm = createTemporaryObject(dropdownC, tc, { service: svc, width: 540 })
    calm.opened = true
    svc.rows = [svc.rows[1], svc.rows[2]]
    tryVerify(function() { return has(calm, /^NOTHING NEEDS YOU  ·  1 WORKING$/) })
    verify(!named(calm, "needPill")[0].visible)
  }

  // The two-pane window is as tall as what it shows: a view of a few threads asks for a short
  // card, not a full-height one with its lower half empty; a long list asks for more than any card
  // can give (the window caps it). It is never shorter than the selected thread's detail needs,
  // and while a thread's detail is still on its way the card keeps the height it had.
  function test_windowHeightFollowsItsContent() {
    var svc = createTemporaryObject(serviceC, tc)
    svc.environments = [liveEnv("e", "laptop")]
    var few = [row({ key: "e:a", id: "a", state: "plan", completedAt: now - 240000, lastRunMs: 360000 }),
               row({ key: "e:b", id: "b", state: "failed", rawStatus: "failed", error: "502", errorClass: "provider_error", completedAt: now - 660000 })]
    svc.rows = few
    svc.details = { "e:a": { activity: [], pending: [], runs: [], context: null, subagents: [], todo: null },
                    "e:b": { activity: [], pending: [], runs: [], context: null, subagents: [], todo: null } }
    var long = { pending: [], runs: [], context: null, subagents: [], todo: null,
      activity: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16].map(function(i) { return { icon: "terminal", label: "step " + i, status: "completed", at: now - i * 60000 } }) }
    svc.details = { "e:a": svc.details["e:a"], "e:b": long }
    var p = createTemporaryObject(panelC, tc, { service: svc, height: 760 })
    p.opened = true
    p.setFilter("all")
    tryCompare(p, "selectedKey", "e:a")
    wait(50)
    var short = p.implicitHeight
    verify(short < 520, "two threads ask for a short card: " + short)
    // Everything it shows fits in that height: the list and the selected thread's detail.
    verify(p.bodyHeight >= p.listView.contentHeight - 0.5, "the list fits: " + p.bodyHeight + " vs " + p.listView.contentHeight)
    verify(p.bodyHeight >= p.detailItem.naturalHeight - 0.5, "the detail fits: " + p.bodyHeight + " vs " + p.detailItem.naturalHeight)
    p.height = short
    wait(50)
    verify(!p.detailItem.scrollable, "so at its own height the detail doesn't scroll")
    verify(!has(p, /more below/), "and nothing is cut: " + texts(p).join(" | "))
    // A thread with a long detail makes it taller.
    p.moveCursor(1)
    tryCompare(p, "selectedKey", "e:b")
    tryVerify(function() { return p.implicitHeight > short + 100 }, 1000, "a longer detail asks for more: " + p.implicitHeight + " vs " + short)
    var tall = p.implicitHeight
    // Moving on to a thread whose detail hasn't arrived: the card holds its height instead of
    // dropping to the loading line and growing back.
    svc.rows = few.concat([row({ key: "e:c", id: "c", state: "working", rawStatus: "running", activeSince: now - 60000 })])
    wait(0)
    compare(p.implicitHeight, tall, "one more row in a short list changes nothing: the detail is the taller")
    p.moveCursor(1)
    tryCompare(p, "selectedKey", "e:c")
    verify(p.detailItem.loading)
    compare(p.implicitHeight, tall, "held while the detail loads")
    // When it arrives, the card takes the height that detail needs.
    svc.details = { "e:a": svc.details["e:a"], "e:b": long, "e:c": { activity: [], pending: [], runs: [], context: null, subagents: [], todo: null } }
    tryVerify(function() { return !p.detailItem.loading && p.implicitHeight < tall - 100 }, 1000, "and released when it has: " + p.implicitHeight)
    // A thread T3 never sends detail for: the card holds for a moment, then takes the height of
    // what it has. It doesn't stay tall over an empty pane until "Loading activity…" gives up.
    p.moveCursor(-1)
    tryCompare(p, "selectedKey", "e:b")
    tryVerify(function() { return p.implicitHeight === tall }, 1000, "back on the long detail: " + p.implicitHeight)
    svc.rows = svc.rows.concat([row({ key: "e:d", id: "d", state: "failed", rawStatus: "failed", error: "401", errorClass: "provider_error", completedAt: now - 60000 })])
    wait(0)
    p.moveCursor(2)
    tryCompare(p, "selectedKey", "e:d")
    verify(p.detailItem.loading)
    compare(p.implicitHeight, tall, "held at first")
    tryVerify(function() { return p.detailItem.loading && p.implicitHeight < tall - 100 }, 2000, "released after a moment, though nothing arrived: " + p.implicitHeight)
    p.moveCursor(-1)
    tryCompare(p, "selectedKey", "e:c")
    // A long list asks for more than a short one, with the same thread selected.
    var before = p.implicitHeight
    svc.rows = svc.rows.concat(manyRows())
    tryVerify(function() { return p.implicitHeight > before + 200 }, 1000, "a long list asks for more: " + p.implicitHeight + " vs " + before)
    // The dropdown is unchanged: its height has always followed its list.
    var d = createTemporaryObject(dropdownC, tc, { service: svc })
    verify(d.implicitHeight > 0)
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
    verify(has(p, /^Not connected to T3 Code$/))
    verify(has(p, /^\$ t3-loupe pair-ssh --ssh-host build-box --label build-box$/))
    verify(!has(p, /No recent threads/))
    verify(!has(p, /Select a thread/))
    compare(tabLabels(p).length, 0, "no tabs of zeros")
  }

  // Offline, the one useful thing is running the re-pair commands: each has a digit key that copies
  // it (the digits switch views otherwise, and there are none here), the legend says so, and the
  // block says "copied" only once the collector reports the clipboard took it.
  function test_offlineCommandsAreCopiedByKey() {
    var svc = createTemporaryObject(serviceC, tc)
    svc.known = false
    svc.environments = [
      { id: "a", label: "laptop", sshHost: "", state: "expired", stale: false, url: "http://127.0.0.1:3773", sessionExpiresAt: now - 2 * 86400000, providers: [] },
      { id: "b", label: "build-box", sshHost: "build-box", state: "expired", stale: false, url: "http://127.0.0.1:46363", sessionExpiresAt: now - 5 * 3600000, providers: [] }
    ]
    var p = createTemporaryObject(panelC, tc, { service: svc })
    p.opened = true
    tryVerify(function() { return p.disconnected })
    verify(legendKeys(p).indexOf("1–2 copy command") >= 0, legendKeys(p).join(" | "))
    compare(texts(p).filter(function(t) { return t === "copy" }).length, 2, "a copy action on each command")
    p.keyCatcher.textKey("2")
    compare(svc.sent.length, 1)
    compare(svc.sent[0].cmd, "copy")
    compare(svc.sent[0].text, "t3-loupe pair-ssh --ssh-host build-box --label build-box")
    verify(!has(p, /copied/), "nothing is claimed before the collector answers")
    svc.copied(true)
    tryVerify(function() { return has(p, /^✓ copied$/) })
    compare(texts(p).filter(function(t) { return t === "copy" }).length, 1, "the other command still offers its key")
    // A failed copy says so, in the failure colour.
    p.keyCatcher.textKey("1")
    compare(svc.sent[1].text, "t3-loupe pair-local --label laptop")
    svc.copied(false)
    tryVerify(function() { return has(p, /^copy failed$/) })
    compare(String(textItem(p, "copy failed").color), String(Qt.color(tc.colors.attentionInk)))
    // A digit past the last command, and the view keys, do nothing here.
    p.keyCatcher.textKey("3")
    compare(svc.sent.length, 2)
    compare(p.filter, "all")
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
    verify(has(p, /^open T3$/) && has(p, /^open PR$/) && has(p, /^copy title$/), "each action is labelled")
    verify(has(p, /^#412$/), "the PR number stands alone")
    verify(has(p, /^checks pending · \+2140 −388$/), texts(p).join(" | "))
  }

  // The PR's checks and size are never cut: in a cell too narrow for one line they wrap onto two.
  function test_prNoteWrapsInsteadOfBeingCut() {
    var r = row({ state: "working", rawStatus: "running", activeSince: now - 60000, childCount: 3, activeChildren: 2,
      pr: { number: 412, title: "x", url: "https://example.invalid/pr/412", state: "open", checks: "pending", draft: false, additions: 2140000, deletions: 1388000, review: "" } })
    var widths = [640, 440]
    var lines = {}
    for (var i = 0; i < widths.length; i++) {
      var p = createTemporaryObject(paneC, tc, { row: r, width: widths[i] })
      waitForRendering(p)
      var note = textItem(p, "checks pending · +2140000 −1388000")
      verify(note !== null, "the whole note is the text at " + widths[i])
      verify(!note.truncated, "and none of it is cut at " + widths[i] + " (" + note.lineCount + " lines)")
      verify(note.contentWidth <= note.width + 0.5, "it stays inside its cell at " + widths[i])
      lines[widths[i]] = note.lineCount
    }
    compare(lines[640], 1)
    compare(lines[440], 2, "the narrow cell wraps it")
  }

  // The actions are in one place on every thread: a line of their own from the pane's left edge,
  // whatever the state's words are and whether or not there is a PR (its action comes last).
  function test_detailActionsStayInOnePlace() {
    var pr = { number: 412, title: "x", url: "https://example.invalid/pr/412", state: "open", checks: "pending", draft: false, additions: 1, deletions: 1, review: "" }
    var threads = [
      row({ state: "working", rawStatus: "running", activeSince: now - 23 * 60000, project: "t3-loupe", branch: "main", pr: pr }),
      row({ state: "input", rawStatus: "running", pendingKind: "command", pendingSince: now - 120000, project: "web-app", branch: "feat/sessions-v2" }),
      row({ state: "failed", rawStatus: "failed", errorClass: "provider_error", error: "502", completedAt: now - 11 * 60000, project: "sdk" }),
      row({ state: "limited", rawStatus: "failed", errorClass: "usage_limit", error: "Usage limit reached.", usageResetAt: now + 47 * 60000, project: "docs" }),
      row({ state: "idle", completedAt: now - 3600000, project: "omarchy" })
    ]
    // Two places, one for each kind of thread: under where it runs for a thread with nothing to
    // hand off, and at the end of the block that says what to do for one that has. Within a kind
    // they never move, whatever the state's words are and whether or not there is a PR.
    var at = { lead: {}, plain: {} }
    for (var i = 0; i < threads.length; i++) {
      var p = createTemporaryObject(paneC, tc, { row: threads[i], machineLabel: "laptop" })
      waitForRendering(p)
      var open = textItem(p, "open T3"), copy = textItem(p, "copy title")
      verify(open !== null && copy !== null, threads[i].state)
      compare(texts(p).filter(function(t) { return t === "open T3" }).length, 1, threads[i].state + ": the T3 key appears once")
      compare(open.mapToItem(p, 0, 0).y, copy.mapToItem(p, 0, 0).y, "one line")
      verify(open.mapToItem(p, 0, 0).x < copy.mapToItem(p, 0, 0).x, "T3 first")
      if (threads[i].pr) verify(textItem(p, "open PR").mapToItem(p, 0, 0).x > copy.mapToItem(p, 0, 0).x, "the PR action comes after the two every thread has")
      // A thread whose callout already names the state doesn't say it a second time above it.
      var leads = { input: /^Waiting for your answer$/, failed: /^The provider failed during the run$/, limited: /^Paused by a provider usage limit$/ }
      var stateLine = { input: /^Run command\? \d/, failed: /^Failed 11m ago$/, limited: /^Usage limit resets in 47m$/ }
      var spot = Math.round(open.mapToItem(p, 0, 0).x) + "," + Math.round(copy.mapToItem(p, 0, 0).x)
      if (leads[threads[i].state]) {
        var headline = textItem(p, null, leads[threads[i].state])
        verify(headline !== null, texts(p).join(" | "))
        verify(!has(p, stateLine[threads[i].state]), "the state line would repeat the callout: " + texts(p).join(" | "))
        verify(open.mapToItem(p, 0, 0).y > headline.mapToItem(p, 0, 0).y, threads[i].state + ": the keys end the block that says what to do")
        at.lead[spot] = true
      } else {
        verify(has(p, /^(Working|Idle) /), "a thread with no callout keeps its state line: " + texts(p).join(" | "))
        at.plain[spot] = true
      }
    }
    compare(Object.keys(at.lead).length, 1, "in a callout, open and copy start at the same x on every thread: " + Object.keys(at.lead).join(" / "))
    compare(Object.keys(at.plain).length, 1, "under the header too: " + Object.keys(at.plain).join(" / "))
  }

  // Weight says what to read first: a thread's title is heavier than anything else on its row, and
  // a subagent's lighter than its parent's.
  function test_rowTitleOutweighsTheRestOfItsRow() {
    var kinds = [{ c: rowC, name: "row" }, { c: cardC, name: "card" }]
    for (var k = 0; k < kinds.length; k++) {
      var item = createTemporaryObject(kinds[k].c, tc, { row: row({ title: "Design a robust plugin", state: "working", rawStatus: "running", activeSince: now - 60000, project: "t3-loupe",
        activity: [{ icon: "eye", label: "Read Bar.qml", status: "running", at: now }] }) })
      var title = textItem(item, "Design a robust plugin")
      verify(title.font.weight >= Font.DemiBold, kinds[k].name + ": the title is heavy (" + title.font.weight + ")")
      var others = []
      function walk(it) {
        if (!it || it.visible === false || it.opacity === 0) return
        if (it.font !== undefined && typeof it.text === "string" && it.text !== "" && it !== title) others.push(it)
        var kids = it.children || []
        for (var i = 0; i < kids.length; i++) walk(kids[i])
      }
      walk(item)
      verify(others.length >= 2, kinds[k].name)
      for (var o = 0; o < others.length; o++) {
        verify(others[o].font.weight < title.font.weight, kinds[k].name + ": '" + others[o].text + "' is lighter than the title")
        verify(others[o].font.pixelSize <= title.font.pixelSize, kinds[k].name + ": and no larger")
      }
    }
    var sub = createTemporaryObject(rowC, tc, { row: row({ parentId: "t", key: "e:s", id: "s", title: "Survey the UI kit", state: "working", rawStatus: "running", activeSince: now - 60000 }) })
    verify(textItem(sub, "Survey the UI kit").font.weight < Font.DemiBold, "a subagent's title is a step lighter")
  }

  // The run chart is as wide as its runs, with its figures beside it: not a few bars at the left of
  // an empty plot with the figures underneath.
  function test_runChartHasItsFiguresBesideIt() {
    var r = row({ state: "working", rawStatus: "running", activeSince: now - 23 * 60000 })
    var runs = [5, 12, 3, 22, 9, 31, 14].map(function(m, i) { return { ordinal: i + 1, status: i === 3 ? "failed" : "completed", startedAt: now - (200 - i * 25) * 60000, completedAt: now, durationMs: m * 60000 } })
      .concat([{ ordinal: 8, status: "running", startedAt: now - 23 * 60000, completedAt: null, durationMs: null }])
    var d = createTemporaryObject(detailC, tc, { row: r, detail: { activity: [], pending: [], runs: runs, context: null, subagents: [], todo: null } })
    var chart = named(d, "runChart")[0], figures = named(d, "runFigures")[0]
    var bars = named(d, "runBar")
    compare(bars.length, 8)
    verify(chart.width <= bars[7].mapToItem(chart, bars[7].width, 0).x + 0.5, "the chart ends with its last bar: " + chart.width)
    verify(figures.mapToItem(d, 0, 0).x >= chart.mapToItem(d, chart.width, 0).x, "the figures start to the right of the bars")
    verify(figures.mapToItem(d, 0, 0).y < chart.mapToItem(d, 0, chart.height).y, "on the chart's own rows, not under it")
    // Each figure on its own line, so they read as a list.
    verify(has(d, /^current 23m 00s$/) && has(d, /^longest 31m 00s$/) && has(d, /^run 4 failed$/), texts(d).join(" | "))
    // So many runs that the figures can't fit beside them: they go under the bars, whole.
    var many = []
    for (var i = 0; i < 34; i++) many.push({ ordinal: i + 1, status: "completed", startedAt: now - 1000000, completedAt: now, durationMs: (i + 1) * 60000 })
    var wide = createTemporaryObject(detailC, tc, { row: r, detail: { activity: [], pending: [], runs: many, context: null, subagents: [], todo: null } })
    var wideChart = named(wide, "runChart")[0], under = named(wide, "runFigures")[0]
    verify(under.mapToItem(wide, 0, 0).y >= wideChart.mapToItem(wide, 0, wideChart.height).y, "under a chart too wide to sit beside")
    verify(has(wide, /^longest 34m 00s$/))
  }

  // A fold line names its key ("↵ unfold", "↵ fold") where the cursor is, and only there: on every
  // fold line at once it named Enter on rows Enter would not act on. Unselected, the chevron and
  // the count are what say it opens.
  Component { id: foldC; IdleLine { width: 420; colors: tc.colors; count: 1; label: "Done" } }
  function test_foldLinesNameTheirKey() {
    var line = createTemporaryObject(foldC, tc)
    var hint = named(line, "foldHint")[0]
    verify(!hint.visible, "no Enter hint on a line the cursor is not on")
    verify(has(line, /^DONE$/) && has(line, /^1$/), texts(line).join(" | "))
    line.selected = true
    verify(hint.visible)
    compare(hint.text, "↵ unfold")
    compare(String(hint.color), String(Qt.color(tc.colors.text)), "full ink under the cursor")
    line.open = true
    compare(hint.text, "↵ fold")
    compare(Store.enterVerb({ kind: "idle-line", open: true }, true, false), "fold", "the legend says the same word")
  }

  // Facts are quiet tiles in the rows' surface tone, with no outline (an outlined grid outweighed
  // the block that says what the thread needs); their words hold body-text contrast on the tile.
  // One fact alone is a line under its caption, not a box.
  function test_factsAreQuietTilesAndALoneFactIsALine() {
    var themes = [tc.colors, tc.matteBlack, tc.latte]
    var r = row({ state: "working", rawStatus: "running", activeSince: now - 60000, childCount: 3, activeChildren: 2 })
    for (var t = 0; t < themes.length; t++) {
      var p = createTemporaryObject(paneC, tc, { row: r, colors: themes[t], detail: { activity: [], pending: [], runs: [], subagents: [], todo: null, context: { used: 1000, max: 4000, cost: 1, currency: "USD" } } })
      verify(named(p, "factsGrid")[0].visible)
      verify(!named(p, "factLine")[0].visible)
      var tiles = named(p, "factTile")
      compare(tiles.length, 3, "subagents, context, cost")
      for (var i = 0; i < tiles.length; i++) {
        compare(String(tiles[i].color), String(Qt.color(themes[t].surface)), "a tile is the rows' surface")
        compare(tiles[i].border.width, 0, "and has no outline")
        verify(Palette.contrast(themes[t].textFaint, String(tiles[i].color)) >= 4.5 && Palette.contrast(themes[t].text, String(tiles[i].color)) >= 7, "its words read on it")
      }
      verify(tiles[1].y === tiles[0].y && tiles[1].x > tiles[0].x + tiles[0].width, "two to a row, with the panel showing between them")
    }
    // A thread whose only fact is its last run: a caption and a line, no tile.
    var lone = createTemporaryObject(paneC, tc, { row: row({ state: "plan", lastRunMs: 360000, completedAt: now - 240000 }), detail: { activity: [], pending: [], runs: [], subagents: [], todo: null, context: null } })
    verify(!named(lone, "factsGrid")[0].visible, "no grid for one fact")
    var fact = named(lone, "factLine")[0]
    verify(fact.visible)
    verify(has(fact, /^LAST RUN$/) && has(fact, /^6m 00s$/), texts(fact).join(" | "))
    compare(named(lone, "factTile").filter(function(x) { return x.visible }).length, 0)
  }

  // A sentence that wraps fills the width it has and never leaves one word alone on its last
  // line. It takes no more lines than plain wrapping would, one line stays one line, and a lead
  // ("→ ") hangs: later lines start under the sentence, not under the arrow.
  Component { id: sentenceC; Sentence { font.family: "monospace"; font.pixelSize: 10 } }
  Component { id: plainTextC; Text { textFormat: Text.PlainText; wrapMode: Text.Wrap; font.family: "monospace"; font.pixelSize: 10 } }
  function test_wrappedSentencesLeaveNoOrphan() {
    var sentences = ["Retry the thread in T3; if it fails again, check the provider", "Restore the folder at that path, then retry the thread in T3",
      "Polish the panel and verify every theme in the two-pane window", "T3 resumes it after the reset if auto-resume is on; otherwise retry it in T3"]
    var orphansBefore = 0
    for (var s = 0; s < sentences.length; s++) {
      var one = createTemporaryObject(sentenceC, tc, { text: sentences[s], width: 2000 })
      compare(one.lineCount, 1)
      var full = one.implicitWidth
      // Widths at which plain wrapping strands the last word or two.
      for (var cut = 6; cut <= 60; cut += 6) {
        var width = full - cut
        var plain = createTemporaryObject(plainTextC, tc, { text: sentences[s], width: width })
        var b = createTemporaryObject(sentenceC, tc, { text: sentences[s], width: width })
        var where = "'" + sentences[s].slice(0, 24) + "…' at " + Math.round(width)
        compare(b.lineCount, plain.lineCount, where + ": no more lines than plain wrapping")
        verify(b.contentWidth <= width + 0.5, where + ": inside its width")
        verify(b.height >= plain.height - 0.5 && b.height <= plain.height + 0.5, where + ": as tall as its lines")
        var lines = b.laid.split("\n")
        compare(lines.length, b.lineCount, where + ": drawn as broken")
        if (plain.lineCount === 2) {
          if (full - plain.contentWidth < full * 0.2) orphansBefore++
          verify(lines[1].indexOf(" ") > 0, where + ": no word alone on the last line ('" + lines[1] + "')")
          // The first line is filled: it is not cut back to even the two out.
          verify(b.contentWidth >= width * 0.7, where + ": the first line runs most of the width (" + Math.round(b.contentWidth) + " of " + Math.round(width) + ")")
          verify(!/-$/.test(lines[0]), where + ": no break after a hyphen")
        }
      }
    }
    verify(orphansBefore > 0, "the test met widths where plain wrapping leaves an orphan")
    // A lead hangs: both lines of the sentence start at the same x, to the right of the arrow.
    var led = createTemporaryObject(sentenceC, tc, { lead: "→ ", text: sentences[0], width: 300 })
    verify(led.lineCount >= 2, "wraps at 300: " + led.lineCount)
    var parts = led.children.filter(function(c) { return c.text !== undefined && c.visible })
    compare(parts.length, 2)
    compare(parts[0].text, "→ ")
    verify(parts[1].x >= parts[0].width - 0.5, "the sentence starts after the lead")
    verify(led.contentWidth <= 300.5, "and stays inside the width, lead included")
  }

  // A detail longer than the pane says so and names the keys that page it; they work, and the
  // strip follows where you are. A detail that fits shows no strip.
  function test_detailNamesItsPagingKeys() {
    var r = row({ state: "working", rawStatus: "running", activeSince: now - 60000 })
    var long = { pending: [], runs: [], context: null, subagents: [], todo: null,
      activity: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24].map(function(i) { return { icon: "terminal", label: "step " + i, status: "completed", at: now - i * 60000 } }) }
    var p = createTemporaryObject(paneC, tc, { row: r, detail: long, height: 260 })
    waitForRendering(p)
    verify(p.scrollable)
    verify(has(p, /^more below ↓$/) && textItem(p, "d") !== null, "the strip names the key that pages down: " + texts(p).join(" | "))
    verify(!has(p, /up ↑$/), "nothing above yet")
    p.page(1)
    tryVerify(function() { return has(p, /^up ↑$/) && has(p, /^more below ↓$/) && textItem(p, "u") !== null })
    for (var i = 0; i < 12; i++) p.page(1)
    tryVerify(function() { return has(p, /^back up ↑$/) && !has(p, /^more below ↓$/) })
    // The last line clears the strip.
    var last = textItem(p, "step 24"), strip = textItem(p, "back up ↑")
    verify(last.mapToItem(p, 0, last.height).y <= strip.mapToItem(p, 0, 0).y, "the end of the detail is above the strip")
    // Another thread starts at its top.
    p.row = row({ key: "e:other", id: "other", state: "working", rawStatus: "running", activeSince: now - 60000 })
    tryVerify(function() { return !p.moreAbove })
    var short = createTemporaryObject(paneC, tc, { row: r, detail: { pending: [], runs: [], context: null, subagents: [], todo: null, activity: long.activity.slice(0, 2) } })
    waitForRendering(short)
    verify(!short.scrollable && !has(short, /more below|up ↑/), texts(short).join(" | "))
  }

  // The detail's scroll edge never cuts through a line: whatever the strip's top edge would slice
  // is covered whole, at any pane height. A section's caption is not left as the last thing above
  // the edge with none of its rows. Paging starts with the first row that was hidden, so no row is
  // skipped, and lands with the top line whole; at the end of the detail the top edge is covered
  // the same way.
  function test_detailScrollEdgeCutsNothing() {
    var r = row({ state: "working", rawStatus: "running", activeSince: now - 60000 })
    var steps = []
    for (var i = 1; i <= 24; i++) steps.push({ icon: "terminal", label: "step " + i, status: "completed", at: now - i * 60000 })
    var long = { pending: [], runs: [], context: null, subagents: [], todo: null, activity: steps }
    // Every visible line of the detail, as [top, bottom] in the pane.
    function lines(p) {
      var out = []
      function walk(it) {
        if (!it || it.visible === false || it.opacity === 0) return
        if (it.font !== undefined && typeof it.text === "string" && /^(step \d+|ACTIVITY|\d+m ago)$/.test(it.text)) {
          var top = it.mapToItem(p, 0, 0).y
          out.push({ text: it.text, top: top, bottom: top + it.height })
        }
        var kids = it.children || []
        for (var k = 0; k < kids.length; k++) walk(kids[k])
      }
      walk(p)
      return out
    }
    var sawCover = false
    for (var h = 200; h <= 330; h += 7) {
      var p = createTemporaryObject(paneC, tc, { row: r, detail: long, height: h })
      waitForRendering(p)
      verify(p.scrollable && p.moreBelow, "at " + h)
      var edge = h - p.stripBase - p.coverExtra
      if (p.coverExtra > 0) sawCover = true
      var all = lines(p)
      for (var n = 0; n < all.length; n++)
        verify(all[n].bottom <= edge + 0.5 || all[n].top >= edge - 0.5, "at " + h + ": '" + all[n].text + "' is cut by the edge at " + edge + " (" + all[n].top + "–" + all[n].bottom + ")")
      var caption = all.filter(function(l) { return l.text === "ACTIVITY" })[0], first = all.filter(function(l) { return l.text === "step 1" })[0]
      if (caption && caption.bottom <= edge + 0.5) verify(first.bottom <= edge + 0.5, "at " + h + ": the caption is not left without its first row")
      verify(p.coverExtra <= p.coverMax, "the cover is bounded")
    }
    verify(sawCover, "some of those heights cut a row, and it was covered")
    // Paging: every row is shown whole on some page, in order, and each page's top line is whole.
    var pane = createTemporaryObject(paneC, tc, { row: r, detail: long, height: 263 })
    waitForRendering(pane)
    var seen = {}
    for (var page = 0; page < 20; page++) {
      var edgeNow = pane.height - pane.stripBase - pane.coverExtra, topNow = pane.coverTop
      var now_ = lines(pane)
      for (var m = 0; m < now_.length; m++) {
        verify(now_[m].bottom <= topNow + 0.5 || now_[m].top >= topNow - 0.5, "page " + page + ": '" + now_[m].text + "' is cut by the top cover")
        if (now_[m].top >= topNow - 0.5 && now_[m].bottom <= edgeNow + 0.5 && /^step/.test(now_[m].text)) seen[now_[m].text] = true
        if (now_[m].top < -0.5 && now_[m].bottom > 0.5) verify(topNow >= now_[m].bottom - 0.5, "page " + page + ": '" + now_[m].text + "' sticks out of the top uncovered")
      }
      if (!pane.moreBelow) break
      pane.page(1)
      wait(0)
    }
    verify(!pane.moreBelow, "paging reaches the end")
    for (var q = 1; q <= 24; q++) verify(seen["step " + q] === true, "step " + q + " was shown whole on some page")
    // And back: u returns to the top, where nothing is covered.
    for (var u = 0; u < 20 && pane.moreAbove; u++) { pane.page(-1); wait(0) }
    verify(!pane.moreAbove)
    compare(pane.coverTop, 0)
  }

  // In the two-pane window the detail's scrollbar sits in the window's padding, so the detail's
  // right edge is the pane's own: text ends where the filter box and the footer's rules end.
  // Without that room (the default) the bar stays inside the pane and the content stops short of it.
  function test_detailScrollbarSitsInTheWindowsPadding() {
    var r = row({ state: "failed", rawStatus: "failed", errorClass: "provider_error", error: "Provider stream closed unexpectedly (502 from upstream) after 41 tool calls.", completedAt: now - 660000 })
    var inside = createTemporaryObject(paneC, tc, { row: r, detail: { activity: [], pending: [], runs: [], context: null, subagents: [], todo: null } })
    var out = createTemporaryObject(paneC, tc, { row: r, gutter: 18, detail: { activity: [], pending: [], runs: [], context: null, subagents: [], todo: null } })
    waitForRendering(out)
    function rightOf(p) { var t = textItem(p, r.title); return t.mapToItem(p, t.width, 0).x }
    fuzzyCompare(rightOf(out), out.width, 0.5, "with room in the padding, the detail runs to the pane's edge")
    verify(rightOf(inside) <= inside.width - Style.space(12), "without it, it stops short of the bar: " + rightOf(inside))
    compare(out.contentInset, 0)
    // A narrower padding takes the bar as far out as there is room, never further.
    var tight = createTemporaryObject(paneC, tc, { row: r, gutter: 5, detail: { activity: [], pending: [], runs: [], context: null, subagents: [], todo: null } })
    compare(tight.outset, 5)
    fuzzyCompare(rightOf(tight), tight.width - (Style.space(14) - 5), 0.5)
  }

  // The plan says how far it is, and on a line of its own what it is doing now, in full ink.
  function test_planSaysWhatItIsDoingNowOnItsOwnLine() {
    var r = row({ state: "working", rawStatus: "running", activeSince: now - 60000 })
    var d = createTemporaryObject(detailC, tc, { row: r, detail: { activity: [], pending: [], runs: [], context: null, subagents: [], todo: { done: 6, total: 9, current: "Polish the panel and verify every theme" } } })
    verify(has(d, /^6 of 9 steps done$/), texts(d).join(" | "))
    var count = textItem(d, "6 of 9 steps done"), step = textItem(d, "Polish the panel and verify every theme")
    verify(step !== null && textItem(d, "now: ") !== null, texts(d).join(" | "))
    verify(step.mapToItem(d, 0, 0).y >= count.mapToItem(d, 0, count.height).y - 0.5, "under the count, not after it")
    compare(String(step.color), String(Qt.color(tc.colors.text)), "the step in hand is full ink")
    compare(String(count.color), String(Qt.color(tc.colors.textFaint)), "the count is quiet")
    // No step named: just the count.
    var bare = createTemporaryObject(detailC, tc, { row: r, detail: { activity: [], pending: [], runs: [], context: null, subagents: [], todo: { done: 2, total: 3, current: "" } } })
    verify(has(bare, /^2 of 3 steps done$/) && !has(bare, /^now: $/), texts(bare).join(" | "))
  }

  // Secondary text is the shell's body-small, one step over its caption, at every size; and on a
  // row the state's word is never smaller than the time beside it.
  function test_secondaryTextIsOneStepUp() {
    try {
      var bumps = [0, 2, 4, 6]
      for (var b = 0; b < bumps.length; b++) {
        Typo.bump = bumps[b]
        compare(Typo.caption, Style.font.bodySmall + bumps[b], "at bump " + bumps[b])
        verify(Typo.caption > Style.font.caption + bumps[b], "above the shell's caption")
        verify(Typo.caption <= Typo.bodySmall && Typo.bodySmall < Typo.title, "titles keep their sizes above it")
        var item = createTemporaryObject(rowC, tc, { row: row({ state: "input", rawStatus: "running", pendingKind: "command", pendingSince: now - 120000 }) })
        var word = textItem(item, "Run command?"), time = textItem(item, "waiting 2m")
        verify(word !== null && time !== null, texts(item).join(" | "))
        verify(word.font.pixelSize >= time.font.pixelSize, "the state's word is no smaller than its time")
        compare(time.font.pixelSize, Typo.caption)
      }
    } finally {
      Typo.bump = 0
    }
  }

  // The visible Text whose text is `value` (or, with value null, matches `pattern`).
  function textItem(item, value, pattern) {
    var found = null
    function walk(it) {
      if (!it || found || it.visible === false || it.opacity === 0) return
      if (it.font !== undefined && typeof it.text === "string" && (value !== null ? it.text === value : pattern.test(it.text))) { found = it; return }
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
      // The full labels where they fit; the short ones where they don't. Never a broken label.
      var full = textItem(p, "open T3") !== null
      var labels = full ? ["open T3", "copy title", "open PR"] : ["open", "copy", "PR"]
      var y = {}
      for (var j = 0; j < labels.length; j++) {
        var t = textItem(p, labels[j])
        verify(t !== null && t.visible, labels[j] + " at " + widths[i] + ": " + texts(p).join(" | "))
        compare(t.lineCount, 1, labels[j] + " at " + widths[i])
        verify(t.width >= t.implicitWidth - 0.5, labels[j] + " has its full width at " + widths[i])
        verify(t.mapToItem(p, t.width, 0).x <= widths[i] + 0.5, labels[j] + " stays inside the pane at " + widths[i])
        y[t.mapToItem(p, 0, 0).y] = true
      }
      compare(Object.keys(y).length, 1, "the actions share one line at " + widths[i])
    }
    verify(textItem(createTemporaryObject(paneC, tc, { row: r, machineLabel: "laptop", width: 520 }), "open T3") !== null, "the usual pane has room for the full labels")
    verify(textItem(createTemporaryObject(paneC, tc, { row: r, machineLabel: "laptop", width: 200 }), "open") !== null, "a very narrow one uses the short ones")
  }

  // Copying the title answers: the action says "copied" once the collector reports the clipboard
  // took it, and says so if it didn't. Its neighbour doesn't move while it does.
  function test_copyTitleSaysHowItEnded() {
    var svc = createTemporaryObject(serviceC, tc)
    svc.environments = [liveEnv("e", "laptop")]
    svc.rows = [row({ key: "e:c", id: "c", title: "Design a robust plugin", state: "working", rawStatus: "running", activeSince: now - 60000,
      pr: { number: 412, title: "x", url: "https://example.invalid/pr/412", state: "open", checks: "pending", draft: false, additions: 1, deletions: 1, review: "" } })]
    var p = createTemporaryObject(panelC, tc, { service: svc })
    p.opened = true
    tryCompare(p, "selectedKey", "e:c")
    var pr = textItem(p.detailItem, "open PR")
    var prX = pr.mapToItem(p, 0, 0).x
    p.keyCatcher.textKey("c")
    compare(svc.sent.filter(function(m) { return m.cmd === "copy" }).length, 1)
    compare(svc.sent.filter(function(m) { return m.cmd === "copy" })[0].text, "Design a robust plugin")
    verify(has(p, /^copy title$/), "no claim before the collector answers")
    svc.copied(true)
    tryVerify(function() { return has(p.detailItem, /^✓ copied$/) })
    compare(textItem(p.detailItem, "open PR").mapToItem(p, 0, 0).x, prX, "the next action stays where it was")
    tryVerify(function() { return has(p.detailItem, /^copy title$/) }, 4000, "and the label comes back")
    p.keyCatcher.textKey("c")
    svc.copied(false)
    tryVerify(function() { return has(p.detailItem, /^copy failed$/) })
    // A report with no copy asked for is ignored.
    tryVerify(function() { return has(p.detailItem, /^copy title$/) }, 4000)
    svc.copied(true)
    wait(50)
    verify(!has(p, /copied/))
  }

  function test_rowReasonSurvivesAFontChangeAfterCreation() {
    var r = row({ state: "failed", rawStatus: "failed", errorClass: "provider_error", completedAt: now - 60000, project: "a-long-project-name",
      error: '401: {"code":"1000","message":"Authentication Failed"}' })
    var q = row({ key: "e:q", id: "q", state: "input", rawStatus: "running", pendingKind: "user_input", pendingSince: now - 360000, project: "ingest" })
    var bumps = [0, 2, 4, 6]
    var made = []
    for (var w = 0; w < 2; w++) made.push(createTemporaryObject(rowC, tc, { row: w ? q : r, width: 340 }))
    try {
      for (var i = 0; i < bumps.length; i++) {
        Typo.bump = bumps[i]
        // The two-pane list's width at this size: 44% of a card that widens 56 px per step of bump.
        for (var m = 0; m < made.length; m++) made[m].width = Math.round((820 + bumps[i] * 56) * 0.44) - 20
        wait(0)
        verify(has(made[0], /^Failed · sign-in rejected$/), "bump " + bumps[i] + ": " + texts(made[0]).join(" | "))
        verify(has(made[1], /^Question$/), "bump " + bumps[i] + ": " + texts(made[1]).join(" | "))
        // The reason and the time share the second line, and neither is cut.
        var reason = textItem(made[0], "Failed · sign-in rejected"), time = textItem(made[0], "1m ago")
        verify(time !== null, "bump " + bumps[i] + ": " + texts(made[0]).join(" | "))
        verify(reason.mapToItem(made[0], reason.contentWidth, 0).x <= time.mapToItem(made[0], 0, 0).x, "bump " + bumps[i] + ": the reason stops before the time")
        verify(has(made[1], /^waiting 6m$/), "bump " + bumps[i] + ": " + texts(made[1]).join(" | "))
        verify(!has(made[0], /a-long-project-name|build-box/), "where it runs is left to the headings and the detail")
      }
    } finally {
      Typo.bump = 0
    }
  }

  // The title is what tells one thread from another: it has the whole first line, takes a second
  // if it needs one, and is cut only beyond that. With the demo's titles at the two-pane list's
  // real widths, none is cut at any text size.
  function test_rowTitlesAreShownWhole() {
    var titles = ["Migrate auth middleware to sessions v2", "Pick a queue backend for the ingest worker", "Plan: split the monorepo build into stages",
      "Regenerate API client from OpenAPI", "Nightly dependency audit (8AM daily)", "Port notch strip tooltips to the shell API",
      "Benchmark streaming latency across providers", "Rework onboarding flow for new users", "Write the Postgres 18 migration plan"]
    var bumps = [0, 2, 4, 6]
    try {
      for (var b = 0; b < bumps.length; b++) {
        Typo.bump = bumps[b]
        var width = Math.round((820 + bumps[b] * 56) * 0.44) - 14
        var oneLine = 0
        for (var i = 0; i < titles.length; i++) {
          var r = row({ title: titles[i], state: "input", rawStatus: "running", pendingKind: "command", pendingSince: now - 124000 })
          var item = createTemporaryObject(rowC, tc, { row: r, width: width })
          var title = named(item, "rowTitle")[0]
          compare(title.text, titles[i])
          verify(!title.truncated, "bump " + bumps[b] + ": '" + titles[i] + "' is cut")
          verify(title.lineCount <= 2)
          if (title.lineCount === 1) oneLine++
          // The time is on the second line, with its kind; it takes nothing from the title.
          var time = named(item, "rowTime")[0]
          compare(time.text, "waiting 2m")
          verify(time.mapToItem(item, 0, 0).y >= title.mapToItem(item, 0, title.height).y - 0.5, "bump " + bumps[b] + ": the time is under the title")
        }
        verify(oneLine >= titles.length - 2, "bump " + bumps[b] + ": most titles fit one line (" + oneLine + " of " + titles.length + ")")
      }
      // A title too long even for two lines is cut there, with the row still in one piece.
      Typo.bump = 0
      var long = createTemporaryObject(rowC, tc, { width: 340, row: row({ title: "Investigate why the nightly integration suite times out on the arm64 runners after the base image update last week", state: "working", rawStatus: "running", activeSince: now - 60000 }) })
      var cut = named(long, "rowTitle")[0]
      compare(cut.lineCount, 2)
      verify(cut.truncated)
      verify(cut.contentWidth <= cut.width + 0.5)
    } finally {
      Typo.bump = 0
    }
  }

  // A thread with subagents says so on its row, with a marker for the key that lists them: Enter
  // is not a guess. The marker turns when they are all listed. A thread without any has none.
  function test_rowWithSubagentsShowsAnExpandMarker() {
    var parent = row({ state: "working", rawStatus: "running", activeSince: now - 60000, childCount: 3, activeChildren: 2 })
    var item = createTemporaryObject(rowC, tc, { row: parent })
    var marker = named(item, "rowChildren")[0]
    verify(marker.visible)
    compare(texts(marker), ["3"])
    var title = named(item, "rowTitle")[0]
    verify(title.mapToItem(item, title.width, 0).x <= marker.mapToItem(item, 0, 0).x, "the title stops before the marker")
    var chevron = marker.children[1]
    compare(chevron.rotation, 0)
    item.expanded = true
    compare(chevron.rotation, 90)
    var lone = createTemporaryObject(rowC, tc, { row: row({ state: "background", background: { subagents: 2, commands: 0, monitors: 0, other: 0 }, activeSince: now - 60000 }) })
    verify(!named(lone, "rowChildren")[0].visible, "no child threads to list: no marker, as the legend has no Enter")
    // While only the live ones are listed under it, the count says so ("2/3"), so it matches the
    // rows there are; with all of them listed it is the plain count.
    var some = createTemporaryObject(rowC, tc, { row: row({ state: "working", rawStatus: "running", activeSince: now - 60000, childCount: 3, activeChildren: 2 }), listedChildren: 2 })
    verify(has(named(some, "rowChildren")[0], /^2\/3$/), texts(some).join(" | "))
    some.listedChildren = 3
    verify(has(named(some, "rowChildren")[0], /^3$/), texts(some).join(" | "))
    compare(Store.enterVerb(lone.row, true, false), "")
    compare(Store.enterVerb(parent, true, false), "subagents")
  }

  // What is running is drawn in ink in every theme: no spinner, live step or current plan step
  // borrows the accent (which marks selection) or a needs-you hue.
  function test_workingIsInkNotTheAccent() {
    var themes = [{ name: "matte black", c: tc.matteBlack }, { name: "latte", c: tc.latte }]
    var working = row({ state: "working", rawStatus: "running", activeSince: now - 60000, activity: [{ icon: "eye", label: "Read Bar.qml", status: "running", at: now }] })
    var runs = [{ ordinal: 1, status: "completed", startedAt: now - 3600000, completedAt: now - 3000000, durationMs: 600000 },
                { ordinal: 2, status: "failed", startedAt: now - 2000000, completedAt: now - 1900000, durationMs: 100000 },
                { ordinal: 3, status: "running", startedAt: now - 60000, completedAt: null, durationMs: null }]
    for (var t = 0; t < themes.length; t++) {
      var colors = themes[t].c, where = themes[t].name
      var ink = String(Qt.color(colors.text))
      var item = createTemporaryObject(rowC, tc, { row: working, colors: colors })
      compare(String(item.glyphColor), ink, where + ": the spinner")
      var d = createTemporaryObject(detailC, tc, { colors: colors, row: working, detail: { pending: [], runs: runs, context: null,
        subagents: [{ id: "s", title: "Sub", status: "running", progress: "", model: "m", startedAt: now - 1000, completedAt: null, childThreadId: "" }],
        todo: { total: 4, done: 2, current: "Polish" }, activity: working.activity } })
      var steps = named(d, "planStep")
      compare(String(steps[2].color), ink, where + ": the current plan step")
      verify(steps[2].height > steps[1].height, where + ": and it is taller than a done one")
      var bars = named(d, "runBar")
      compare(String(bars[2].color), ink, where + ": the run in progress")
      compare(named(bars[2], "currentRunMark")[0].visible, true, where + ": which also carries a mark, not just a colour")
      compare(named(bars[0], "currentRunMark")[0].visible, false)
      compare(String(named(d, "liveDot").filter(function(x) { return x.visible })[0].color), ink, where + ": the live dot")
      // Nothing in a working thread's row or detail is the accent or a needs-you hue, except the
      // failed run, which is the failure colour because it failed.
      var hues = [colors.accent, colors.accentInk, colors.warning, colors.warningInk, colors.ask, colors.askInk].map(function(c) { return String(Qt.color(c)) })
      var used = inks(item).concat(inks(d)).map(function(x) { return x.color })
      for (var u = 0; u < used.length; u++) verify(hues.indexOf(used[u]) < 0, where + ": a working thread's text is in " + used[u])
      for (var s = 0; s < steps.length; s++) verify(hues.indexOf(String(steps[s].color)) < 0, where + ": plan step " + s)
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
    var sawAbove = false, sawBelow = false, sawHeading = false
    function check(where) {
      var cell = list.itemAtIndex(p.cursor)
      verify(cell !== null, where)
      var scrolled = list.contentY - list.originY >= 2
      var more = list.contentY + list.height < list.contentHeight + list.originY - 2
      var covers = p.edgeCovers
      // The selection is fully visible, clear of both strips and their covers.
      verify(cell.y + cell.rowTop >= list.contentY + covers.top - 0.5, where + ": the selected row is under the top cover " + JSON.stringify({ y: cell.y + cell.rowTop, cy: list.contentY, top: covers.top }))
      verify(cell.y + cell.rowTop + cell.rowHeight <= list.contentY + list.height - covers.bottom + 0.5, where + ": the selected row is under the bottom cover")
      // "more above" exactly when there is more above, "more below" exactly when there is more below.
      compare(has(p, /^more above ↑$/), scrolled, where)
      compare(has(p, /^more below ↓$/), more, where)
      compare(covers.top >= p.pinnedHeight - 0.5, scrolled, where + ": the top cover is at least its strip")
      compare(covers.bottom >= p.moreBelowHeight - 0.5, more, where)
      sawAbove = sawAbove || scrolled
      sawBelow = sawBelow || more
      // No row or heading is drawn in part: each one in the list is wholly inside the window
      // between the covers, or wholly outside it.
      var top = list.contentY + covers.top, bottom = list.contentY + list.height - covers.bottom
      for (var i = 0; i < p.visible_.length; i++) {
        var c = list.itemAtIndex(i)
        if (!c) continue
        var boxes = []
        if (c.hasHeading) boxes.push({ what: "heading", a: c.y, b: c.y + c.rowTop })
        if (c.hasRow) boxes.push({ what: "row", a: c.y + c.rowTop, b: c.y + c.rowTop + c.rowHeight })
        for (var n = 0; n < boxes.length; n++) {
          var inside = boxes[n].a >= top - 0.5 && boxes[n].b <= bottom + 0.5
          var outside = boxes[n].b <= top + 0.5 || boxes[n].a >= bottom - 0.5
          verify(inside || outside, where + ": the " + boxes[n].what + " of item " + i + " is cut by an edge " + JSON.stringify({ a: boxes[n].a, b: boxes[n].b, top: top, bottom: bottom }))
        }
      }
      // The pinned heading, when shown, is the group of the first row drawn whole; when that
      // row's own heading is the first thing drawn, nothing is pinned over it.
      var heading = p.pinnedHeading
      if (heading) {
        sawHeading = true
        verify(!covers.firstIsHeading, where)
        var k = covers.first
        while (k > 0 && p.visible_[k].parentId) k--
        compare(heading.label, Store.groupKey(p.visible_[k], svc.environments), where)
      }
    }
    for (var step = 0; step < 30; step++) {
      p.moveCursor(1)
      wait(20)
      check("down " + step)
    }
    for (var up = 0; up < 30; up++) {
      p.moveCursor(-1)
      wait(20)
      check("up " + up)
    }
    verify(sawAbove && sawBelow && sawHeading, "the walk met both edges and a pinned heading")
    // The same holds wherever the wheel leaves the list, not only where the keys do.
    var maxY = list.originY + list.contentHeight - list.height
    for (var w = 0; w <= 24; w++) {
      list.contentY = list.originY + Math.round(maxY * w / 24) + (w % 3)
      wait(0)
      var covers = p.edgeCovers
      var top = list.contentY + covers.top, bottom = list.contentY + list.height - covers.bottom
      var whole = 0
      for (var i = 0; i < p.visible_.length; i++) {
        var c = list.itemAtIndex(i)
        if (!c || !c.hasRow) continue
        var a = c.y + c.rowTop, b = a + c.rowHeight
        if (a >= top - 0.5 && b <= bottom + 0.5) whole++
        verify((a >= top - 0.5 && b <= bottom + 0.5) || b <= top + 0.5 || a >= bottom - 0.5, "wheel at " + list.contentY + ": row " + i + " is cut by an edge")
      }
      verify(whole >= 2, "wheel at " + list.contentY + ": the covers leave rows in view (" + whole + ")")
    }
  }

  // The row of view tabs: the filter box is one of its controls (the tabs' top edge, height and
  // border tone), and the current view is marked once, by its tab's bottom edge in the theme's accent.
  function test_filterBoxAndTabMarkSitOnTheTabRow() {
    var svc = createTemporaryObject(serviceC, tc)
    svc.palette = tc.matteBlack
    svc.environments = [liveEnv("e", "laptop"), { id: "f", label: "build-box", sshHost: "build-box", state: "live", stale: false, url: "", sessionExpiresAt: now + 2 * 86400000, providers: [] }]
    svc.rows = manyRows()
    var p = createTemporaryObject(panelC, tc, { service: svc })
    p.opened = true
    tryVerify(function() { return p.cursor >= 0 })
    var tabs = []
    function walk(it) {
      if (!it || it.visible === false) return
      if (it.selected !== undefined && it.modelData !== undefined && typeof it.text === "string") tabs.push(it)
      var kids = it.children || []
      for (var i = 0; i < kids.length; i++) walk(kids[i])
    }
    walk(p)
    compare(tabs.length, 4)
    var box = named(p, "filterBox")[0]
    compare(Math.round(box.mapToItem(p, 0, 0).y), Math.round(tabs[0].mapToItem(p, 0, 0).y), "the filter box starts at the tabs' top edge")
    compare(box.height, tabs[0].height, "and is as tall as a tab")
    var mark = named(p, "tabMark")[0]
    var current = tabs.filter(function(t) { return t.selected })[0]
    compare(Math.round(mark.mapToItem(p, 0, 0).x), Math.round(current.mapToItem(p, 0, 0).x))
    compare(mark.width, current.width)
    compare(Math.round(mark.mapToItem(p, 0, mark.height).y), Math.round(current.mapToItem(p, 0, current.height).y), "the mark is the tab's own bottom edge, not a line under it")
    // "Where you are" is one colour in a theme: the tab's mark is the selection ring's. On a
    // theme whose accent is plan amber that is ink, so nothing under the tabs passes for a plan.
    compare(String(mark.color), String(Qt.color(tc.matteBlack.focus)), "the selection ring's colour")
    verify(Palette.hsl(String(mark.color)).s < 0.05, "ink on matte black, not the amber accent: " + mark.color)
    var cell = p.listView.itemAtIndex(p.cursor)
    compare(String(named(cell, "fill")[0].border.color), String(mark.color), "the same as the selected row's ring")
    // A pairing about to lapse is told from the healthy machine beside it by shape, not colour.
    compare(named(p, "machineExpiring").filter(function(x) { return x.visible }).length, 1, "one machine is expiring")
    verify(has(p, /^pairing expires in 2d$/))
    compare(String(textItem(p, "pairing expires in 2d").color), String(Qt.color(tc.matteBlack.text)), "full ink, no hue")
  }

  // The keys the legend is showing, in reading order: "key verb".
  function legendKeys(p) {
    var out = []
    var groups = p.legendShown
    for (var g = 0; g < groups.length; g++) for (var c = 0; c < groups[g].columns.length; c++) for (var i = 0; i < groups[g].columns[c].length; i++)
      if (groups[g].columns[c][i].key) out.push(groups[g].columns[c][i].key + " " + groups[g].columns[c][i].verb)
    return out
  }

  // The legend as drawn: every cell with where it is in the panel, by group, column and row.
  // [{ group, column, row, key, verb, x, y, width, right, item }]
  function legendLayout(p) {
    var cells = []
    var groups = shown(p.legendItem, "legendGroup:")
    for (var g = 0; g < groups.length; g++) {
      var columns = shown(groups[g], "legendColumn")
      for (var c = 0; c < columns.length; c++) {
        var inColumn = shown(columns[c], "legendCell")
        for (var i = 0; i < inColumn.length; i++) {
          var at = inColumn[i].mapToItem(p, 0, 0)
          cells.push({ group: groups[g].objectName.replace("legendGroup:", ""), column: c, row: i, key: inColumn[i].shownKey, verb: inColumn[i].shownVerb,
            x: Math.round(at.x), y: Math.round(at.y), width: inColumn[i].width, right: at.x + inColumn[i].width, item: inColumn[i] })
        }
      }
    }
    return cells
  }

  // The footer's key legend: three groups by purpose, their keys in columns that line up down the
  // two rows; exactly two rows tall for every selection; no key ever moves as the selection moves
  // (Enter comes and goes at the foot of its own column); every key has its label; it starts under
  // the usage band's content and fits its band. Checked at each text size, at the widths the shell
  // gives the two-pane window (820 px + 56 per step) and the dropdown (540 + 36).
  function test_legendHoldsAtEverySizeAndSelection() {
    var svc = createTemporaryObject(serviceC, tc)
    var meter = { name: "Claude", driver: "claudeAgent", status: "ready", auth: "authenticated", checkedAt: now, windows: windowsOf(3) }
    svc.environments = [{ id: "e", label: "laptop", sshHost: "", state: "live", stale: false, url: "", sessionExpiresAt: now + 20 * 86400000, providers: [meter] }]
    var rows = manyRows()
    rows.push(row({ key: "e:i1", id: "i1", title: "Idle one", project: "alpha", state: "idle", rawStatus: "completed", completedAt: now - 7200000 }))
    svc.rows = rows
    var layouts = [{ c: shortPanelC, base: 820, step: 56, name: "panel", centered: true }, { c: dropdownC, base: 540, step: 36, name: "dropdown", centered: false }]
    var bumps = [0, 2, 4, 6]
    try {
      for (var l = 0; l < layouts.length; l++) {
        for (var b = 0; b < bumps.length; b++) {
          Typo.bump = bumps[b]
          var p = createTemporaryObject(layouts[l].c, tc, { service: svc, width: layouts[l].base + layouts[l].step * bumps[b] })
          p.opened = true
          p.setFilter("all")
          tryVerify(function() { return p.cursor >= 0 })
          var where = layouts[l].name + " at bump " + bumps[b]
          var heights = {}, enter = {}, places = {}
          for (var i = 0; i < 26; i++) {
            wait(0)
            heights[p.legendHeight] = true
            var cells = legendLayout(p)
            var ys = {}
            for (var c = 0; c < cells.length; c++) {
              var cell = cells[c]
              ys[cell.y] = true
              if (cell.key === "") { enter["(none)"] = true; continue }
              verify(cell.verb !== "", where + ": '" + cell.key + "' without its label")
              verify((cell.key + cell.verb).indexOf("·") < 0, where + ": a separator in the legend")
              if (cell.key === "↵") { enter[cell.verb] = true; continue }
              // Every other key is where it was for every other selection.
              var spot = cell.x + "," + cell.y
              if (places[cell.key] === undefined) places[cell.key] = spot
              compare(spot, places[cell.key], where + ": '" + cell.key + " " + cell.verb + "' moved when the selection did")
              verify(cell.right <= p.width + 0.5, where + ": '" + cell.key + " " + cell.verb + "' runs past the edge at " + Math.round(cell.right) + " of " + p.width)
            }
            compare(Object.keys(ys).length, 2, where + ": the keys sit on two rows")
            // A column's cells share their left edge: that is what makes the rows line up.
            var edges = {}
            for (var k = 0; k < cells.length; k++) {
              var id = cells[k].group + ":" + cells[k].column
              if (edges[id] === undefined) edges[id] = cells[k].x
              compare(cells[k].x, edges[id], where + ": column " + id + " is ragged")
            }
            verify(p.legendWidth <= p.legendRoom + 0.5, where + ": legend " + p.legendWidth + " wider than its room " + p.legendRoom)
            p.moveCursor(1)
          }
          compare(Object.keys(heights).length, 1, where + ": heights " + Object.keys(heights).join(", "))
          verify(Object.keys(enter).length >= 2, where + ": the cursor met different Enter actions: " + Object.keys(enter).join(", "))
          verify(p.legendHeight <= 2 * Typo.caption * 1.6 + Style.space(4), where + ": more than two lines (" + p.legendHeight + ")")
          // The groups, left to right, by purpose.
          var seen = legendLayout(p)
          var order = []
          for (var s = 0; s < seen.length; s++) if (order.indexOf(seen[s].group) < 0) order.push(seen[s].group)
          compare(order, ["navigate", "act", "window"], where)
          // The text-size control is inside the cell of its keys, not somewhere else in the footer.
          var size = seen.filter(function(x) { return x.key === "+/−" })[0]
          verify(size !== undefined && size.item.cell.slot === "size", where + ": the size keys are in the legend")
          var bars = textItemAbsent(size.item)
          verify(bars, where + ": the size control sits beside '+/− size'")
          // Paging the detail is a key of the two-pane window only, and it is in its legend.
          compare(legendKeys(p).indexOf("d/u scroll detail") >= 0, layouts[l].centered, where + ": " + legendKeys(p).join(" | "))
          // Two-pane: the keys start where the usage band's content starts, under one caption column.
          if (layouts[l].centered) {
            verify(has(p, /^KEYS$/) && has(p, /^LIMITS USED$/), where + ": both bands are captioned")
            var name = shown(p, "block:Claude:name")[0]
            compare(Math.round(p.legendItem.mapToItem(p, 0, 0).x), Math.round(name.mapToItem(p, 0, 0).x), where + ": the two bands' content shares a left edge")
          }
        }
      }
    } finally {
      Typo.bump = 0
    }
  }

  // A cell holds a text-size control if something in it is neither a Text nor empty: its bars.
  function textItemAbsent(cellItem) {
    var found = false
    function walk(it) {
      if (!it || found || it.visible === false) return
      if (it.sizes !== undefined && it.step !== undefined) { found = true; return }
      var kids = it.children || []
      for (var i = 0; i < kids.length; i++) walk(kids[i])
    }
    walk(cellItem)
    return found
  }

  function test_offlineLegendKeepsOnlyTheKeysThatWork() {
    var svc = createTemporaryObject(serviceC, tc)
    svc.known = false
    svc.environments = [{ id: "a", label: "laptop", sshHost: "", state: "expired", stale: false, url: "http://127.0.0.1:3773", sessionExpiresAt: now - 1000, providers: [] }]
    var p = createTemporaryObject(panelC, tc, { service: svc })
    p.opened = true
    tryVerify(function() { return p.disconnected })
    compare(legendKeys(p), ["1 copy command", "o open T3", "f layout", "r refresh", "+/− size", "esc close"])
    var drawn = legendLayout(p).filter(function(c) { return c.key !== "" }).map(function(c) { return c.key + " " + c.verb })
    compare(drawn, legendKeys(p), "what is drawn is what the legend holds")
    verify(has(p, /^KEYS$/), "the band keeps its caption with no usage band above it")
  }

  Component { id: stripC; ProviderStrip { colors: tc.colors; now: tc.now } }

  function xOf(item, value, from) {
    var t = textItem(item, value)
    verify(t !== null, "found '" + value + "' in " + texts(item).join(" | "))
    return t.mapToItem(item, 0, 0).x
  }

  // Items in the shown layout (not hidden, not transparent) whose objectName starts with prefix.
  function shown(item, prefix) {
    var out = []
    function walk(it) {
      if (!it || it.visible === false || it.opacity === 0) return
      if (it.objectName && it.objectName.indexOf(prefix) === 0) out.push(it)
      var kids = it.children || []
      for (var i = 0; i < kids.length; i++) walk(kids[i])
    }
    walk(item)
    return out
  }

  function windowsOf(n) {
    var all = [{ label: "Session", kind: "session", usedPercent: 95, resetsAt: now + 3600000, durationMins: 300 },
               { label: "Weekly", kind: "weekly", usedPercent: 55, resetsAt: now + 3 * 86400000, durationMins: 10080 },
               { label: "Weekly · Fable", kind: "weekly", usedPercent: 0, resetsAt: now + 3 * 86400000, durationMins: 10080 },
               { label: "Session", kind: "session", usedPercent: 100, resetsAt: now + 47 * 60000, durationMins: 300 }]
    return all.slice(0, n)
  }

  // Usage limits with real accounts: one to four windows per provider (Sean's live Claude has
  // three: 5-hour, weekly, weekly · Fable). In both layouts, at each text size and real width:
  // each provider's windows stay in its own row (wrapping inside it if they must), every label is
  // distinct, and it fits.
  function test_usageLimitsKeepEachProvidersWindowsTogether() {
    var combos = [[2, 3], [3, 2], [1, 4], [4, 1], [3, 3], [1, 1]]
    var layouts = [{ compact: false, base: 820, step: 56, name: "panel" }, { compact: true, base: 540, step: 36, name: "dropdown" }]
    var bumps = [0, 2, 4, 6]
    try {
      for (var l = 0; l < layouts.length; l++) for (var b = 0; b < bumps.length; b++) for (var c = 0; c < combos.length; c++) {
        Typo.bump = bumps[b]
        var L = layouts[l]
        var width = L.base + L.step * bumps[b] - 24
        var providers = [
          { name: "Codex", driver: "codex", status: "ready", auth: "authenticated", checkedAt: now, windows: windowsOf(combos[c][0]) },
          { name: "Claude", driver: "claudeAgent", status: "ready", auth: "authenticated", checkedAt: now, windows: windowsOf(combos[c][1]) }
        ]
        var strip = createTemporaryObject(stripC, tc, { compact: L.compact, width: width })
        strip.environments = [{ id: "e", label: "laptop", state: "live", providers: providers }]
        waitForRendering(strip)
        wait(20)
        var where = L.name + " at bump " + bumps[b] + " with " + combos[c].join("+") + " windows"
        verify(strip.implicitWidth <= width + 0.5, where + ": " + strip.implicitWidth + " wider than " + width)
        var prefix = "block:"
        var bands = []
        for (var p = 0; p < providers.length; p++) {
          var nm = shown(strip, prefix + providers[p].name + ":name")
          compare(nm.length, 1, where + ": " + providers[p].name + "'s name")
          bands.push(nm[0].mapToItem(strip, 0, 0).y)
        }
        for (var q = 0; q < providers.length; q++) {
          var top = bands[q], bottom = q + 1 < bands.length ? bands[q + 1] : 1e9
          var labels = []
          for (var k = 0; k < providers[q].windows.length; k++) {
            var items = shown(strip, "block:" + providers[q].name + ":" + k)
            compare(items.length, 1, where + ": " + providers[q].name + " window " + k)
            var y = items[0].mapToItem(strip, 0, 0).y
            var x = items[0].mapToItem(strip, items[0].width, 0).x
            verify(y >= top - 1 && y < bottom - 1, where + ": " + providers[q].name + " window " + k + " at y " + y + " is outside its band " + top + "–" + bottom)
            verify(x <= width + 0.5, where + ": window " + k + " runs past the edge")
            labels.push(named(items[0], "usageLabel")[0].text)
          }
          var distinct = {}
          for (var d = 0; d < labels.length; d++) distinct[labels[d]] = true
          compare(Object.keys(distinct).length, labels.length, where + ": " + providers[q].name + " labels " + labels.join(", "))
        }
      }
    } finally {
      Typo.bump = 0
    }
  }

  // Sean's live footer: Codex with two windows, Claude with three, in the two-pane footer. Each
  // provider's windows sit on its own row, side by side; a hit limit widens only its own row.
  function test_seansLiveFooterKeepsEachProviderOnItsRow() {
    var providers = [
      { name: "Codex", driver: "codex", status: "ready", auth: "authenticated", checkedAt: now,
        windows: [{ label: "Session", kind: "session", usedPercent: 100, resetsAt: now + 47 * 60000, durationMins: 300 }, { label: "Weekly", kind: "weekly", usedPercent: 30, resetsAt: now + 4 * 86400000, durationMins: 10080 }] },
      { name: "Claude", driver: "claudeAgent", status: "ready", auth: "authenticated", checkedAt: now,
        windows: [{ label: "Session", kind: "session", usedPercent: 95, resetsAt: now + 3600000, durationMins: 300 }, { label: "Weekly", kind: "weekly", usedPercent: 55, resetsAt: now + 3 * 86400000, durationMins: 10080 },
                  { label: "Weekly · Fable", kind: "weekly", usedPercent: 0, resetsAt: now + 3 * 86400000, durationMins: 10080 }] }
    ]
    var strip = createTemporaryObject(stripC, tc, { width: 796 })
    strip.environments = [{ id: "e", label: "laptop", state: "live", providers: providers }]
    waitForRendering(strip)
    wait(20)
    verify(has(strip, /^weekly · Fable$/), texts(strip).join(" | "))
    // The heading says which way the numbers count. A cell's value is a percentage, or "full" in
    // full-strength ink for a spent window; a spent or nearly spent window says when it resets
    // right after it.
    verify(has(strip, /^LIMITS USED$/))
    verify(has(strip, /^95%$/) && has(strip, /^full$/), texts(strip).join(" | "))
    compare(String(textItem(strip, "full").color), String(Qt.color(tc.colors.text)))
    verify(has(strip, /^resets in 47m$/) && has(strip, /^resets in 1h$/), texts(strip).join(" | "))
    verify(!texts(strip).some(function(t) { return /%.*resets|limit reached/.test(t) }), "no sentence in a cell: " + texts(strip).join(" | "))
    // The meters are long enough to read a share from, and drawn whole: an outline as long as the
    // limit, filled as far as the use, so 0% still shows how long 100% would be. A spent window's is full.
    var meters = []
    var cells = shown(strip, "block:").filter(function(c) { return c.kind !== undefined })
    for (var n = 0; n < cells.length; n++) meters = meters.concat(named(cells[n], "meter"))
    compare(meters.length, 5, "one meter per window")
    var spentCell = shown(strip, "block:Codex:0")[0]
    compare(named(spentCell, "meterFill")[0].width, named(spentCell, "meter")[0].width, "the spent window's meter is full")
    for (var m = 0; m < meters.length; m++) {
      verify(meters[m].width >= 56, "meter " + m + " is " + meters[m].width + " px long")
      var track = named(meters[m], "meterTrack")[0], fill = named(meters[m], "meterFill")[0]
      compare(track.width, meters[m].width, "the outline runs the meter's full length")
      verify(Palette.contrast(String(track.border.color), tc.colors.background) >= 3, "the outline is a 3:1 mark")
      verify(fill.width <= meters[m].width + 0.5)
    }
    verify(!texts(strip).some(function(t) { return /:$/.test(t) }), "no stray colon after a label")
    function y(name) { return shown(strip, name)[0].mapToItem(strip, 0, 0).y }
    function x(name) { return shown(strip, name)[0].mapToItem(strip, 0, 0).x }
    for (var k = 0; k < 2; k++) compare(y("block:Codex:" + k), y("block:Codex:name"), "Codex window " + k + " on Codex's row")
    for (var j = 0; j < 3; j++) compare(y("block:Claude:" + j), y("block:Claude:name"), "Claude window " + j + " on Claude's row")
    compare(x("block:Codex:0"), x("block:Claude:0"), "first windows start in one column")
    compare(x("block:Claude:1"), x("block:Codex:1"), "weekly starts at the same x on both rows")
    // Each reset is in its own window's cell, on its provider's line, after the value and before
    // the next column: the band is one line a provider.
    var codexCell = shown(strip, "block:Codex:0")[0], claudeCell = shown(strip, "block:Claude:0")[0]
    var codexReset = named(codexCell, "usageResetInline")[0], claudeReset = named(claudeCell, "usageResetInline")[0]
    verify(codexReset.visible && claudeReset.visible)
    verify(!named(codexCell, "usageReset")[0].visible, "not under the meter as well")
    function midY(item) { return item.mapToItem(strip, 0, item.height / 2).y }
    fuzzyCompare(midY(codexReset), midY(named(codexCell, "usageValue")[0]), 1, "Codex's reset is on the line of its value")
    fuzzyCompare(midY(claudeReset), midY(named(claudeCell, "usageValue")[0]), 1, "Claude's too")
    verify(codexReset.mapToItem(strip, 0, 0).x > named(codexCell, "usageValue")[0].mapToItem(strip, 0, 0).x, "after the value")
    verify(codexReset.mapToItem(strip, codexReset.width, 0).x <= x("block:Codex:1"), "and before the next column")
    // The band is as tall as its two provider lines: no third line for a reset.
    var nameTall = shown(strip, "block:Codex:name")[0].parent.height
    verify(y("block:Claude:name") - y("block:Codex:name") <= nameTall + Style.space(6), "Claude's line follows Codex's directly")
    // Quiet until it matters: a window with room left is dim, one near or at its limit is full ink.
    compare(String(textItem(strip, "30%").color), String(Qt.color(tc.colors.textDim)))
    compare(String(textItem(strip, "95%").color), String(Qt.color(tc.colors.text)))
  }

  // Where a cell's parts start, in the strip's coordinates: its label, its meter and its value.
  function cellParts(strip, cell) {
    var label = named(cell, "usageLabel")[0], meter = named(cell, "meter")[0], value = named(cell, "usageValue")[0]
    // The reset is beside the value (the two-pane window) or under the meter (the dropdown).
    var inline = named(cell, "usageResetInline")[0], reset = inline.visible ? inline : named(cell, "usageReset")[0]
    return { kind: cell.kind, resetInline: inline.visible, valueY: value.mapToItem(strip, 0, value.height / 2).y, resetMidY: reset.mapToItem(strip, 0, reset.height / 2).y, x: Math.round(cell.mapToItem(strip, 0, 0).x), y: Math.round(cell.mapToItem(strip, 0, 0).y), label: label.text,
      meterX: Math.round(meter.mapToItem(strip, 0, 0).x), meterWidth: meter.width, valueX: Math.round(value.mapToItem(strip, 0, 0).x), value: value.text,
      // The cell's first line ends with its value; a reset line under the meter may run further.
      right: value.mapToItem(strip, value.width, 0).x,
      reset: reset.visible ? reset.text : "", resetX: Math.round(reset.mapToItem(strip, 0, 0).x), resetY: reset.mapToItem(strip, 0, 0).y,
      resetRight: reset.visible ? reset.mapToItem(strip, reset.width, 0).x : 0, meterBottom: meter.mapToItem(strip, 0, meter.height).y }
  }

  // Usage is one grid: each kind of window has its own column, the same for every provider row.
  // With the demo's accounts (Codex has two windows, one of them spent; Claude has three, with
  // "weekly · Fable"), in both layouts and at each text size: the same kind of window starts at the
  // same x on both rows, its meter too, the meters are one length, a kind only one provider has
  // keeps its own column, and nothing overlaps the column after it.
  function test_usageWindowsShareColumnsAcrossProviders() {
    var providers = [
      { name: "Claude", driver: "claudeAgent", status: "ready", auth: "authenticated", checkedAt: now,
        windows: [{ label: "Session", kind: "session", usedPercent: 38, resetsAt: now + 140 * 60000, durationMins: 300 }, { label: "Weekly", kind: "weekly", usedPercent: 61, resetsAt: now + 3 * 86400000, durationMins: 10080 },
                  { label: "Weekly · Fable", kind: "weekly", usedPercent: 4, resetsAt: now + 3 * 86400000, durationMins: 10080 }] },
      { name: "Codex", driver: "codex", status: "ready", auth: "authenticated", checkedAt: now,
        windows: [{ label: "Session", kind: "session", usedPercent: 100, resetsAt: now + 47 * 60000, durationMins: 300 }, { label: "Weekly", kind: "weekly", usedPercent: 82, resetsAt: now + 5 * 86400000, durationMins: 10080 }] }
    ]
    var layouts = [{ compact: false, base: 820, step: 56, name: "panel", kinds: ["5-hour", "weekly", "weekly · Fable"] },
                   { compact: true, base: 540, step: 36, name: "dropdown", kinds: ["5h", "week", "week · Fable"] }]
    var bumps = [0, 2, 4, 6]
    try {
      for (var l = 0; l < layouts.length; l++) for (var b = 0; b < bumps.length; b++) {
        Typo.bump = bumps[b]
        var L = layouts[l]
        var where = L.name + " at bump " + bumps[b]
        var strip = createTemporaryObject(stripC, tc, { compact: L.compact, width: L.base + L.step * bumps[b] - 24 })
        strip.environments = [{ id: "e", label: "laptop", state: "live", providers: providers }]
        waitForRendering(strip)
        wait(20)
        var claude = [0, 1, 2].map(function(i) { return cellParts(strip, shown(strip, "block:Claude:" + i)[0]) })
        var codex = [0, 1].map(function(i) { return cellParts(strip, shown(strip, "block:Codex:" + i)[0]) })
        compare(claude.map(function(c) { return c.kind }), L.kinds, where + ": Claude's windows, each in its kind's column")
        compare(codex.map(function(c) { return c.kind }), L.kinds.slice(0, 2), where + ": Codex's")
        for (var k = 0; k < 2; k++) {
          compare(codex[k].label, claude[k].label, where)
          compare(codex[k].x, claude[k].x, where + ": '" + claude[k].kind + "' starts at the same x on both rows")
          compare(codex[k].meterX, claude[k].meterX, where + ": so does its meter")
          compare(codex[k].valueX, claude[k].valueX, where + ": and its value")
        }
        // "full" is no wider than a percentage: the values themselves end about together.
        verify(Math.abs(codex[0].right - claude[0].right) <= claude[0].valueX - claude[0].meterX, where + ": the spent value is about as wide as the other (" + Math.round(codex[0].right) + " vs " + Math.round(claude[0].right) + ")")
        var widest = Math.max(codex[0].right, claude[0].right, codex[0].resetRight)
        verify(claude[1].x >= widest, where + ": the next column starts after the widest entry of this one")
        verify(claude[1].x - widest <= strip.itemGap + 2, where + ": and only a column's gap after it (" + (claude[1].x - widest) + ")")
        // When Codex's spent window resets is said in that window's own cell, so "full" is followed
        // by what it means: beside the value in the two-pane window (one line a provider), under
        // the meter in the dropdown, where it stays inside the column's ordinary width.
        compare(codex[0].value, "full", where)
        compare(codex[0].reset, "resets in 47m", where)
        compare(codex[0].resetInline, !L.compact, where)
        if (L.compact) {
          var cellWide = Math.max(claude[0].right, codex[0].right) - claude[0].x
          verify(widest - claude[0].x <= cellWide + 3 * Typo.caption, where + ": the column is about one cell wide (" + Math.round(widest - claude[0].x) + " vs " + Math.round(cellWide) + ")")
          verify(codex[0].resetX === codex[0].meterX || codex[0].resetX === codex[0].x, where + ": it starts under the meter, or under the label where the cell is too narrow for that")
          verify(codex[0].resetY >= codex[0].meterBottom - 0.5, where + ": below it")
        } else {
          verify(codex[0].resetX > codex[0].valueX, where + ": after the value")
          verify(Math.abs(codex[0].resetMidY - codex[0].valueY) <= 1, where + ": on the value's own line")
        }
        verify(codex[0].resetRight <= claude[1].x, where + ": and ends before the next column (" + Math.round(codex[0].resetRight) + " vs " + claude[1].x + ")")
        compare(codex[1].reset, "", where + ": a window with room left adds nothing")
        claude.forEach(function(c) { compare(c.reset, "", where + ": Claude has nothing near its limit") })
        // The kind only Claude has keeps a column of its own, clear of weekly on either row.
        verify(claude[2].x >= Math.max(claude[1].right, codex[1].right) || claude[2].y > claude[1].y, where + ": 'weekly · Fable' has its own column")
        var lengths = {}
        claude.concat(codex).forEach(function(c) { lengths[c.meterWidth] = true })
        compare(Object.keys(lengths).length, 1, where + ": every meter is one length: " + Object.keys(lengths).join(", "))
        // On one line where there is room for it (the usual sizes); nothing runs past the band.
        claude.concat(codex).forEach(function(c) { verify(c.right <= strip.width + 0.5, where + ": '" + c.kind + "' runs past the edge") })
        if (!L.compact && bumps[b] <= 2) compare(claude[2].y, claude[0].y, where + ": all three columns fit one line")
        compare(codex[0].y, codex[1].y, where + ": Codex's two share a line")
        // Provider rows are a row apart, and each provider's name leads its row.
        verify(codex[0].y > claude[0].y, where)
        compare(Math.round(shown(strip, "block:Codex:name")[0].mapToItem(strip, 0, 0).x), Math.round(shown(strip, "block:Claude:name")[0].mapToItem(strip, 0, 0).x), where + ": names share a column")
      }
    } finally {
      Typo.bump = 0
    }
  }

  // A band too narrow for every column breaks at the same column on every row, so the kinds still
  // line up; a provider with nothing on the second line stays one line tall.
  function test_usageColumnsWrapTogetherWhenTheBandIsNarrow() {
    var providers = [
      { name: "Claude", driver: "claudeAgent", status: "ready", auth: "authenticated", checkedAt: now, windows: windowsOf(3) },
      { name: "Codex", driver: "codex", status: "ready", auth: "authenticated", checkedAt: now, windows: [windowsOf(4)[3], windowsOf(2)[1]] }
    ]
    // Wide enough for the first two columns beside the heading and the names, not for the third.
    var wide = createTemporaryObject(stripC, tc, { width: 2000 })
    wide.environments = [{ id: "e", label: "laptop", state: "live", providers: providers }]
    waitForRendering(wide)
    wait(20)
    var third = cellParts(wide, shown(wide, "block:Claude:2")[0])
    var strip = createTemporaryObject(stripC, tc, { width: third.x + 20 })
    strip.environments = [{ id: "e", label: "laptop", state: "live", providers: providers }]
    waitForRendering(strip)
    wait(20)
    var claude = [0, 1, 2].map(function(i) { return cellParts(strip, shown(strip, "block:Claude:" + i)[0]) })
    var codex = [0, 1].map(function(i) { return cellParts(strip, shown(strip, "block:Codex:" + i)[0]) })
    compare(claude[1].y, claude[0].y, "the first two columns still share the first line")
    verify(claude[2].y > claude[0].y, "the third column moved to a second line: " + JSON.stringify(claude.map(function(c) { return [c.x, c.y] })))
    compare(claude[1].x, codex[1].x, "weekly still starts at the same x on both rows")
    compare(claude[0].x, codex[0].x)
    compare(claude[2].x, claude[0].x, "the wrapped column starts where the first does")
    verify(codex[0].y > claude[2].y, "Codex's row starts below Claude's second line")
    claude.concat(codex).forEach(function(c) { verify(c.right <= strip.width + 0.5, "'" + c.kind + "' runs past the edge") })
  }


  // Both panes' scrollbars: a thumb at 3:1 against its track and the panel, on a visible track.
  function test_scrollbarsUseThePalettesScrollTones() {
    var svc = createTemporaryObject(serviceC, tc)
    svc.environments = [liveEnv("e", "laptop")]
    svc.rows = manyRows()
    var p = createTemporaryObject(shortPanelC, tc, { service: svc })
    p.opened = true
    p.setFilter("all")
    tryVerify(function() { return p.cursor >= 0 })
    var bar = p.listView.ScrollBar.vertical
    verify(bar !== null)
    compare(String(bar.contentItem.color), String(Qt.color(tc.colors.scrollThumb)))
    compare(String(bar.background.color), String(Qt.color(tc.colors.scrollTrack)))
    compare(bar.policy, ScrollBar.AlwaysOn, "shown while the list is longer than its pane")
    verify(bar.background.visible, "the track shows")
    // Rows stop short of the bar.
    var cell = p.listView.itemAtIndex(p.cursor)
    verify(cell.x + cell.width <= p.listView.width - bar.width + 0.5, "row " + (cell.x + cell.width) + " runs under the bar at " + (p.listView.width - bar.width))
    verify(Palette.contrast(tc.colors.scrollThumb, tc.colors.scrollTrack) >= 3)
    verify(Palette.contrast(tc.colors.scrollThumb, tc.colors.background) >= 3)
  }

  // Text that can't elide or wrap, drawn past `edge` (in pane coordinates) or narrower than itself.
  function clippedTexts(pane, edge) {
    var bad = []
    function walk(it) {
      if (!it || it.visible === false || it.opacity === 0) return
      if (it.font !== undefined && typeof it.text === "string" && it.text !== "" && it.elide === Text.ElideNone && it.wrapMode === Text.NoWrap) {
        var right = it.mapToItem(pane, it.implicitWidth, 0).x
        if (right > edge + 0.5) bad.push("'" + it.text + "' ends at " + Math.round(right) + " past " + Math.round(edge))
        else if (it.width + 0.5 < it.implicitWidth) bad.push("'" + it.text + "' squeezed to " + Math.round(it.width) + " of " + Math.round(it.implicitWidth))
      }
      var kids = it.children || []
      for (var i = 0; i < kids.length; i++) walk(kids[i])
    }
    walk(pane)
    return bad
  }

  // The detail pane never runs content under its scrollbar, whether or not one is showing: no
  // "copy titl", no "3r" or "waitin". At each text size, at the pane's real width, with a short
  // detail (no scrollbar) and a long one (scrollbar on).
  function test_detailContentStopsShortOfTheScrollbar() {
    var approval = row({ state: "input", rawStatus: "running", pendingKind: "command", pendingSince: now - 124000, project: "web-app", branch: "feat/sessions-v2", model: "claude-opus-5-5" })
    var shortDetail = { runs: [], context: { used: 412000, max: 1000000, cost: 3.42, currency: "USD" }, subagents: [], todo: null,
      activity: [{ icon: "terminal", label: "pnpm vitest run auth", status: "completed", at: now - 180000 }, { icon: "message-circle", label: "Awaiting approval", status: "pending", at: now - 120000 }],
      pending: [{ id: "r1", kind: "command", since: now - 124000, prompt: "git push --force-with-lease origin feat/sessions-v2 && pnpm db:migrate --env staging", appName: "", options: ["Allow once", "Allow for session", "Decline"], questions: [] }] }
    var longDetail = { runs: shortDetail.runs, context: shortDetail.context, subagents: [], todo: { total: 6, done: 4, current: "Run the migration against staging" }, pending: shortDetail.pending,
      activity: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map(function(i) { return { icon: "terminal", label: "step " + i + " of a long thread", status: i === 12 ? "pending" : "completed", at: now - i * 7 * 60000 } }) }
    var details = [{ d: shortDetail, name: "short" }, { d: longDetail, name: "long" }]
    var bumps = [0, 2, 4, 6]
    try {
      for (var b = 0; b < bumps.length; b++) for (var k = 0; k < details.length; k++) {
        Typo.bump = bumps[b]
        var width = Math.round((820 + 56 * bumps[b]) * 0.56) - 30
        var p = createTemporaryObject(paneC, tc, { row: approval, detail: details[k].d, machineLabel: "laptop", width: width, height: 640 })
        waitForRendering(p)
        wait(20)
        var bad = clippedTexts(p, p.width - Style.space(8))
        compare(bad.length, 0, details[k].name + " detail at bump " + bumps[b] + ": " + bad.join("; "))
        verify(has(p, /^copy title$/) && has(p, /^open T3$/), "both actions are labelled in full")
        verify(has(p, /^waiting$/), "the time column shows 'waiting' whole")
      }
    } finally {
      Typo.bump = 0
    }
  }

  // Round 10: the working thread (03) has three actions, PR included, the widest action row; and
  // the usage-limit thread shows a reset time ("resets in 47m") in its list row, its detail and the
  // footer. At each text size and real width, nothing of either is clipped.
  function test_threeActionsAndResetTimesAreNeverClipped() {
    var working = row({ state: "working", rawStatus: "running", activeSince: now - 23 * 60000, project: "t3-loupe", branch: "main", model: "claude-opus-5-5", childCount: 3, activeChildren: 2,
      background: { subagents: 2, commands: 0, monitors: 0, other: 0 },
      pr: { number: 412, title: "x", url: "https://example.invalid/pr/412", state: "open", checks: "pending", draft: false, additions: 2140, deletions: 388, review: "" } })
    var limited = row({ key: "e:l", id: "l", title: "Bulk-translate docs to German", state: "limited", rawStatus: "failed", project: "docs", model: "gpt-6.1-sol",
      errorClass: "usage_limit", error: "Usage limit reached for this session window.", usageResetAt: now + 47 * 60000 })
    var detail = { pending: [], runs: [], context: { used: 731000, max: 1000000, cost: 12.8, currency: "USD" }, subagents: [], todo: null,
      activity: [{ icon: "terminal", label: "node --test tests/", status: "completed", at: now - 180000 }] }
    var bumps = [0, 2, 4, 6]
    try {
      for (var b = 0; b < bumps.length; b++) {
        Typo.bump = bumps[b]
        var paneWidth = Math.round((820 + 56 * bumps[b]) * 0.56) - 30
        var listWidth = Math.round((820 + 56 * bumps[b]) * 0.44) - 14
        var cases = [{ r: working, d: detail, name: "working" }, { r: limited, d: null, name: "usage limit" }]
        for (var c = 0; c < cases.length; c++) {
          var p = createTemporaryObject(paneC, tc, { row: cases[c].r, detail: cases[c].d, machineLabel: "build-box", width: paneWidth, height: 640 })
          waitForRendering(p)
          wait(20)
          var bad = clippedTexts(p, p.width - Style.space(8))
          compare(bad.length, 0, cases[c].name + " detail at bump " + bumps[b] + ": " + bad.join("; "))
          // The action row ends with clear space before the scrollbar's track (round 9 ran it right
          // up to it, which reads as cut), wrapping below the metadata when it doesn't fit.
          var copy = textItem(p, "copy title") || textItem(p, "copy")
          verify(copy !== null, cases[c].name + " at bump " + bumps[b] + ": copy action shown")
          var end = copy.mapToItem(p, copy.implicitWidth, 0).x
          verify(end <= p.width - Style.space(14) - Style.space(16) + 0.5, cases[c].name + " at bump " + bumps[b] + ": action row ends at " + Math.round(end) + ", too close to the scrollbar at " + Math.round(p.width - Style.space(14)))
          if (cases[c].r.pr) verify((textItem(p, "open PR") || textItem(p, "PR")) !== null, "three actions, PR included")
        }
        // The list row, from the list's width at this size down to a narrow one (the shell's spacing
        // scale makes the real list narrower against its text than the card's nominal width).
        for (var lw = listWidth; lw >= 260; lw -= 40) {
          var r = createTemporaryObject(rowC, tc, { row: limited, width: lw, showMachine: true, machineLabel: "build-box" })
          waitForRendering(r)
          var where = "usage-limit row " + lw + " px wide at bump " + bumps[b]
          var badRow = clippedTexts(r, r.width)
          compare(badRow.length, 0, where + ": " + badRow.join("; "))
          verify(has(r, /^resets in 47m$/), where + ": " + texts(r).join(" | "))
          // A reset time is never cut: anything that says "resets" says it with its unit.
          var times = texts(r).filter(function(t) { return /resets/.test(t) })
          for (var t = 0; t < times.length; t++) verify(/resets in \d+[smhd]$/.test(times[t]), where + ": cut reset time '" + times[t] + "'")
        }
      }
    } finally {
      Typo.bump = 0
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
