# T3 Loupe

<a href="https://github.com/AmbitiousRealism2025/t3-loupe-media/blob/main/t3-loupe-promo.mp4"><img src="https://raw.githubusercontent.com/AmbitiousRealism2025/t3-loupe-media/main/t3-loupe-teaser.gif" width="100%" alt="T3 Loupe promo: a magnifying lens glides over the T3 Loupe window, bringing a thread's activity, PR, context and plan into focus"></a>

<sub>▶ <a href="https://github.com/AmbitiousRealism2025/t3-loupe-media/blob/main/t3-loupe-promo.mp4">Watch the 45-second promo</a> · made with <a href="https://github.com/heygen-com/hyperframes">HyperFrames</a>; source in <a href="https://github.com/AmbitiousRealism2025/t3-loupe-media">t3-loupe-media</a></sub>

**A live, read-only view of your [T3 Code](https://t3.codes) agents, in your [Omarchy](https://omarchy.org) bar.**

![T3 Loupe in the bar](https://raw.githubusercontent.com/AmbitiousRealism2025/t3-loupe-media/main/screens/bar.png)

T3 Loupe shows what every T3 Code thread is doing across all your machines. It tells you which threads are working, which are waiting on you, and how close you are to your usage limits, without switching to the T3 window.

![The two-pane window floating over the desktop: threads grouped by status on the left, the selected thread's live detail on the right](https://raw.githubusercontent.com/AmbitiousRealism2025/t3-loupe-media/main/screens/two-pane.png)

<sub>The two-pane window: every thread on the left, grouped by status, and the selected one in full on the right. That includes live activity with T3's own icons, the PR, context and cost, the plan, the runs chart and subagents.</sub>

| A pending approval, with the full command | The compact dropdown (press <code>f</code>) |
|:---:|:---:|
| ![Pending command approval with the full command text and the provider's options](https://raw.githubusercontent.com/AmbitiousRealism2025/t3-loupe-media/main/screens/two-pane-approval.png) | ![The compact dropdown under the bar](https://raw.githubusercontent.com/AmbitiousRealism2025/t3-loupe-media/main/screens/inbox.png) |

<sub>Screenshots: built-in demo feed, Omarchy's <b>Hackerman</b> theme. Loupe takes its colours from whatever theme is active.</sub>

---

## Features

- **Live, not polled.** T3 Loupe subscribes to T3's orchestration stream, so changes reach the bar in about a second. It resumes cleanly after a network drop or a suspend.
- **A quiet, glanceable ring.** The ring in the bar is drawn in plain text colour, like its bar neighbours. Working threads are full ink and the rest are faint. Only the threads that need you are coloured, with an outlined badge showing how many. The ring turns slowly while agents work and breathes when something is waiting on you.
- **Structure over colour.** Threads are grouped under **Needs you**, **Working** and **Done** headings in the shell's own section style, so urgency reads from position in every theme, monochrome ones included. Only three meanings get a colour: needs you, working, and done-and-unseen. Everything else uses its icon and plain text.
- **What the agent is doing right now.** Each busy thread shows its current step, with **the same icons T3's timeline uses**: terminal for commands, pen for edits, eye for reads, magnifier for code search, globe for web, brain for reasoning, bot for subagents, and so on.
- **The approval text itself.** When an agent is waiting for approval, you see the exact command, file change or question, and the choices the provider offered.
- **Two-pane window.** By default the panel opens as a floating window in the middle of the screen. Threads are listed on the left. The selected thread's live detail is on the right, and it follows `j`/`k` without anything expanding or jumping. Press `f` for a compact dropdown under the bar instead.
- **Per-thread detail:**
  - the last six activities
  - plan progress
  - a run-duration chart
  - context-window use and cost
  - subagents with their progress
  - pull request number, checks and diff size
- **Usage limits at a glance.** Session and weekly windows for providers that report them (such as Codex and Claude), with reset times.
- **Notifications that matter.** You're notified when a thread needs input, a plan is ready, a run fails, a usage limit hits, checks fail, or a long run finishes while you were away. Startup and reconnects are silent, and clicking a notification opens the panel on that thread.
- **Many machines.** Pair your laptop and any remote T3 servers, including ones you reach through an SSH tunnel. All threads are ranked together, and each machine shows its connection health.
- **Native to your theme.** Every color comes from the active Omarchy theme and is held to WCAG contrast floors. All 22 shipped themes are tested, light and monochrome ones included. Changing theme recolors the plugin live.
- **Four views.** **Inbox** (what needs you), **Active**, **Done** (finished work, newest first) and **All** (grouped by machine and project).
- **Idle stays out of the way.** In Active and All, idle and stopped threads fold behind a collapsible **› Idle (n)** line, so busy work stays on top.
- **Keyboard-first.** `j`/`k`, `Enter`, filters on `1`–`4`, `/` to search, `g` to jump to whatever needs you.

## Requirements

| | Tested with |
|---|---|
| Omarchy shell | 4.0.x (Quickshell 0.3) |
| Node.js | **22.18 or newer** on the shell's `PATH`; the collector is plain TypeScript run directly by Node |
| T3 Code | Orchestration protocol 2 (nightly `0.0.46`, Oct 2026) |

There are no npm packages to install and nothing runs as root.

## Install

```sh
omarchy plugin add https://github.com/AmbitiousRealism2025/t3-loupe.git --enable
```

Omarchy validates the plugin, asks which side of the bar to use (right by default) and installs it into `~/.config/omarchy/plugins/ambitiousrealism.t3-loupe/`. There are no install hooks.

Move it later with `omarchy bar move ambitiousrealism.t3-loupe --section center` (or `left`).

### Update

```sh
omarchy plugin update ambitiousrealism.t3-loupe
```

Omarchy shows the incoming changes, fast-forwards, re-validates and rolls back if anything fails. [`CHANGELOG.md`](CHANGELOG.md) lists what changed.

### Remove

```sh
omarchy plugin remove ambitiousrealism.t3-loupe
rm -rf ~/.config/t3-loupe          # optional: your pairings and settings
```

Then revoke each machine's session in that machine's T3 → Settings → Connections.

## Pair your T3 machines

T3 Loupe needs one read-only session per T3 environment.

```sh
L=~/.config/omarchy/plugins/ambitiousrealism.t3-loupe/daemon/main.ts

node $L pair-local                                  # the T3 running on this machine
node $L pair-ssh --ssh-host my-server               # a remote T3 you reach with  ssh -L PORT:127.0.0.1:3773 my-server
node $L pair --url https://t3.example.com           # paste a pairing link from T3 → Settings → Connections
node $L doctor                                      # check every machine: reachability, identity, scope, expiry
```

- **`pair-local`** asks your own T3 installation for a five-minute, single-use pairing grant, then exchanges it.
- **`pair-ssh`** does the same on the remote machine. It runs one fixed command there, once. It uses an SSH forward you already have; T3 Loupe never opens tunnels itself.
- **`pair`** prompts for the link with hidden input. Don't paste tokens into command arguments or chat.

Sessions last 30 days, and T3 doesn't issue refresh tokens. T3 Loupe warns you three days before a session expires; re-pair the same way.

## Using it

| | |
|---|---|
| **Click** the name or the ring | open or close the panel |
| **Middle-click** | reconnect now |
| `j` / `k`, `↑` / `↓` | select a thread; the two-pane detail follows |
| `Enter` | show all of a thread's subagents (two-pane) or expand its card (dropdown); on **Idle (n)**, fold or unfold |
| `f` | switch between the two-pane window and the dropdown |
| `+` / `-` | step the panel text size up / down (also the **A↓ ▁▂▃▅ A↑** control in the footer); the choice is saved |
| `1` `2` `3` `4`, `h` / `l` | **Inbox** (needs you) · **Active** · **Done** (finished, newest first) · **All** (grouped by machine and project) |
| `/` | filter by text |
| `g` | jump to the first thread that needs you |
| `o` | bring the T3 window forward |
| `r` | reconnect |
| `Tab` | next bar panel |
| `Esc` | close |

The same actions are available over IPC, for keybindings or scripts:

```sh
omarchy-shell ambitiousrealism.t3-loupe open
omarchy-shell ambitiousrealism.t3-loupe focus <environmentId>:<threadId>
omarchy-shell ambitiousrealism.t3-loupe status
omarchy-shell ambitiousrealism.t3-loupe testNotification
```

## Configuration

### Bar widget

Set these with `omarchy bar set ambitiousrealism.t3-loupe <key> <value>`.

| Key | Values | Default |
|---|---|---|
| `display` | `label`: "T3 Loupe" + ring · `ring`: ring with the count inside · `ring-count`: count beside the ring | `label` |
| `reduceMotion` | `true` stops the spin, pulse and halo | `false` |
| `presentation` | `centered`: two-pane floating window · `dropdown`: compact panel under the bar | `centered` |
| `panelWidth` | `420` – `900` (dropdown width) | `540` |

### Notifications and the collector

These settings live in `~/.config/t3-loupe/settings.json`. The file is optional and reloads live.

```json
{
  "notifications": {
    "enabled": true,
    "attention": true,
    "milestone": true,
    "info": false,
    "whenPanelOpen": false,
    "kinds": { "checks_passed": false }
  },
  "node": "/usr/bin/node",
  "presentation": "centered",
  "textSize": 0,
  "demo": false
}
```

| Group | Kinds |
|---|---|
| `attention` | `needs_input` · `plan_ready` · `run_failed` · `usage_limit` · `checks_failed` · `session_expiring` |
| `milestone` | `run_completed` (runs ≥ 1 min that you haven't opened yet) · `subagents_done` · `pr_opened` · `pr_merged` · `checks_passed` |
| `info` | `environment_offline` · `environment_restored` |

- Each kind fires at most once per thread every two minutes.
- `"textSize"` makes the panel's text larger without changing the shell-wide font size. There are four steps: `0` (the shell's own size, the smallest), `2`, `4` and `6`, measured in pixels on top of the shell's type scale. You can set it with the **A↓ ▁▂▃▅ A↑** control in the panel footer, by clicking a bar to jump to that size, or with `+` / `-`. Loupe saves the choice to this file. The window widens with the text, so bigger text means easier reading rather than more truncation. Other values from `-2` to `8` can be set by hand.
- `"node"` pins a Node binary when the shell's `PATH` doesn't have a suitable one.
- `"demo": true` replaces live data with a synthetic feed that exercises every state.

## Security and privacy

- **Read-only by design.**
  - Each session is narrowed to T3's `orchestration:read` scope.
  - T3 Loupe can't send messages, approve, decline, interrupt or change anything.
  - You answer approvals in T3 itself.
- **Credentials stay in one place.**
  - Sessions are stored in `~/.config/t3-loupe/connections.json`, which must be owner-only (`0600` inside a `0700` directory); symlinks are refused.
  - Tokens never reach the shell's QML or IPC.
  - The wider one-time pairing credential is consumed and never stored.
- **Narrow network surface.**
  - Plain HTTP is accepted only on loopback (your local T3 or an SSH forward); anything else must be HTTPS.
  - Redirects are never followed, so a token can't leak to another host.
  - Each machine's server identity is pinned.
  - Responses are size-capped.
- **Minimal data kept.** Only display fields are kept. Command output, diffs and message bodies are dropped on arrival. Approval and question text is shown because that is the point of the panel.
- **Know what read scope can reach.** In T3, `orchestration:read` can also read any file the server's account can read. T3 Loupe only calls the descriptor, session, socket-ticket, shell and thread-stream endpoints.

To remove a machine, run `node $L forget --id <prefix>`, then revoke the session in that machine's T3 → Settings → Connections.

## How it works

```
Omarchy shell (Quickshell)                         T3 server(s)
┌──────────────────────────────────────┐          ┌─────────────────────────────┐
│ Service.qml ─ Process ─► t3-loupe    │  ws/RPC  │ /ws  orchestration.         │
│   stdout NDJSON (state/notice/detail)│◄────────►│      subscribeShell         │
│   stdin  {"cmd":"detail",…}          │          │      subscribeThread (busy) │
│ BarWidget.qml ─ ThreadsPanel.qml     │          │      subscribeServerConfig  │
│ Theme.qml (palette) · Notifier.qml   │          │ /api/auth/session · ticket  │
└──────────────────────────────────────┘          └─────────────────────────────┘
```

**The collector, `daemon/`.**
- It keeps one connection per paired machine and authenticates the socket with a short-lived ticket.
- It speaks T3's Effect-RPC protocol: it acknowledges every streamed chunk and resumes from the last sequence it applied.
- Busy threads, and threads waiting on you, get their own live subscription; that feeds the activity line and the approval text.
- Transition detection turns state changes into notifications.
- When the socket path is down but HTTP still answers, it falls back to HTTP polling.

**The QML plugin.**
- One shared service runs the collector, the theme palette and notifications.
- Bar widgets can live in any section, with one instance per monitor.
- The two-pane window is a layer-shell overlay with a dimmed backdrop. Clicking outside, `Esc`, or opening another bar panel closes it. The dropdown is a standard Omarchy `KeyboardPanel`.
- Icons are Lucide vector paths drawn in theme colors.

[`docs/DESIGN.md`](docs/DESIGN.md) records the original design and the T3 source evidence behind it. [`VALIDATION.md`](VALIDATION.md) records what has been verified on a live system and what hasn't.

## Troubleshooting

| Symptom | What to do |
|---|---|
| The bar shows `—` | The collector can't reach any machine. Run `node $L doctor`. |
| The bar shows `+` | Nothing is paired yet; see [Pair your T3 machines](#pair-your-t3-machines). |
| "No SSH tunnel" | Start your `ssh -L …:127.0.0.1:3773 host` forward. T3 Loupe picks it up within 15 s. |
| "Pairing required" / "Pairing expired" | Re-pair that machine. |
| "Collector stopped" | Node is missing or too old on the shell's `PATH`. Set `"node"` in `settings.json`. `omarchy-shell ambitiousrealism.t3-loupe status` shows the last error. |
| Changes to the plugin don't show | Some nested QML components don't hot-reload; run `omarchy-restart-shell`. |

## Limitations

- **No deep link into a thread.** T3 can't yet be told to open a specific thread from outside. *Focus T3* (`o`) brings the T3 window forward through Hyprland, matching the window class (`com.t3tools.T3Code`, `t3code`, `t3code-dev`). It doesn't use the `t3code://` link, which can fall back to the browser or launch a stale build after an update.
- **Read-only.** Answering approvals or interrupting from the panel would need T3's much wider `orchestration:operate` scope, which also allows sending messages. That is deliberately not included.
- **Usage gauges only where T3 has data.** Providers that don't report usage windows show only a status dot.
- **Newer shells untested.** Newer Omarchy shells that give plugins narrower APIs haven't been tested.

## Development

```sh
npm test                                              # daemon, fake-T3 end-to-end, view logic, palette × every installed theme
node daemon/main.ts demo                              # synthetic feed (or "demo": true in settings.json)
node tools/extract-icons.mjs <path-to-lucide-react>   # regenerate lib/Icons.js
node tools/probe.ts 20                                # record raw frames from your paired servers to ~/.cache (never the repo)
```

**Layout:**
- The repository root is the plugin: `manifest.json`, the QML files, `components/`, `lib/`, `daemon/` and `bin/`.
- `daemon/` is the collector.
- `lib/` holds pure JavaScript shared by QML and the tests.
- `tests/` and `tools/` are for development only.
- `tests/lib/fake-t3.mjs` is a dependency-free fake T3 server that speaks real WebSocket and Effect-RPC.

## Credits and license

MIT © 2026 ambitiousrealism. See [`LICENSE`](LICENSE).

Icons are from [Lucide](https://lucide.dev), under the ISC license; see [`THIRD_PARTY.md`](THIRD_PARTY.md).

T3 Loupe is an independent project, not affiliated with T3 Tools or Omarchy.
