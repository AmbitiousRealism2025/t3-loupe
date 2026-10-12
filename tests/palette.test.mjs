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
  });
}

test("survives a theme that only has the base tokens", () => {
  const p = Palette.derive({ background: "#101010", foreground: "#eeeeee", accent: "#3399ff", urgent: "#ff4455", colors: {} });
  for (const role of ["success", "warning", "info", "subagent"]) assert.match(p[role], /^#[0-9a-f]{6}$/);
});
