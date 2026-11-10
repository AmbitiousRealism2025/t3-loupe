# T3 Loupe

**See which [T3 Code](https://t3.codes) agent needs you, from your [Omarchy](https://omarchy.org) bar.** A live, read-only view of every T3 thread across your machines: what's waiting on you, what's working, and how close you are to your usage limits.

![The two-pane window: threads grouped by status on the left, the selected thread's live detail on the right](https://raw.githubusercontent.com/AmbitiousRealism2025/t3-loupe-media/main/screens/2.6.1/two-pane.png)

![T3 Loupe in the bar](https://raw.githubusercontent.com/AmbitiousRealism2025/t3-loupe-media/main/screens/2.6.1/bar.png)

## Quick start

You need Omarchy 4, Node 22.18 or newer (`node --version`), and T3 Code running on this machine.

1. **Install.** Omarchy warns that plugins run unsandboxed, then adds the widget to the bar.
   ```sh
   omarchy plugin add https://github.com/AmbitiousRealism2025/t3-loupe.git --enable
   ```
2. **Add the `t3-loupe` command** to your `PATH`, once:
   ```sh
   ln -sf ~/.config/omarchy/plugins/ambitiousrealism.t3-loupe/bin/t3-loupe ~/.local/bin/t3-loupe
   ```
3. **Pair.** The ring shows `+` until you do.
   ```sh
   t3-loupe pair-local
   ```
4. **Open it.** Click **T3 Loupe** in the bar. A new pairing is picked up within five seconds; there's nothing to restart.

**Just looking?** Skip pairing and turn on the built-in demo feed. If you don't have a `settings.json` yet:

```sh
mkdir -p -m 700 ~/.config/t3-loupe
echo '{ "demo": true }' > ~/.config/t3-loupe/settings.json
```

Remove the file, or set `"demo": false`, to go back to live data.

## What it shows

- **Who needs you, first.** Threads waiting on an approval, a question or a plan review sit under **Needs you**, coloured by kind. In the bar, a badge beside the ring counts them: **6 need you**.
- **The approval text itself.** The exact command, file change or question, with the choices the provider offered. You answer in T3: Loupe is read-only.
- **What each agent is doing now,** with the icons T3's timeline uses, plus plan progress, runs, context use and cost, subagents and the pull request.
- **Failures named by cause,** such as "sign-in rejected" or "folder missing", with the next step.
- **Usage limits** for providers that report them, such as Claude and Codex, with reset times.
- **Every machine in one list.** Pair your laptop and any remote T3 servers; all threads are ranked together, and each machine shows its connection health.
- **Live, not polled.** Changes reach the bar in about a second, and it resumes cleanly after a network drop or a suspend.
- **Native to your theme.** Colours come from the active Omarchy theme and are held to WCAG contrast floors in all 22 shipped themes, light and monochrome ones included.

| A pending approval, with the full command | The compact dropdown (press <code>f</code>) |
|:---:|:---:|
| ![Pending command approval with the full command text](https://raw.githubusercontent.com/AmbitiousRealism2025/t3-loupe-media/main/screens/2.6.1/two-pane-approval.png) | ![The compact dropdown under the bar](https://raw.githubusercontent.com/AmbitiousRealism2025/t3-loupe-media/main/screens/2.6.1/dropdown.png) |

<sub>Screenshots: built-in demo feed, Omarchy's <b>Matte Black</b> theme. Loupe takes its colours from whatever theme is active.</sub>

## Requirements

| | Needs | Tested with |
|---|---|---|
| Omarchy | shell 4.0.x | 4.0.2, Quickshell 0.3.2, Qt 6.12 |
| Node.js | **22.18 or newer**, visible to the shell. The Node Omarchy installs with mise works | 26 |
| T3 Code | orchestration protocol 2 | desktop app 0.1.8 nightly, `t3 serve` 0.1.5 (Nov 2026) |
| `pair-local` | T3 running on this machine, and `python3` | |
| `pair-ssh` | a Linux machine running T3 that you can `ssh` to, with `python3` | |
| T3 on macOS or Windows | `pair --url` with a pairing link; the address must be HTTPS or an SSH forward | not tested |

There are no npm packages to install and nothing runs as root.

## Pair your T3 machines

T3 Loupe needs one read-only session per T3 machine. The panel, `doctor` and this README write commands as `t3-loupe …`; step 2 of the [quick start](#quick-start) puts that command on your `PATH`.

```sh
t3-loupe pair-local                                                      # the T3 running on this machine
t3-loupe pair-ssh --ssh-host my-server                                   # a remote T3 you reach with  ssh -L PORT:127.0.0.1:3773 my-server
t3-loupe pair-ssh --ssh-host my-server --url https://my-server.example.ts.net   # a remote T3 at an HTTPS address, such as Tailscale Serve
t3-loupe pair --url https://t3.example.com                               # a pairing link, pasted at the prompt
t3-loupe doctor                                                          # check every machine: reachability, identity, scope, expiry
```

- **`pair-local`** asks your own T3 installation for a five-minute, single-use pairing grant, then exchanges it.
- **`pair-ssh`** does the same on a remote Linux machine. It runs one fixed command there, once, whether T3 runs as the desktop app or as `t3 serve`. Without `--url` it uses an SSH forward you already have; T3 Loupe never opens tunnels itself. With an HTTPS `--url`, SSH is only used to pair, and T3 Loupe connects to that address directly.
- **`pair`** is for any other machine, including macOS. `--url` is the server's address; copy a pairing link from that T3's **Settings → Connections** and paste it when asked. Input is hidden; don't paste tokens into command arguments or chat.
- Every pairing command takes `--label NAME` for the name shown in the panel. Up to 12 machines can be paired.

Sessions last 30 days, and T3 doesn't issue refresh tokens. T3 Loupe warns you three days before a session expires; re-pair the same way. To drop a machine, run `t3-loupe forget --id <prefix>`, then revoke its session in that machine's T3 → Settings → Connections.

## Using it

| | |
|---|---|
| **Click** the name or the ring | open or close the panel |
| **Middle-click** | reconnect now |
| `j` / `k`, `↑` / `↓` | select a thread; the two-pane detail follows |
| `Enter` or `Space` | show all of a thread's subagents (two-pane) or expand its card (dropdown); on a folded group, fold or unfold |
| `1` `2` `3` `4`, `h` / `l` | **Needs you** · **Active** (needs you plus working) · **Done** (finished, newest first) · **All** (grouped by machine and project) |
| `g` | jump to the first thread that needs you |
| `/` | filter by text: `Backspace` deletes, `Ctrl+W` and `Ctrl+U` clear a word or the line, `Enter` keeps the filter, `Esc` clears it. Pasting isn't supported |
| `d` / `u` | page the two-pane detail down / up |
| `f` | switch between the two-pane window and the dropdown until the shell restarts; set `presentation` to keep a layout |
| `+` / `-` | step the text size up / down (also the **A↓ ▁▂▃▅ A↑** control in the footer); the choice is saved |
| `o` | bring the T3 desktop window on this machine forward |
| `p` | open the selected thread's pull request |
| `c` | copy the selected thread's title |
| `r` | reconnect |
| `Tab` / `Shift+Tab` | next / previous bar panel |
| `Esc` | close |

The same actions are available over IPC, for keybindings or scripts:

```sh
omarchy-shell ambitiousrealism.t3-loupe open
omarchy-shell ambitiousrealism.t3-loupe focus <environmentId>:<threadId>
omarchy-shell ambitiousrealism.t3-loupe refresh
omarchy-shell ambitiousrealism.t3-loupe status
omarchy-shell ambitiousrealism.t3-loupe testNotification
```

## Configuration

### Bar widget

Set these with `omarchy bar set ambitiousrealism.t3-loupe <key> <value>`. Move the widget with `omarchy bar move ambitiousrealism.t3-loupe --section center` (or `left`).

| Key | Values | Default |
|---|---|---|
| `display` | `label`: "T3 Loupe" + ring, and "need you" after the badge · `ring`: the ring alone · `ring-count`: the active count beside the ring. The needs-you badge shows in all three | `label` |
| `reduceMotion` | `true` stops the spin and pulse | `false` |
| `presentation` | `centered`: two-pane floating window · `dropdown`: compact panel under the bar | `centered` |
| `panelWidth` | `420` – `900` (dropdown width) | `540` |

### `settings.json`

These settings live in `~/.config/t3-loupe/settings.json`. The file is optional and reloads live; leave out anything you don't want to change. If you create the folder yourself, make it private (`mkdir -p -m 700 ~/.config/t3-loupe`), or pairing will refuse to store a session there.

```json
{
  "notifications": { "milestone": false, "kinds": { "pr_merged": true } }
}
```

| Key | Default | What it does |
|---|---|---|
| `notifications.enabled` | `true` | Master switch |
| `notifications.attention` / `milestone` / `info` | `true` / `true` / `false` | Switch a whole group (below) |
| `notifications.kinds` | `{}` | Switch one kind, overriding its group |
| `notifications.whenPanelOpen` | `false` | Also show non-attention notifications while the panel is open |
| `notifications.details` | `false` | Put titles and errors in notifications (see [Security and privacy](#security-and-privacy)) |
| `node` | `node` on the shell's `PATH` | Full path to a Node binary, from `which node` |
| `presentation` | unset | `centered` or `dropdown`. If set, it wins over the bar setting |
| `textSize` | `0` | `0`, `2`, `4` or `6` pixels on top of the shell's type scale |
| `demo` | `false` | `true` for the demo feed, `"offline"` for expired pairings and no threads |

| Group | Kinds |
|---|---|
| `attention` | `needs_input` · `plan_ready` · `run_failed` · `usage_limit` · `checks_failed` · `session_expiring` |
| `milestone` | `run_completed` (runs of a minute or more that you haven't opened yet) · `subagents_done` · `pr_opened` · `pr_merged` · `checks_passed` |
| `info` | `environment_offline` · `environment_restored` |

Each kind fires at most once per thread every two minutes. Startup and reconnects are silent, and clicking a notification opens the panel on that thread.

## Update and remove

```sh
omarchy plugin update ambitiousrealism.t3-loupe
```

Omarchy shows the incoming changes, fast-forwards and re-validates. [`CHANGELOG.md`](CHANGELOG.md) lists what changed.

```sh
omarchy plugin remove ambitiousrealism.t3-loupe
rm -f ~/.local/bin/t3-loupe          # the command from the quick start
rm -rf ~/.config/t3-loupe            # optional: your pairings and settings
```

Then revoke each machine's session in that machine's T3 → Settings → Connections.

## Troubleshooting

| You see | What to do |
|---|---|
| `+` in the ring | Nothing is paired, or the collector isn't running. Open the panel: if the header says COLLECTOR STOPPED, see that row; otherwise pair. |
| A dash in the ring | No paired machine is reachable. Run `t3-loupe doctor`. |
| COLLECTOR STOPPED | The shell can't find Node 22.18 or newer. `omarchy-shell ambitiousrealism.t3-loupe status` shows the last error. Set `"node"` in `settings.json` to the full path from `which node`. |
| PAIRINGS UNREADABLE, or `private_config_required` | `chmod 700 ~/.config/t3-loupe && chmod 600 ~/.config/t3-loupe/connections.json` |
| `t3-loupe: command not found` | Run step 2 of the [quick start](#quick-start). |
| "No SSH tunnel", or `tunnel_missing` | Start `ssh -L PORT:127.0.0.1:3773 host` with the same host name you paired, and `-L` on the command line; a `LocalForward` in `~/.ssh/config` isn't found. If you reach the machine over HTTPS instead, re-pair with `--url`. |
| "Pairing required" / "Pairing expired" | Re-pair that machine; the panel shows the command. |
| "Server changed" | A different T3 now answers at that address. Pair it again. |
| "Unsupported T3" | Update T3 on that machine. |
| "Port owned by another user" | Another user account is listening on that machine's T3 port, so T3 Loupe won't send it your session. Check with `ss -ltnp`, and run T3 (or your SSH forward) as your own user. |
| `server_not_found` | T3 isn't running on that machine, or not on port 3773. |
| `endpoint_invalid` | `--url` takes the server address only, such as `https://host`, with no path. Plain HTTP works only on `127.0.0.1`, not `localhost`. |
| Changes to the plugin don't show | Some nested QML components don't hot-reload; run `omarchy-restart-shell`. |

Still stuck? [Open an issue](https://github.com/AmbitiousRealism2025/t3-loupe/issues) with the plugin version and the output of `omarchy-shell ambitiousrealism.t3-loupe status`, which contains no thread titles.

## Security and privacy

- **Read-only.** Each session is narrowed to T3's `orchestration:read` scope. T3 Loupe can't send messages, approve, decline, interrupt or change anything.
- **Sessions stay in one file,** `~/.config/t3-loupe/connections.json`, owner-only inside a private folder. They never reach the shell's QML or IPC, and the one-time pairing credential is never stored.
- **HTTPS or loopback only.** Plain HTTP is accepted only on `127.x.x.x` and `[::1]` (your local T3 or an SSH forward). Redirects are never followed, and each machine's identity is pinned and checked before its session is sent.
- **Generic notifications by default.** Omarchy's notification service passes notification text to a command as an argument, which other accounts on the machine can see, so titles stay in the panel unless you turn on `"details"`.
- **Know what read scope reaches.** In T3, `orchestration:read` can also read any file the server's account can read. T3 Loupe only calls the descriptor, session, socket-ticket, shell and thread-stream endpoints.

[`SECURITY.md`](SECURITY.md) has the full model and how to report a vulnerability.

## Limitations

- **No deep link into a thread.** T3 can't yet be told to open a specific thread from outside. `o` brings the T3 window forward through Hyprland by its window class, and only for T3 on this machine.
- **Read-only.** Answering approvals from the panel would need T3's much wider `orchestration:operate` scope, which also allows sending messages. That is deliberately not included.
- **Usage gauges only where T3 has data.** Providers that don't report usage windows show only a status dot.
- **Newer shells untested.** Omarchy shells after 4.0.x haven't been tested.

## For developers

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

- **The collector, `daemon/`,** keeps one connection per paired machine, speaks T3's Effect-RPC protocol, resumes from the last sequence it applied, and falls back to HTTP polling when the socket is down. Busy threads, and threads waiting on you, get their own live subscription.
- **The QML plugin** runs one shared service for the collector, the theme palette and notifications. The two-pane window is a layer-shell overlay; the dropdown is a standard Omarchy `KeyboardPanel`.
- `lib/` holds pure JavaScript shared by QML and the tests. `tests/lib/fake-t3.mjs` is a dependency-free fake T3 server.

```sh
npm test                                              # daemon, fake-T3 end-to-end, view logic, palette × every installed theme
node daemon/main.ts demo [offline]                    # synthetic feed
node tools/extract-icons.mjs <path-to-lucide-react>   # regenerate lib/Icons.js
node tools/probe.ts 20                                # record raw frames from your paired servers to ~/.cache (never the repo)
```

[`docs/DESIGN.md`](docs/DESIGN.md) records the original design. [`VALIDATION.md`](VALIDATION.md) records what each release was verified against.

## Credits and license

MIT © 2026 ambitiousrealism. See [`LICENSE`](LICENSE).

Icons are from [Lucide](https://lucide.dev), under the ISC license; see [`THIRD_PARTY.md`](THIRD_PARTY.md).

T3 Loupe is an independent project, not affiliated with T3 Tools or Omarchy.
