// Static mock of the proposed visual-polish direction (design review only).
// Usage: node tools/mock-polish.mjs <theme|current> [panel|bar] > file.html
import { readFileSync } from "node:fs";
import { loadQmlJs } from "../tests/lib/qml-js.mjs";

const theme = process.argv[2] ?? "current";
const what = process.argv[3] ?? "panel";
const Palette = loadQmlJs(new URL("../plugin/lib/Palette.js", import.meta.url).pathname);
const Icons = loadQmlJs(new URL("../plugin/lib/Icons.js", import.meta.url).pathname);
const path = theme === "current" ? `${process.env.HOME}/.local/state/omarchy/current/theme/colors.toml` : `/usr/share/omarchy/themes/${theme}/colors.toml`;
const c = Palette.parseColorsToml(readFileSync(path, "utf8"));
const p = Palette.derive({ background: c.background, foreground: c.foreground, accent: c.accent, urgent: c.red, muted: c.muted, colors: c });
const a = (hex, alpha) => { const n = parseInt(hex.slice(1), 16); return `rgba(${n >> 16},${(n >> 8) & 255},${n & 255},${alpha})`; };
// Omarchy shell state fills (Style.qml): normal 4%, hover 8%, selected 18% of the foreground.
const fill = { normal: a(p.text, 0.04), hover: a(p.text, 0.08), selected: a(p.text, 0.13) };
const dimInk = Palette.mix(p.text, p.background, 0.4); // PanelSectionHeader: Qt.darker(fg, 1.4)
const icon = (name, color, size = 15, sw = 2) =>
  `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" style="flex:none">${Array.from(Icons.get(name)).map((d) => `<path d="${d}"/>`).join("")}</svg>`;

// Color budget: only three states earn a hue. Everything else is ink.
const glyphColor = { input: p.attention, failed: p.attention, working: p.accent, waiting: p.accent, review: p.success };
const gc = (s) => glyphColor[s] ?? p.textDim;

const sections = [
  { name: "Needs you", rows: [
    { s: "input", i: "terminal", t: "Migrate auth middleware to sessions v2", sub: ["message-circle", "Run command? · git push --force-with-lease …"], r: "2m 04s", alarm: true },
    { s: "input", i: "message-circle-question", t: "Pick a queue backend for the ingest worker", sub: ["message-circle-question", "Question · Which queue should the ingest worker use?"], r: "6m 04s", alarm: true },
    { s: "failed", i: "circle-x", t: "Regenerate API client from OpenAPI", sub: [null, "Failed · provider error · build-box"], r: "11m", alarm: true },
    { s: "plan", i: "notebook-pen", t: "Plan: split the monorepo build into stages", sub: [null, "Plan ready · laptop · infra"], r: "4m" },
  ] },
  { name: "Working", rows: [
    { s: "working", i: "loader-circle", t: "Design a robust T3 Loupe plugin", sub: ["square-pen", "Edit plugin/ThreadsPanel.qml"], r: "23m 03s", sel: true, live: true },
    { s: "working", i: "loader-circle", t: "Palette contrast tests across themes", sub: ["terminal", "node --test tests/palette.test.mjs"], r: "4m 03s", child: true, live: true },
    { s: "working", i: "loader-circle", t: "Survey Omarchy shell UI kit", sub: ["search", "grep KeyboardPanel /usr/share/omarchy/shell"], r: "7m 03s", child: true, live: true },
    { s: "working", i: "loader-circle", t: "Benchmark GLM 5.3 flash vs opus", sub: ["globe", "Search: GLM-5.3 latency benchmarks"], r: "12m 18s", live: true },
    { s: "background", i: "bot", t: "Improve bot onboarding flow", sub: ["bot", "1 subagent · Stage 0a: sandbox and dev env"], r: "9m 02s" },
    { s: "queued", i: "hourglass", t: "Bump dependencies and re-run CI", sub: [null, "Queued · build-box · ingest"], r: "1m" },
  ] },
  { name: "Done", rows: [
    { s: "review", i: "circle-check", t: "Fix flaky websocket reconnect test", sub: ["git-pull-request", "#409 ✓ checks · 19m run"], r: "8m ago" },
    { s: "limited", i: "gauge", t: "Bulk-translate docs to German", sub: [null, "Usage limit · resets in 47m"], r: "" },
  ] },
];

const row = (x) => `
  <div class="row ${x.sel ? "sel" : ""} ${x.child ? "child" : ""}">
    ${x.sel ? `<div class="mark"></div>` : ""}
    ${icon(x.i, gc(x.s), x.child ? 13 : 15)}
    <div class="rmain">
      <div class="rtitle">${x.t}</div>
      <div class="rsub">${x.sub[0] ? icon(x.sub[0], x.live ? p.accentInk : p.textFaint, 12) : ""}<span style="${x.alarm ? `color:${p.attentionInk}` : ""}">${x.sub[1]}</span></div>
    </div>
    <div class="rtime">${x.r}</div>
  </div>`;

const runs = [5, 12, 3, 22, 9, 31, 14, 23];
const max = Math.max(...runs);

const panel = `
<div class="card">
  <div class="head">
    <div class="ring"><svg width="40" height="40" viewBox="0 0 40 40">
      <circle cx="20" cy="20" r="16" fill="none" stroke="${p.track}" stroke-width="4"/>
      <circle cx="20" cy="20" r="16" fill="none" stroke="${p.attention}" stroke-width="4" stroke-dasharray="26 100.5" stroke-dashoffset="0" transform="rotate(-90 20 20)"/>
      <circle cx="20" cy="20" r="16" fill="none" stroke="${p.text}" stroke-width="4" stroke-dasharray="40 100.5" stroke-dashoffset="-29" transform="rotate(-90 20 20)" opacity=".55"/>
      <text x="20" y="24.5" text-anchor="middle" font-size="12" font-weight="700" fill="${p.text}">12</text></svg></div>
    <div class="htext"><div class="title">T3 Loupe</div><div class="meta">4 NEED YOU · 5 WORKING · 2 MACHINES</div></div>
    <div class="spacer"></div>
    <div class="machines">
      <span><i style="background:${p.text}"></i>laptop</span>
      <span><i style="background:${p.text}"></i>build-box <em style="color:${p.attentionInk}">re-pair in 2d</em></span>
    </div>
    <span class="iconbtn">${icon("refresh-cw", p.textDim, 15)}</span><span class="iconbtn">${icon("x", p.textDim, 15)}</span>
  </div>
  <div class="tabs"><span class="tab">Inbox <b>6</b></span><span class="tab on">Active <b>12</b></span><span class="tab">Done <b>2</b></span><span class="tab">All <b>13</b></span><span class="search">${icon("search", p.textFaint, 13)} filter</span></div>
  <div class="panes">
    <div class="list">
      ${sections.map((sec) => `<div class="sechead">${sec.name.toUpperCase()} <span>${sec.rows.filter((r) => !r.child).length}</span></div>${sec.rows.map(row).join("")}`).join("")}
      <div class="sechead fold">${icon("chevron-right", dimInk, 13)} IDLE <span>3</span></div>
    </div>
    <div class="detail">
      <div class="dhead">
        <div style="flex:1;min-width:0">
          <div class="dtitle">Design a robust T3 Loupe plugin</div>
          <div class="dmeta">${icon("loader-circle", p.accent, 13)} <span style="color:${p.text}">Working 23m 03s</span> · laptop · t3-loupe · main · opus-5-5</div>
        </div>
        <span class="iconbtn" title="Focus T3">${icon("app-window", p.textDim, 15)}</span><span class="iconbtn">${icon("git-pull-request", p.textDim, 15)}</span><span class="iconbtn">${icon("copy", p.textDim, 15)}</span>
      </div>
      <div class="facts">
        <div><label>SUBAGENTS</label><b>2 running</b></div>
        <div><label>PULL REQUEST</label><b>#412 · checks pending</b><small>+2140 −388</small></div>
        <div><label>CONTEXT</label><b>731k / 1M</b><div class="meter"><div style="width:73%;background:${p.text}"></div></div></div>
        <div><label>COST</label><b>$12.80</b></div>
      </div>
      <div class="sechead">ACTIVITY</div>
      ${[["eye", "Read plugin/components/ThreadCard.qml", "4m"], ["terminal", "node --test tests/", "3m"], ["bot", "Palette contrast tests across themes", "live"], ["brain", "Thought", "1m"], ["square-pen", "Edit plugin/ThreadsPanel.qml", "live"]]
        .map(([i, t, w]) => `<div class="act ${w === "live" ? "live" : ""}">${icon(i, w === "live" ? p.accentInk : p.textFaint, 14)}<span class="t">${t}</span><span class="w">${w === "live" ? `<i style="background:${p.accent}"></i>now` : w}</span></div>`).join("")}
      <div class="two">
        <div><div class="sechead">PLAN <span>6 / 9</span></div><div class="steps">${Array.from({ length: 9 }, (_, i) => `<div style="background:${i < 6 ? p.text : i === 6 ? p.accent : p.track};opacity:${i < 6 ? 0.55 : 1}"></div>`).join("")}</div>
          <div class="dsub">Now: polish the panel and verify every theme</div></div>
        <div><div class="sechead">RUNS <span>8 · longest 31m</span></div>
          <div class="runs">${runs.map((m, i) => `<div style="height:${Math.max(2, Math.round(44 * m / max))}px;background:${i === runs.length - 1 ? p.accent : i === 3 ? p.attention : p.text};opacity:${i === runs.length - 1 || i === 3 ? 1 : 0.35}"></div>`).join("")}</div>
          <div class="dsub">current run 23m · one failed</div></div>
      </div>
      <div class="sechead">SUBAGENTS</div>
      ${[["loader-circle", p.accent, "Palette contrast tests across themes", "18 of 22 themes", "glm-5.3-flash · 4m"], ["loader-circle", p.accent, "Survey Omarchy shell UI kit", "", "gpt-6.1-sol · 7m"], ["circle-check", p.textFaint, "Record live WebSocket frames", "", "glm-5.3 · 4m"]]
        .map(([i, col, t, prog, m]) => `<div class="act">${icon(i, col, 14)}<span class="t" style="color:${col === p.textFaint ? p.textDim : p.text}">${t}${prog ? `<span style="color:${p.textFaint}"> — ${prog}</span>` : ""}</span><span class="w">${m}</span></div>`).join("")}
    </div>
  </div>
  <div class="foot">
    <span class="prov">Claude <span class="meter s"><div style="width:38%;background:${p.text}"></div></span>38% <span class="meter s"><div style="width:61%;background:${p.text}"></div></span>61%</span>
    <span class="prov">Codex <span class="meter s"><div style="width:100%;background:${p.attention}"></div></span><em style="color:${p.attentionInk}">100% · 47m</em> <span class="meter s"><div style="width:82%;background:${p.text}"></div></span>82%</span>
    <span class="keys"><b>j/k</b> select · <b>↵</b> subagents · <b>1–4</b> view · <b>/</b> filter · <b>f</b> toggle view · <b>esc</b></span>
  </div>
</div>`;

// Bar variants: current (multi-hue ring) vs monochrome ring vs attention-only.
const ringSvg = (segs, count, size = 20, th = 2.6) => {
  const r = (size - th) / 2, C = 2 * Math.PI * r, total = segs.reduce((s, x) => s + x.n, 0);
  let off = 0;
  const arcs = segs.map((x) => { const len = (x.n / total) * C - (segs.length > 1 ? 1.6 : 0); const el = `<circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${x.c}" stroke-width="${th}" stroke-dasharray="${len} ${C}" stroke-dashoffset="${-off}" transform="rotate(-90 ${size / 2} ${size / 2})" opacity="${x.o ?? 1}"/>`; off += (x.n / total) * C; return el; }).join("");
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}"><circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${p.track}" stroke-width="${th}"/>${arcs}<text x="${size / 2}" y="${size / 2 + 3.6}" text-anchor="middle" font-size="10" font-weight="700" fill="${p.text}">${count}</text></svg>`;
};
const barRow = (label, inner) => `<div class="bar"><span class="blabel">${label}</span><span class="bstrip">${inner}<span class="other">RAM 73%</span><span class="other">Main Coding</span></span></div>`;
const bars = `
<div class="bars">
  ${barRow("Now (v2.3)", `<span class="w">T3 Loupe ${ringSvg([{ n: 3, c: p.attention }, { n: 2, c: p.warning }, { n: 5, c: p.accent }, { n: 1, c: p.success }, { n: 1, c: p.idle }], 12)}<span class="badge" style="background:${p.attention}">4</span></span>`)}
  ${barRow("Proposed: monochrome, attention in color", `<span class="w">T3 Loupe ${ringSvg([{ n: 4, c: p.attention }, { n: 7, c: p.text, o: 0.75 }, { n: 1, c: p.text, o: 0.35 }], 12)}<span class="pill" style="color:${p.attentionInk};border-color:${a(p.attention, 0.6)}">4</span></span>`)}
  ${barRow("Proposed: quiet (nothing needs you)", `<span class="w">T3 Loupe ${ringSvg([{ n: 7, c: p.text, o: 0.75 }, { n: 5, c: p.text, o: 0.3 }], 12)}</span>`)}
  ${barRow("Proposed: compact (ring only)", `<span class="w">${ringSvg([{ n: 4, c: p.attention }, { n: 7, c: p.text, o: 0.75 }, { n: 1, c: p.text, o: 0.35 }], 12)}</span>`)}
</div>`;

const css = `
* { box-sizing: border-box; margin: 0 }
body { background: ${Palette.mix(p.background, "#000000", 0.45)}; font: 12.5px "JetBrainsMono Nerd Font", monospace; color: ${p.text}; display: flex; align-items: center; justify-content: center; ${what === "panel" ? "width:1400px;height:900px" : "width:900px;height:330px"} }
.card { width: 1220px; height: 830px; background: ${p.background}; border: 2px solid ${p.line}; padding: 20px 24px 16px; display: flex; flex-direction: column; gap: 16px }
.head { display: flex; align-items: center; gap: 14px }
.title { font-size: 19px; font-weight: 700 } .meta { color: ${dimInk}; font-size: 11px; font-weight: 700; letter-spacing: 1.2px; margin-top: 3px }
.spacer { flex: 1 } .machines { display: flex; gap: 16px; font-size: 11.5px; color: ${p.textDim} } .machines i { display: inline-block; width: 7px; height: 7px; border-radius: 50%; margin-right: 7px; vertical-align: 1px } .machines em { font-style: normal; margin-left: 6px }
.iconbtn { width: 28px; height: 28px; display: grid; place-items: center }
.tabs { display: flex; gap: 6px; align-items: center } .tab { padding: 6px 12px; font-size: 12px; color: ${p.textDim}; border: 1px solid ${p.line} } .tab b { font-weight: 400; color: ${p.textFaint}; margin-left: 6px } .tab.on { background: ${fill.selected}; color: ${p.text}; border-color: ${p.textFaint} } .tab.on b { color: ${p.textDim} }
.search { margin-left: auto; display: flex; gap: 8px; align-items: center; color: ${p.textFaint}; border-bottom: 1px solid ${p.line}; padding: 6px 4px; width: 200px }
.panes { flex: 1; display: flex; gap: 0; min-height: 0 }
.list { width: 43%; padding-right: 16px; border-right: 1px solid ${p.line}; overflow: hidden }
.sechead { color: ${dimInk}; font-size: 11px; font-weight: 700; letter-spacing: 1.2px; margin: 12px 0 5px 2px; display: flex; gap: 8px; align-items: center } .sechead span { color: ${p.textFaint}; font-weight: 400; letter-spacing: 0 } .list .sechead:first-child { margin-top: 2px } .fold { margin-top: 14px }
.row { position: relative; display: flex; align-items: center; gap: 10px; padding: 6px 10px; min-height: 40px }
.row:hover { background: ${fill.hover} } .row.sel { background: ${fill.selected} } .mark { position: absolute; left: 0; top: 6px; bottom: 6px; width: 2px; background: ${p.accent} }
.row.child { padding-left: 32px; min-height: 30px }
.rmain { flex: 1; min-width: 0 } .rtitle { font-size: 12.5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis } .child .rtitle { font-size: 11.5px; color: ${p.textDim} }
.rsub { display: flex; gap: 6px; align-items: center; color: ${p.textFaint}; font-size: 11px; margin-top: 2px; white-space: nowrap; overflow: hidden } .rsub span { overflow: hidden; text-overflow: ellipsis }
.rtime { color: ${p.textDim}; font-size: 11px; font-variant-numeric: tabular-nums }
.detail { flex: 1; padding-left: 22px; overflow: hidden; display: flex; flex-direction: column; gap: 4px }
.dhead { display: flex; gap: 4px; align-items: flex-start; margin-bottom: 10px } .dtitle { font-size: 16px; font-weight: 700 } .dmeta { color: ${p.textFaint}; font-size: 11.5px; margin-top: 6px; display: flex; gap: 6px; align-items: center }
.facts { display: grid; grid-template-columns: repeat(4, 1fr); gap: 1px; background: ${p.line}; border: 1px solid ${p.line}; margin-bottom: 6px }
.facts > div { background: ${p.background}; padding: 9px 12px } .facts label { display: block; color: ${dimInk}; font-size: 10px; font-weight: 700; letter-spacing: 1.1px; margin-bottom: 4px } .facts b { font-weight: 600; font-size: 12.5px } .facts small { display: block; color: ${p.textFaint}; font-size: 10.5px; margin-top: 2px }
.meter { height: 4px; background: ${a(p.text, 0.12)}; margin-top: 6px; border-radius: 2px } .meter div { height: 100%; border-radius: 2px; opacity: .7 }
.act { display: flex; gap: 10px; align-items: center; padding: 3px 0; font-size: 12px } .act .t { flex: 1; color: ${p.textDim}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis } .act.live .t { color: ${p.text} } .act .w { color: ${p.textFaint}; font-size: 11px; display: flex; gap: 6px; align-items: center } .act .w i { width: 6px; height: 6px; border-radius: 50% }
.two { display: grid; grid-template-columns: 1fr 1fr; gap: 28px; margin-top: 4px }
.steps { display: flex; gap: 3px; height: 6px } .steps div { flex: 1 } .dsub { color: ${p.textFaint}; font-size: 11px; margin-top: 7px }
.runs { display: flex; gap: 3px; align-items: flex-end; height: 44px; border-bottom: 1px solid ${p.line} } .runs div { width: 12px; border-radius: 2px 2px 0 0 }
.foot { display: flex; gap: 26px; align-items: center; border-top: 1px solid ${p.line}; padding-top: 12px; font-size: 11px; color: ${p.textDim} }
.prov { display: flex; gap: 8px; align-items: center } .prov em { font-style: normal } .meter.s { width: 70px; margin-top: 0; display: inline-block }
.keys { margin-left: auto; color: ${p.textFaint} } .keys b { color: ${p.textDim}; font-weight: 400 }
.bars { display: flex; flex-direction: column; gap: 14px } .bar { display: flex; align-items: center; gap: 18px } .blabel { width: 300px; color: ${p.textDim}; font-size: 12px; text-align: right }
.bstrip { background: ${c.background}; height: 34px; padding: 0 16px; display: flex; gap: 22px; align-items: center; font-size: 14px; color: ${p.text}; width: 520px; border: 1px solid ${p.line} }
.bstrip .w { display: flex; gap: 7px; align-items: center } .other { color: ${p.text} }
.badge { color: ${p.background}; font-weight: 700; font-size: 11px; padding: 1px 5px } .pill { border: 1px solid; font-size: 11px; font-weight: 700; padding: 0 5px; border-radius: 8px }
`;
process.stdout.write(`<!doctype html><html><head><meta charset="utf-8"><style>${css}</style></head><body>${what === "panel" ? panel : bars}</body></html>`);
