.pragma library

// Which notices become desktop notifications, and what they say.
//
// Notification text is not private on Omarchy: the desktop notification service passes each
// notification's summary and body to a shell command as an argument when it saves it, so
// other local accounts can read it in process listings. By default notifications therefore
// say only what kind of thing happened; the thread title, project and error stay in the
// panel. "notifications": { "details": true } opts in to the full text.

var GENERIC = {
  needs_input: "A T3 thread needs your input",
  plan_ready: "A T3 plan is ready for review",
  run_failed: "A T3 run failed",
  usage_limit: "A T3 provider hit a usage limit",
  run_completed: "A T3 run finished",
  subagents_done: "T3 subagents finished",
  pr_opened: "A T3 thread opened a pull request",
  pr_merged: "A T3 pull request was merged",
  checks_failed: "Checks failed on a T3 pull request",
  checks_passed: "Checks passed on a T3 pull request",
  session_expiring: "A T3 pairing expires soon",
  environment_offline: "A T3 machine disconnected",
  environment_restored: "A T3 machine reconnected"
}

var DEFAULTS = { attention: true, milestone: true, info: false }

function prefsOf(settings) {
  var p = settings && settings.notifications
  return p && typeof p === "object" ? p : {}
}

// Explicit kind and severity switches decide whether a notice is wanted at all; while a panel
// is open, everything but "attention" is held back unless whenPanelOpen is true.
function wanted(n, settings, panelsOpen) {
  var p = prefsOf(settings)
  if (p.enabled === false) return false
  var on
  if (p.kinds && typeof p.kinds === "object" && typeof p.kinds[n.kind] === "boolean") on = p.kinds[n.kind]
  else if (typeof p[n.severity] === "boolean") on = p[n.severity]
  else on = DEFAULTS[n.severity] === true
  if (!on) return false
  if (panelsOpen > 0 && p.whenPanelOpen !== true && n.severity !== "attention") return false
  return true
}

// { title, body } to show for a notice.
function text(n, settings) {
  if (prefsOf(settings).details === true || n.kind === "test")
    return { title: String(n.title || ""), body: String(n.body || "") }
  return { title: GENERIC[n.kind] || "T3 Loupe", body: "Open T3 Loupe for details." }
}
