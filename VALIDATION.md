# Validation receipt — v2.0.0

Validated on 2026-10-12, on this setup:
- Omarchy 4.0.2 (Mac lineage), Quickshell 0.3.1 / Qt 6.11.2, ARM64.
- The shell runs the plugin with Node 26.10 (mise shim); tests ran on Node 24.21.
- T3 nightly `0.0.46-nightly.20261003.2623` (`fed41fa8`), orchestration protocol 2.
- Theme: Ristretto.

## Verified

**Automated tests.** `npm test` runs 51 tests, all passing:
- shell replica rules: snapshot reset, metadata-only snapshot, duplicate sequences, archive and remove;
- state classification;
- row selection and nesting;
- T3 activity-icon mapping;
- transition detection: silent before sync, dedupe, long-run milestone, PR and checks;
- thread-watch reduction, including recovering a pending command's text from its running command item;
- private config: permissions and symlinks rejected, identity-keyed relabel;
- SSH-forward selection;
- endpoint policy;
- HTTP behavior: no redirects followed (token not forwarded), auth and size classification;
- pairing-link parsing;
- view filters, grouping and search;
- formatting;
- palette contrast floors and state distinctness for **all 22 shipped themes** (5 light, 2 grayscale, several single-hue).

**Fake T3, end to end.** A fake T3 server speaks real RFC 6455 and Effect-RPC JSON. Against it, these were verified:
- every chunk is acknowledged;
- the `synchronized` marker leads to the live state;
- deltas are applied;
- a needs-input notice fires;
- busy threads get a `subscribeThread` subscription;
- after a dropped socket, the reconnect resumes with `afterSequence` and keeps rows without a fresh snapshot;
- a wrong environment identity is refused;
- a rejected token reports pairing required;
- the expiry warning fires once per day.

**Live protocol.** Real frames were recorded from the local T3. That confirmed:
- ticket authentication on `/ws`;
- Ack back-pressure;
- the snapshot → synchronized → metadata-snapshot sequence;
- `subscribeServerConfig` provider status and usage-limit windows;
- the bounded thread projection (context usage, runs, subagents).

**Live install** (Notch Strip, right flank, where v1 was).
- `omarchy plugin validate` passed.
- The service reached `live` against the local environment.
- The bar ring rendered with live counts.
- The panel opened through IPC and rendered:
  - live activity lines with T3 icons (for example, this session's own "Read …" step);
  - a Background state with a running subagent;
  - provider usage windows.
- After the fixes listed below, no QML warnings came from this plugin.
- **Demo feed:** the inbox, the expanded detail view (activity trail, runs chart, context/cost, subagents, plan progress) and the approval drawer with full command text and options were all inspected visually.
- `focus <env>:<thread>` IPC opened the panel, expanded the thread and scrolled to it.
- A desktop notification was delivered through the custom notifications service.

**v1 removal.**
- Removed from `shell.json` and the Notch Strip layout; backups were taken first.
- The installed folder, the source folder and the v1 config dir were deleted.
- A source archive is kept in `.attic/`, which is gitignored.
- The two existing read-only pairings were moved to `~/.config/t3-threads/`. `doctor` confirms scope `orchestration:read` and that they expire in 23 days.

## Fixed during validation

- Grid polish loop in the bar layout: replaced with a manual layout.
- `palette` shadowed `Item.palette`: renamed to `colors`.
- Lucide paths that start with a relative `m` lost their implicit relative line-tos: rewritten as `M x y l …`.
- Ristretto attention fell back to lavender: red is now preferred unless it is nearly the accent.
- Subagent threads showed as unread.
- Archived `thread.updated` events weren't removed from the replica.
- Subagents were double-counted.
- The "All" view repeated groups.
- Wrong RFC 6455 GUID in the test fake server.

## Not verified

- **The remote environment (reached over an SSH forward).** Its SSH forward wasn't running, so it showed the expected "No SSH tunnel" state. Remote push over a tunnel is covered only by the fake server.
- **`pair-local`, `pair-ssh` and `pair` against real servers.** These are ported from v1's validated flow but weren't re-run; the existing pairings were migrated instead.
- **Clicking a notification.** The `focus` IPC it calls was verified directly; the click itself wasn't.
- **Visual check of light themes, other themes, vertical bars, the main bar placement (`install.sh --section`), and multiple monitors.** Light-theme correctness rests on the palette tests.
- **Rendering of the `session_expiring`, `usage_limit` and `checks_failed` transitions on live data.** These were unit-tested only.
- **Behaviour across a T3 server restart or upgrade.** Session expiry and server changes are classified, but weren't exercised live.
- **The "widget not available" warning.** The Notch Strip logs it once at shell start, before the plugin registry finishes registering; the widget mounts right afterwards.

## Rename to T3 Loupe — v2.1.0 (2026-10-12)

- **New identifiers:**
  - Plugin id: `ambitiousrealism.t3-loupe`.
  - Config dir: `~/.config/t3-loupe` (pairings and settings were moved over).
  - CLI name: `t3-loupe`.
  - Notification app name: "T3 Loupe".
  - New pairings register with T3 under the label "T3 Loupe". Existing sessions keep their old label in T3 → Settings → Connections.
- **Live install migrated in place.** The id was replaced in `shell.json` and in the Notch Strip layout, so the right-flank position was kept; backups are `*.before-t3-loupe-*`. The old plugin folder was removed. After a shell restart the service reported `live`.
- **Bar.** The default display is now `label`: "T3 Loupe" left of the ring, inside the same `WidgetButton`, whose mouse area spans both. The rendered bar was inspected after the restart. The click was not physically exercised, because no pointer automation is available here; the panel opens through the same `toggle()` that the IPC `open` call verifies.
- **Tests.** The tests passed after the rename.

## Idle fold and Done tab — v2.2.0 (2026-10-12)

**New behaviour:**
- **Idle fold.** In **Active**, idle and stopped root threads (with their subagents) fold behind one **Idle (n)** line at the bottom. In **All**, there is one line at the end of each machine/project group.
  - The line is collapsed by default and keeps its state while the shell runs.
  - It toggles on click or `Enter`.
  - A text search never folds.
  - Focusing a thread from a notification unfolds the line that hides it.
- **Done tab**, placed between Active and All, with keys `1`–`4`. It lists threads whose latest run completed and that are not busy or waiting on you, newest first; this includes settled threads from the last day.

**Verified:**
- Tests: 55 passing, including new cases for folding across machines, per-group lines, search, Done order and membership, and filter order.
- Live in the Notch Strip with real data, using the Lumon theme:
  - The collapsed line showed **Idle (4)** under 2 busy threads.
  - Keyboard `j j j Enter` expanded it, with the caret rotated, the line highlighted and the four threads revealed.
  - Key `3` opened Done, showing 5 threads newest first.
  - No QML warnings came from this plugin.
- Not verified: clicking with the mouse (no pointer automation here; the click and `Enter` use the same handler), and per-group lines with live data across two machines (unit-tested only).
