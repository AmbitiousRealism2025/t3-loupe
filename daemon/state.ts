// The state line: one NDJSON message the shell redraws from, merged across machines and bounded.
import type { EnvironmentView } from "./connection.ts";
import { compareRows, type Counts, type Row } from "./model.ts";

export const PROTOCOL = 1;
export const MAX_LINE = 2 * 1024 * 1024;

export function summarize(views: EnvironmentView[]) {
  // One list across machines, in the same order each machine uses.
  const rows: Row[] = views.flatMap((v) => v.rows.map((r) => ({ ...r, stale: v.stale }))).sort(compareRows);
  const live = views.filter((v) => v.state === "live" || v.state === "polling");
  const counts: Counts = { active: 0, busy: 0, attention: 0, input: 0, review: 0 };
  for (const v of live) for (const k of Object.keys(counts) as (keyof Counts)[]) counts[k] += v.counts[k];
  return {
    environments: views.map(({ rows: _rows, ...rest }) => rest),
    rows,
    counts,
    known: live.length > 0,
  };
}

/**
 * Keep a state line under the cap by shedding idle subagents, then idle roots, then finished
 * threads. If that still isn't enough, keep only the highest-ranked rows: the line is always sent
 * within the cap, so the shell never has to drop it.
 */
export function fitState(state: ReturnType<typeof summarize>, maxLine = MAX_LINE): string {
  let line = JSON.stringify({ v: PROTOCOL, type: "state", at: Date.now(), ...state });
  const droppable = [(r: Row) => r.parentId !== "" && r.state === "idle", (r: Row) => r.state === "idle", (r: Row) => r.state === "review"];
  for (const drop of droppable) {
    if (line.length <= maxLine) break;
    state = { ...state, rows: state.rows.filter((r) => !drop(r)) };
    line = JSON.stringify({ v: PROTOCOL, type: "state", at: Date.now(), ...state, truncated: true });
  }
  // Rows are ranked most urgent first, so what's left to cut is the end of the list.
  for (let keep = state.rows.length; line.length > maxLine && keep > 0; ) {
    keep = Math.floor(keep / 2);
    state = { ...state, rows: state.rows.slice(0, keep) };
    line = JSON.stringify({ v: PROTOCOL, type: "state", at: Date.now(), ...state, truncated: true });
  }
  return line;
}
