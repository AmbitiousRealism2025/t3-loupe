# Security policy

T3 Loupe stores T3 session tokens and reads live data from your T3 servers, so security reports are welcome.

## Reporting a vulnerability

Please report privately through [GitHub's private vulnerability reporting](https://github.com/AmbitiousRealism2025/t3-loupe/security/advisories/new) rather than a public issue. Include the version (`manifest.json`), what you did, and what happened. Don't include real tokens, pairing links or thread content.

## Supported versions

Only the latest version on `main` gets fixes. Omarchy installs plugins from the default branch, so `omarchy plugin update ambitiousrealism.t3-loupe` picks fixes up.

## What T3 Loupe does and doesn't do

- **Read-only.** Sessions are narrowed to T3's `orchestration:read` scope. T3 Loupe can't send messages, approve, decline, interrupt or change anything.
- **Credentials.** Sessions live in `~/.config/t3-loupe/connections.json`, which must be owner-only (`0600` in a `0700` directory); symlinks are refused. Tokens never reach the shell's QML or IPC. The one-time pairing credential is consumed and never stored.
- **Network.** Plain HTTP only on loopback (a local T3 or an SSH forward); everything else must be HTTPS. Redirects are never followed, and responses are size-capped.
- **Server identity.** Each paired server's environment ID is pinned. It is verified, without credentials, when connecting, before the session check, socket ticket and socket use the token, and again before every HTTP poll. A failed or mismatched check means the token isn't sent.
- **Loopback ownership.** Any local account can listen on a vacant loopback port. Before a token, socket ticket or pairing credential goes to a loopback address, T3 Loupe reads `/proc/net/tcp` and `/proc/net/tcp6` and requires every socket that could answer to belong to the current user. If ownership can't be established, the secret isn't sent. An SSH forward is owned by your own `ssh` process, so it passes. The identity and ownership checks run just before each request rather than being bound to the connection itself, so a narrow window remains if T3 stops and another account takes its port in those milliseconds.
- **Process arguments.** Any local account can read a process's command line (`/proc/<pid>/cmdline`), so private text is never passed as one. Notifications name only the kind of event by default; `"notifications": { "details": true }` opts in to titles, projects, machines, error messages and pull request titles, which then reach Omarchy's notification service, and that service passes notification text to a shell command as an argument when it saves it. **Copy title** pipes the title to `wl-copy` on stdin. **Open PR** hands the pull request URL to your browser, which receives it as an argument like any opened link. Clipboard contents are available to other programs in your session, as with any copy.
- **Processes.** The shell runs one collector, `node daemon/main.ts`, as your user. Pairing runs T3's own CLI locally (`pair-local`), or a fixed script over an SSH connection you already have (`pair-ssh`), passed on stdin. Nothing runs as root, and no install hooks run. T3 Loupe itself writes nothing to `/tmp`; `wl-copy` may keep a private temporary copy of clipboard text while it serves it.
- **Data kept.** Only display fields. Command output, diffs and message bodies are dropped on arrival.

Note that in T3, `orchestration:read` can also read any file the T3 server's account can read. T3 Loupe only calls the descriptor, session, socket-ticket, shell and thread-stream endpoints.
