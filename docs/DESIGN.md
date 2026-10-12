# T3 Loupe — design proposal

> Historical record: the proposal that led to T3 Loupe, written when the project was called "T3 Threads v2". It was written before any code existed, so where it differs from the code, README.md and the code are authoritative. Line citations refer to T3 commit `fed41fa8` and Omarchy 4.0.2.

Status: **implemented as v2.0.0** (see README.md and VALIDATION.md) · proposal written 2026-10-12
Targets: Omarchy 4.0.2 (Mac lineage) · Quickshell 0.3.1 / Qt 6.11.2 · T3 nightly `0.0.46-nightly.20261003.2623` (`fed41fa8`), orchestration protocol 2.

---

## 1. What v1 is today

The v1 plugin (plugin id `ambitiousrealism.t3-status`, v0.1.2), installed at `~/.config/omarchy/plugins/ambitiousrealism.t3-status`. About 1,400 lines in total. Its repo has no commits.

| Part | What it does |
|---|---|
| `helper.py` (441 lines) | Python stdlib. Handles pairing, private config, HTTP polling, normalization and retry. Runs `watch` in a loop every 15 s. **Spawns a fresh `python3` worker per environment on every tick** (`helper.py:327`). |
| `Service.qml` | Runs the helper and parses one JSON line per tick. Exposes `snapshot` and an `IpcHandler`. |
| `BarWidget.qml` | Text `T3 Threads` + an outlined count pill, then `!N` / `?` suffixes. |
| `ThreadPanel.qml` (344 lines) | `KeyboardPanel` popup with cards grouped machine → project. Each row shows a title and a status badge. |
| `StatusBadge.qml` | A tinted pill for "attention" states; everything else is plain dim text. |

### Keep: v1 got these right

- **Credentials.** Read-only `orchestration:read` scope. Owner-private config written with O_NOFOLLOW / fsync. Tokens never reach QML. The pairing credential is consumed and not stored.
- **Bounded input.** Response size caps, timeouts, and the environment ID is pinned against the descriptor.
- **Stale data is honest.** The last good rows are kept and marked stale. An unknown count shows `—`, never a misleading `0`.
- **Discovering SSH tunnels without creating them.**

### Replace: why v1 feels "quick and dirty"

1. **Polling latency and churn.** Data can be up to 15 s old (60 s after a failure). Each environment costs one Python start-up per tick, even though T3 offers a push stream (see §3).
2. **Thin data.** Each row shows only title + state. No elapsed time, model, branch, PR/CI state, pending-request kind, subagents, context or cost, provider health, or rate-limit windows.
3. **Subagents are dropped entirely** (`helper.py:250`). `pendingBackgroundTasks` collapses to a boolean.
4. **Two colours.** Only `accent` and `urgent` are used, so *Waiting*, *Idle*, *Queued* and *Completed* look nearly the same. The bar never moves, so you can't tell at a glance that something is running.
5. **Brittle layout.** The panel and scroll heights are hand-computed sums (`ThreadPanel.qml:73-76, 179-180`).
6. **Identity bugs.**
   - Retry and last-good state are keyed by display **label** (`helper.py:331`), so renaming a machine or two machines with the same label collide.
   - `pair-local` hard-codes the label `"Mac"` (`helper.py:416`).
   - There is a cap of four environments.
7. **Silent expiry.** Bearer sessions last 30 days and there is no refresh token. v1 only notices when the session fails.
8. **Notch Strip has no tooltips.** Its BarShim `showTooltip` is a no-op (`notch-strip/NotchStrip.qml:326-409`), so v1's tooltip breakdown is never seen there.
9. **No action path.** You can't jump to a thread, and nothing alerts you when a thread needs input.

---

## 2. Goals for v2

- **Live.** State updates within about 1 s of the change in T3, with no polling while connected.
- **Glanceable.** The bar shows *something is running* / *something needs you* through motion and colour, not just a number.
- **Useful when opened.** The panel answers, for each thread: what state, for how long, on what model and branch, is the PR green, and is it close to the context or rate limit.
- **Theme-native.**
  - Every colour comes from the active Omarchy theme.
  - Correct in all 22 shipped themes, including the 5 light ones.
  - Re-themes live on `omarchy-theme-set`.
- **Robust.**
  - A typed state machine per environment, with a resume cursor.
  - Backoff, an HTTP fallback, and warnings before a session expires.
  - Tested against a fake T3 server and every shipped theme.
- **Read-only by default.** Write actions are a separate, explicit opt-in phase, if wanted at all.

---

## 3. What T3 can give us (verified at `fed41fa8`)

Full research notes, with file and line citations into the T3 source at commit `fed41fa8`, are summarised in Appendix A.

- **A push stream exists.**
  - Connect to `GET /ws?orchestrationProtocol=2`, authenticated with `?wsTicket=` (a 5-minute ticket from `POST /api/auth/websocket-ticket`) or a Bearer header.
  - Then call the Effect-RPC `orchestration.subscribeShell {afterSequence, requestCompletionMarker:true}` with the existing `orchestration:read` scope.
  - The server sends a snapshot, then `thread.updated` / `thread.removed` / `project.*` deltas, each with a sequence number.
  - **The client must send an `Ack` after every `Chunk`.**
  - Resume uses `afterSequence`. If the gap is over 1,000 events or 8 MiB, the server sends a fresh snapshot.
- **The shell snapshot is richer than v1 uses.**
  - Timing: `activityRunStartedAt`, `latestRun*At`.
  - Location: `branch`, `worktreePath`.
  - PRs: `pullRequests[].snapshot` (state, checks passing/failing/pending, +/-, draft).
  - Pending requests: `pendingRuntimeRequest.kind` (command, file-change, permission, user_input …).
  - Background work: `pendingBackgroundTasks[]` (subagent, command, monitor).
  - Lineage: `lineage` (fork/subagent tree).
  - Errors and limits: `lastErrorClass` (usage_limit, provider_error …), `usageLimitResetAt`.
  - Flags: `hasActionableProposedPlan`, `lastVisitedAt` (unread), `pinnedAt`, `snoozedUntil`.
- **Per-thread detail, fetched lazily.**
  - Fetch with `GET /api/orchestration/threads/:id/bounded` or `orchestration.getThreadProjection`.
  - Run history with durations and queue position.
  - Subagent status and progress.
  - Context usage (`usedTokens/maxTokens`), per-turn token usage and cost.
- **Environment-level data.**
  - `subscribeServerConfig` gives provider status (ready/warning/error) and **usage-limit windows (`usedPercent`, `resetsAt`)**.
  - `server.getUsageSummary` gives daily or hourly tokens and API-equivalent cost.
  - `scheduledTasks.subscribe` gives next and last run plus status.
- **Session expiry.** `GET /api/auth/session` returns `expiresAt`, so v2 can warn days ahead.
- **Deep-link limit.**
  - `t3code://` only **focuses** the desktop app. At this nightly it cannot open a specific thread.
  - The web route `/<environmentId>/<threadId>` works in a browser that has its own paired session.
  - v2 can therefore offer *Focus T3* and *Open in browser*, not *open this thread in the desktop app*.
- **Scope caveat (unchanged from v1).** `orchestration:read` can also read any file the server account can read. v2 must not call `projects.readFile`, `filesystem.browse` or diff RPCs.

Inference / unverified: no live WebSocket frame has been captured yet. Date encoding in WS payloads is assumed to match the HTTP shell. Phase 1 starts by recording real frames as fixtures.

---

## 4. Proposed architecture

```
┌───────────────── Omarchy shell (Quickshell) ──────────────────┐
│ Service.qml ── Process ──► t3-threadsd (Node 24, zero deps)   │
│   ▲  stdin: commands (detail <env> <thread>, refresh, …)      │
│   │  stdout: NDJSON {type:"state"|"patch"|"event"|"detail"}   │
│   ▼                                                           │
│ Store.qml (view model) ──► BarWidget.qml / Panel/*.qml        │
│ Theme.qml (extended palette)  Notifier.qml (desktop alerts)   │
└───────────────────────────────────────────────────────────────┘
      t3-threadsd: one EnvironmentConnection per paired machine
        descriptor → ws-ticket → WS subscribeShell (+serverConfig)
        Ack/Ping, resume cursor, backoff+jitter, HTTP fallback
```

### 4.1 Collector daemon: `t3-threadsd`

**Recommendation: TypeScript on the system Node 24, with no npm dependencies.**
- Node 24 runs `.ts` directly through type stripping.
- It has built-in `WebSocket` and `fetch`.
- Python's stdlib has no WebSocket client, so a Python daemon would need a hand-rolled RFC 6455 client.
- QtWebSockets isn't installed, and tokens shouldn't live in QML anyway.

**Modules:**
- `config.ts` — the private connections file. Same hardening as v1. Environments are keyed by `environmentId`, not by label.
- `pairing.ts` — port of v1 `pair`, `pair-local` and `pair-ssh`, with the hard-coded label removed.
- `connection.ts` — per-environment state machine: `idle → resolving → connecting → syncing → live ⇄ degraded(http-poll) → auth-expired | unsupported | env-changed`. Exponential backoff with jitter (1 s → 60 s). Keeps the resume cursor.
- `rpc.ts` — minimal Effect-RPC JSON framing: Request / Chunk / Ack / Exit / Ping / Interrupt.
- `reconcile.ts` — applies the snapshot and then the deltas, drops stale sequences, and treats any authoritative snapshot as a reset.
- `model.ts` — pure functions that derive the view model:
  - state classification, attention ranking, subagent tree, elapsed anchors, PR summary;
  - the same allowlist / clean / truncate discipline as v1.
- `events.ts` — detects transitions for notifications: → needs-input, → failed, long run → completed, usage-limit hit, session expiring.
- `detail.ts` — on-demand bounded projection per thread, with an LRU cache. Only fetched while the detail drawer is open.

**Output:**
- A full `state` message on change, debounced to 150 ms and capped in size.
- `event` messages for notifications.
- Elapsed times go out as **anchor timestamps**, not strings, so QML can tick clocks locally without the daemon pushing updates every second.

**Lifecycle:**
- Shell-owned, the same as v1, so it stops with the service.
- The NDJSON protocol is versioned, so the daemon can move to a systemd user unit with a Unix socket later without touching QML.

**Introspection:** a CLI with `t3-threadsd status`, `doctor` and `pair …`.
- `doctor` checks reachability, protocol version, session expiry and scope for each environment.

### 4.2 QML plugin: `ambitiousrealism.t3-threads`

The plugin kinds are `bar-widget` and `service`. A new plugin id lets v1 and v2 run side by side during the switch.

```
manifest.json
Service.qml            daemon process, restart policy, IPC (status/open/close/refresh)
Store.qml              derived counts/groups/filters; local 1 s clock for elapsed
Theme.qml              extended palette (see §5)
Notifier.qml           omarchy-notification-send wrapper, rate-limited
BarWidget.qml          + bar/ActivityGlyph.qml (Shapes/Canvas ring)
Panel/ThreadsPanel.qml KeyboardPanel host
Panel/Header.qml       totals + segmented state bar + machine chips
Panel/FilterBar.qml    ButtonGroup: Attention · Active · All · Recent
Panel/ThreadRow.qml    the card
Panel/DetailDrawer.qml runs timeline, context meter, subagents, PR
Panel/ProviderStrip.qml provider health + usage-limit gauges
Panel/EmptyState.qml   setup / offline / expiring / all-quiet
```

Layout uses anchors, `ColumnLayout` and `ListView` with `ScrollBar.vertical`, not hand-summed heights.

---

## 5. Theme and visual system

**Colours come from three layers:**

1. **Shell tokens.** `Color.popups.{background,text,border}`, `Color.accent`, `Color.urgent`, `Color.muted`, `Color.foreground`, `Color.background`. On the bar, glyphs use `bar.barForeground`, because the bar is transparent and its text colour adapts to the wallpaper.
2. **Extended semantic palette.** Parsed from the active theme's `colors.toml` (`~/.local/state/omarchy/current/theme/colors.toml`). The shell exposes only 5 base colours; this file has `green`, `yellow`, `blue`, `cyan`, `magenta`, `orange` and the rest.

   | Semantic | Source key | Fallback |
   |---|---|---|
   | `working` | accent | — |
   | `attention` | urgent / `red` | — |
   | `success` | `green` | accent mixed toward foreground |
   | `warning` | `yellow`, then `orange` | urgent mixed toward foreground |
   | `info` | `blue` / `cyan` | — |
   | `subagent` | `magenta` | — |
   | `idle` | muted | — |

   - Reload on `Color.onShellValuesChanged`; a file watch is unreliable because the theme dir is `rm -rf`'d and replaced on each switch.
   - Fallbacks are mixed from accent and urgent, so a theme missing a key still works.
3. **Contrast guard.**
   - Detect light or dark from background luminance.
   - Push each semantic colour to at least WCAG 3:1 against the popup background (4.5:1 for text). This is the fathom `Palette.js` approach.
   - A Node test loads **every** theme in `/usr/share/omarchy/themes/*/colors.toml` and asserts the contrast floors.

**Spacing, type and motion:**
- Spacing and type: only `Style.space()`, `Style.spacing.*` and `Style.font.*`.
- Corners: `Style.cornerRadius`, which is 0 on this setup, so everything renders square. The design must look intentional with square corners, not just tolerate them.
- Borders: `Border.surfaceSpec("popups","border",…)` and `BorderSurface`.
- Motion follows shell convention: 140 ms `OutCubic` for state changes, and a slow 1.6 s breathing pulse for "running".
- A `reduceMotion` widget setting turns off every looping animation.

### Bar widget

```
 ◔ 7  ●2          horizontal: activity glyph · active count · attention badge
```

The **activity glyph** is a small ring drawn with `QtQuick.Shapes`:
- Arc segments are proportional to working / queued / waiting / idle, each in its semantic colour.
- The working arc rotates slowly while any thread is running.
- The ring breathes in `attention` when something needs input.
- It is static and muted when everything is quiet.
- It shows a dashed outline when an environment is offline.

**Modes** (setting `display`): `glyph`, `glyph+count` (default), or `label` (v1-style text).

The **vertical bar** stacks the glyph and the count.

There is no tooltip dependency, since the Notch Strip can't show tooltips. Middle-click could cycle the filter or jump to the first thread that needs input.

### Panel

```
┌──────────────────────────────────────────────────────────┐
│  T3 Threads                                 ⟳ 0.4s   ×   │
│  ▓▓▓▓▓▓▓▓▓▓▓▓▒▒▒▒░░░░░░░░░░░░░░░░  2 input · 3 working   │
│  ● mac   ● remote-box   ○ build-box (offline)         │
├──────────────────────────────────────────────────────────┤
│ [Attention 2] [Active 7] [All 19] [Recent]               │
├──────────────────────────────────────────────────────────┤
│ ▌◉ Refactor auth middleware                     12m 04s  │
│ ▌  t3-code · feat/auth · opus-5.5   ⚑ Approval: command  │
│ ▌  PR #412 ✓ checks  +210 −88   ⑂ 2 subagents            │
│──────────────────────────────────────────────────────────│
│ ▌◌ Port bar widget to Shapes                     3m 51s  │
│ ▌  t3-loupe · main · sonnet-5.5   ctx ▰▰▰▰▱ 71%        │
│   └ ◌ subagent: palette contrast tests      running 40s  │
├──────────────────────────────────────────────────────────┤
│ codex   ▰▰▰▰▰▰▱▱ 5h 74%  ▰▰▱▱▱▱▱▱ wk 22%   ● ready       │
│ claude  ▰▰▱▱▱▱▱▱ 5h 18%                    ● ready       │
│ remote-box pairing expires in 3 days · ↵ details      │
└──────────────────────────────────────────────────────────┘
```

**Thread rows:**
- A left **state rail** in the semantic colour.
- An animated status dot: pulse for running, breathe for needs-input, static for idle.
- Title, then project · branch · model.
- A **live elapsed timer** that ticks from the anchor timestamp.
- Chips:
  - pending-request kind;
  - PR number with checks colour and diff stats;
  - subagent count;
  - usage-limit reset countdown when `lastErrorClass = usage_limit`;
  - an unread dot when `latestUserMessageAt > lastVisitedAt`.

**Grouping:**
- In *Attention* / *Active*, rows are sorted by urgency across all machines.
- In *All*, rows are grouped machine → project, and groups can collapse.
- Subagent children nest under their root thread.

**Detail drawer** (`Enter` / click):
- Fetched lazily.
- A last-N-runs duration sparkline.
- Context meter (`usedTokens / maxTokens`), turn tokens and API-equivalent cost.
- Subagents with progress.
- PR detail.
- Actions: *Focus T3*, *Open in browser*, *Copy thread link*.

**Provider strip.** Provider health dots and rate-limit window gauges for each environment. This is often the most useful thing at a glance.

**Keyboard:**
- `j/k` move.
- `Enter` expands.
- `1-4` switch filters, since Tab is reserved for switching to the neighbouring panel.
- `/` filters by text.
- `g` jumps to the first thread needing attention.
- `Esc` closes.
- `CursorSurface` gives keyboard and mouse a shared highlight; `PointerMoveGate` suppresses phantom hover.

**States designed explicitly:**
- First-run setup, with pairing instructions.
- Connecting (skeleton rows).
- Partially offline (machine chip hollow, its rows dimmed and labelled with how old they are).
- Session expiring or expired.
- Unsupported T3 version.
- All quiet (a calm empty state, not a blank card).

---

## 6. Notifications (opt-in, per kind)

The daemon emits `event`s and `Notifier.qml` sends them with `omarchy-notification-send` (delivered by your `ambitiousrealism.notifications` service).

| Event | Default |
|---|---|
| Thread → needs input (approval / question) | on |
| Run failed (with error class) | on |
| Long run (> N min) completed | on |
| Usage limit hit, with reset time | on |
| Session expiring in ≤ 3 days | on |
| Environment offline for more than 5 min | off |

- Coalesced and rate-limited (one per thread per kind per 2 min).
- Suppressed while the panel is open.
- Nothing fires on start-up or replay before the `synchronized` marker.

---

## 7. Optional later phase: act from the panel

All of these need **`orchestration:operate`**, a much wider scope that also allows sending messages.

- Approve or decline (`runtime-request.respond`).
- Interrupt (`run.interrupt`).
- Settle / snooze / mark read.

If wanted, this would be:
- a separate, explicit pairing per environment, labelled "T3 Threads (operate)";
- a separate daemon code path behind a setting that is off by default;
- every action behind a `ConfirmDialog`.

**Recommendation: ship v2 read-only and decide after living with it.**

---

## 8. Quality and testing

- **Daemon** (`node --test`):
  - A **fake T3 server** that speaks descriptor, ws-ticket, `/ws` Effect-RPC (including Ack back-pressure, resume, gap → snapshot reset, `synchronized`), 401/426, oversize payloads and redirects.
  - Reconciliation and model-derivation unit tests.
  - Port v1's 11 hardening tests (private file, symlink rejection, bounds).
- **Recorded fixtures.** Capture real frames from both of your environments once, scrubbed of titles and paths, and replay them in tests and in a `--demo` mode.
- **QML.** Offscreen `qmltestrunner` with stub `qs.Commons` / `qs.Ui` modules (fathom pattern) for Store logic and component contracts. `qmllint` clean.
- **Theme.** Contrast assertions across all shipped themes. A screenshot script renders the panel in `--demo` under five representative themes (dark, light, high-saturation …) for visual review.
- **Validation.** `omarchy plugin validate`, plus a VALIDATION.md receipt like v1's, recording what was and wasn't exercised live.

---

## 9. Phased plan

| Phase | Deliverable | Exit check |
|---|---|---|
| 0 | Scaffold, fake T3 server, capture real WS frames → fixtures | Fixture replay prints a reconciled model |
| 1 | `t3-threadsd`: config/pairing port, WS shell subscription, reconcile, HTTP fallback, `doctor` | Live with both environments; kill/restart server → resumes without full reload |
| 2 | `Theme.qml` + contrast tests; bar widget with activity glyph | Correct in all 22 themes; reduce-motion works; vertical bar |
| 3 | Panel: header, filters, thread rows, grouping, keyboard nav, empty/error states | Demo + live visual review |
| 4 | Detail drawer, provider/usage-limit strip, session-expiry warnings | Lazy fetch only while open; cache bounded |
| 5 | Notifications | No storm on start-up/replay; rate limits hold |
| 6 | Install alongside v1 → swap in Notch Strip layout → retire v1 | v1 entries removed cleanly; v1 sessions revoked or imported |
| 7 (optional) | Operate actions | Separate scope, confirm dialogs |

**Migration.** v2 can import v1's `connections.json`; its sessions are already read-only. Entries are re-keyed by `environmentId` and get a `doctor` check. Alternatively, re-pair from scratch.

---

## 10. Decisions (answered 2026-10-12)

Node 24+ TypeScript daemon · read-only first · notifications on (milestones and attention) · Notch Strip right flank for the author, any bar section for everyone else · approval and question text shown · v1 removed immediately.

The original questions:

1. **Daemon runtime.** Node 24 TypeScript with no npm dependencies (recommended), or stay on Python stdlib with a hand-rolled WebSocket client.
2. **Scope.** Read-only forever, or plan for the opt-in operate phase (§7).
3. **Notifications.** Want them, and which defaults.
4. **Placement.** Notch Strip only, the main (bottom, transparent) bar, or both.
5. **Privacy level.** v1 never showed message or prompt bodies. Should the detail drawer show the approval prompt text (for example the command awaiting approval), or only its kind?
6. **Plugin identity.** New id `ambitiousrealism.t3-threads` running side by side with v1 (recommended), or replace in place.

---

## Appendix A — evidence index

**T3 source** (commit `fed41fa8`):
- Shell snapshot and thread shape: `packages/contracts/src/orchestrationV2.ts` 1684-1784.
- Stream items: 1786-1822.
- `subscribeThread`: 3006-3137.
- Commands: 2437-2769.
- WS endpoint, auth and resume: `apps/server/src/ws.ts` 453-457, 840-1075, 3727-3777.
- Ticket auth: `apps/server/src/auth/EnvironmentAuth.ts` 515-597, 1075-1095.
- Ack requirement: `.repos/effect-smol/.../rpc/RpcServer.ts` 402-427.
- Scope map: `apps/server/src/auth/RpcAuthorization.ts` 24-201.
- Session lifetime: `apps/server/src/auth/SessionStore.ts` 423-424.
- Usage limits and provider status: `packages/contracts/src/server.ts` 211-290, 604-668; `providerUsageLimits.ts` 18-75.
- Token usage and cost: `packages/contracts/src/providerRuntime.ts` 263-352.
- Deep links: `apps/desktop/src/app/DesktopClerk.ts` 141-197, `ElectronProtocol.ts` 15-28.

**Omarchy shell** (`/usr/share/omarchy/shell`):
- Colour tokens and theme apply: `Commons/Color.qml` 19-23, 73-165, 204-253.
- Style tokens: `Commons/Style.qml` 31-32, 70-199, 213-355.
- KeyboardPanel: `Ui/KeyboardPanel.qml` 37-418.
- Plugin registry: `services/PluginRegistry.qml` 43-91.
- Service and host injection: `shell.qml` 275-309, 586-654.
- Theme IPC: `/usr/bin/omarchy-theme-set` 292-308.

**Pattern references:**
- `~/.config/omarchy/plugins/io.github.mtolhuys.fathom` (`src/Palette.js`, `tests/qml/`).
- `stappmus.activity-monitor/Sparkline.qml`.
- `davies-sam.omatheme/Ui/Theme.qml` (colors.toml parsing).
