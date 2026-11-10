.pragma library

// T3 Loupe colors, derived from the active Omarchy theme.
//
// The shell exposes five base tokens (foreground, background, accent, urgent,
// muted). States need more hues than that, so the named colors of the theme's
// colors.toml (green, yellow, cyan, magenta …) are mapped to meanings. Every
// meaning has a fallback chain, is kept visibly apart from the accent, and is
// held to a contrast floor against the surface it is drawn on — on light
// themes as well as dark ones.

function clamp01(v) { return v < 0 ? 0 : v > 1 ? 1 : v }

function parse(hex) {
  if (typeof hex !== "string") return null
  var m = /^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.exec(hex.trim())
  if (!m) return null
  var h = m[1]
  if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
  return { r: parseInt(h.substr(0, 2), 16) / 255, g: parseInt(h.substr(2, 2), 16) / 255, b: parseInt(h.substr(4, 2), 16) / 255 }
}

function hex(c) {
  function part(v) { var s = Math.round(clamp01(v) * 255).toString(16); return s.length < 2 ? "0" + s : s }
  return "#" + part(c.r) + part(c.g) + part(c.b)
}

// Accepts "#rrggbb" strings or Qt color objects ({r,g,b} in 0..1).
function rgb(value) {
  if (value && typeof value === "object" && "r" in value) return { r: value.r, g: value.g, b: value.b }
  return parse(String(value))
}

function channel(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
function luminance(c) { c = rgb(c); return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b) }
function contrast(a, b) {
  var la = luminance(a), lb = luminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

// "#aarrggbb" for QML: a palette color (a "#rrggbb" string) at the given opacity.
function alpha(color, a) {
  var c = rgb(color)
  if (!c) return "#00000000"
  var h = hex(c)
  var part = Math.round(clamp01(a) * 255).toString(16)
  return "#" + (part.length < 2 ? "0" + part : part) + h.slice(1)
}

function mix(a, b, t) {
  a = rgb(a); b = rgb(b)
  return hex({ r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t })
}

// Euclidean RGB distance, 0..~1.73. Below ~0.16 two state colors read as one.
function distance(a, b) {
  a = rgb(a); b = rgb(b)
  return Math.sqrt(Math.pow(a.r - b.r, 2) + Math.pow(a.g - b.g, 2) + Math.pow(a.b - b.b, 2))
}

function isLight(background, foreground) { return luminance(background) > luminance(foreground) }

// Moves a color toward black or white (away from the background) until it
// reaches the contrast floor. Keeps hue as far as the floor allows.
function ensureContrast(color, background, floor) {
  var c = hex(rgb(color))
  if (contrast(c, background) >= floor) return c
  var target = luminance(background) > 0.18 ? "#000000" : "#ffffff"
  for (var i = 1; i <= 20; i++) {
    var next = mix(c, target, i * 0.05)
    if (contrast(next, background) >= floor) return next
  }
  return target
}

// First candidate that exists, stays away from colors already taken, and
// is not lost against the background. Falls back to the first that exists.
function pick(candidates, taken, background, minDistance) {
  var apart = minDistance || 0.18
  var first = null
  for (var i = 0; i < candidates.length; i++) {
    var c = candidates[i]
    if (!rgb(c)) continue
    if (first === null) first = c
    var clear = true
    for (var j = 0; j < taken.length; j++) if (distance(c, taken[j]) < apart) { clear = false; break }
    if (clear && contrast(c, background) >= 1.6) return c
  }
  return first
}

// Monochrome or single-hue themes have no second hue to give. Separate by
// lightness instead: step toward the foreground (more emphasis) or back
// toward the background until the color stands apart from the others.
function separate(color, others, background, foreground) {
  function clear(c) {
    for (var i = 0; i < others.length; i++) if (distance(c, others[i]) < 0.16) return false
    return contrast(c, background) >= 3.0
  }
  if (clear(color)) return color
  for (var step = 1; step <= 10; step++) {
    var up = mix(color, foreground, step * 0.1)
    if (clear(up)) return up
    var down = mix(color, background, step * 0.06)
    if (clear(down)) return down
  }
  return color
}

// Hue (0..360), saturation and lightness (0..1), for telling a red from a lavender.
function hsl(value) {
  var c = rgb(value)
  var max = Math.max(c.r, c.g, c.b), min = Math.min(c.r, c.g, c.b), l = (max + min) / 2
  if (max === min) return { h: 0, s: 0, l: l }
  var d = max - min
  var s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
  var h = max === c.r ? (c.g - c.b) / d + (c.g < c.b ? 6 : 0) : max === c.g ? (c.b - c.r) / d + 2 : (c.r - c.g) / d + 4
  return { h: h * 60, s: s, l: l }
}

function fromHsl(h, s, l) {
  function f(n) {
    var k = (n + h / 30) % 12
    var a = s * Math.min(l, 1 - l)
    return l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))
  }
  return hex({ r: f(0), g: f(8), b: f(4) })
}

// Whether a color reads as the given hue family: inside [from, to] degrees (wrapping) and saturated.
function inHue(value, from, to) {
  var c = rgb(value)
  if (!c) return false
  var x = hsl(c)
  if (x.s < 0.35 || x.l < 0.12 || x.l > 0.92) return false
  return from <= to ? x.h >= from && x.h <= to : x.h >= from || x.h <= to
}

// A theme with any real hue. Monochrome themes keep their greys: lightness separates states there.
function chromatic(colors) {
  for (var i = 0; i < colors.length; i++) {
    var c = rgb(colors[i])
    if (c && hsl(c).s >= 0.2 && hsl(c).l > 0.12 && hsl(c).l < 0.92) return true
  }
  return false
}

// The first candidate in the hue family; failing that, the theme's own color turned to that hue,
// keeping its lightness, so a theme whose "red" is lavender still gets a red that sits in its palette.
// `avoid`: colors a candidate must stay clear of (e.g. the text, so a pastel never passes for ink).
function hueRole(candidates, from, to, target, base, avoid) {
  avoid = avoid || []
  for (var i = 0; i < candidates.length; i++) {
    if (!inHue(candidates[i], from, to)) continue
    var clear = true
    for (var j = 0; j < avoid.length; j++) if (distance(candidates[i], avoid[j]) < 0.28) clear = false
    if (clear) return hex(rgb(candidates[i]))
  }
  var b = hsl(base)
  return fromHsl(target, Math.max(0.62, b.s), Math.max(0.42, Math.min(0.68, b.l)))
}

// Whether two colours read as one hue family: both saturated, and close on the colour wheel.
function hueGap(a, b) {
  var d = Math.abs(hsl(a).h - hsl(b).h) % 360
  return d > 180 ? 360 - d : d
}
function sameHue(a, b, within) {
  if (!rgb(a) || !rgb(b)) return false
  return hsl(a).s >= 0.15 && hsl(b).s >= 0.15 && hueGap(a, b) < (within || 30)
}

// The selected row: a neutral lift over the panel (the foreground at 12%) under the selection
// ring. It carries no hue of its own: with the accent mixed in, an amber theme's selection read as
// one more amber status and dulled the row's own colours. Text and marks are held to their floors
// against it, the lightest surface they sit on in a dark theme and the darkest in a light one.
var SELECTED_FILL = 0.12

// A row waiting on your answer carries a faint wash of its colour, selected or not.
// On a light surface the same share of the tone hardly shows (a 7% lavender on near-white read as
// one more grey row), so a light theme's wash is stronger. Text and marks are floored against the
// washed row either way (see derive).
var WASH = 0.07
var WASH_LIGHT = 0.12
function wash(surface, tone) { return mix(surface, tone, luminance(surface) > 0.4 ? WASH_LIGHT : WASH) }

// The detail's tinted blocks: a callout that says what a thread needs (a failure's, a plan's), and
// a pending request's card, are the state's mark at BLOCK over what is under them; calmer callouts
// (an answer with no text loaded, done, paused) at BLOCK_QUIET.
var BLOCK = 0.09
var BLOCK_QUIET = 0.05
function blockFill(under, tone, quiet) { return mix(under, tone, quiet ? BLOCK_QUIET : BLOCK) }
function tints(tone, shares, under) {
  var out = []
  for (var i = 0; i < shares.length; i++) for (var j = 0; j < under.length; j++) out.push(mix(under[j], tone, shares[i]))
  return out
}

// A waiting row's glyph breathes: its opacity eases down and back. How far down depends on the
// row it is on: to the faintest it can be and still be a 3:1 mark there, and never below
// BREATH_DEEPEST. It used to fade to 0.35 on every row, which for half of each breath left the
// icon near 1.5:1 (a still of a light theme caught it as a pale pink on lavender).
var BREATH_DEEPEST = 0.5
function breathFloor(glyph, surface) {
  if (!rgb(glyph) || !rgb(surface)) return 1
  for (var a = BREATH_DEEPEST; a < 1; a += 0.02) if (contrast(mix(surface, glyph, a), surface) >= 3.0) return Math.round(a * 100) / 100
  return 1
}

// A colour held to a contrast floor on each of several surfaces in turn.
function hold(color, surfaces, floor) {
  var c = hex(rgb(color))
  for (var i = 0; i < surfaces.length; i++) c = ensureContrast(c, surfaces[i], floor)
  return c
}

// How much colour a colour has, whatever its lightness (HSL saturation falls as a pastel is
// darkened by mixing; this does not).
function chroma(value) {
  var x = hsl(value)
  return x.s * (1 - Math.abs(2 * x.l - 1))
}

// A colour moved away from its surfaces by lightness alone, keeping its hue and at least `keep`
// chroma, until it holds every floor asked of it: checks = [[surfaces, floor], …]. For light
// themes: darkening by mixing toward black greys a pastel out, and this keeps it a colour.
function deepen(color, keep, checks) {
  var x = hsl(color)
  var want = Math.max(chroma(color), keep || 0)
  var down = luminance(checks[0][0][0]) > 0.18
  function holds(c) {
    for (var i = 0; i < checks.length; i++)
      for (var j = 0; j < checks[i][0].length; j++) if (contrast(c, checks[i][0][j]) < checks[i][1]) return false
    return true
  }
  for (var step = 0; step <= 90; step++) {
    var l = down ? x.l - step * 0.01 : x.l + step * 0.01
    if (l < 0.03 || l > 0.97) break
    var c = fromHsl(x.h, Math.min(1, want / Math.max(0.0001, 1 - Math.abs(2 * l - 1))), l)
    if (holds(c)) return c
  }
  var out = hex(rgb(color))
  for (var k = 0; k < checks.length; k++) out = hold(out, checks[k][0], checks[k][1])
  return out
}

// theme: { background, foreground, accent, urgent, muted, colors: {red, green, …} }
// background/foreground should be the surface the colors are drawn on (popup).
function derive(theme) {
  var named = theme.colors || {}
  var bg = hex(rgb(theme.background) || parse("#1e1e1e"))
  var fg = hex(rgb(theme.foreground) || parse("#e0e0e0"))
  var light = isLight(bg, fg)
  var accent = hex(rgb(theme.accent) || rgb(named.blue) || parse("#7aa2f7"))
  var urgent = hex(rgb(theme.urgent) || rgb(named.red) || parse("#f7768e"))

  var hues = [accent, urgent]
  for (var key in named) if (/^(bright_)?(red|green|yellow|blue|magenta|cyan|orange)$/.test(key)) hues.push(named[key])
  var hued = chromatic(hues)

  // Assign in priority order so the most important meanings get first choice.
  var taken = [accent]
  // Red means "needs you" in every theme with colour. A theme's "red" can be any hue (Blue Clouds'
  // is lavender, next to its foreground), so require a real red and derive one if the theme has none.
  var attention = hued ? hueRole([urgent, named.red, named.bright_red], 340, 15, 352, urgent)
    : pick([urgent, named.red, named.bright_red, named.orange, named.magenta, named.yellow], [accent], bg, 0.12) || urgent
  var attentionSource = attention
  // With hue, keep it off the text colour too; a monochrome theme separates it by lightness from the accent.
  attention = separate(ensureContrast(attention, bg, 3.0), hued ? [ensureContrast(accent, bg, 3.0), fg] : [ensureContrast(accent, bg, 3.0)], bg, fg)
  taken.push(attention)
  var success = pick([named.green, named.bright_green, named.cyan, mix(accent, fg, 0.45)], taken, bg)
  var successSource = success
  success = separate(ensureContrast(success, bg, 3.0), [ensureContrast(accent, bg, 3.0), attention], bg, fg)
  // Amber means "your turn, not urgent" (plan ready, usage limit): a real yellow or orange, as for red.
  var warning = hued ? hueRole([named.yellow, named.orange, named.bright_yellow], 22, 62, 38, named.yellow || urgent)
    : pick([named.yellow, named.orange, named.bright_yellow, mix(attention, fg, 0.4)], taken, bg)
  var warningSource = warning
  // Some themes' accent is itself amber: then plan-ready would read as working. Step it apart.
  warning = separate(ensureContrast(warning, bg, 3.0), [ensureContrast(accent, bg, 3.0), attention], bg, fg)
  // Done is a quiet state. Where the theme's "green" sits in a needs-you hue (Matte Black's is an
  // amber yellow, beside its plan amber), a done check would pass for a plan: it is drawn in ink.
  if (hued && (sameHue(success, warning, 20) || sameHue(success, attention, 20))) { success = fg; successSource = fg }
  taken.push(success)
  taken.push(warning)
  // Violet means "waiting for your answer" (an approval or a question): it needs you like a failure
  // does, but nothing is broken, so it is kept off red. A real magenta-violet, derived if the theme has none.
  // A monochrome theme has no hue to spare: there, an answer waits in the needs-you grey like the rest.
  var ask = hued ? hueRole([named.magenta, named.bright_magenta, named.purple], 268, 318, 290, named.magenta || accent, [fg, accent])
    : attention
  var askSource = ask
  if (hued) ask = separate(ensureContrast(ask, bg, 3.0), [ensureContrast(accent, bg, 3.0), attention, warning, fg], bg, fg)
  taken.push(ask)
  var subagent = pick([named.magenta, named.bright_magenta, named.blue, mix(accent, attention, 0.5)], taken, bg)
  taken.push(subagent)
  var info = pick([named.cyan, named.blue, named.bright_cyan, mix(accent, success, 0.5)], taken, bg)

  // Graphic marks (dots, rails, rings) need 3:1; text tinted with a state color needs 4.5:1.
  // Both are measured on the selected row, and on the selected row under an answer's wash (the
  // surface furthest from the panel that text sits on), so they hold wherever a row can be.
  var surface = mix(bg, fg, light ? 0.035 : 0.045)
  var selected = mix(bg, fg, SELECTED_FILL)
  // The answer mark is settled first, against its own wash too (the wash is made of it), so the
  // washed row the palette measures on is exactly the one the rows draw.
  var askMark = ensureContrast(ensureContrast(ask, bg, 3.0), selected, 3.0)
  for (var round = 0; round < 8; round++) {
    var lifted = ensureContrast(askMark, wash(selected, askMark), 3.0)
    if (lifted === askMark) break
    askMark = lifted
  }
  var selectedWash = wash(selected, askMark)
  function floor(c, ratio) { return ensureContrast(ensureContrast(ensureContrast(c, bg, ratio), selected, ratio), selectedWash, ratio) }
  function mark(c) { return floor(c, 3.0) }
  // State-tinted words keep a margin above 4.5:1 on every one of those surfaces.
  function ink(c) { return floor(c, 5.5) }

  // What a state's words and icons really sit on is more than those three: an ordinary and a washed
  // row, and the tinted blocks the detail leads with (a callout, a request card), which are the
  // state's own mark at a few percent over the panel or, in the dropdown's open card, over that
  // card's fill. Each state's colours are held on all of its own surfaces.
  var marks = { attention: mark(attention), warning: mark(warning), success: mark(success), ask: askMark }
  var sources = { attention: attentionSource, warning: warningSource, success: successSource, ask: askSource }
  var washed = wash(surface, askMark)
  var rows = [bg, surface, washed]
  var selectedRows = [selected, selectedWash]
  // An answer's row is washed, so its blocks sit on the panel or on a washed card; the others' on
  // the panel or on a plain card.
  var blocks = {
    ask: { shares: [BLOCK, BLOCK_QUIET], cards: [washed, selectedWash] },
    attention: { shares: [BLOCK], cards: [surface, selected] },
    warning: { shares: [BLOCK], cards: [surface, selected] },
    success: { shares: [BLOCK_QUIET], cards: [surface, selected] }
  }
  function onPanel(role) { return tints(marks[role], blocks[role].shares, [bg]) }
  function onCards(role) { return tints(marks[role], blocks[role].shares, blocks[role].cards) }
  // A state's words. Dark themes: the colour mixed lighter to 5.5:1 on the rows, as before, and
  // held to 4.5:1 on its blocks. Light themes: 7:1 on a row and on a block in the detail pane, 6:1
  // on a selected row (the floors plain secondary text has), reached by lowering the colour's
  // lightness at the theme colour's own chroma. Mixing a pastel toward black (Latte's pink
  // magenta) gave a dusty plum that measured 6:1 and still read as the faintest text on its
  // lavender row; the same hue kept vivid and a step darker reads with the weight of the theme's red.
  function wordsFor(role, base) {
    if (!light) return hold(hold(ink(base), onPanel(role), 4.5), onCards(role), 4.5)
    return deepen(marks[role], chroma(sources[role]), [[rows.concat(onPanel(role)), 7.0], [selectedRows, 6.0], [onCards(role), 4.5]])
  }
  // A state's line icons (a row's glyph, a calm block's icon). A thin stroke is nearer to text than
  // to a rail: in a light theme, where the light around a dark stroke thins it further, it holds
  // text's 4.5:1 on every row; in a dark theme it is the mark. Either way it holds 3:1 on the calm
  // blocks whose icon it is (a loud block's icon, a failure's or a plan's, is drawn in the ink).
  function glyphFor(role) {
    var calm = blocks[role].shares.indexOf(BLOCK_QUIET) >= 0 ? tints(marks[role], [BLOCK_QUIET], [bg].concat(blocks[role].cards)) : []
    if (!light) return hold(marks[role], rows.concat(selectedRows, calm), 3.0)
    return deepen(marks[role], chroma(sources[role]), [[rows.concat(selectedRows), 4.5], [calm, 3.0]])
  }

  var text = floor(fg, 7.0)
  // Secondary text: dim for details, faint for timestamps and metadata. Each keeps its own margin
  // on an ordinary row (7:1 and 6:1) as well as on the selected one (6:1 and 5:1), so metadata
  // stays body-text legible and the three tiers stay apart.
  var dim = floor(ensureContrast(mix(fg, bg, 0.24), surface, 7.0), 6.0)
  var faint = floor(ensureContrast(mix(fg, bg, 0.4), surface, 6.0), 5.0)
  // Selection never shares a hue with a status. The ring is the accent, unless the accent sits in
  // the hue family of a needs-you colour (an amber accent beside plan amber, a red one beside
  // failure red): then it is drawn in ink, as the shell draws its own keyboard cursor.
  var neutralRing = hued && (sameHue(accent, attention) || sameHue(accent, warning) || sameHue(accent, ask))
  var ring = neutralRing ? fg : accent

  var p = {
    light: light,
    background: bg,
    surface: surface,
    surfaceRaised: mix(bg, fg, light ? 0.07 : 0.085),
    surfaceSelected: selected,
    surfaceSelectedWash: selectedWash,
    line: mix(bg, fg, light ? 0.14 : 0.13),
    track: mix(bg, fg, light ? 0.10 : 0.11),
    text: text,
    textDim: dim,
    textFaint: faint,
    accent: mark(accent),
    accentInk: ink(accent),
    // What is running (spinners, the step and the run in progress, live activity) is drawn in ink.
    // It has no hue: a hue says "this needs you", and the accent says "this is selected".
    working: text,
    workingInk: text,
    attention: marks.attention,
    attentionInk: wordsFor("attention", attention),
    attentionGlyph: glyphFor("attention"),
    success: marks.success,
    successInk: wordsFor("success", success),
    successGlyph: glyphFor("success"),
    warning: marks.warning,
    warningInk: wordsFor("warning", warning),
    warningGlyph: glyphFor("warning"),
    info: mark(info),
    infoInk: ink(info),
    subagent: mark(subagent),
    subagentInk: ink(subagent),
    ask: askMark,
    askInk: wordsFor("ask", ask),
    askGlyph: glyphFor("ask"),
    // Graphics that carry meaning without being the value itself (meter tracks, pending plan steps,
    // past runs, control borders): 3:1 on the panel and on a raised surface, per WCAG 1.4.11.
    edge: floor(mix(fg, bg, 0.5), 3.0),
    // Scrollbars: a track a step off the panel, so it shows, and a thumb in the edge tone held to
    // 3:1 against the track as well as the panel.
    scrollTrack: mix(bg, fg, light ? 0.10 : 0.11),
    scrollThumb: ensureContrast(floor(mix(fg, bg, 0.5), 3.0), mix(bg, fg, light ? 0.10 : 0.11), 3.0),
    idle: faint,
    // Selection ring at text strength (4.5:1 on the selected fill), so in a dark theme with a muted
    // accent it is as clear as in a light one. focusNeutral: it is ink, not the accent (see `ring`).
    focus: floor(ring, 4.5),
    focusNeutral: neutralRing
  }
  return p
}

// Display state → palette role. Kept here so the bar, the panel and the tests agree.
var STATE_ROLE = {
  input: "ask",
  plan: "warning",
  failed: "attention",
  limited: "idle",
  working: "working",
  waiting: "working",
  queued: "info",
  background: "subagent",
  review: "success",
  stopped: "idle",
  idle: "idle"
}

function stateColor(palette, state) {
  var role = STATE_ROLE[state] || "idle"
  return palette[role]
}

function stateInk(palette, state) {
  var role = STATE_ROLE[state] || "idle"
  return palette[role + "Ink"] || palette.textDim
}

// Minimal TOML reader for colors.toml: `key = "#hex"` lines only.
function parseColorsToml(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^\s*([A-Za-z0-9_]+)\s*=\s*"([^"]*)"\s*(#.*)?$/.exec(lines[i])
    if (m) out[m[1]] = m[2]
  }
  return out
}
