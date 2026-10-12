.pragma library

// Pure view logic for the panel: filters, grouping, labels and icons.
// Rows arrive from the daemon already ranked and bounded.

var ATTENTION = { input: true, plan: true, failed: true }
var BUSY = { working: true, waiting: true, queued: true, background: true }
var NEEDS_YOU = { input: true, plan: true, failed: true, limited: true, review: true }

var FILTERS = ["attention", "active", "all"]

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

function isRoot(row) { return !row.parentId }

function rootMatches(row, filter) {
  if (filter === "attention") return NEEDS_YOU[row.state] === true
  if (filter === "active") return !row.settled || BUSY[row.state] === true || ATTENTION[row.state] === true || row.state === "review"
  return true
}

function textMatches(row, query) {
  if (!query) return true
  var q = query.toLowerCase()
  return (row.title + " " + row.project + " " + row.branch + " " + row.model + " " + row.provider).toLowerCase().indexOf(q) >= 0
}

// Rows for a filter, with children following their parent.
// Children appear when their parent appears and they are busy or need attention
// (or always, when the parent is expanded).
function visibleRows(rows, filter, query, expanded) {
  expanded = expanded || {}
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
  }
  var out = []
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
    out.push(root)
    for (var m = 0; m < kids.length; m++) {
      var kid = kids[m]
      if (expanded[root.key] || BUSY[kid.state] || ATTENTION[kid.state]) out.push(kid)
    }
  }
  return out
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
  }
  return "Error"
}

function environmentOk(state) { return state === "live" || state === "polling" }
