# Validation receipts — v2.0.0 to v2.5.0

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

## Two-pane window — v2.3.0 (2026-10-12)

**New:**
- **`presentation` setting**, with `centered` as the new default and `dropdown` as the alternative. It can be set in `settings.json` or as a widget setting, and `f` switches it for the session.
- **Centered window:**
  - a layer-shell overlay (`t3-loupe` namespace) with a dimmed backdrop and an 820px card up to 84% of the screen height;
  - a fade and scale on open and close;
  - exclusive keyboard focus while open;
  - closes on a backdrop click or `Esc`, and claims the bar's shared popup slot so other bar panels close it.
- **Two-pane layout:**
  - a 44% compact list on the left;
  - `ThreadDetailPane` on the right, showing the selected thread (title, meta, chips, pending request, activity, plan, runs, context, subagents, actions);
  - the selection follows the cursor, and detail is requested after a 150 ms debounce;
  - the first thread is selected when the panel opens or the filter changes.
- **Key hints** wrap between hints, and `f toggle view` was added.

**Fixed:**
- A thread whose only chip was its PR never showed that chip.
- Chip-row visibility depended on its own children, which made it circular.
- The detail pane's position was a binding loop.
- An undefined `row.error` caused a warning.

**Verified:**
- The tests pass.
- Live in the Notch Strip with real data (Lumon theme): the centered window opened over T3, and the detail of the current thread updated live (activity, 12-run chart, context 502k/1M).
- Demo feed: Inbox with the command approval and options in the right pane; `j` moved the selection and the pane followed (activity, plan, runs, context, subagents, PR chip); `f` switched to the dropdown and back.
- No QML warnings came from this plugin.

**Not verified:**
- Multiple monitors.
- The centered window on the main bar rather than the Notch Strip.
- Mouse clicks: list clicks and `j`/`k` share a handler, but no click was physically made.

## Visual polish — v2.4.0 (2026-10-12)

Implements the [design review](https://github.com/AmbitiousRealism2025/t3-loupe-media/blob/main/design-review/DESIGN-REVIEW.md).

**What changed:**
- **Colour budget.** Only needs-you (attention), working (accent) and done-unseen (success) take a hue, and only on icons. State words use ink, except the alarm states (needs input, failed). Coloured edges are gone. Tags are neutral and outlined, except failures and failing checks.
- **Status sections.** Inbox and Active group threads under **Needs you / Working / Done**, using the shell's `PanelSectionHeader`. The cursor skips headings, and the Idle fold uses the same heading style with a chevron.
- **Flat rows.** Rows use the shell's state fills (`Style.normal/hover/selectedFillFor`), with a 2px accent marker on the selected row only. Subagents indent without connector lines.
- **Header.** `PanelHero`-style: the ring as the mark, the title at `Style.font.heading`, and one uppercase meta line. Machines show as dots in the header in two-pane, and on one quiet line in the dropdown. The segment bar, legend and machine chips are gone.
- **Two-pane detail.** The meta line leads with the state. Focus T3 / Open PR / Copy are icon buttons in the header, followed by a facts strip (subagents, PR, context with meter, cost).
- **Charts.**
  - The runs chart is linear (it was a square-root scale), with past runs dimmed, the current run in accent, failures in attention, a baseline and the longest run labelled.
  - Plan progress is shown as steps.
  - Meters use ink and turn attention at 90% or more.
  - Usage takes one line per provider.
- **Bar.** The ring is ink with only the needs-you slice coloured, and the badge is now an outlined pill.
- **Centered card.** 1px line border instead of 2px.

**Verified:**
- Tests pass, including new ones for sections, the colour budget and ring segments.
- The manifest validates.
- With the demo feed, checked live in a monochrome theme (the hardest case for colour):
  - two-pane in Active and Inbox (with the approval command text);
  - the dropdown, via `f`;
  - the bar.
- No QML warnings from this plugin.

**Not verified:**
- Colourful and light themes visually. I didn't change your active theme to test them; the palette contrast tests cover all 22 shipped themes.
- Mouse hover and click states (they share handlers with keyboard input).

**Also in v2.4.0:**
- **Focus T3 (`o`).** Now uses `bin/focus-t3`, which focuses the window through Hyprland by window class. The old `xdg-open t3code://app` route fell back to the browser, and its registered handler pointed at a stale AppImage after a nightly update. Verified live: with another app focused, opening Loupe and pressing `o` focused `com.t3tools.T3Code`.
- **Text size.** `textSize` in `settings.json` and `+`/`-` in the panel scale every panel text token through a `Typo` singleton (`components/qmldir`). The centered card widens by 56px per pixel of bump, and the dropdown by 36px. Section labels elide instead of overflowing. Verified live at 0 and +2 in two-pane with the demo feed, on a colourful amber theme. No QML warnings.
- **Text size control.** The footer has **A↓**, four rising bars (one per preset, each clickable) and **A↑**. The presets are 0 (default, smallest), +2, +4 and +6. `+`/`-` step through the same presets, and every change is written to `settings.json` with any other keys preserved. Verified live: +2 → `+` → +4 (saved) → `-` → +2 → `-` → 0 → `-` stays at 0, with A↓ greyed out → `+` → +2. The panel widened at each step. Clicking a bar wasn't physically tested; it uses the same `setTextSize` path.
- **Backdrop and row shading (user request).**
  - The centered window's backdrop goes from 38% to 58% black. Measured live: brightness outside the card went 37 → 16 with the panel open.
  - Thread rows again sit on the palette `surface` fill, in both the two-pane list and the dropdown cards, with 3px gaps in two-pane. Subagent rows stay unshaded. Hover and selection use the shell fills on top.
  - Verified live with real threads.
