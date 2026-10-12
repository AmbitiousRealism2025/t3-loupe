// Static mock of the experimental two-pane (centered) layout, for design review only.
// Colors come from lib/Palette.js for a given Omarchy theme; icons from lib/Icons.js.
// Usage: node tools/mock-two-pane.mjs <theme-name> > docs/mocks/two-pane-<theme>.html
import { readFileSync } from "node:fs";
import { loadQmlJs } from "../tests/lib/qml-js.mjs";

const theme = process.argv[2] ?? "lumon";
const Palette = loadQmlJs(new URL("../lib/Palette.js", import.meta.url).pathname);
const Icons = loadQmlJs(new URL("../lib/Icons.js", import.meta.url).pathname);
const colorsPath = theme === "current"
  ? `${process.env.HOME}/.local/state/omarchy/current/theme/colors.toml`
  : `/usr/share/omarchy/themes/${theme}/colors.toml`;
const c = Palette.parseColorsToml(readFileSync(colorsPath, "utf8"));
const p = Palette.derive({ background: c.background, foreground: c.foreground, accent: c.accent, urgent: c.red, muted: c.muted, colors: c });

const icon = (name, color, size = 15) =>
  `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex:none">${Array.from(Icons.get(name)).map((d) => `<path d="${d}"/>`).join("")}</svg>`;
const role = { input: "attention", failed: "attention", plan: "warning", limited: "warning", working: "accent", waiting: "accent", queued: "info", background: "subagent", review: "success" };
const tone = (s) => p[role[s] ?? "idle"];
const ink = (s) => p[(role[s] ?? "idle") + "Ink"] ?? p.textDim;

// Same threads as the demo feed.
const threads = [
  { s: "input", i: "terminal", t: "Migrate auth middleware to sessions v2", m: "laptop · web-app", r: "2m 04s", l: "Run command?", a: ["message-circle", "Awaiting approval"] },
  { s: "input", i: "message-circle-question", t: "Pick a queue backend for the ingest worker", m: "build-box · ingest", r: "6m 04s", l: "Question" },
  { s: "plan", i: "notebook-pen", t: "Plan: split the monorepo build into stages", m: "laptop · infra", r: "4m ago", l: "Plan ready" },
  { s: "failed", i: "circle-x", t: "Regenerate API client from OpenAPI", m: "build-box · sdk", r: "11m ago", l: "Failed" },
  { s: "working", i: "loader-circle", t: "Design a robust T3 Loupe plugin", m: "laptop · t3-loupe", r: "23m 03s", l: "Working", a: ["square-pen", "Edit plugin/ThreadsPanel.qml"], sel: true, kids: 2 },
  { s: "working", i: "loader-circle", t: "Palette contrast tests across themes", m: "", r: "4m 03s", l: "", a: ["terminal", "node --test tests/palette.test.mjs"], child: true },
  { s: "working", i: "loader-circle", t: "Survey Omarchy shell UI kit", m: "", r: "7m 03s", l: "", a: ["search", "grep KeyboardPanel /usr/share/omarchy/shell"], child: true },
  { s: "limited", i: "gauge", t: "Bulk-translate docs to German", m: "build-box · docs", r: "resets 47m", l: "Usage limit" },
  { s: "queued", i: "hourglass", t: "Bump dependencies and re-run CI", m: "build-box · ingest", r: "1m 02s", l: "Queued" },
  { s: "review", i: "circle-check", t: "Fix flaky websocket reconnect test", m: "laptop · web-app", r: "8m ago", l: "Done" },
  { s: "working", i: "loader-circle", t: "Port notch strip tooltips", m: "laptop · omarchy", r: "2m 40s", l: "Working", a: ["eye", "Read NotchStrip.qml"] },
  { s: "working", i: "loader-circle", t: "Benchmark GLM 5.3 flash vs opus", m: "build-box · research", r: "12m 18s", l: "Working", a: ["globe", "Search: GLM-5.3 latency benchmarks"] },
  { s: "background", i: "bot", t: "Improve bot onboarding flow", m: "laptop · botmarchy", r: "9m 02s", l: "Background", a: ["bot", "Stage 0a: sandbox and dev env"] },
];

const row = (x) => `
  <div class="row ${x.sel ? "sel" : ""} ${x.child ? "child" : ""}" style="--tone:${tone(x.s)}">
    <div class="rail" style="opacity:${["idle", "stopped"].includes(x.s) ? 0.3 : 1}"></div>
    ${icon(x.i, tone(x.s), x.child ? 13 : 15)}
    <div class="rmain">
      <div class="rtitle">${x.t}</div>
      ${x.a ? `<div class="ract">${icon(x.a[0], x.a[1] === "Awaiting approval" ? p.textDim : p.accentInk, 12)}<span>${x.a[1]}</span></div>` : x.m ? `<div class="rmeta">${x.m}</div>` : ""}
    </div>
    <div class="rright"><div class="rtime">${x.r}</div>${x.l ? `<div class="rlabel" style="color:${ink(x.s)}">${x.l}</div>` : ""}</div>
  </div>`;

const activity = [
  ["eye", "Read plugin/components/ThreadCard.qml", "4m ago"],
  ["terminal", "node --test tests/", "3m ago"],
  ["bot", "Palette contrast tests across themes", "running"],
  ["brain", "Thought", "1m ago"],
  ["search", "grep -n \"idleLineKey\" plugin/lib/Store.js", "40s ago"],
  ["square-pen", "Edit plugin/ThreadsPanel.qml", "running"],
];
const runs = [5, 12, 3, 22, 9, 31, 14, 23];

const html = `<!doctype html><html><head><meta charset="utf-8"><style>
* { box-sizing: border-box; margin: 0 }
body { width: 1400px; height: 900px; background: ${Palette.mix(p.background, "#000000", 0.45)}; font: 12.5px "JetBrainsMono Nerd Font", monospace; color: ${p.text};
  display: flex; align-items: center; justify-content: center }
.card { width: 1220px; height: 820px; background: ${p.background}; border: 2px solid ${p.accent}; padding: 20px 22px; display: flex; flex-direction: column; gap: 14px }
.head { display: flex; align-items: center; gap: 14px }
.ring { width: 34px; height: 34px; border-radius: 50%; border: 4px solid ${p.track}; border-top-color: ${p.attention}; border-right-color: ${p.warning}; border-bottom-color: ${p.accent};
  display: grid; place-items: center; font-weight: 700; font-size: 12px }
.title { font-size: 18px; font-weight: 600 } .sub { color: ${p.textDim}; font-size: 11px; margin-top: 2px }
.spacer { flex: 1 } .chip { border: 1px solid ${p.line}; background: ${p.surface}; padding: 4px 9px; font-size: 11px; display: inline-flex; align-items: center; gap: 6px }
.dot { width: 7px; height: 7px; border-radius: 50% }
.bar { display: flex; gap: 2px; height: 5px } .bar div { height: 100% }
.tabs { display: flex; gap: 8px; align-items: center } .tab { border: 1px solid ${p.line}; padding: 6px 12px; font-size: 11.5px } .tab.on { background: ${p.surfaceRaised}; border-color: ${p.textFaint}; font-weight: 600 }
.search { margin-left: auto; border: 1px solid ${p.line}; padding: 6px 12px; width: 220px; color: ${p.textFaint}; font-size: 11.5px }
.panes { flex: 1; display: flex; gap: 16px; min-height: 0 }
.list { width: 44%; display: flex; flex-direction: column; gap: 3px; overflow: hidden; border-right: 1px solid ${p.line}; padding-right: 14px }
.group { color: ${p.textFaint}; font-size: 10.5px; letter-spacing: .8px; text-transform: uppercase; margin: 6px 0 2px }
.row { position: relative; display: flex; align-items: center; gap: 9px; padding: 6px 10px 6px 13px; background: ${p.surface}; min-height: 36px }
.row.child { margin-left: 22px; background: transparent; min-height: 28px; padding-top: 3px; padding-bottom: 3px }
.row.sel { background: ${p.surfaceSelected}; outline: 1px solid ${Palette.mix(p.accent, p.background, 0.4)} }
.rail { position: absolute; left: 0; top: 0; bottom: 0; width: 3px; background: var(--tone) }
.rmain { flex: 1; min-width: 0 } .rtitle { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; font-weight: 600 }
.child .rtitle { font-weight: 400; font-size: 11.5px; color: ${p.textDim} }
.rmeta, .ract { color: ${p.textFaint}; font-size: 10.5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: flex; gap: 6px; align-items: center; margin-top: 2px }
.ract span { color: ${p.textDim}; overflow: hidden; text-overflow: ellipsis }
.rright { text-align: right; font-size: 10.5px } .rtime { color: ${p.text} } .rlabel { font-weight: 600 }
.idle { display: flex; align-items: center; gap: 8px; color: ${p.textDim}; font-size: 11px; padding: 8px 6px } .idle hr { flex: 1; border: 0; border-top: 1px solid ${p.line} }
.detail { flex: 1; display: flex; flex-direction: column; gap: 14px; min-width: 0; overflow: hidden }
.dtitle { font-size: 16px; font-weight: 600; display: flex; gap: 10px; align-items: center } .dmeta { color: ${p.textFaint}; font-size: 11px }
.cap { color: ${p.textFaint}; font-size: 10px; letter-spacing: .7px; text-transform: uppercase; margin-bottom: 6px }
.act { display: flex; gap: 9px; align-items: center; padding: 3px 0; font-size: 11.5px } .act .t { flex: 1; color: ${p.textDim}; overflow: hidden; white-space: nowrap; text-overflow: ellipsis } .act.live .t { color: ${p.text} }
.act .w { color: ${p.textFaint}; font-size: 10.5px } .act.live .w { color: ${p.accentInk} }
.cols { display: grid; grid-template-columns: 1fr 1fr; gap: 22px }
.meter { height: 5px; background: ${p.track} } .meter div { height: 100% }
.runs { display: flex; gap: 3px; align-items: flex-end; height: 34px } .runs div { width: 10px }
.sub2 { display: flex; gap: 8px; align-items: center; font-size: 11.5px; padding: 3px 0 } .sub2 .t { flex: 1; overflow: hidden; white-space: nowrap; text-overflow: ellipsis }
.btn { border: 1px solid ${p.line}; padding: 6px 12px; font-size: 11.5px; display: inline-block; margin-right: 6px }
.foot { display: flex; gap: 22px; align-items: center; border-top: 1px solid ${p.line}; padding-top: 10px; font-size: 11px }
.prov { display: flex; gap: 10px; align-items: center; color: ${p.textDim} } .prov .m { width: 110px }
.keys { margin-left: auto; color: ${p.textFaint} } .keys b { color: ${p.textDim}; font-weight: 400 }
</style></head><body><div class="card">
  <div class="head">
    <div class="ring">9</div>
    <div><div class="title">T3 Loupe</div><div class="sub">4 need you · 5 working · 1 done · 2 machines</div></div>
    <div class="spacer"></div>
    <span class="chip"><span class="dot" style="background:${p.success}"></span>${icon("laptop", p.textDim, 13)} laptop <span style="color:${p.textFaint}">6 active</span></span>
    <span class="chip"><span class="dot" style="background:${p.success}"></span>${icon("server", p.textDim, 13)} build-box <span style="color:${p.attentionInk}">pairing expires in 2d</span></span>
    <span style="color:${p.textDim}">⟳ &nbsp;×</span>
  </div>
  <div class="bar"><div style="flex:3;background:${p.attention}"></div><div style="flex:2;background:${p.warning}"></div><div style="flex:5;background:${p.accent}"></div><div style="flex:1;background:${p.success}"></div><div style="flex:1;background:${p.idle}"></div></div>
  <div class="tabs"><span class="tab">Inbox 6</span><span class="tab on">Active 12</span><span class="tab">Done 2</span><span class="tab">All 13</span><span class="search">/ filter</span></div>
  <div class="panes">
    <div class="list">
      ${threads.map(row).join("")}
      <div class="idle">${icon("chevron-right", p.textDim, 13)} Idle (3) <hr></div>
    </div>
    <div class="detail">
      <div>
        <div class="dtitle">${icon("loader-circle", p.accent, 18)} Design a robust T3 Loupe plugin <span class="spacer"></span><span style="font-size:12px;color:${p.text}">23m 03s</span></div>
        <div class="dmeta" style="margin:6px 0 0 28px">laptop · t3-loupe · main · claude-opus-5-5 · full-access</div>
        <div style="margin:10px 0 0 28px;display:flex;gap:6px">
          <span class="chip" style="color:${p.subagentInk}">${icon("bot", p.subagentInk, 12)} 2 subagents running</span>
          <span class="chip" style="color:${p.successInk}">${icon("git-pull-request", p.successInk, 12)} #412 … +2140 −388</span>
          <span class="chip" style="color:${p.textDim}">${icon("gauge", p.textDim, 12)} 73% context</span>
        </div>
      </div>
      <div><div class="cap">Activity</div>
        ${activity.map(([i, t, w]) => `<div class="act ${w === "running" ? "live" : ""}">${icon(i, w === "running" ? p.accentInk : p.textFaint, 14)}<span class="t">${t}</span><span class="w">${w}</span></div>`).join("")}
      </div>
      <div><div class="cap">Plan 6 / 9</div><div class="meter"><div style="width:66%;background:${p.success}"></div></div>
        <div class="dmeta" style="margin-top:5px">Polish the panel and verify every theme</div></div>
      <div class="cols">
        <div><div class="cap">Runs</div><div class="runs">${runs.map((m, i) => `<div style="height:${Math.round(34 * Math.sqrt(m / 31))}px;background:${i === 3 ? p.attention : i === runs.length - 1 ? p.accent : p.success};opacity:${i === runs.length - 1 || i === 3 ? 1 : 0.75}"></div>`).join("")}</div>
          <div class="dmeta" style="margin-top:5px">running 23m 03s · 8 runs</div></div>
        <div><div class="cap">Context</div><div style="height:29px"></div><div class="meter"><div style="width:73%;background:${p.info}"></div></div>
          <div class="dmeta" style="margin-top:5px">731k / 1M · 73% · $12.80</div></div>
      </div>
      <div><div class="cap">Subagents</div>
        <div class="sub2">${icon("loader-circle", p.subagentInk, 13)}<span class="t">Palette contrast tests across themes — 18 of 22 themes</span><span class="dmeta">glm-5.3-flash 4m 03s</span></div>
        <div class="sub2">${icon("loader-circle", p.subagentInk, 13)}<span class="t">Survey Omarchy shell UI kit</span><span class="dmeta">gpt-6.1-sol 7m 03s</span></div>
        <div class="sub2">${icon("circle-check", p.successInk, 13)}<span class="t" style="color:${p.textDim}">Record live WebSocket frames</span><span class="dmeta">glm-5.3 4m 00s</span></div>
      </div>
      <div><span class="btn">Focus T3</span><span class="btn">Open PR</span><span class="btn">Copy title</span></div>
    </div>
  </div>
  <div class="foot">
    <span class="prov"><span class="dot" style="background:${p.success}"></span>Claude <span>Session 38%</span><span class="meter m"><div style="width:38%;background:${p.accent}"></div></span><span>Weekly 61%</span><span class="meter m"><div style="width:61%;background:${p.accent}"></div></span></span>
    <span class="prov"><span class="dot" style="background:${p.success}"></span>Codex <span style="color:${p.attentionInk}">Session 100% · 47m</span><span class="meter m"><div style="width:100%;background:${p.attention}"></div></span></span>
    <span class="keys"><b>j/k</b> select · <b>↵</b> open · <b>1–4</b> filter · <b>/</b> search · <b>f</b> toggle view · <b>esc</b> close</span>
  </div>
</div></body></html>`;
process.stdout.write(html);
