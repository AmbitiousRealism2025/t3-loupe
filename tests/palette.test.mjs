import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { loadQmlJs } from "./lib/qml-js.mjs";

const Palette = loadQmlJs(new URL("../lib/Palette.js", import.meta.url).pathname);
const THEMES = "/usr/share/omarchy/themes";
const themes = existsSync(THEMES) ? readdirSync(THEMES).filter((t) => existsSync(join(THEMES, t, "colors.toml"))) : [];

function themePalette(name) {
  const colors = Palette.parseColorsToml(readFileSync(join(THEMES, name, "colors.toml"), "utf8"));
  return { colors, palette: Palette.derive({ background: colors.background, foreground: colors.foreground, accent: colors.accent, urgent: colors.red ?? colors.color1, muted: colors.muted, colors }) };
}

test("parses colors.toml key/value lines", () => {
  const c = Palette.parseColorsToml('mode = "dark"\naccent = "#f38d70" # comment\n[section]\nred="#ff0000"\n');
  assert.equal(c.accent, "#f38d70");
  assert.equal(c.red, "#ff0000");
  assert.equal(c.mode, "dark");
});

test("contrast math matches WCAG reference points", () => {
  assert.ok(Math.abs(Palette.contrast("#000000", "#ffffff") - 21) < 0.01);
  assert.equal(Palette.contrast("#777777", "#777777"), 1);
});

test("ensureContrast reaches the floor on light and dark backgrounds", () => {
  for (const bg of ["#ffffff", "#f2e9de", "#1a1b26", "#000000"]) {
    for (const c of ["#ffff00", "#00ff00", "#888888", "#ff8800"]) {
      assert.ok(Palette.contrast(Palette.ensureContrast(c, bg, 4.5), bg) >= 4.5, `${c} on ${bg}`);
    }
  }
});

test("found shipped themes", { skip: themes.length === 0 && "no Omarchy themes installed" }, () => {
  assert.ok(themes.length >= 10);
});

for (const name of themes) {
  test(`theme ${name}: contrast floors and distinct state colors`, () => {
    const { colors, palette: p } = themePalette(name);
    const bg = p.background;
    assert.equal(p.light, colors.mode === "light" || Palette.luminance(colors.background) > Palette.luminance(colors.foreground), "light detection");
    assert.ok(Palette.contrast(p.text, bg) >= 7, "text");
    assert.ok(Palette.contrast(p.textDim, bg) >= 4.5, "dim text");
    assert.ok(Palette.contrast(p.textFaint, bg) >= 3, "faint text");
    for (const role of ["accent", "attention", "success", "warning", "info", "subagent"]) {
      assert.ok(Palette.contrast(p[role], bg) >= 3, `${role} mark`);
      assert.ok(Palette.contrast(p[role + "Ink"], bg) >= 4.5, `${role} ink`);
    }
    // The three states that must never be confused at a glance.
    const key = ["attention", "accent", "success"];
    for (let i = 0; i < key.length; i++)
      for (let j = i + 1; j < key.length; j++)
        assert.ok(Palette.distance(p[key[i]], p[key[j]]) > 0.12, `${key[i]} vs ${key[j]}: ${p[key[i]]} ${p[key[j]]}`);
    for (const state of Object.keys(Palette.STATE_ROLE)) assert.match(Palette.stateColor(p, state), /^#[0-9a-f]{6}$/);
    // The selected row is the lightest surface text sits on in a dark theme (darkest in a light one).
    const sel = p.surfaceSelected;
    assert.ok(Palette.contrast(p.textDim, sel) >= 6, `dim text on the selected row: ${Palette.contrast(p.textDim, sel).toFixed(2)}`);
    assert.ok(Palette.contrast(p.textFaint, sel) >= 4.5, `faint text on the selected row: ${Palette.contrast(p.textFaint, sel).toFixed(2)}`);
    // State words keep a margin over 4.5:1, since they also sit on washes.
    for (const role of ["attention", "warning", "accent", "success", "ask"]) assert.ok(Palette.contrast(p[role + "Ink"], sel) >= 5.5, `${role} ink on the selected row: ${Palette.contrast(p[role + "Ink"], sel).toFixed(2)}`);
    assert.ok(Palette.contrast(p.focus, sel) >= 3, "selection outline on the selected fill");
    // Graphics that carry meaning (tracks, pending steps, past runs, borders) hold 3:1 wherever they sit.
    for (const surface of [bg, p.surface, sel]) assert.ok(Palette.contrast(p.edge, surface) >= 3, `edge on ${surface}: ${Palette.contrast(p.edge, surface).toFixed(2)}`);
    assert.ok(Palette.contrast(p.askInk, sel) >= 4.5, "ask ink on the selected row");
    assert.ok(Palette.contrast(p.ask, bg) >= 3, "ask mark");
    if (Palette.hsl(p.attention).s > 0.2) {
      // With hue to spare, an answer waiting is never the failure red, the working accent or the text.
      for (const other of ["attention", "accent", "text"]) assert.ok(Palette.distance(p.ask, p[other]) > 0.25, `ask vs ${other}: ${p.ask} ${p[other]}`);
    }
    // Needs-you red must not pass for routine text.
    assert.ok(Palette.distance(p.attention, p.text) > 0.16, `attention vs text: ${p.attention} ${p.text}`);
  });
}

// Blue Clouds: its "red" is lavender, beside its lavender foreground, and its "yellow" is cyan.
const BLUE_CLOUDS = { background: "#01041f", foreground: "#D6CAE3", accent: "#647dad", urgent: "#958bbb",
  colors: { red: "#958bbb", yellow: "#9dfeff", orange: "#a59cc5", green: "#83cbee", cyan: "#96dfff", blue: "#647dad", magenta: "#9ba3e5", bright_red: "#ab9eda" } };

test("a theme whose red is not red still gets a red for needs-you and an amber for plans", () => {
  const p = Palette.derive(BLUE_CLOUDS);
  const hue = (c) => Palette.hsl(c).h;
  assert.ok(hue(p.attention) >= 340 || hue(p.attention) <= 15, `attention hue ${hue(p.attention)} (${p.attention})`);
  assert.ok(hue(p.warning) >= 22 && hue(p.warning) <= 62, `warning hue ${hue(p.warning)} (${p.warning})`);
  assert.ok(Palette.contrast(p.attentionInk, p.surfaceSelected) >= 4.5);
  assert.ok(Palette.distance(p.attention, p.text) > 0.3, "far from the lavender text");
});

test("a theme with a real red keeps it", () => {
  const p = Palette.derive({ background: "#eff1f5", foreground: "#4c4f69", accent: "#1e66f5", urgent: "#d20f39", colors: { red: "#d20f39", yellow: "#df8e1d" } });
  assert.equal(p.attention, "#d20f39");
});

test("a monochrome theme stays monochrome: lightness, not hue, separates its states", () => {
  const p = Palette.derive({ background: "#000000", foreground: "#cecece", accent: "#8d8d8d", urgent: "#a4a4a4", colors: { red: "#a4a4a4", yellow: "#cecece", green: "#bbbbbb" } });
  assert.ok(Palette.hsl(p.attention).s < 0.05, `attention ${p.attention}`);
  assert.ok(Palette.distance(p.attention, p.accent) > 0.12);
});

test("survives a theme that only has the base tokens", () => {
  const p = Palette.derive({ background: "#101010", foreground: "#eeeeee", accent: "#3399ff", urgent: "#ff4455", colors: {} });
  for (const role of ["success", "warning", "info", "subagent"]) assert.match(p[role], /^#[0-9a-f]{6}$/);
});
