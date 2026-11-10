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
    // The selected row: a neutral lift over the panel, with nothing of the accent or of any state
    // colour in it, a visible step above an ordinary row. The ring round it carries the rest.
    const sel = p.surfaceSelected;
    const ratio = (a, b) => Palette.contrast(a, b).toFixed(2);
    assert.equal(sel, Palette.mix(bg, Palette.hex(Palette.rgb(colors.foreground)), Palette.SELECTED_FILL), "the selected fill is the foreground over the panel, no hue of its own");
    assert.ok(Palette.contrast(sel, p.surface) >= 1.1, `the selected fill is a step above an ordinary row: ${ratio(sel, p.surface)}`);
    // What a selected row's text actually sits on: the selected fill, and under an answer's wash the
    // washed one. With an ordinary row, a washed row and the panel, that is every surface a row has.
    const washedSel = Palette.wash(sel, p.ask), washed = Palette.wash(p.surface, p.ask);
    assert.equal(p.surfaceSelectedWash, washedSel, "the palette's washed selected row is the one the rows draw");
    for (const [name, surface] of [["the panel", bg], ["a row", p.surface], ["a washed row", washed], ["the selected row", sel], ["the washed selected row", washedSel]]) {
      assert.ok(Palette.contrast(p.text, surface) >= 7, `text on ${name}: ${ratio(p.text, surface)}`);
      assert.ok(Palette.contrast(p.textDim, surface) >= 6, `dim text on ${name}: ${ratio(p.textDim, surface)}`);
      // Metadata (machine, time, branch) is small text: it keeps a margin over 4.5:1 even here.
      assert.ok(Palette.contrast(p.textFaint, surface) >= 5, `faint text on ${name}: ${ratio(p.textFaint, surface)}`);
      // State words keep a margin over 4.5:1 too.
      for (const role of ["attention", "warning", "accent", "success", "ask"]) assert.ok(Palette.contrast(p[role + "Ink"], surface) >= 5.5, `${role} ink on ${name}: ${ratio(p[role + "Ink"], surface)}`);
      // Graphics that carry meaning (rails, glyphs, tracks, pending steps, past runs, borders) hold 3:1.
      for (const role of ["attention", "warning", "accent", "success", "ask", "edge"]) assert.ok(Palette.contrast(p[role], surface) >= 3, `${role} mark on ${name}: ${ratio(p[role], surface)}`);
    }
    // What is running is ink, in every theme: the accent means "selected" and a hue "needs you".
    assert.equal(p.working, p.text, "working marks are the text ink");
    assert.equal(p.workingInk, p.text);
    assert.equal(Palette.stateColor(p, "working"), p.text);
    // On an ordinary row the secondary tiers keep more: 7:1 and 6:1.
    assert.ok(Palette.contrast(p.textDim, p.surface) >= 7, `dim text on a row: ${ratio(p.textDim, p.surface)}`);
    assert.ok(Palette.contrast(p.textFaint, p.surface) >= 6, `faint text on a row: ${ratio(p.textFaint, p.surface)}`);
    // The callouts and the request card in the detail pane: a state colour at 9% over the panel.
    for (const role of ["attention", "warning", "ask"]) {
      const card = Palette.mix(bg, p[role], 0.09);
      assert.ok(Palette.contrast(p[role + "Ink"], card) >= 4.5, `${role} ink on its callout: ${ratio(p[role + "Ink"], card)}`);
      assert.ok(Palette.contrast(p.textDim, card) >= 4.5, `dim text on the ${role} callout: ${ratio(p.textDim, card)}`);
    }
    // The selection ring is text-strength on its own fill and on the panel, in every theme.
    for (const surface of [bg, p.surface, sel, washedSel]) assert.ok(Palette.contrast(p.focus, surface) >= 4.5, `selection ring on ${surface}: ${ratio(p.focus, surface)}`);
    // Selection never shares a hue with a status: where the theme's accent sits in the hue family
    // of failure red, plan amber or answer violet, the ring is ink instead.
    // (Measured here on the finished colours, with a margin either side of the palette's 30°.)
    const accent = Palette.hex(Palette.rgb(colors.accent));
    const near = (within) => ["attention", "warning", "ask"].filter((role) => Palette.sameHue(accent, p[role], within));
    if (Palette.hsl(p.attention).s > 0.2) {
      if (near(22).length) assert.equal(p.focusNeutral, true, `accent ${accent} sits beside ${near(22).join(", ")}: the ring must be ink, got ${p.focus}`);
      if (!near(40).length) assert.equal(p.focusNeutral, false, `accent ${accent} is clear of every needs-you hue: the ring stays the accent, got ${p.focus}`);
    } else {
      assert.equal(p.focusNeutral, false, "a monochrome theme keeps its accent ring: lightness separates it");
    }
    if (p.focusNeutral) assert.ok(Palette.distance(p.focus, p.text) < 0.1, `a neutral ring is the text ink: ${p.focus} vs ${p.text}`);
    assert.ok(Palette.contrast(p.ask, bg) >= 3, "ask mark");
    if (Palette.hsl(p.attention).s > 0.2) {
      // With hue to spare, an answer waiting is never the failure red, the working accent or the text.
      for (const other of ["attention", "accent", "text"]) assert.ok(Palette.distance(p.ask, p[other]) > 0.25, `ask vs ${other}: ${p.ask} ${p[other]}`);
    }
    // Scrollbars: the thumb holds 3:1 against its track and the panel, and the track shows.
    assert.ok(Palette.contrast(p.scrollThumb, p.scrollTrack) >= 3, `scroll thumb on its track: ${Palette.contrast(p.scrollThumb, p.scrollTrack).toFixed(2)}`);
    assert.ok(Palette.contrast(p.scrollThumb, bg) >= 3, `scroll thumb on the panel: ${Palette.contrast(p.scrollThumb, bg).toFixed(2)}`);
    assert.ok(Palette.contrast(p.scrollTrack, bg) > 1.1, "the scroll track is visible");
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

// Matte Black: an amber accent, and a "green" that is an amber yellow. Its selection must not look
// like a plan, nor its done check.
const MATTE_BLACK = { background: "#121212", foreground: "#bebebe", accent: "#e68e0d", urgent: "#D35F5F",
  colors: { red: "#D35F5F", yellow: "#b91c1c", orange: "#c63d3d", green: "#FFC107", cyan: "#bebebe", blue: "#e68e0d", magenta: "#D35F5F", bright_magenta: "#B91C1C" } };

test("an amber-accent theme: selection, working and done are ink, amber is left to plans", () => {
  const p = Palette.derive(MATTE_BLACK);
  const grey = (c) => Palette.hsl(c).s < 0.05;
  assert.ok(grey(p.surfaceSelected), `selected fill ${p.surfaceSelected} has no hue`);
  assert.ok(grey(p.focus), `selection ring ${p.focus} is ink, not the amber accent`);
  assert.equal(p.focusNeutral, true);
  assert.ok(grey(p.success) && grey(p.successInk), `done ${p.success} is ink: the theme's green is an amber yellow`);
  // Amber is left to plans: what is working is ink too, so an orange spinner can't pass for one.
  assert.ok(grey(p.working), `working ${p.working} is ink`);
  assert.ok(Palette.hsl(p.warning).h >= 22 && Palette.hsl(p.warning).h <= 62, `plan stays amber: ${p.warning}`);
  // The accent is still the theme's, for the one place it marks: the current view's tab.
  assert.ok(Palette.sameHue(p.accent, "#e68e0d", 10), `the accent stays the theme's: ${p.accent}`);
  // With the fill neutral the state words keep their own colour: the red is a red, not a pink.
  assert.ok(Palette.hsl(p.attentionInk).s > 0.5, `failed reads as red: ${p.attentionInk}`);
});

test("a theme whose accent is clear of the needs-you hues keeps it for selection, and its green for done", () => {
  const p = Palette.derive({ background: "#eff1f5", foreground: "#4c4f69", accent: "#1e66f5", urgent: "#d20f39",
    colors: { red: "#d20f39", yellow: "#df8e1d", green: "#40a02b", magenta: "#ea76cb", blue: "#1e66f5" } });
  assert.equal(p.focusNeutral, false);
  assert.ok(Palette.sameHue(p.focus, "#1e66f5", 10), `ring ${p.focus} is the blue accent`);
  assert.ok(Palette.sameHue(p.success, "#40a02b", 15), `done ${p.success} is the theme's green`);
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
