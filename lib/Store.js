.pragma library
.import "Format.js" as Format

// Pure view logic for the panel: filters, grouping, labels and icons.
// Rows arrive from the daemon already ranked and bounded.

var ATTENTION = { input: true, plan: true, failed: true }
var BUSY = { working: true, waiting: true, queued: true, background: true }
// In progress, including a run paused by a usage limit: it resumes rather than waits on you.
function isWorking(state) { return BUSY[state] === true || state === "limited" }

var FILTERS = ["attention", "active", "done", "all"]

// States that fold behind the "Idle (n)" line in Active and All.
var FOLDED = { idle: true, stopped: true }

var PENDING = {
  command: { label: "Run command?", icon: "terminal" },
  "file-read": { label: "Read file?", icon: "eye" },
  "file-change": { label: "Edit files?", icon: "square-pen" },
  "mcp-elicitation": { label: "MCP input", icon: "plug-zap" },
  permission: { label: "Permission", icon: "shield-alert" },
  dynamic_tool_call: { label: "Use tool?", icon: "hammer" },
  user_input: { label: "Question", icon: "message-circle-question" },
  auth_refresh: { label: "Re-authenticate", icon: "key-round" }
}

function pendingInfo(kind) {
  return PENDING[kind] || { label: "Needs input", icon: "message-circle" }
}

function stateLabel(row) {
  switch (row.state) {
    case "input": return pendingInfo(row.pendingKind).label
    case "plan": return "Plan ready"
    case "failed": return "Failed"
    case "limited": return "Usage limit"
    case "working": return "Working"
    case "waiting": return "Finishing"
    case "queued": return "Queued"
    case "background": return "Background"
    case "review": return "Done"
    case "stopped": return row.rawStatus === "cancelled" ? "Cancelled" : "Stopped"
  }
  return "Idle"
}

// Why a failed run failed, from T3's failure class and the provider's own message. T3 classes most
// failures as provider errors, so the message is what tells a rejected sign-in from a missing folder.
// { key, label (for the row), headline (for the detail), icon, next (what to do in T3) }
function failureCause(row) {
  var error = String(row.error || "")
  var cls = String(row.errorClass || "")
  if (row.state === "limited" || cls === "usage_limit")
    return { key: "limit", label: "usage limit", headline: "Paused by a provider usage limit", icon: "gauge",
             next: "T3 resumes it after the reset if auto-resume is on; otherwise retry it in T3" }
  if (/workspace folder no longer exists|not a directory/i.test(error))
    return { key: "folder", label: "folder missing", headline: "The thread's working folder is gone", icon: "folder",
             next: "Restore the folder at that path, then retry the thread in T3" }
  if (cls === "permission_error" || /\b40[13]\b|authenticat|unauthori[sz]ed|invalid api key|not signed in|credential/i.test(error))
    return { key: "auth", label: "sign-in rejected", headline: "The provider rejected the sign-in", icon: "key-round",
             next: "Sign in to the provider again in T3, then retry the thread" }
  if (cls === "transport_error")
    return { key: "transport", label: "connection lost", headline: "Lost the connection to the provider", icon: "plug-zap",
             next: "Retry the thread in T3 once the provider is reachable" }
  if (cls === "validation_error")
    return { key: "validation", label: "request rejected", headline: "The provider rejected the request", icon: "circle-alert",
             next: "Open the thread in T3 to see what it rejected" }
  if (cls === "provider_error")
    return { key: "provider", label: "provider error", headline: "The provider failed during the run", icon: "circle-alert",
             next: "Retry the thread in T3; if it fails again, check the provider" }
  return { key: "unknown", label: cls ? cls.replace(/_/g, " ") : "", headline: "The last run failed", icon: "circle-x",
           next: "Open the thread in T3 to see what went wrong" }
}

// What the detail pane leads with: one block naming the state, why, and the next step.
// null for states whose detail speaks for itself (working, a request with its text loaded, idle).
// { tone: palette role, icon, headline, body, raw (provider text, shown verbatim), next (or "") }
function statusCallout(row, now, hasPending) {
  if (!row || !row.state) return null
  var ran = row.lastRunMs !== null && row.lastRunMs !== undefined ? Format.duration(row.lastRunMs) : ""
  switch (row.state) {
    case "failed": {
      var cause = failureCause(row)
      return { tone: "attention", icon: cause.icon, headline: cause.headline,
               body: "Failed " + Format.ago(row.completedAt || row.updatedAt, now) + (cause.label ? " · " + cause.label : ""),
               raw: row.error || "", next: cause.next }
    }
    case "limited": {
      var limit = failureCause(row)
      return { tone: "idle", icon: limit.icon, headline: limit.headline,
               body: row.usageResetAt ? "Resets " + Format.until(row.usageResetAt, now) + " · at " + Format.clock(row.usageResetAt) : "Reset time unknown",
               raw: row.error || "", next: limit.next }
    }
    case "plan":
      return { tone: "warning", icon: "notebook-pen", headline: "A plan is waiting for your review",
               body: "Proposed " + Format.ago(row.completedAt || row.updatedAt, now) + (ran ? " after a " + ran + " run" : "") + ". The plan itself is in T3.",
               raw: "", next: "Read it in T3, then approve or revise it" }
    case "input":
      if (hasPending) return null
      return { tone: "ask", icon: pendingInfo(row.pendingKind).icon, headline: "Waiting for your answer",
               body: pendingInfo(row.pendingKind).label + (row.pendingSince ? " · waiting " + Format.duration(now - row.pendingSince) : ""),
               raw: "", next: "Answer it in T3" }
    // Background work and a queued start are routine: they read in ink, like their rows. (Their
    // tones used to come from the theme's spare hues, which on a theme whose magenta is a red
    // dressed healthy background work as a failure.)
    case "background": {
      var subs = Math.max(row.background ? row.background.subagents : 0, row.activeChildren || 0)
      var cmds = row.background ? row.background.commands + row.background.monitors + row.background.other : 0
      var parts = []
      if (subs) parts.push(subs + (subs === 1 ? " subagent" : " subagents"))
      if (cmds) parts.push(cmds + (cmds === 1 ? " task" : " tasks"))
      return { tone: "idle", icon: "bot", headline: "The reply is done; background work is still running",
               body: (parts.length ? parts.join(" and ") + " still out" : "Background tasks still out") + (row.activeSince ? " · started " + Format.ago(row.activeSince, now) : ""),
               raw: "", next: "" }
    }
    case "queued":
      return { tone: "idle", icon: "hourglass", headline: "Queued to start", body: row.activeSince ? "Queued " + Format.ago(row.activeSince, now) : "", raw: "", next: "" }
    case "review":
      return { tone: "success", icon: "circle-check", headline: "Finished, not yet opened in T3",
               body: "Done " + Format.ago(row.completedAt, now) + (ran ? " after a " + ran + " run" : ""), raw: "", next: "Review the result in T3" }
    case "stopped":
      return { tone: "idle", icon: "circle-pause", headline: row.rawStatus === "cancelled" ? "Cancelled" : "Stopped before it finished",
               body: row.completedAt ? "Stopped " + Format.ago(row.completedAt, now) : "", raw: "", next: "" }
  }
  return null
}

function stateIcon(row) {
  switch (row.state) {
    case "input": return pendingInfo(row.pendingKind).icon
    case "plan": return "notebook-pen"
    case "failed": return "circle-x"
    case "limited": return "gauge"
    case "working": return "loader-circle"
    case "waiting": return "loader-circle"
    case "queued": return "hourglass"
    case "background": return "bot"
    case "review": return "circle-check"
    case "stopped": return "circle-pause"
  }
  return "circle-dot"
}

// The choices T3 will offer for a request, as a sentence: "T3 offers: Allow once, Allow for
// session or Decline". A sentence, because Loupe shows them and cannot pick one.
function choicesSentence(options) {
  var list = []
  for (var i = 0; i < options.length; i++) list.push(String(options[i]))
  if (!list.length) return ""
  var last = list.pop()
  return "T3 offers: " + (list.length ? list.join(", ") + " or " + last : last)
}

function isRoot(row) { return !row.parentId }

// Colour budget: a hue means "this needs you", one hue per kind (violet: waiting for your answer;
// red: failed; amber: a plan to review), plus done-and-unseen. Working is the palette's "working"
// role, which is ink: the theme's accent used to mark it, and on a warm-accent theme an orange
// spinner beside an amber plan read as the same thing, while on a blue one the accent meant
// selected, current view, working and current step at once. The accent is now selection alone.
// A usage limit is a wait, not a call to act, so it reads in ink. Everything else reads through
// icon and words in ink. A count of everything that needs you (the header's, the bar badge) has
// no hue either: it is ink on an ink pill, never the colour of one kind.
var ROLE = { input: "ask", failed: "attention", plan: "warning", working: "working", waiting: "working", review: "success" }
function stateRole(state) { return ROLE[state] || "textDim" }

// The states whose words are tinted too, not just their glyph: everything that needs you.
function isAlarm(state) { return state === "input" || state === "failed" }
function inkRole(state) { return ATTENTION[state] ? ROLE[state] + "Ink" : "" }

// Things worth drawing attention to in a row: busy, blocked or rate-limited.
function isLoud(state) { return ATTENTION[state] === true || BUSY[state] === true || state === "limited" }

// Status sections for the Active list (structure carries urgency, not colour).
var SECTION_OF = { input: "needs", plan: "needs", failed: "needs", limited: "working", working: "working", waiting: "working",
  queued: "working", background: "working", review: "done" }
var SECTION_LABEL = { needs: "Needs you", working: "Working", done: "Done" }
function sectionOf(state) { return SECTION_OF[state] || "" }

// The four views. Needs you: what needs you, and only that. Active: what needs you plus what's in
// progress. Done: finished work. All: everything. The header counts the same sets (see tally).
function rootMatches(row, filter) {
  if (filter === "attention") return ATTENTION[row.state] === true
  if (filter === "active") return ATTENTION[row.state] === true || isWorking(row.state)
  if (filter === "done") return isDone(row)
  return true
}

// One count per view, plus the parts of Active, so the header, tabs and sections always agree.
function tally(rows) {
  var t = { needs: 0, working: 0, active: 0, done: 0, unread: 0, all: 0 }
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (r.parentId) continue
    t.all++
    if (ATTENTION[r.state]) t.needs++
    else if (isWorking(r.state)) t.working++
    if (isDone(r)) t.done++
    if (r.state === "review") t.unread++
  }
  t.active = t.needs + t.working
  // The rest, named as the All view's folds name them, so the header's parts add up to All:
  // stopped (interrupted or cancelled), and idle (no finished run to call done).
  t.stopped = 0
  for (var j = 0; j < rows.length; j++) if (!rows[j].parentId && rows[j].state === "stopped") t.stopped++
  t.other = t.all - t.active - t.done - t.stopped
  return t
}

function textMatches(row, query) {
  if (!query) return true
  var q = query.toLowerCase()
  return (row.title + " " + row.project + " " + row.branch + " " + row.model + " " + row.provider).toLowerCase().indexOf(q) >= 0
}

// Finished work: the latest run completed and nothing is running or waiting on you.
function isDone(row) {
  return row.rawStatus === "completed" && (row.state === "review" || row.state === "idle")
}

// Key of the idle line a root folds behind (one per view in Active, one per group in All).
function idleLineKey(row, filter) {
  return filter === "all" ? "idle:" + row.envId + "\u0000" + row.project : "idle:active"
}

// Rows for a filter, with children following their parent.
// Children appear when their parent appears and they are busy or need attention
// (or always, when the parent is expanded).
// In Active and All, idle/stopped roots fold behind an "Idle (n)" line item:
//   { kind: "idle-line", key, envId, project, parentId: "", count, open }
// The line is open when idleOpen[key] is true. A text search never folds.
function visibleRows(rows, filter, query, expanded, idleOpen) {
  expanded = expanded || {}
  idleOpen = idleOpen || {}
  var byParent = {}
  var roots = []
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (r.parentId) {
      var k = r.envId + ":" + r.parentId
      ;(byParent[k] = byParent[k] || []).push(r)
    } else {
      roots.push(r)
    }
  }
  // Grouped view: machine, then project; urgency order within a group.
  if (filter === "all") {
    var order = {}
    for (var o = 0; o < roots.length; o++) order[roots[o].key] = o
    roots.sort(function(a, b) {
      var ga = a.envId + "\u0000" + a.project, gb = b.envId + "\u0000" + b.project
      return ga < gb ? -1 : ga > gb ? 1 : order[a.key] - order[b.key]
    })
  } else if (filter === "done") {
    // Most recently finished first.
    roots.sort(function(a, b) { return (b.completedAt || 0) - (a.completedAt || 0) })
  }

  var folding = !query && (filter === "active" || filter === "all")
  // The Needs you view is all one kind; Active splits into Needs you and Working.
  var sectioned = filter === "active"
  var sectionCounts = {}
  if (sectioned) {
    for (var sc = 0; sc < roots.length; sc++) {
      var sr = roots[sc]
      if (!rootMatches(sr, filter) || (folding && FOLDED[sr.state]) || !textMatches(sr, query)) continue
      var b0 = sectionOf(sr.state)
      if (b0) sectionCounts[b0] = (sectionCounts[b0] || 0) + 1
    }
  }
  var currentSection = ""
  var out = []
  var pending = null // idle roots of the current fold: { key, envId, project, roots: [] }

  function emit(root) {
    out.push(root)
    var kids = byParent[root.key] || []
    for (var m = 0; m < kids.length; m++) {
      var kid = kids[m]
      if (expanded[root.key] || BUSY[kid.state] || ATTENTION[kid.state]) out.push(kid)
    }
  }
  function flush() {
    if (!pending || !pending.roots.length) { pending = null; return }
    var open = idleOpen[pending.key] === true
    out.push({ kind: "idle-line", key: pending.key, envId: pending.envId, project: pending.project, parentId: "",
               count: pending.roots.length, open: open, label: foldLabel(pending.roots) })
    if (open) for (var p = 0; p < pending.roots.length; p++) emit(pending.roots[p])
    pending = null
  }

  for (var j = 0; j < roots.length; j++) {
    var root = roots[j]
    var kids = byParent[root.key] || []
    var kidHit = false
    for (var c = 0; c < kids.length; c++) if (ATTENTION[kids[c].state] && filter === "attention") kidHit = true
    if (!rootMatches(root, filter) && !kidHit) continue
    if (!textMatches(root, query)) {
      var anyKid = false
      for (var q = 0; q < kids.length; q++) if (textMatches(kids[q], query)) anyKid = true
      if (!anyKid) continue
    }
    var lineKey = folding ? idleLineKey(root, filter) : ""
    if (pending && pending.key !== lineKey) flush()
    if (folding && FOLDED[root.state]) {
      if (!pending) pending = { key: lineKey, envId: root.envId, project: root.project, roots: [] }
      pending.roots.push(root)
      continue
    }
    if (sectioned) {
      var bucket = sectionOf(root.state)
      if (bucket && bucket !== currentSection && sectionCounts[bucket]) {
        out.push({ kind: "section", key: "sec:" + bucket, label: SECTION_LABEL[bucket], count: sectionCounts[bucket], parentId: "" })
        currentSection = bucket
      }
    }
    emit(root)
  }
  flush()
  return out
}

// A fold is named for what it holds, in the header's words: "Done", "Stopped", "Idle", or a mix.
function foldLabel(roots) {
  var kinds = []
  for (var i = 0; i < roots.length; i++) {
    var k = isDone(roots[i]) ? "Done" : roots[i].state === "stopped" ? "Stopped" : "Idle"
    if (kinds.indexOf(k) < 0) kinds.push(k)
  }
  var order = ["Done", "Stopped", "Idle"]
  kinds.sort(function(a, b) { return order.indexOf(a) - order.indexOf(b) })
  return kinds.length ? kinds.join(" & ") : "Idle"
}

function filterCount(rows, filter) {
  var n = 0
  for (var i = 0; i < rows.length; i++) if (isRoot(rows[i]) && rootMatches(rows[i], filter)) n++
  return n
}

// Section key for grouped ("all") view: machine, then project.
function groupKey(row, environments) {
  if (environments.length <= 1) return row.project
  var label = row.envId
  for (var i = 0; i < environments.length; i++) if (environments[i].id === row.envId) label = environments[i].label
  return label + "  ·  " + row.project
}

// Distribution of root states for the header bar: [{role, count}] in display order.
// Segments for the activity ring, one per kind. Roles resolve against a colour map that adds
// "ink" and "rest" to the palette.
function ringSegments(rows) {
  var failed = 0, ask = 0, plan = 0, busy = 0, rest = 0
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (r.parentId) continue
    if (r.state === "failed") failed++
    else if (r.state === "input") ask++
    else if (r.state === "plan") plan++
    else if (BUSY[r.state] || r.state === "limited") busy++
    else if (!r.settled || r.state === "review") rest++
  }
  // What needs you in the colour of its kind, as in the list; working in ink; the rest in the edge tone.
  return [
    { role: "attention", count: failed },
    { role: "ask", count: ask },
    { role: "warning", count: plan },
    { role: "ink", count: busy },
    { role: "rest", count: rest }
  ]
}

// Edits the panel's filter text from key presses, so the filter box needs no editable text input
// (TextField and TextInput can read the clipboard on their own, and a filter has no use for paste).
// action: "text" | "backspace" | "word" | "clear" | "enter" | "escape". `text` is the typed character(s).
// Returns { query, done, handled }: `done` hands the keys back to the panel; `handled` means the key was used.
var FILTER_MAX = 80
var CONTROL_CHARS = /[\u0000-\u001f\u007f-\u009f]/

function editFilter(query, action, text) {
  query = String(query || "")
  switch (action) {
    case "escape": return { query: "", done: true, handled: true }
    case "enter": return { query: query, done: true, handled: true }
    case "clear": return { query: "", done: false, handled: true }
    case "backspace": {
      var chars = Array.from(query)
      chars.pop()
      return { query: chars.join(""), done: false, handled: true }
    }
    case "word": return { query: query.replace(/\S+\s*$|\s+$/, ""), done: false, handled: true }
    case "text": {
      var typed = String(text || "")
      if (!typed || CONTROL_CHARS.test(typed)) break
      return { query: Array.from(query + typed).slice(0, FILTER_MAX).join(""), done: false, handled: true }
    }
  }
  return { query: query, done: false, handled: false }
}

// The four views, by the names the tabs, the header and the legend all use. What needs you has one
// name everywhere: "needs you".
var VIEW_LABEL = { attention: "Needs you", active: "Active", done: "Done", all: "All" }

// The header's count line, as parts: { text, tone, join }. tone: "needs" (full ink; its count sits
// on an ink pill), "strong", "quiet". join: the sign before the part ("+", "=") in place of
// the usual dot. With something waiting, the line spells out how the Active tab's number is made:
// "6 NEED YOU + 7 WORKING = 13 ACTIVE · 3 DONE · 1 STOPPED". sum: false drops "= 13 ACTIVE" where
// there is no room for it; the "+" still says the two add up. The parts after Active add up to All.
function headerCounts(t, sum) {
  var parts = []
  if (t.needs) {
    // The count is drawn apart from its words, on the same ink pill as the bar's badge.
    parts.push({ text: t.needs + " NEED" + (t.needs === 1 ? "S" : "") + " YOU", tone: "needs", join: "", count: t.needs, words: "NEED" + (t.needs === 1 ? "S" : "") + " YOU" })
    parts.push({ text: t.working + " WORKING", tone: "strong", join: "+" })
    if (sum !== false) parts.push({ text: t.active + " ACTIVE", tone: "quiet", join: "=" })
  } else {
    parts.push({ text: "NOTHING NEEDS YOU", tone: "quiet", join: "" })
    parts.push({ text: t.working + " WORKING", tone: "strong", join: "" })
  }
  parts.push({ text: t.done + " DONE", tone: "quiet", join: "" })
  if (t.stopped) parts.push({ text: t.stopped + " STOPPED", tone: "quiet", join: "" })
  if (t.other) parts.push({ text: t.other + " IDLE", tone: "quiet", join: "" })
  return parts
}

// The key legend: three groups by purpose, side by side, each a few columns two rows tall.
//   navigate (the list and the views)  |  act (on the selected thread)  |  window
// Columns line up across the two rows. A key that does nothing here isn't shown. The cells that
// come and go with the selection (Enter, and nothing else) sit at the foot of a column, so their
// coming and going never moves another key; `widest` is the longest thing such a cell can say, so
// its column can hold its width.
// mode: "list" (threads shown) | "empty" (no threads, but connected) | "offline" (nothing reachable).
// opts: { enter: enterVerb's answer, centered: the two-pane window, commands: how many re-pair
//         commands the offline screen offers to copy }
// Returns [{ name, columns: [[cell, …], …] }], cell = { key, verb, slot, widest }.
var ENTER_VERBS = ["subagents", "details", "unfold", "fold"]

function legendGroups(mode, opts) {
  opts = opts || {}
  var centered = opts.centered === true
  function cell(key, verb, slot, widest) { return { key: key, verb: verb, slot: slot || "", widest: widest || "" } }
  // What Enter can say in this layout: its column is as wide as the longest.
  var verbs = centered ? ["subagents", "unfold", "fold"] : ["details", "unfold", "fold"]
  var longest = verbs.reduce(function(a, b) { return b.length > a.length ? b : a }, "")
  var enter = opts.enter ? cell("↵", opts.enter, "enter", longest) : null
  var navigate = [], act = []
  if (mode === "list") {
    navigate.push([cell("j/k", "select"), cell("g", "needs you")])
    navigate.push([cell("1–4", "view"), cell("/", "filter")])
    // The two-pane window scrolls its detail with d and u; Enter sits under them.
    var last = centered ? [cell("d/u", "scroll detail")] : []
    // With nothing for Enter to do, an empty slot keeps its place, so the groups after it stay put.
    last.push(enter || cell("", "", "enter", longest))
    navigate.push(last)
    act.push([cell("o", "open T3"), cell("c", "copy title")])
  } else if (mode === "empty") {
    navigate.push([cell("1–4", "view"), cell("/", "filter")])
    act.push([cell("o", "open T3")])
  } else {
    var n = Math.min(9, opts.commands || 0)
    act.push((n > 0 ? [cell(n === 1 ? "1" : "1–" + n, "copy command")] : []).concat([cell("o", "open T3")]))
  }
  var window_ = [[cell("f", "layout"), cell("r", "refresh")], [cell("+/−", "size", "size"), cell("esc", "close")]]
  var groups = []
  if (navigate.length) groups.push({ name: "navigate", columns: navigate })
  groups.push({ name: "act", columns: act })
  groups.push({ name: "window", columns: window_ })
  return groups
}

// Every key the legend shows for a mode, in reading order: "key verb".
function legendKeys(mode, opts) {
  var out = []
  var groups = legendGroups(mode, opts)
  for (var g = 0; g < groups.length; g++)
    for (var c = 0; c < groups[g].columns.length; c++)
      for (var i = 0; i < groups[g].columns[c].length; i++)
        if (groups[g].columns[c][i].key) out.push(groups[g].columns[c][i].key + " " + groups[g].columns[c][i].verb)
  return out
}

// What Enter does on an item: unfold or fold an Idle line, show or hide a thread's subagents
// (two-pane) or its details (dropdown card). "" when it does nothing there.
function enterVerb(item, centered, expanded) {
  if (!item) return ""
  if (item.kind === "idle-line") return item.open ? "fold" : "unfold"
  if (item.kind) return ""
  if (centered) return item.childCount > 0 ? "subagents" : ""
  return "details"
}


// Where a thread runs, for the detail header: machine (when several), project, branch, model.
function metaParts(row, machineLabel) {
  var parts = []
  if (machineLabel) parts.push(machineLabel)
  if (row.project) parts.push(row.project)
  if (row.branch) parts.push(row.branch + (row.worktree ? " (worktree)" : ""))
  if (row.model) parts.push(Format.model(row.model))
  return parts
}

// What the runs chart says in words. The chart is drawn only if some run lasted a second or more;
// otherwise a row of zero-height bars would look broken, and the caption says it all.
// Failed runs are named by number, so the red bar is never the only sign.
// { chart: bool, text }
function runsSummary(runs, now) {
  runs = runs || []
  if (!runs.length) return { chart: false, text: "" }
  function length(r) { return r.durationMs !== null && r.durationMs !== undefined ? r.durationMs : (r.startedAt ? now - r.startedAt : 0) }
  var longest = 0, failed = []
  for (var i = 0; i < runs.length; i++) {
    longest = Math.max(longest, length(runs[i]))
    if (runs[i].status === "failed") failed.push(runs[i].ordinal || i + 1)
  }
  var last = runs[runs.length - 1]
  var running = last.durationMs === null || last.durationMs === undefined
  var failures = failed.length === 0 ? "" : failed.length === 1 ? "run " + failed[0] + " failed" : "runs " + failed.join(", ") + " failed"
  if (longest < 1000) {
    var only = runs.length === 1
      ? "1 run, " + (last.status === "failed" ? "failed" : running ? "started" : "finished") + " after " + Format.duration(length(last))
      : runs.length + " runs, each under a second"
    return { chart: false, text: only + (failures && !only.match(/failed/) ? "  ·  " + failures : "") }
  }
  var parts = [(running ? "current " : "last ") + Format.duration(length(last)), "longest " + Format.duration(longest)]
  if (failures) parts.push(failures)
  // One or two runs are a sentence, not a stub of a chart; the chart starts at three.
  if (runs.length === 1) return { chart: false, text: "1 run, " + (running ? "running for " : last.status === "failed" ? "failed after " : "took ") + Format.duration(length(last)) }
  if (runs.length < 3) return { chart: false, text: runs.length + " runs  ·  " + parts.join("  ·  ") }
  return { chart: true, text: parts.join("  ·  ") }
}

// An activity line that repeats the error the callout above already shows in full.
function repeatsError(activity, row) {
  if (!activity || activity.status !== "failed" || !row || !row.error) return false
  var label = String(activity.label || "").replace(/…$/, "")
  return label.length > 12 && String(row.error).indexOf(label) === 0
}

// A usage window's name, from T3's own label: its base word named for what it is ("Session" of
// 300 min → "5-hour", "Weekly" → "weekly"), and any qualifier after it kept ("Weekly · Fable" →
// "weekly · Fable"). A label Loupe doesn't know is kept as T3 wrote it; with no label, the length
// names it. compact: the short forms for the dropdown ("5h", "week").
function windowLabel(w, compact) {
  var label = String(w && w.label || "").trim()
  var mins = w && w.durationMins
  function span() {
    if (!mins) return compact ? "sess" : "session"
    if (mins === 10080) return compact ? "week" : "weekly"
    if (mins < 1440) return Math.round(mins / 60) + (compact ? "h" : "-hour")
    return Math.round(mins / 1440) + (compact ? "d" : "-day")
  }
  if (!label) return span()
  var m = /^(session|weekly|week|daily|monthly)\b(.*)$/i.exec(label)
  if (!m) return label
  var base = m[1].toLowerCase()
  var word = base === "session" ? span()
    : base === "weekly" || base === "week" ? (compact ? "week" : "weekly")
    : base === "daily" ? (compact ? "day" : "daily")
    : (compact ? "month" : "monthly")
  var rest = m[2].replace(/^[\s·:\-–—]+/, "").trim()
  return rest ? word + " · " + rest : word
}

// The labels for one provider's windows, made distinct if two would read the same.
function windowLabels(windows, compact) {
  var out = [], seen = {}
  for (var i = 0; i < windows.length; i++) {
    var label = windowLabel(windows[i], compact)
    seen[label] = (seen[label] || 0) + 1
    out.push(seen[label] > 1 ? label + " " + seen[label] : label)
  }
  return out
}

// What a window says after its meter: how much of the limit is used (the band's heading, "LIMITS
// USED", says which way the number counts, once); a spent window says "full". Nothing longer goes
// here: the value sits in a column every provider shares, and a sentence in one row's cell pushed
// every row's next window away. When a window resets is said after the row instead (usageNote).
function windowValue(w) {
  return w.usedPercent >= 100 ? "full" : Math.round(w.usedPercent) + "%"
}

// What a provider's row says after its windows: when each window that is spent or nearly spent
// (90% or more) resets, named by its kind: "5-hour resets in 47m". "" when none is that close.
// row: a usageGrid row; columns: the grid's labels.
function usageNote(row, columns, now, compact) {
  var parts = []
  for (var i = 0; i < row.cells.length; i++) {
    var w = row.cells[i] ? row.cells[i].window : null
    if (!w || !(w.usedPercent >= 90) || !w.resetsAt) continue
    var resets = Format.until(w.resetsAt, now)
    parts.push(columns[i] + " resets " + (compact ? resets.replace("in ", "") : resets))
  }
  return parts.join("  ·  ")
}

// Where that note goes: on the row's last line of windows, starting where the next column would
// (so it sits on the grid), if it fits there; otherwise on a line of its own under them.
// { line: which of the lines this row uses (0 for its first), x }
function usageNotePlace(row, lines, widths, gap, room, noteWidth) {
  var used = -1, x = 0
  for (var l = 0; l < lines.length; l++) {
    var any = false
    for (var i = 0; i < lines[l].length; i++) {
      var c = lines[l][i]
      if (!row.cells[c.column]) continue
      if (!any) { any = true; used++; x = 0 }
      x = c.x + (widths[c.column] || 0) + gap
    }
  }
  if (used < 0) return { line: 0, x: 0 }
  return x + noteWidth <= room ? { line: used, x: x } : { line: used + 1, x: 0 }
}

// The usage band as one grid: a column per kind of window (5-hour, weekly, weekly · Fable …), the
// same for every provider row, so the same kind of window sits in the same place on every row. A
// kind is its label; a provider without that kind has an empty cell there (null).
// Columns run shortest window first (a 5-hour before a weekly), then in the order first seen.
// { columns: [label], rows: [{ name, cells: [{ window, index } | null] }] }; `index` is the
// window's place in its provider's own list.
function usageGrid(providers, compact) {
  var columns = [], rows = []
  for (var p = 0; p < providers.length; p++) {
    var labels = windowLabels(providers[p].windows, compact)
    var byLabel = {}
    for (var w = 0; w < labels.length; w++) {
      var mins = providers[p].windows[w].durationMins
      var column = null
      for (var c = 0; c < columns.length; c++) if (columns[c].label === labels[w]) column = columns[c]
      if (!column) { column = { label: labels[w], mins: mins > 0 ? mins : Infinity, seen: columns.length }; columns.push(column) }
      else if (mins > 0 && mins < column.mins) column.mins = mins
      byLabel[labels[w]] = { window: providers[p].windows[w], index: w }
    }
    rows.push({ name: providers[p].name, byLabel: byLabel })
  }
  columns.sort(function(a, b) { return a.mins !== b.mins ? (a.mins < b.mins ? -1 : 1) : a.seen - b.seen })
  return {
    columns: columns.map(function(c) { return c.label }),
    rows: rows.map(function(r) { return { name: r.name, cells: columns.map(function(c) { return r.byLabel[c.label] || null }) } })
  }
}

// Where each column goes when the columns have these widths and the band has this much room: as
// many as fit on a line, the rest on the next, so a band too narrow for every column breaks at the
// same column on every provider's row and the columns still line up.
// [[{ column, x }]], one inner list per line.
function usageLines(widths, room, gap) {
  var lines = [[]], x = 0
  for (var i = 0; i < widths.length; i++) {
    var line = lines[lines.length - 1]
    if (line.length && x + widths[i] > room) { line = []; lines.push(line); x = 0 }
    line.push({ column: i, x: x })
    x += widths[i] + gap
  }
  return lines
}

// The usage band's heading. It says the numbers are the share used, not the share left.
var USAGE_HEADING = "LIMITS USED"

// Items the cursor can rest on (sections are headings, not stops).
function isStop(item) { return !!item && item.kind !== "section" }

function distribution(rows) {
  var buckets = { attention: 0, warning: 0, busy: 0, done: 0, idle: 0 }
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (r.parentId) continue
    if (r.state === "input" || r.state === "failed") buckets.attention++
    else if (r.state === "plan" || r.state === "limited") buckets.warning++
    else if (BUSY[r.state]) buckets.busy++
    else if (r.state === "review") buckets.done++
    else if (!r.settled) buckets.idle++
  }
  return [
    { role: "attention", count: buckets.attention, label: "blocked" },
    { role: "warning", count: buckets.warning, label: "to review" },
    { role: "accent", count: buckets.busy, label: "working" },
    { role: "success", count: buckets.done, label: "done" },
    { role: "idle", count: buckets.idle, label: "idle" }
  ]
}

// The one-line "what is it doing" for a row: newest running activity, else newest activity.
function currentActivity(row) {
  var list = row.activity || []
  for (var i = list.length - 1; i >= 0; i--) if (list[i].status === "running" || list[i].status === "pending") return list[i]
  return list.length ? list[list.length - 1] : null
}

function environmentLabel(state) {
  switch (state) {
    case "live": return "Live"
    case "polling": return "Polling"
    case "connecting": return "Connecting"
    case "offline": return "Offline"
    case "tunnel_missing": return "No SSH tunnel"
    case "authentication_required": return "Pairing required"
    case "expired": return "Pairing expired"
    case "unsupported": return "Unsupported T3"
    case "environment_changed": return "Server changed"
    case "listener_untrusted": return "Port owned by another user"
  }
  return "Error"
}

function environmentOk(state) { return state === "live" || state === "polling" }

function isLoopback(url) { return /^https?:\/\/(127\.0\.0\.1|localhost|\[::1\])(:|\/|$)/.test(String(url || "")) }

// The command that brings a machine back, by how it was paired and what is wrong.
// Pairing problems name the exact re-pair command; transport problems name what to start.
function repairStep(env) {
  var label = String(env.label || "")
  var named = label && /^[A-Za-z0-9_.@-]+$/.test(label) ? " --label " + label : ""
  // Pairing again the way it was paired: over SSH, locally, or with a link.
  var repair = env.sshHost ? "t3-loupe pair-ssh --ssh-host " + env.sshHost + (env.url && !isLoopback(env.url) ? " --url " + env.url : "") + named
    : !env.url || isLoopback(env.url) ? "t3-loupe pair-local" + named
    : "t3-loupe pair --url " + env.url + named
  switch (env.state) {
    case "expired":
    case "authentication_required":
      return { kind: "command", text: repair }
    case "tunnel_missing":
      return { kind: "note", text: "Start your ssh -L forward to " + (env.sshHost || label) + "; Loupe finds it within 15 s" }
    case "offline":
    case "connecting":
      return { kind: "note", text: "Start T3 on " + (label || "this machine") + "; Loupe reconnects on its own" }
    case "unsupported":
      return { kind: "note", text: "Update T3 on " + (label || "this machine") }
    case "environment_changed":
      return { kind: "command", text: repair }
  }
  return { kind: "command", text: "t3-loupe doctor" }
}

// Connection summary for the header and the disconnected state.
// { total, connected, none: true when no machine is reachable }
function connection(environments) {
  var ok = 0
  for (var i = 0; i < environments.length; i++) if (environmentOk(environments[i].state)) ok++
  return { total: environments.length, connected: ok, none: environments.length > 0 && ok === 0 }
}
