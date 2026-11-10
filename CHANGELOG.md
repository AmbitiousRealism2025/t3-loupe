# Changelog

What changed in each version. [`VALIDATION.md`](VALIDATION.md) records how each one was verified.

## 2.6.0 — 2026-11-09

A second UI overhaul, from a review panel of Fable 5.2 and Sol 6.1 judges. Over three rounds the overall review score went from 6.9 to 7.5 out of 10. No new network, process, file or text-input access; copying a re-pair command uses the existing copy route.

- **Selection doesn't hide state.** The selected row is drawn with an outline in neutral ink, so its coloured status text keeps its contrast, and selection never borrows a state colour.
- **Colours mean one thing each.**
  - Working is plain ink: spinners, the current plan step and the run in progress no longer use the theme accent, so on warm themes they can't be mistaken for "Plan ready".
  - Background work that is still running is neutral, not failure red.
  - The needs-you count is an ink pill in the header and the bar, not red.
- **The bar says what it counts:** `T3 Loupe ◔ [6] need you` in the `label` display, only while something needs you.
- **Rows read at a glance.**
  - Each title gets its own line, semi-bold, and wraps rather than being cut.
  - The second line has the state and reason on the left and a time that says its kind on the right: `waiting 2m`, `running 23m`, `4m ago`, `resets in 47m`.
  - The machine name moved off two-pane rows; it is in the All view's headings, the detail pane and the dropdown.
  - Rows are never drawn cut in half at the list's edges, and `more above ↑` pairs with `more below ↓`.
- **The window fits its content.** The two-pane window is as tall as what it shows, up to its old height, so a short thread no longer leaves half the window empty. Its top edge stays put.
- **One name for what needs you.** The first tab is "Needs you", and the header reads `6 NEED YOU + 7 WORKING`.
- **The hand-off to T3:** every next step ("→ Decide in T3: …") has `[o] open T3` right under it.
- **The footer is one grid.**
  - Each kind of usage window (5-hour, weekly, weekly · Fable) has a column shared by every provider.
  - A spent window reads `full`, with its reset time under its meter.
  - The key legend is grouped by purpose and lines up with the usage rows, with the size control beside `+/- size`.
- **Keys you can see:**
  - `d`/`u` page the detail pane, and the "more below" strip shows `d`.
  - Folded groups show `↵ unfold` / `↵ fold`.
  - Threads with subagents show their count and a chevron.
  - On the offline screen, digit keys copy the re-pair commands.
- **Contrast:** the facts grid's lines are held to 3:1, and the expiring-pairing note gets an hourglass.
- New tests for the shared usage columns at every text size, the palette roles and the row layout (112 pass).

## 2.5.11 — 2026-11-09

Settled threads stay out of Needs you. Contributed by [@farseenmanekhan1232](https://github.com/farseenmanekhan1232) in [#5](https://github.com/AmbitiousRealism2025/t3-loupe/pull/5).

- **Settled means put away.** T3's own inbox leaves out a thread you have settled (`settledAt`, or `settledOverride: "settled"`), but T3 Loupe classified it from its last run. A settled failed run, a stale plan, a leftover pending request, a past usage limit or background tasks all put it under Needs you, raised the bar badge and the Active count, and kept a finished parent showing "1 subagent running". Settled threads now skip those states: a settled failure shows as stopped, and a settled finished thread as done. A run that is actually running still shows as working, so settling a live thread doesn't hide it.
- New tests for each case (103 pass).

## 2.5.10 — 2026-11-09

A working `t3-loupe` command, and a README rewritten for someone installing T3 Loupe for the first time.

- **`t3-loupe` is a real command.** The panel, its re-pair cards, `doctor` and the expiry notification all said to run `t3-loupe …`, but nothing installed one, so a new user's first step failed with "command not found". The plugin now ships `bin/t3-loupe`, which runs the collector with the same Node the shell uses (`"node"` in `settings.json`, or `node` on `PATH`). Link it onto your `PATH` once; the README's quick start shows how. With no arguments it prints the commands.
- **Re-pairing a changed server names the right command.** "Server changed" suggested `pair-local` even for a machine paired over SSH or with a link; it now repeats how that machine was paired.
- **The header names the right file.** It said "SETTINGS UNREADABLE" when the unreadable file was `connections.json`; it now says "PAIRINGS UNREADABLE".
- **README:**
  - A quick start on the first screen, and the demo feed for anyone just looking.
  - Requirements that match what was tested, including `python3` for pairing and how to pair a T3 on macOS.
  - A `settings.json` table with every key and its default, instead of a sample that pinned `/usr/bin/node` and a presentation.
  - Troubleshooting keyed to what you actually see.
  - A shorter feature list, security summary and developer section.
- **New screenshots and marketplace preview** of the current UI, in Omarchy's Matte Black theme, replacing ones from before the 2.5.7 redesign.
- `VALIDATION.md` no longer names a real Tailscale host, and a test keeps it that way.
- New tests: the command runs from a symlink and honours a pinned Node; "Server changed" re-pairs the way the machine was paired (101 pass).

## 2.5.9 — 2026-11-09

Addresses the Medium findings from the marketplace review of 2.5.7. Each needed a paired T3 server that had turned hostile; none could be reached otherwise.

- **What the collector keeps from a server is bounded.** Thread, project and request ids must look like T3's ids (up to 256 characters of letters, digits and `_ . : % -`); anything else is dropped on arrival instead of being kept and echoed into the state line. Each machine holds at most 5,000 threads and 1,000 projects, and each open thread at most 64 requests, runs, provider threads and subagents. Option, question and plan-step lists are trimmed when they arrive.
- **The state line always fits.** When shedding idle and finished threads isn't enough, the collector keeps the most urgent rows that fit, so the shell never has to drop the whole update.
- **Pending requests are capped.** The detail pane shows the first three pending requests and "+N more waiting in T3" for the rest, instead of drawing every one.
- **Text is never read as markup.** The provider-name label used to size the usage footer didn't force plain text, so markup in a provider name could make Qt fetch an image. Every Text element now sets its format, and a test holds them to it.
- **Subagent rows keep their whole id.** Ids were cut to 80 characters, and real subagent ids are about 200 characters with a long shared prefix, so sibling subagents could share an id and their detail couldn't load. Ids are kept whole now.
- New tests for each (99 pass).

## 2.5.8 — 2026-11-09

Fixes pairing a remote machine that runs T3 as a server rather than the desktop app.

- **`pair-ssh` works with `t3 serve`.** On a machine running T3's standalone server, `pair-ssh` stopped with `cli_not_found`: it only knew how to find the CLI inside the desktop app. When the server program is `t3` itself, it now runs that as the CLI.
- **`pair-ssh` can pair over HTTPS.** `pair-ssh --ssh-host HOST --url https://…` uses SSH only to issue the pairing, then connects to the HTTPS address directly, such as a Tailscale Serve name. Before, any machine paired with `pair-ssh` was looked up through an `ssh -L` forward, so one reached over HTTPS showed "No SSH tunnel". Machines paired at a loopback forward work as before.
- The panel's re-pair command for such a machine includes its `--url`.
- New test: a machine paired over SSH at an HTTPS address is reached there, not through a forward (94 pass).

## 2.5.7 — 2026-11-08

A UI overhaul driven by design reviews. Four reviewer agents scored the panel on eight categories, and it was reworked over ten rounds against their findings. The overall review score went from 5.8 to 7.6 out of 10. No new network, process, file, clipboard or text-input access.

- **States say what's actually wrong.**
  - **Offline:** when every machine's pairing has expired, the panel says it isn't connected and gives each machine's re-pair command, instead of "No recent threads".
  - **Failures:** they are named by cause ("sign-in rejected", "folder missing") in the list and the detail.
  - **Detail callouts:** every detail opens with the state, the provider's message and the next step.
  - **Loading:** a "Loading…" line never sits under an error.
- **Urgency shows in every theme.**
  - **Colour:** needs-you is red, plans and limits amber, and questions and approvals violet, even in themes whose own "red" is close to their text colour, such as Blue Clouds.
  - **Without colour:** failed rows carry a dashed rail, so they don't rely on colour alone.
  - **Bar:** the bar badge is filled while anything needs you, and its tooltip names the counts.
- **The counts agree.**
  - The header, the tabs and both rings count the same threads: "6 NEED YOU · 7 WORKING · 3 DONE · 1 STOPPED".
  - The Inbox holds only threads that need you.
- **Rows keep what matters.** A row's second line is its state and reason, never cut off. The machine sits under the time.
- **Read-only, and it looks it.** A provider's choices show as plain text with the `o` key to answer in T3, not as buttons that do nothing.
- **Contrast:**
  - Secondary text is held to 4.5:1, including on the selected row.
  - Plan bars, meters, tracks, scrollbars and the bar ring are held to 3:1, across all shipped themes.
  - The selection ring is the theme accent, 2 px wide.
- **Layout:**
  - **Legend:** a fixed two-row key legend that doesn't move as you navigate.
  - **Detail panes:** the action comes first, stats sit two to a row, and plan and runs come before the activity list.
  - **Scrollbars:** they never cover text.
  - **Pinned headings:** only one group heading stays pinned at a time.
  - **Usage limits:** grouped per provider, with each window labelled ("5-hour", "weekly", "weekly · Fable"), so accounts with three or more windows lay out cleanly.
- **Keys:** `d` and `u` page the detail pane. Tabs show their number keys.
- **Demo feed:** gains a sign-in error, a missing folder and an offline mode (`"demo": "offline"`), so every state can be reproduced for screenshots.
- **Tests:** they now run the real components in Qt's test runner at every text size and the real panel widths (93 tests).

## 2.5.6 — 2026-11-08

Fixes the panel ignoring the Omarchy theme on Qt 6.12.

- **The panel follows the theme again.** Qt 6.12 added a `Color` type to Qt Quick, and it wins over the shell's `qs.Commons` `Color` singleton whatever order the imports come in. T3 Loupe named the shell's palette as plain `Color`, so on Qt 6.12 the palette came out undefined: the centered panel drew white with black text and unstyled controls, the shell logged `Cannot read property 'background' of undefined`, and theme switches were missed because the watch listened on the wrong object. Every reference now goes through `import qs.Commons as Omarchy` as `Omarchy.Color`, which resolves the same way on every Qt version. Omarchy's own shell avoids the clash by pinning `import QtQuick 6.11`; a qualified name doesn't depend on a version.
- New tests: `Theme.qml` run in Qt's test runner with the shell's tokens stubbed, checking that the palette resolves, follows token changes and detects a light background, and a check that no QML file names `Color` unqualified (75 pass).

## 2.5.5 — 2026-10-22

Fixes a crash reported in [#1](https://github.com/AmbitiousRealism2025/t3-loupe/issues/1).

- **Threads with a linked PR no longer stop the collector.** T3's `linkedPullRequest` and `branchPullRequest` are bare references (repository, number, URL); the PR's details live on the matching `pullRequests[]` entry. The collector read the details straight off the reference, so any thread with a linked PR, or on a branch with an open PR, threw, and the widget stayed on "Collector stopped · restarting" with no threads. The reference is now resolved to its `pullRequests[]` entry. A linked PR still wins over more recent ones, and one whose details haven't synced yet gives way to the most relevant synced PR, or to none.
- **PRs are matched the way T3 identifies them: forge host, repository and number.** T3 stores `pullRequests[]` repositories lowercased and keeps the original case on the references, so `Owner/Repo` and `owner/repo` are the same PR. Without this, a link to a repository with capitals in its name would never find its details. The host comes from the entry, or from the reference's URL, so the same `owner/repo#7` on two forges stays two PRs instead of one overwriting the other.
- New test: linked and branch references resolved against T3's shapes, including the case difference, the same PR path on two forges, and an entry not yet synced (73 pass).

## 2.5.4 — 2026-10-16

Security fix from the [marketplace review](https://github.com/omacom/omarchy-plugin-marketplace/issues/11810).

- **The filter box no longer uses an editable text input.** It was a stock `TextField`, which can read the clipboard on its own, and a filter has no use for paste. It is now `components/FilterField.qml`, built from plain `Text`, with typing delivered as key events. The plugin has no `TextField`, `TextInput` or `TextEdit` left. Typing, `Backspace`, `Ctrl+W` (delete word), `Ctrl+U` (clear), `Enter` (keep the filter) and `Esc` (clear it) work as before; paste, mouse selection and input-method composition are no longer supported in the filter.
- The troubleshooting entry for "No SSH tunnel" says what to do when T3 reaches the machine another way, such as over Tailscale HTTPS: re-pair with `pair --url`.
- New tests: the filter's editing rules, and the real component driven with key events through Qt's test runner (72 pass).

## 2.5.3 — 2026-10-16

Fixes the list order and the two-pane selection when several threads are running at once.

- **Threads keep their places.** Needs you and Working used to be ordered by last update, so two busy threads swapped places on nearly every tool call. They are now ordered by when each thread was created: oldest on top, newest at the bottom. Creation time never changes, so nothing moves while it works. "Finishing", "queued" and "background" threads no longer sort as separate tiers inside Working. Done, Stopped and Idle still go most recent first.
- **The highlight follows the thread, not the row.** When the list reordered, the highlight stayed on its row and landed on a different thread while the right pane kept showing the old one. The cursor now follows its thread when the list changes, and the right pane always shows the highlighted thread. If that thread leaves the current view, the highlight moves to the nearest row and the pane follows it.
- **One order across machines.** Rows from every paired machine are sorted together. They were joined machine by machine before.
- Each row carries one more allowlisted field, the thread's creation time. There is no new network, process or file access.
- Two new tests for the ordering (69 pass).

## 2.5.2 — 2026-10-13

Privacy fix from the [marketplace review](https://github.com/omacom/omarchy-plugin-marketplace/issues/11292). Any local account can read a process's command-line arguments, and private text was reaching them.

- **Notifications are generic by default.** They now name only the kind of event, such as "A T3 thread needs your input". Clicking still opens that thread. Thread titles, projects and errors used to be passed to `omarchy-notification-send` as arguments. Omarchy's notification service also passes notification text to a shell command as an argument when it saves a notification, so no wording choice on our side can keep detailed text private. `"notifications": { "details": true }` opts back in to full text, with that caveat documented.
- **Copy title pipes the title to `wl-copy` on stdin** through the collector, instead of passing it as an argument. A failed or missing `wl-copy` is reported by code and can't crash the collector.
- **An open panel now holds back non-attention notifications even when their kind is switched on explicitly**, matching the README.
- `tools/probe.ts`, a developer tool, now uses the collector's own request helpers, so it gets the same identity check, the same loopback-ownership check before every secret, and the same redirect, timeout and size limits.
- The README and SECURITY.md describe exactly when identity and ownership are checked, and the window that remains.
- New tests for notification wording and preferences and for clipboard success, failure and timeout paths (67 pass).

## 2.5.1 — 2026-10-12

Security fix from the [marketplace review](https://github.com/omacom/omarchy-plugin-marketplace/issues/11292).

- **The token is never sent before the server's identity is verified.** If the connection failed at the identity check itself, the HTTP fallback used to poll with the token anyway. A process from another local account listening on T3's vacant port could answer the check with an error and receive the token. The fallback now runs only after the pinned identity matched, and every poll re-checks it.
- **Loopback secrets only go to your own listener.** Before a token, socket ticket or pairing credential is sent to a loopback address, T3 Loupe checks `/proc/net/tcp` and `tcp6` and requires the listening socket to belong to the current user. The new state "Port owned by another user" reports a refusal.
- Four new tests cover the reported scenario, re-verification on every poll, and listener ownership.

## 2.5.0 — 2026-10-12

Ready for the [Omarchy plugin marketplace](https://plugins.omarchy.org/).

- **Installs with Omarchy's own plugin manager.** The plugin now sits at the repository root, so `omarchy plugin add https://github.com/AmbitiousRealism2025/t3-loupe.git --enable` installs it, `omarchy plugin update` updates it and `omarchy plugin remove` removes it. The custom `tools/install.sh` is gone.
- **Smaller download.** Screenshots, the promo video and its source moved to [t3-loupe-media](https://github.com/AmbitiousRealism2025/t3-loupe-media), and the repository history was rewritten without them.
- **Marketplace preview.** `preview.webp` shows the two-pane window.
- Added this changelog and a [security policy](SECURITY.md).

## 2.4.0 — 2026-10-12

- **Visual polish.** Colour only for needs-you, working and done-unseen; status sections (**Needs you / Working / Done**) in the shell's own heading style; flat rows on the shell's state fills; a facts strip in the two-pane detail; linear run charts and step-style plan progress; an ink ring in the bar with only the needs-you slice coloured.
- **Reliable Focus T3 (`o`).** Focuses the T3 window through Hyprland by window class instead of the `t3code://` link.
- **Adjustable text size.** `+` / `-` or the footer control step through four sizes; the choice is saved.
- **Stronger backdrop** behind the centered window, and shaded thread rows.

## 2.3.0 — 2026-10-12

- **Two-pane window** as the default panel: every thread on the left, the selected one's live detail on the right. `f` switches to the compact dropdown, and the `presentation` setting picks the default.

## 2.2.0 — 2026-10-12

- **Idle fold.** Idle and stopped threads collapse behind an **Idle (n)** line.
- **Done tab** between Active and All: finished threads, newest first.

## 2.1.0 — 2026-10-12

- Renamed to **T3 Loupe** (plugin id `ambitiousrealism.t3-loupe`, config in `~/.config/t3-loupe`). The bar shows "T3 Loupe" beside the ring; both open the panel.

## 2.0.0 — 2026-10-12

- First release: a live, read-only view of T3 Code threads across paired machines, with the activity ring, per-thread activity using T3's icons, approval text, usage limits and notifications.
